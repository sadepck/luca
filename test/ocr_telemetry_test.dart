import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:luca/services/ocr_telemetry.dart';

void main() {
  group('opt-in', () {
    test('está desactivada por defecto', () async {
      SharedPreferences.setMockInitialValues({});

      expect(await telemetriaOcrActiva(), isFalse);
    });

    test('activarTelemetriaOcr cambia el estado', () async {
      SharedPreferences.setMockInitialValues({});

      await activarTelemetriaOcr(true);
      expect(await telemetriaOcrActiva(), isTrue);

      await activarTelemetriaOcr(false);
      expect(await telemetriaOcrActiva(), isFalse);
    });
  });

  group('registrarEventoOcr', () {
    test('sin opt-in, no registra nada', () async {
      SharedPreferences.setMockInitialValues({});

      await registrarEventoOcr(descuadre: true, montoCero: true);

      final metricas = await leerMetricasOcr();
      expect(metricas.totalEscaneos, 0);
    });

    test('con opt-in, acumula los contadores correctamente', () async {
      SharedPreferences.setMockInitialValues({});
      await activarTelemetriaOcr(true);

      await registrarEventoOcr(descuadre: true, montoCero: false);
      await registrarEventoOcr(descuadre: false, montoCero: true);
      await registrarEventoOcr(descuadre: false, montoCero: false);

      final metricas = await leerMetricasOcr();
      expect(metricas.totalEscaneos, 3);
      expect(metricas.totalDescuadre, 1);
      expect(metricas.totalMontoCero, 1);
    });

    test('las tasas se calculan sobre el total de escaneos', () async {
      SharedPreferences.setMockInitialValues({});
      await activarTelemetriaOcr(true);

      await registrarEventoOcr(descuadre: true, montoCero: false);
      await registrarEventoOcr(descuadre: true, montoCero: false);
      await registrarEventoOcr(descuadre: false, montoCero: false);
      await registrarEventoOcr(descuadre: false, montoCero: false);

      final metricas = await leerMetricasOcr();
      expect(metricas.tasaDescuadre, 0.5);
      expect(metricas.tasaMontoCero, 0.0);
    });

    test('sin escaneos registrados, las tasas son 0 (no NaN por división por cero)', () async {
      SharedPreferences.setMockInitialValues({});

      final metricas = await leerMetricasOcr();

      expect(metricas.tasaDescuadre, 0);
      expect(metricas.tasaMontoCero, 0);
    });
  });

  group('reiniciarMetricasOcr', () {
    test('borra los contadores acumulados sin tocar el estado de opt-in', () async {
      SharedPreferences.setMockInitialValues({});
      await activarTelemetriaOcr(true);
      await registrarEventoOcr(descuadre: true, montoCero: true);

      await reiniciarMetricasOcr();

      final metricas = await leerMetricasOcr();
      expect(metricas.totalEscaneos, 0);
      expect(metricas.totalDescuadre, 0);
      expect(metricas.totalMontoCero, 0);
      expect(await telemetriaOcrActiva(), isTrue);
    });
  });
}
