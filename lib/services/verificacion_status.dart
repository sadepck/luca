import 'package:shared_preferences/shared_preferences.dart';

/// Resultado de la última corrida de [verificarNuevasOportunidades]
/// (`oportunidades_watcher.dart`), sea que la haya disparado la tarea
/// periódica de Workmanager en segundo plano o el usuario manualmente.
enum ResultadoVerificacion { exito, sinCoincidencias, error }

class EstadoVerificacion {
  final DateTime fecha;
  final ResultadoVerificacion resultado;
  final String detalle;

  const EstadoVerificacion({
    required this.fecha,
    required this.resultado,
    required this.detalle,
  });
}

const String _kFechaKey = 'mp_ultima_verificacion_fecha';
const String _kResultadoKey = 'mp_ultima_verificacion_resultado';
const String _kDetalleKey = 'mp_ultima_verificacion_detalle';

/// Guarda el resultado de la verificación que se acaba de correr, para que
/// la pantalla de configuración pueda mostrar si las revisiones en
/// segundo plano siguen funcionando (o por qué dejaron de hacerlo).
Future<void> registrarResultadoVerificacion(
  ResultadoVerificacion resultado, {
  required String detalle,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kFechaKey, DateTime.now().toIso8601String());
  await prefs.setString(_kResultadoKey, resultado.name);
  await prefs.setString(_kDetalleKey, detalle);
}

/// Devuelve el resultado de la última verificación registrada, o `null` si
/// todavía no ha corrido ninguna.
Future<EstadoVerificacion?> leerUltimaVerificacion() async {
  final prefs = await SharedPreferences.getInstance();
  final fechaStr = prefs.getString(_kFechaKey);
  final resultadoStr = prefs.getString(_kResultadoKey);
  if (fechaStr == null || resultadoStr == null) return null;

  final fecha = DateTime.tryParse(fechaStr);
  if (fecha == null) return null;

  final resultado = ResultadoVerificacion.values.firstWhere(
    (r) => r.name == resultadoStr,
    orElse: () => ResultadoVerificacion.error,
  );

  return EstadoVerificacion(
    fecha: fecha,
    resultado: resultado,
    detalle: prefs.getString(_kDetalleKey) ?? '',
  );
}
