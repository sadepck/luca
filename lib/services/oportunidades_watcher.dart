import 'package:shared_preferences/shared_preferences.dart';
import '../models/licitacion.dart';
import '../screens/mercado_publico_config_screen.dart'
    show kMpTicketPrefKey, kMpKeywordsPrefKey;
import 'database_service.dart';
import 'mercado_publico_service.dart';
import 'notification_service.dart';

/// Revisa las licitaciones activas de Mercado Público, las cruza con las
/// palabras clave del rubro del usuario y notifica solo las que no se
/// habían visto antes. La usan tanto la pantalla principal (al refrescar)
/// como la tarea periódica de Workmanager en segundo plano.
Future<int> verificarNuevasOportunidades() async {
  final prefs = await SharedPreferences.getInstance();
  final ticket = prefs.getString(kMpTicketPrefKey) ?? '';
  final palabrasClave = (prefs.getString(kMpKeywordsPrefKey) ?? '')
      .split(',')
      .map((p) => p.trim().toLowerCase())
      .where((p) => p.isNotEmpty)
      .toList();

  if (ticket.isEmpty || palabrasClave.isEmpty) return 0;

  final service = MercadoPublicoService();
  List<Licitacion> activas;
  try {
    activas = await service.buscarActivas(ticket);
  } catch (_) {
    return 0;
  }

  final coincidentes = activas.where((licitacion) {
    final texto =
        '${licitacion.nombre} ${licitacion.descripcion ?? ''}'.toLowerCase();
    return palabrasClave.any((p) => texto.contains(p));
  }).toList();

  if (coincidentes.isEmpty) return 0;

  final codigos = coincidentes.map((l) => l.codigo).toList();
  final nuevos = await DatabaseService.instance.filtrarNoVistas(codigos);

  if (nuevos.isEmpty) return 0;

  await NotificationService.instance.mostrarNuevasOportunidades(nuevos.length);
  await DatabaseService.instance.marcarComoVistas(nuevos);

  return nuevos.length;
}
