import 'package:shared_preferences/shared_preferences.dart';

/// Todo lo relacionado a la telemetría local (opt-in) de calidad del
/// parser OCR: solo cuenta cuántos escaneos tuvieron descuadre o monto en
/// $0, nunca guarda la foto, el texto reconocido ni ningún otro dato del
/// documento. Por defecto está desactivada — el usuario debe activarla
/// explícitamente.
const String kOcrTelemetriaActivaPrefKey = 'ocr_telemetria_activa';

const String _kTotalEscaneos = 'ocr_telemetria_total_escaneos';
const String _kTotalDescuadre = 'ocr_telemetria_total_descuadre';
const String _kTotalMontoCero = 'ocr_telemetria_total_monto_cero';

Future<bool> telemetriaOcrActiva() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(kOcrTelemetriaActivaPrefKey) ?? false;
}

Future<void> activarTelemetriaOcr(bool activa) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kOcrTelemetriaActivaPrefKey, activa);
}

/// Registra el resultado de un escaneo recién procesado, solo si el
/// usuario activó el opt-in. No hace nada si está desactivada.
Future<void> registrarEventoOcr({
  required bool descuadre,
  required bool montoCero,
}) async {
  if (!await telemetriaOcrActiva()) return;

  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_kTotalEscaneos, (prefs.getInt(_kTotalEscaneos) ?? 0) + 1);
  if (descuadre) {
    await prefs.setInt(_kTotalDescuadre, (prefs.getInt(_kTotalDescuadre) ?? 0) + 1);
  }
  if (montoCero) {
    await prefs.setInt(_kTotalMontoCero, (prefs.getInt(_kTotalMontoCero) ?? 0) + 1);
  }
}

class MetricasOcr {
  final int totalEscaneos;
  final int totalDescuadre;
  final int totalMontoCero;

  const MetricasOcr({
    required this.totalEscaneos,
    required this.totalDescuadre,
    required this.totalMontoCero,
  });

  double get tasaDescuadre => totalEscaneos == 0 ? 0 : totalDescuadre / totalEscaneos;
  double get tasaMontoCero => totalEscaneos == 0 ? 0 : totalMontoCero / totalEscaneos;
}

Future<MetricasOcr> leerMetricasOcr() async {
  final prefs = await SharedPreferences.getInstance();
  return MetricasOcr(
    totalEscaneos: prefs.getInt(_kTotalEscaneos) ?? 0,
    totalDescuadre: prefs.getInt(_kTotalDescuadre) ?? 0,
    totalMontoCero: prefs.getInt(_kTotalMontoCero) ?? 0,
  );
}

Future<void> reiniciarMetricasOcr() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_kTotalEscaneos);
  await prefs.remove(_kTotalDescuadre);
  await prefs.remove(_kTotalMontoCero);
}
