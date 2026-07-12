import 'package:flutter/material.dart';
import '../models/expense.dart';
import '../models/licitacion.dart';
import '../models/oportunidad_guardada.dart';
import '../services/database_service.dart';
import 'cotizacion_screen.dart';

class OportunidadDetalleScreen extends StatefulWidget {
  final Licitacion licitacion;

  const OportunidadDetalleScreen({super.key, required this.licitacion});

  @override
  State<OportunidadDetalleScreen> createState() =>
      _OportunidadDetalleScreenState();
}

class _OportunidadDetalleScreenState extends State<OportunidadDetalleScreen> {
  bool _guardada = false;
  bool _loading = true;
  double? _promedioHistorico;
  int _totalCoincidencias = 0;
  List<Expense> _mejoresCoincidencias = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final guardada = await DatabaseService.instance
        .estaOportunidadGuardada(widget.licitacion.codigo);
    await _estimarSegunHistorial();
    setState(() {
      _guardada = guardada;
      _loading = false;
    });
  }

  /// Rankea los gastos propios por cuántas palabras relevantes (>3 letras)
  /// del nombre/descripción de la licitación comparten con el título del
  /// gasto, y se queda con los mejores. Es solo una referencia para armar
  /// una cotización, no un dato oficial.
  Future<void> _estimarSegunHistorial() async {
    final gastos = await DatabaseService.instance.getAllExpenses();
    final palabrasClave =
        '${widget.licitacion.nombre} ${widget.licitacion.descripcion ?? ''}'
            .toLowerCase()
            .split(RegExp(r'[^a-záéíóúñ0-9]+'))
            .where((p) => p.length > 3)
            .toSet();

    if (palabrasClave.isEmpty || gastos.isEmpty) return;

    final puntuados = <MapEntry<Expense, int>>[];
    for (final gasto in gastos) {
      final titulo = gasto.title.toLowerCase();
      final score = palabrasClave.where(titulo.contains).length;
      if (score > 0) puntuados.add(MapEntry(gasto, score));
    }

    if (puntuados.isEmpty) return;

    puntuados.sort((a, b) => b.value.compareTo(a.value));

    final total =
        puntuados.fold<double>(0, (sum, e) => sum + e.key.amount);
    _promedioHistorico = total / puntuados.length;
    _totalCoincidencias = puntuados.length;
    _mejoresCoincidencias =
        puntuados.take(5).map((e) => e.key).toList();
  }

  Future<void> _toggleGuardar() async {
    if (_guardada) {
      await DatabaseService.instance
          .eliminarOportunidad(widget.licitacion.codigo);
    } else {
      await DatabaseService.instance.guardarOportunidad(
          OportunidadGuardada.fromLicitacion(widget.licitacion));
    }
    setState(() => _guardada = !_guardada);
  }

  String _fmtFecha(DateTime? d) {
    if (d == null) return 'No informada';
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.licitacion;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de oportunidad'),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_guardada ? Icons.bookmark : Icons.bookmark_border),
            onPressed: _toggleGuardar,
            tooltip: _guardada ? 'Dejar de seguir' : 'Seguir oportunidad',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (l.esCompraAgil)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('Compra Ágil',
                          style: TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold)),
                    ),
                  const SizedBox(height: 8),
                  Text(l.nombre,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Código: ${l.codigo}',
                      style: TextStyle(color: Colors.grey[600])),
                  const SizedBox(height: 16),
                  if (l.descripcion != null) ...[
                    const Text('Descripción',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(l.descripcion!),
                    const SizedBox(height: 16),
                  ],
                  _infoRow('Organismo', l.organismo ?? 'No informado'),
                  _infoRow('Estado', l.estado.isEmpty ? 'No informado' : l.estado),
                  _infoRow('Rubro', l.rubro ?? 'No informado'),
                  _infoRow('Publicación', _fmtFecha(l.fechaPublicacion)),
                  _infoRow('Cierre', _fmtFecha(l.fechaCierre)),
                  if (l.montoEstimado != null)
                    _infoRow('Monto estimado',
                        '\$${l.montoEstimado!.toStringAsFixed(0)}'),
                  const SizedBox(height: 24),
                  _buildEstimacionCard(),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                CotizacionScreen(licitacion: l),
                          ),
                        );
                      },
                      icon: const Icon(Icons.request_quote_outlined),
                      label: const Text('Cotizar y generar orden de compra'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Para revisar las bases oficiales, busca este código '
                    'directamente en mercadopublico.cl.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(
                    color: Colors.grey[600], fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildEstimacionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF6C63FF).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Estimación según tu historial de gastos',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_promedioHistorico == null)
            const Text(
              'No hay suficientes gastos escaneados con productos '
              'similares para estimar un precio de referencia.',
              style: TextStyle(color: Colors.grey),
            )
          else ...[
            Text(
              'Basado en $_totalCoincidencias gasto(s) similares, el monto '
              'promedio en tu historial es \$${_promedioHistorico!.toStringAsFixed(0)}. '
              'Úsalo solo como referencia para tu cotización.',
            ),
            const SizedBox(height: 12),
            const Text('Coincidencias más relevantes',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            ..._mejoresCoincidencias.map((g) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(g.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      Text('\$${g.amount.toStringAsFixed(0)}',
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}
