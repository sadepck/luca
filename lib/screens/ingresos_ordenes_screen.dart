import 'package:flutter/material.dart';
import '../models/orden_compra_generada.dart';
import '../services/database_service.dart';

/// Lista los ingresos esperados registrados al generar órdenes de compra:
/// cada orden guarda tanto lo que se le pagará al proveedor (montoCompra)
/// como lo que se le cobrará al cliente por cumplir esa oportunidad
/// (montoIngreso), para ver de un vistazo el margen esperado de cada
/// trabajo.
class IngresosOrdenesScreen extends StatefulWidget {
  const IngresosOrdenesScreen({super.key});

  @override
  State<IngresosOrdenesScreen> createState() => _IngresosOrdenesScreenState();
}

class _IngresosOrdenesScreenState extends State<IngresosOrdenesScreen> {
  List<OrdenCompraGenerada> _ordenes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final ordenes = await DatabaseService.instance.getOrdenesCompra();
    if (mounted) {
      setState(() {
        _ordenes = ordenes;
        _loading = false;
      });
    }
  }

  double get _totalIngresos =>
      _ordenes.fold(0, (sum, o) => sum + o.montoIngreso);

  double get _totalMargen => _ordenes.fold(0, (sum, o) => sum + o.margen);

  Future<void> _eliminar(OrdenCompraGenerada orden) async {
    setState(() => _ordenes.removeWhere((o) => o.id == orden.id));
    await DatabaseService.instance.eliminarOrdenCompra(orden.id!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Ingresos por órdenes de compra'),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: _ordenes.isEmpty
                  ? _buildEmptyState()
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: [
                        _buildResumen(),
                        const SizedBox(height: 16),
                        const Text('Órdenes generadas',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        ..._ordenes.map(_buildOrdenCard),
                      ],
                    ),
            ),
    );
  }

  Widget _buildResumen() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ingreso esperado total',
              style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          Text('\$${_totalIngresos.toStringAsFixed(0)}',
              style: const TextStyle(
                  color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Margen estimado: \$${_totalMargen.toStringAsFixed(0)}',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildOrdenCard(OrdenCompraGenerada orden) {
    return Dismissible(
      key: ValueKey(orden.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => _eliminar(orden),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(orden.nombreOportunidad,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Text('\$${orden.montoIngreso.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF2E7D32))),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                  '${orden.fecha.day}/${orden.fecha.month}/${orden.fecha.year}'
                  '${orden.proveedorNombre != null ? ' · Proveedor: ${orden.proveedorNombre}' : ''}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const SizedBox(height: 4),
              Text(
                'Costo proveedor: \$${orden.montoCompra.toStringAsFixed(0)} · '
                'Margen: \$${orden.margen.toStringAsFixed(0)}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.request_quote_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('Aún no hay ingresos registrados',
              style: TextStyle(color: Colors.grey[600], fontSize: 16)),
          const SizedBox(height: 8),
          Text(
            'Genera una orden de compra desde una oportunidad de\n'
            'Mercado Público para registrar el ingreso esperado.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }
}
