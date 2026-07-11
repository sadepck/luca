import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/item_cotizacion.dart';
import '../models/licitacion.dart';
import '../services/database_service.dart';
import '../services/enlaces_compra_service.dart';
import 'orden_compra_screen.dart';

/// Arma la cotización a mano para responder una oportunidad de Mercado
/// Público / Compra Ágil: el usuario agrega los productos que necesita
/// cotizar, puede abrir enlaces de búsqueda reales para comparar precios
/// de proveedores, y al final genera la orden de compra con el total.
class CotizacionScreen extends StatefulWidget {
  final Licitacion licitacion;

  const CotizacionScreen({super.key, required this.licitacion});

  @override
  State<CotizacionScreen> createState() => _CotizacionScreenState();
}

class _CotizacionScreenState extends State<CotizacionScreen> {
  final _ciudadController = TextEditingController();
  bool _loading = true;
  List<ItemCotizacion> _items = [];

  double get _total => _items.fold(0, (sum, i) => sum + i.subtotal);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _ciudadController.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final items = await DatabaseService.instance
        .getItemsCotizacion(widget.licitacion.codigo);
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  Future<void> _agregarItem() async {
    final nombreController = TextEditingController();
    final cantidadController = TextEditingController(text: '1');
    final precioController = TextEditingController();

    final guardar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar producto'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreController,
              decoration: const InputDecoration(labelText: 'Producto'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: cantidadController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Cantidad'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: precioController,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Precio unitario'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF)),
            child:
                const Text('Agregar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (guardar != true) return;

    final cantidad = double.tryParse(cantidadController.text);
    final precio = double.tryParse(precioController.text);
    if (nombreController.text.trim().isEmpty ||
        cantidad == null ||
        precio == null) {
      return;
    }

    await DatabaseService.instance.guardarItemCotizacion(ItemCotizacion(
      codigoOportunidad: widget.licitacion.codigo,
      nombre: nombreController.text.trim(),
      cantidad: cantidad,
      precioUnitario: precio,
    ));
    _cargar();
  }

  Future<void> _eliminarItem(ItemCotizacion item) async {
    await DatabaseService.instance.eliminarItemCotizacion(item.id!);
    _cargar();
  }

  void _mostrarEnlaces(String producto) {
    final enlaces =
        generarEnlacesBusqueda(producto, _ciudadController.text);
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Buscar "$producto"',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            ...enlaces.map((e) => ListTile(
                  leading: const Icon(Icons.open_in_new),
                  title: Text(e.tienda),
                  onTap: () async {
                    Navigator.pop(context);
                    final uri = Uri.parse(e.url);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    }
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Cotización'),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _ciudadController,
                    decoration: const InputDecoration(
                      labelText: 'Ciudad para buscar proveedores',
                      hintText: 'ej: Concepción',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                  ),
                ),
                Expanded(
                  child: _items.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Agrega los productos que necesitas cotizar '
                              'para responder "${widget.licitacion.nombre}".',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text(item.nombre),
                                subtitle: Text(
                                    '${item.cantidad.toStringAsFixed(0)} x \$${item.precioUnitario.toStringAsFixed(0)} = \$${item.subtotal.toStringAsFixed(0)}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.search),
                                      tooltip: 'Buscar proveedores',
                                      onPressed: () =>
                                          _mostrarEnlaces(item.nombre),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => _eliminarItem(item),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 8,
                          offset: const Offset(0, -2)),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          Text('\$${_total.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _agregarItem,
                              icon: const Icon(Icons.add),
                              label: const Text('Agregar producto'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _items.isEmpty
                                  ? null
                                  : () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => OrdenCompraScreen(
                                            licitacion: widget.licitacion,
                                            items: _items,
                                          ),
                                        ),
                                      );
                                    },
                              icon: const Icon(Icons.description_outlined),
                              label: const Text('Generar orden'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6C63FF),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
