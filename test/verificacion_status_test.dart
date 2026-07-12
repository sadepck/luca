import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:luca/services/verificacion_status.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('leerUltimaVerificacion', () {
    test('devuelve null si nunca se registró una verificación', () async {
      expect(await leerUltimaVerificacion(), isNull);
    });

    test('devuelve lo último registrado con registrarResultadoVerificacion', () async {
      await registrarResultadoVerificacion(ResultadoVerificacion.exito,
          detalle: '3 oportunidades nuevas');

      final estado = await leerUltimaVerificacion();

      expect(estado, isNotNull);
      expect(estado!.resultado, ResultadoVerificacion.exito);
      expect(estado.detalle, '3 oportunidades nuevas');
      expect(estado.fecha.difference(DateTime.now()).abs(), lessThan(const Duration(seconds: 5)));
    });

    test('una segunda llamada sobrescribe el resultado anterior', () async {
      await registrarResultadoVerificacion(ResultadoVerificacion.error, detalle: 'Sin conexión');
      await registrarResultadoVerificacion(ResultadoVerificacion.sinCoincidencias,
          detalle: 'Sin oportunidades nuevas');

      final estado = await leerUltimaVerificacion();

      expect(estado!.resultado, ResultadoVerificacion.sinCoincidencias);
      expect(estado.detalle, 'Sin oportunidades nuevas');
    });

    test('persiste correctamente el resultado de error con su detalle', () async {
      await registrarResultadoVerificacion(ResultadoVerificacion.error,
          detalle: 'Tu ticket de Mercado Público no es válido o fue rechazado.');

      final estado = await leerUltimaVerificacion();

      expect(estado!.resultado, ResultadoVerificacion.error);
      expect(estado.detalle, 'Tu ticket de Mercado Público no es válido o fue rechazado.');
    });
  });
}
