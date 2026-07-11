import 'package:flutter/material.dart';
import 'expense_detail_screen.dart';
import 'proveedores_screen.dart';

/// Detalle de un proveedor: total gastado, cantidad de compras y el
/// listado de gastos asociados, ordenados del más reciente al más
/// antiguo.
class ProveedorDetalleScreen extends StatelessWidget {
  final ResumenProveedor proveedor;

  const ProveedorDetalleScreen({super.key, required this.proveedor});

  @override
  Widget build(BuildContext context) {
    final gastos = [...proveedor.gastos]..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(proveedor.nombre, overflow: TextOverflow.ellipsis),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF9C27B0)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total gastado',
                    style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 8),
                Text('\$${proveedor.totalGastado.toStringAsFixed(0)}',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  '${proveedor.cantidadCompras} compra(s) · última el '
                  '${proveedor.ultimaCompra.day}/${proveedor.ultimaCompra.month}/${proveedor.ultimaCompra.year}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          if (proveedor.rut != null) ...[
            const SizedBox(height: 12),
            Text('RUT: ${proveedor.rut}',
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ],
          const SizedBox(height: 20),
          const Text('Historial de compras',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...gastos.map((g) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(g.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${g.category} · ${g.date.day}/${g.date.month}/${g.date.year}'),
                  trailing: Text('\$${g.amount.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  onTap: () {
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => ExpenseDetailScreen(expense: g)));
                  },
                ),
              )),
        ],
      ),
    );
  }
}
