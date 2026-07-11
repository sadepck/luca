import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/item_cotizacion.dart';
import '../models/licitacion.dart';
import '../models/orden_compra_generada.dart';
import '../services/database_service.dart';

const String kProveedorNombrePrefKey = 'proveedor_nombre';
const String kProveedorRutPrefKey = 'proveedor_rut';

/// Genera el borrador de orden de compra a partir de la cotización armada
/// por el usuario, para que la envíe al organismo comprador. No emite un
/// documento tributario ni se conecta a ningún sistema del SII/ChileCompra
/// — es un borrador de texto compartible.
class OrdenCompraScreen extends StatefulWidget {
  final Licitacion licitacion;
  final List<ItemCotizacion> items;

  const OrdenCompraScreen({
    super.key,
    required this.licitacion,
    required this.items,
  });

  @override
  State<OrdenCompraScreen> createState() => _OrdenCompraScreenState();
}

class _OrdenCompraScreenState extends State<OrdenCompraScreen> {
  final _nombreController = TextEditingController();
  final _rutController = TextEditingController();
  final _montoIngresoController = TextEditingController();
  bool _loading = true;
  bool _guardando = false;
  DateTime? _fechaPagoEsperada;

  double get _total => widget.items.fold(0, (sum, i) => sum + i.subtotal);

  @override
  void initState() {
    super.initState();
    _cargarDatosProveedor();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _rutController.dispose();
    _montoIngresoController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatosProveedor() async {
    final prefs = await SharedPreferences.getInstance();
    _nombreController.text = prefs.getString(kProveedorNombrePrefKey) ?? '';
    _rutController.text = prefs.getString(kProveedorRutPrefKey) ?? '';
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _elegirFechaPago() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (elegida != null) setState(() => _fechaPagoEsperada = elegida);
  }

  Future<void> _guardarDatosProveedor() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kProveedorNombrePrefKey, _nombreController.text.trim());
    await prefs.setString(kProveedorRutPrefKey, _rutController.text.trim());
  }

  String _generarTexto() {
    final l = widget.licitacion;
    final hoy = DateTime.now();
    final fecha = '${hoy.day.toString().padLeft(2, '0')}/'
        '${hoy.month.toString().padLeft(2, '0')}/${hoy.year}';

    final buffer = StringBuffer();
    buffer.writeln('ORDEN DE COMPRA (borrador)');
    buffer.writeln('Fecha: $fecha');
    buffer.writeln();
    if (_nombreController.text.trim().isNotEmpty) {
      buffer.writeln('Proveedor: ${_nombreController.text.trim()}');
    }
    if (_rutController.text.trim().isNotEmpty) {
      buffer.writeln('RUT: ${_rutController.text.trim()}');
    }
    buffer.writeln();
    buffer.writeln('Oportunidad: ${l.nombre}');
    buffer.writeln('Código: ${l.codigo}');
    if (l.organismo != null) buffer.writeln('Organismo: ${l.organismo}');
    buffer.writeln();
    buffer.writeln('Ítems:');
    for (var i = 0; i < widget.items.length; i++) {
      final item = widget.items[i];
      buffer.writeln(
          '${i + 1}. ${item.nombre} x${item.cantidad.toStringAsFixed(0)} '
          '— \$${item.precioUnitario.toStringAsFixed(0)} c/u = '
          '\$${item.subtotal.toStringAsFixed(0)}');
    }
    buffer.writeln();
    buffer.writeln('TOTAL: \$${_total.toStringAsFixed(0)}');
    buffer.writeln();
    buffer.writeln('Generado con la app Luca.');
    return buffer.toString();
  }

  Future<void> _compartir() async {
    await _guardarDatosProveedor();
    await SharePlus.instance.share(
      ShareParams(
        text: _generarTexto(),
        subject: 'Orden de compra - ${widget.licitacion.codigo}',
      ),
    );
  }

  Future<void> _copiar() async {
    await _guardarDatosProveedor();
    await Clipboard.setData(ClipboardData(text: _generarTexto()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copiado al portapapeles')),
      );
    }
  }

  /// Guarda la orden y registra el ingreso esperado por cumplir esta
  /// oportunidad: el total de la orden (_total) es lo que se le pagará al
  /// proveedor (un gasto futuro), así que el ingreso se pide aparte — es
  /// lo que el organismo/cliente le pagará a la empresa por el trabajo.
  Future<void> _guardarOrden() async {
    final montoIngreso = double.tryParse(_montoIngresoController.text);
    if (montoIngreso == null || montoIngreso <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Ingresa cuánto le cobrarás al cliente por este trabajo')),
      );
      return;
    }

    setState(() => _guardando = true);
    await _guardarDatosProveedor();
    await DatabaseService.instance.crearOrdenCompra(OrdenCompraGenerada(
      codigoOportunidad: widget.licitacion.codigo,
      nombreOportunidad: widget.licitacion.nombre,
      proveedorNombre: _nombreController.text.trim().isEmpty
          ? null
          : _nombreController.text.trim(),
      proveedorRut:
          _rutController.text.trim().isEmpty ? null : _rutController.text.trim(),
      montoCompra: _total,
      montoIngreso: montoIngreso,
      fecha: DateTime.now(),
      fechaPagoEsperada: _fechaPagoEsperada,
    ));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Orden guardada e ingreso registrado')),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Orden de compra'),
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
                  const Text('Datos del proveedor',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nombreController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre o razón social',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _rutController,
                    decoration: const InputDecoration(
                      labelText: 'RUT',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 24),
                  const Text('Ingreso esperado',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(
                    'El total de arriba (\$${_total.toStringAsFixed(0)}) es lo que le '
                    'pagarás al proveedor. Registra aparte cuánto le cobrarás tú al '
                    'cliente por cumplir esta oportunidad.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _montoIngresoController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Monto a cobrar al cliente',
                      border: OutlineInputBorder(),
                      prefixText: '\$ ',
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _elegirFechaPago,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: '¿Cuándo esperas que te paguen? (opcional)',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today, size: 18),
                      ),
                      child: Text(
                        _fechaPagoEsperada == null
                            ? 'Sin definir'
                            : '${_fechaPagoEsperada!.day.toString().padLeft(2, '0')}/'
                                '${_fechaPagoEsperada!.month.toString().padLeft(2, '0')}/'
                                '${_fechaPagoEsperada!.year}',
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Si la defines, este ingreso se muestra en el día '
                    'correspondiente dentro de Flujo de Caja.',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 24),
                  const Text('Vista previa',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      _generarTexto(),
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _copiar,
                          icon: const Icon(Icons.copy),
                          label: const Text('Copiar'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _compartir,
                          icon: const Icon(Icons.share),
                          label: const Text('Compartir'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6C63FF),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _guardando ? null : _guardarOrden,
                      icon: _guardando
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: const Text('Guardar orden y registrar ingreso'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
