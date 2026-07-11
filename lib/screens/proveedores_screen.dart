import 'package:flutter/material.dart';
import '../models/expense.dart';
import '../services/database_service.dart';
import 'proveedor_detalle_screen.dart';

/// Un proveedor (comercio/empresa emisora) agrupado a partir de los datos
/// que ya se extraen de cada boleta escaneada — no es una tabla nueva ni
/// algo que el usuario tenga que crear a mano, se arma solo del
/// historial de gastos.
class ResumenProveedor {
  final String clave;
  final String nombre;
  final String? rut;
  final List<Expense> gastos;

  ResumenProveedor({
    required this.clave,
    required this.nombre,
    required this.rut,
    required this.gastos,
  });

  double get totalGastado => gastos.fold(0, (sum, g) => sum + g.amount);
  int get cantidadCompras => gastos.length;
  DateTime get ultimaCompra =>
      gastos.map((g) => g.date).reduce((a, b) => a.isAfter(b) ? a : b);
}

/// Agrupa los gastos por empresa emisora (RUT si está disponible, si no
/// por nombre) — solo cuenta gastos que tengan al menos uno de los dos
/// datos; boletas sin empresa identificada no forman un "proveedor".
List<ResumenProveedor> agruparPorProveedor(List<Expense> gastos) {
  final grupos = <String, List<Expense>>{};
  for (final g in gastos) {
    final clave = g.rutEmisor ?? g.nombreEmisor;
    if (clave == null) continue;
    grupos.putIfAbsent(clave, () => []).add(g);
  }

  final resultado = grupos.entries.map((entry) {
    final gastosDelGrupo = entry.value;
    final conNombre = gastosDelGrupo.firstWhere(
      (g) => g.nombreEmisor != null,
      orElse: () => gastosDelGrupo.first,
    );
    return ResumenProveedor(
      clave: entry.key,
      nombre: conNombre.nombreEmisor ?? entry.key,
      rut: gastosDelGrupo.firstWhere((g) => g.rutEmisor != null,
              orElse: () => gastosDelGrupo.first)
          .rutEmisor,
      gastos: gastosDelGrupo,
    );
  }).toList();

  resultado.sort((a, b) => b.totalGastado.compareTo(a.totalGastado));
  return resultado;
}

class ProveedoresScreen extends StatefulWidget {
  const ProveedoresScreen({super.key});

  @override
  State<ProveedoresScreen> createState() => _ProveedoresScreenState();
}

class _ProveedoresScreenState extends State<ProveedoresScreen> {
  bool _loading = true;
  List<ResumenProveedor> _proveedores = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final gastos = await DatabaseService.instance.getAllExpenses();
    if (!mounted) return;
    setState(() {
      _proveedores = agruparPorProveedor(gastos);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Proveedores'),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _proveedores.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Aún no hay proveedores — se arman solos a medida que '
                      'escaneas boletas donde se identifica la empresa emisora.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _proveedores.length,
                    itemBuilder: (context, index) {
                      final p = _proveedores[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0x1A6C63FF),
                            child: Icon(Icons.storefront_outlined,
                                color: Color(0xFF6C63FF)),
                          ),
                          title: Text(p.nombre,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              '${p.cantidadCompras} compra(s)'
                              '${p.rut != null ? ' · RUT ${p.rut}' : ''}'),
                          trailing: Text('\$${p.totalGastado.toStringAsFixed(0)}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ProveedorDetalleScreen(proveedor: p),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
