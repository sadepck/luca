import 'package:shared_preferences/shared_preferences.dart';
import '../models/licitacion.dart';
import '../screens/mercado_publico_config_screen.dart' show kMpKeywordsPrefKey;
import 'database_service.dart';
import 'mercado_publico_service.dart';
import 'mp_ticket_storage.dart';
import 'notification_service.dart';
import 'verificacion_status.dart';

/// Revisa las licitaciones activas de Mercado Público, las cruza con las
/// palabras clave del rubro del usuario y notifica solo las que no se
/// habían visto antes. La usan tanto la pantalla principal (al refrescar)
/// como la tarea periódica de Workmanager en segundo plano.
///
/// [ticketStore] permite inyectar un almacenamiento seguro fake en los
/// tests; en producción siempre se usa el real (Keystore/Keychain).
/// [service] permite inyectar un [MercadoPublicoService] fake en los
/// tests, para poder ejercitar los caminos de éxito/error sin red real.
/// [notificar] permite inyectar un callback fake en los tests, para no
/// depender del canal de plataforma real de `flutter_local_notifications`.
Future<int> verificarNuevasOportunidades({
  TicketSecureStore? ticketStore,
  MercadoPublicoService? service,
  Future<void> Function(int cantidad)? notificar,
}) async {
  final ticket = await leerTicketMercadoPublico(store: ticketStore);
  final prefs = await SharedPreferences.getInstance();
  final palabrasClave = (prefs.getString(kMpKeywordsPrefKey) ?? '')
      .split(',')
      .map((p) => p.trim().toLowerCase())
      .where((p) => p.isNotEmpty)
      .toList();

  if (ticket.isEmpty || palabrasClave.isEmpty) return 0;

  final mpService = service ?? MercadoPublicoService();
  List<Licitacion> activas;
  try {
    activas = await mpService.buscarActivas(ticket);
  } catch (e) {
    await registrarResultadoVerificacion(ResultadoVerificacion.error,
        detalle: e.toString());
    return 0;
  }

  final coincidentes = activas
      .where((licitacion) => coincideConPalabrasClave(licitacion, palabrasClave))
      .toList();

  final codigos = coincidentes.map((l) => l.codigo).toList();
  final nuevos = await DatabaseService.instance.filtrarNoVistas(codigos);

  if (nuevos.isEmpty) {
    await registrarResultadoVerificacion(ResultadoVerificacion.sinCoincidencias,
        detalle: 'Sin oportunidades nuevas');
    return 0;
  }

  final avisar = notificar ?? NotificationService.instance.mostrarNuevasOportunidades;
  await avisar(nuevos.length);
  await DatabaseService.instance.marcarComoVistas(nuevos);

  await registrarResultadoVerificacion(ResultadoVerificacion.exito,
      detalle: '${nuevos.length} oportunidad${nuevos.length == 1 ? '' : 'es'} nueva${nuevos.length == 1 ? '' : 's'}');

  return nuevos.length;
}

/// Compara, sin distinguir mayúsculas/minúsculas, si alguna [palabrasClave]
/// aparece en el nombre o la descripción de [licitacion]. Extraída como
/// función pura para poder testearla sin depender del API ni de la base
/// de datos.
bool coincideConPalabrasClave(Licitacion licitacion, List<String> palabrasClave) {
  final texto =
      '${licitacion.nombre} ${licitacion.descripcion ?? ''}'.toLowerCase();
  return palabrasClave.any((p) => texto.contains(p));
}
