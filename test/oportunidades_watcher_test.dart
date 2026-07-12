import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:luca/models/licitacion.dart';
import 'package:luca/services/database_service.dart';
import 'package:luca/services/mercado_publico_service.dart';
import 'package:luca/services/mp_ticket_storage.dart';
import 'package:luca/services/oportunidades_watcher.dart';
import 'package:luca/services/verificacion_status.dart';

Licitacion _licitacion({required String nombre, String? descripcion}) {
  return Licitacion(
    codigo: 'X-1',
    nombre: nombre,
    descripcion: descripcion,
    estado: 'activa',
  );
}

/// Fake en memoria de [TicketSecureStore], para no depender del canal de
/// plataforma de `flutter_secure_storage` (no disponible en el entorno de
/// test) al ejercitar `verificarNuevasOportunidades`.
class _FakeTicketSecureStore implements TicketSecureStore {
  String? valor;
  _FakeTicketSecureStore([this.valor]);

  @override
  Future<String?> read() async => valor;

  @override
  Future<void> write(String value) async => valor = value;
}

/// Fake de [MercadoPublicoService]: `buscarActivas` no es `final`, así que
/// se puede sobrescribir en una subclase para ejercitar los caminos de
/// éxito/error de `verificarNuevasOportunidades` sin red real.
class _FakeMercadoPublicoService extends MercadoPublicoService {
  final List<Licitacion> Function(String ticket)? resultado;
  final Object? error;
  _FakeMercadoPublicoService({this.resultado, this.error});

  @override
  Future<List<Licitacion>> buscarActivas(String ticket) async {
    if (error != null) throw error!;
    return resultado?.call(ticket) ?? [];
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('coincideConPalabrasClave', () {
    test('coincide sin distinguir mayúsculas/minúsculas contra el nombre', () {
      final licitacion = _licitacion(nombre: 'Suministro de FERRETERÍA para obra');

      expect(coincideConPalabrasClave(licitacion, ['ferretería']), isTrue);
    });

    test('coincide contra la descripción cuando el nombre no matchea', () {
      final licitacion = _licitacion(
        nombre: 'Adquisición de insumos',
        descripcion: 'Incluye elementos de protección personal',
      );

      expect(coincideConPalabrasClave(licitacion, ['protección personal']), isTrue);
    });

    test('no coincide si ninguna palabra clave aparece', () {
      final licitacion = _licitacion(nombre: 'Servicio de aseo');

      expect(coincideConPalabrasClave(licitacion, ['ferretería', 'construcción']), isFalse);
    });

    test('licitación sin descripción no falla al buscar coincidencias', () {
      final licitacion = _licitacion(nombre: 'Compra de equipos');

      expect(coincideConPalabrasClave(licitacion, ['equipos']), isTrue);
    });
  });

  group('verificarNuevasOportunidades — guard temprano', () {
    test('sin ticket configurado, devuelve 0 sin llamar al API', () async {
      SharedPreferences.setMockInitialValues({
        'mp_keywords': 'ferretería',
      });

      expect(
        await verificarNuevasOportunidades(ticketStore: _FakeTicketSecureStore()),
        0,
      );
    });

    test('sin palabras clave configuradas, devuelve 0 sin llamar al API', () async {
      SharedPreferences.setMockInitialValues({});

      expect(
        await verificarNuevasOportunidades(
          ticketStore: _FakeTicketSecureStore('un-ticket-cualquiera'),
        ),
        0,
      );
    });

    test('con solo comas/espacios como palabras clave, devuelve 0', () async {
      SharedPreferences.setMockInitialValues({
        'mp_keywords': ' , , ',
      });

      expect(
        await verificarNuevasOportunidades(
          ticketStore: _FakeTicketSecureStore('un-ticket-cualquiera'),
        ),
        0,
      );
    });
  });

  group('dedup de oportunidades (filtrarNoVistas + marcarComoVistas)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('luca_watcher_test_');
      await DatabaseService.instance.openForTesting(join(tempDir.path, 'watcher.db'));
    });

    tearDown(() async {
      await DatabaseService.resetForTesting();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('una oportunidad ya marcada como vista no se vuelve a considerar nueva', () async {
      await DatabaseService.instance.marcarComoVistas(['LIC-1']);

      final nuevas = await DatabaseService.instance.filtrarNoVistas(['LIC-1', 'LIC-2']);

      expect(nuevas, ['LIC-2']);
    });

    test('marcar como vistas y luego re-filtrar deja la lista de nuevas vacía', () async {
      final codigos = ['LIC-1', 'LIC-2'];

      final primeraVez = await DatabaseService.instance.filtrarNoVistas(codigos);
      expect(primeraVez, codigos);

      await DatabaseService.instance.marcarComoVistas(primeraVez);

      final segundaVez = await DatabaseService.instance.filtrarNoVistas(codigos);
      expect(segundaVez, isEmpty);
    });
  });

  group('verificarNuevasOportunidades — estado de la última verificación', () {
    late Directory tempDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({'mp_keywords': 'ferretería'});
      tempDir = await Directory.systemTemp.createTemp('luca_watcher_estado_test_');
      await DatabaseService.instance.openForTesting(join(tempDir.path, 'watcher.db'));
    });

    tearDown(() async {
      await DatabaseService.resetForTesting();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('si el API falla, registra resultado de error con la causa', () async {
      final resultado = await verificarNuevasOportunidades(
        ticketStore: _FakeTicketSecureStore('ticket'),
        service: _FakeMercadoPublicoService(
          error: MercadoPublicoException('Tu ticket no es válido.'),
        ),
      );

      expect(resultado, 0);
      final estado = await leerUltimaVerificacion();
      expect(estado!.resultado, ResultadoVerificacion.error);
      expect(estado.detalle, 'Tu ticket no es válido.');
    });

    test('si no hay licitaciones nuevas que calcen, registra "sin coincidencias"', () async {
      final resultado = await verificarNuevasOportunidades(
        ticketStore: _FakeTicketSecureStore('ticket'),
        service: _FakeMercadoPublicoService(
          resultado: (_) => [_licitacion(nombre: 'Servicio de aseo')],
        ),
      );

      expect(resultado, 0);
      final estado = await leerUltimaVerificacion();
      expect(estado!.resultado, ResultadoVerificacion.sinCoincidencias);
    });

    test('si hay licitaciones nuevas que calcen, notifica, marca como vistas y registra éxito',
        () async {
      var cantidadNotificada = -1;

      final resultado = await verificarNuevasOportunidades(
        ticketStore: _FakeTicketSecureStore('ticket'),
        service: _FakeMercadoPublicoService(
          resultado: (_) => [_licitacion(nombre: 'Suministro de ferretería para obra')],
        ),
        notificar: (cantidad) async => cantidadNotificada = cantidad,
      );

      expect(resultado, 1);
      expect(cantidadNotificada, 1);
      expect(await DatabaseService.instance.filtrarNoVistas(['X-1']), isEmpty);

      final estado = await leerUltimaVerificacion();
      expect(estado!.resultado, ResultadoVerificacion.exito);
      expect(estado.detalle, '1 oportunidad nueva');
    });
  });
}
