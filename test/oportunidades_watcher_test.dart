import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:luca/models/licitacion.dart';
import 'package:luca/services/database_service.dart';
import 'package:luca/services/oportunidades_watcher.dart';

Licitacion _licitacion({required String nombre, String? descripcion}) {
  return Licitacion(
    codigo: 'X-1',
    nombre: nombre,
    descripcion: descripcion,
    estado: 'activa',
  );
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

      expect(await verificarNuevasOportunidades(), 0);
    });

    test('sin palabras clave configuradas, devuelve 0 sin llamar al API', () async {
      SharedPreferences.setMockInitialValues({
        'mp_ticket': 'un-ticket-cualquiera',
      });

      expect(await verificarNuevasOportunidades(), 0);
    });

    test('con solo comas/espacios como palabras clave, devuelve 0', () async {
      SharedPreferences.setMockInitialValues({
        'mp_ticket': 'un-ticket-cualquiera',
        'mp_keywords': ' , , ',
      });

      expect(await verificarNuevasOportunidades(), 0);
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
}
