import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/background_tasks.dart';
import '../services/mp_ticket_storage.dart';
import '../services/notification_service.dart';
import '../services/verificacion_status.dart';

const String kMpKeywordsPrefKey = 'mp_keywords';
const String kMpNotificacionesPrefKey = 'mp_notificaciones_activas';

class MercadoPublicoConfigScreen extends StatefulWidget {
  const MercadoPublicoConfigScreen({super.key});

  @override
  State<MercadoPublicoConfigScreen> createState() =>
      _MercadoPublicoConfigScreenState();
}

class _MercadoPublicoConfigScreenState
    extends State<MercadoPublicoConfigScreen> {
  final _ticketController = TextEditingController();
  final _keywordsController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _notificacionesActivas = false;
  EstadoVerificacion? _ultimaVerificacion;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ticket = await leerTicketMercadoPublico();
    final prefs = await SharedPreferences.getInstance();
    final ultimaVerificacion = await leerUltimaVerificacion();
    setState(() {
      _ticketController.text = ticket;
      _keywordsController.text = prefs.getString(kMpKeywordsPrefKey) ?? '';
      _notificacionesActivas =
          prefs.getBool(kMpNotificacionesPrefKey) ?? false;
      _ultimaVerificacion = ultimaVerificacion;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await guardarTicketMercadoPublico(_ticketController.text.trim());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        kMpKeywordsPrefKey, _keywordsController.text.trim());
    setState(() => _saving = false);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _toggleNotificaciones(bool activar) async {
    if (_keywordsController.text.trim().isEmpty && activar) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Agrega al menos una palabra clave de tu rubro antes de activar los avisos.'),
      ));
      return;
    }

    if (activar) {
      final permitido = await NotificationService.instance.solicitarPermiso();
      if (!permitido) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Sin permiso de notificaciones no podemos avisarte de oportunidades nuevas.'),
          ));
        }
        return;
      }
      await activarVerificacionPeriodica();
    } else {
      await desactivarVerificacionPeriodica();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kMpNotificacionesPrefKey, activar);
    setState(() => _notificacionesActivas = activar);
  }

  @override
  void dispose() {
    _ticketController.dispose();
    _keywordsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurar Mercado Público'),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ticket de acceso al API',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                    'El API pública de ChileCompra requiere un ticket personal '
                    'y gratuito. Solicítalo con tu Clave Única en:\n'
                    'api.mercadopublico.cl/modules/IniciarSesion.aspx\n\n'
                    'Este mismo ticket se usa tanto para Licitaciones como '
                    'para Compra Ágil. Si al activar el filtro "Solo Compra '
                    'Ágil" te sale un error de acceso, solicita un ticket '
                    'específico para ese API en chilecompra.cl/api («Pide tu '
                    'ticket»), con la misma Clave Única.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _ticketController,
                    decoration: const InputDecoration(
                      labelText: 'Ticket',
                      border: OutlineInputBorder(),
                      hintText: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('Palabras clave de tu rubro',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                    'Se usan para filtrar las oportunidades activas. '
                    'Sepáralas por coma, ej: aseo, oficina, informática',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _keywordsController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Palabras clave',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Avisarme de oportunidades nuevas',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text(
                      'Revisa Mercado Público en segundo plano (cada ~6h en '
                      'Android) y notifica solo lo nuevo que calce con tus '
                      'palabras clave. En iOS el sistema puede retrasar o '
                      'saltarse estas revisiones.',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: _notificacionesActivas,
                    activeThumbColor: const Color(0xFF6C63FF),
                    onChanged: _toggleNotificaciones,
                  ),
                  if (_ultimaVerificacion != null) ...[
                    const SizedBox(height: 4),
                    _buildUltimaVerificacion(_ultimaVerificacion!),
                  ],
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Guardar'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildUltimaVerificacion(EstadoVerificacion estado) {
    final IconData icono;
    final Color color;
    switch (estado.resultado) {
      case ResultadoVerificacion.exito:
        icono = Icons.check_circle_outline;
        color = Colors.green;
      case ResultadoVerificacion.sinCoincidencias:
        icono = Icons.check_circle_outline;
        color = Colors.grey[600]!;
      case ResultadoVerificacion.error:
        icono = Icons.error_outline;
        color = Colors.red;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, size: 14, color: color),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            'Última verificación: ${_formatearFecha(estado.fecha)} — ${estado.detalle}',
            style: TextStyle(fontSize: 12, color: color),
          ),
        ),
      ],
    );
  }

  String _formatearFecha(DateTime fecha) {
    String dosDigitos(int n) => n.toString().padLeft(2, '0');
    return '${dosDigitos(fecha.day)}/${dosDigitos(fecha.month)}/${fecha.year} '
        '${dosDigitos(fecha.hour)}:${dosDigitos(fecha.minute)}';
  }
}
