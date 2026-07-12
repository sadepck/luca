import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/ocr_telemetry.dart';

/// Pantalla de telemetría local (opt-in) de calidad del parser OCR: no
/// sube nada a ningún servidor — es solo un contador que vive en el
/// dispositivo, pensado para revisarlo junto al usuario durante el
/// período de prueba y priorizar mejoras del parser con datos reales en
/// vez de a ciegas.
class OcrTelemetriaScreen extends StatefulWidget {
  const OcrTelemetriaScreen({super.key});

  @override
  State<OcrTelemetriaScreen> createState() => _OcrTelemetriaScreenState();
}

class _OcrTelemetriaScreenState extends State<OcrTelemetriaScreen> {
  bool _loading = true;
  bool _activa = false;
  MetricasOcr _metricas = const MetricasOcr(
    totalEscaneos: 0,
    totalDescuadre: 0,
    totalMontoCero: 0,
  );

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final activa = await telemetriaOcrActiva();
    final metricas = await leerMetricasOcr();
    if (mounted) {
      setState(() {
        _activa = activa;
        _metricas = metricas;
        _loading = false;
      });
    }
  }

  Future<void> _toggleActiva(bool valor) async {
    await activarTelemetriaOcr(valor);
    setState(() => _activa = valor);
  }

  Future<void> _reiniciar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reiniciar métricas'),
        content: const Text(
            'Se borran los contadores acumulados en este dispositivo. Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reiniciar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    await reiniciarMetricasOcr();
    await _cargar();
  }

  String get _resumenTexto {
    final m = _metricas;
    return 'Calidad del parser OCR de Luca (medición local del dispositivo)\n'
        'Escaneos registrados: ${m.totalEscaneos}\n'
        'Con descuadre: ${m.totalDescuadre} (${(m.tasaDescuadre * 100).toStringAsFixed(1)}%)\n'
        'Con monto en \$0: ${m.totalMontoCero} (${(m.tasaMontoCero * 100).toStringAsFixed(1)}%)';
  }

  Future<void> _compartirResumen() async {
    await SharePlus.instance.share(ShareParams(
      text: _resumenTexto,
      subject: 'Calidad del parser OCR — Luca',
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calidad del escaneo (OCR)'),
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
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Registrar calidad de mis escaneos',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text(
                      'Guarda solo en este dispositivo si un escaneo tuvo descuadre '
                      'o quedó con monto en \$0 — nunca la foto ni el texto leído. '
                      'Nada se sube a ningún servidor.',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: _activa,
                    activeThumbColor: const Color(0xFF6C63FF),
                    onChanged: _toggleActiva,
                  ),
                  const SizedBox(height: 24),
                  if (!_activa)
                    Text(
                      'Actívalo para empezar a registrar. Puedes desactivarlo cuando quieras.',
                      style: TextStyle(color: Colors.grey[600]),
                    )
                  else ...[
                    const Text('Métricas de este dispositivo',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _filaMetrica('Escaneos registrados', '${_metricas.totalEscaneos}'),
                    _filaMetrica(
                      'Con descuadre',
                      '${_metricas.totalDescuadre} '
                          '(${(_metricas.tasaDescuadre * 100).toStringAsFixed(1)}%)',
                    ),
                    _filaMetrica(
                      'Con monto en \$0',
                      '${_metricas.totalMontoCero} '
                          '(${(_metricas.tasaMontoCero * 100).toStringAsFixed(1)}%)',
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _metricas.totalEscaneos == 0 ? null : _compartirResumen,
                        icon: const Icon(Icons.ios_share),
                        label: const Text('Compartir resumen'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: _metricas.totalEscaneos == 0 ? null : _reiniciar,
                        child: const Text('Reiniciar métricas'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _filaMetrica(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(valor, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
