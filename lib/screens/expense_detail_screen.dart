import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/expense.dart';
import '../models/item_gasto.dart';
import '../services/database_service.dart';

/// Detalle de un gasto ya guardado, en tres secciones: el monto total (el
/// que cuenta para los cálculos) con la foto del ticket, los datos del
/// documento tributario si se leyó el timbre del SII, y el detalle de
/// productos con cantidad y precio si el OCR alcanzó a detectarlos.
class ExpenseDetailScreen extends StatefulWidget {
  final Expense expense;

  const ExpenseDetailScreen({super.key, required this.expense});

  @override
  State<ExpenseDetailScreen> createState() => _ExpenseDetailScreenState();
}

class _ExpenseDetailScreenState extends State<ExpenseDetailScreen> {
  bool _loading = true;
  List<ItemGasto> _items = [];

  @override
  void initState() {
    super.initState();
    _cargarItems();
  }

  /// Abre el verificador oficial de documentos del SII en el navegador —
  /// nunca dentro de la app, para que el usuario ingrese su Clave Única o
  /// Clave Tributaria directamente en el sitio del SII, sin que Luca vea
  /// esa clave en ningún momento.
  Future<void> _verificarEnSii() async {
    final uri = Uri.parse('https://palena.sii.cl/cgi_dte/UPL/DTEauth?2');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _cargarItems() async {
    if (widget.expense.id == null) {
      setState(() => _loading = false);
      return;
    }
    final items =
        await DatabaseService.instance.getItemsDeGasto(widget.expense.id!);
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final expense = widget.expense;
    final tieneImagen =
        expense.imagePath != null && File(expense.imagePath!).existsSync();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del gasto'),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (tieneImagen)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(expense.imagePath!),
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 16),
            Text(expense.title,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
                '${expense.category} · ${expense.date.day}/${expense.date.month}/${expense.date.year}',
                style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF9C27B0)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Monto total',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text('\$${expense.amount.toStringAsFixed(0)}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            if (expense.folio != null ||
                expense.tipoDte != null ||
                expense.rutEmisor != null ||
                expense.nombreEmisor != null ||
                expense.montoNeto != null ||
                expense.montoIva != null) ...[
              const SizedBox(height: 24),
              const Text('Datos del documento',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (expense.nombreEmisor != null)
                      _filaDocumento('Empresa', expense.nombreEmisor!),
                    if (expense.tipoDte != null)
                      _filaDocumento('Tipo de documento', expense.tipoDte!),
                    if (expense.folio != null)
                      _filaDocumento('Folio', expense.folio!),
                    if (expense.rutEmisor != null)
                      _filaDocumento('RUT emisor', expense.rutEmisor!),
                    if (expense.montoNeto != null)
                      _filaDocumento('Monto neto',
                          '\$${expense.montoNeto!.toStringAsFixed(0)}'),
                    if (expense.montoIva != null)
                      _filaDocumento(
                          'IVA', '\$${expense.montoIva!.toStringAsFixed(0)}'),
                  ],
                ),
              ),
              if (expense.folio != null && expense.rutEmisor != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _verificarEnSii,
                    icon: const Icon(Icons.verified_outlined, size: 18),
                    label: const Text('Verificar en SII'),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Se abre el sitio oficial del SII en tu navegador — inicia '
                  'sesión ahí con tu Clave Única o Clave Tributaria (Luca '
                  'nunca ve esa clave). Ten a mano: RUT ${expense.rutEmisor}, '
                  'folio ${expense.folio}${expense.tipoDte != null ? ', ${expense.tipoDte}' : ''}, '
                  'monto \$${expense.amount.toStringAsFixed(0)}.',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ],
            const SizedBox(height: 24),
            const Text('Detalle de productos',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_items.isEmpty)
              const Text(
                'No se detectaron productos individuales en este ticket.',
                style: TextStyle(color: Colors.grey),
              )
            else
              ..._items.map((item) {
                final precioUnitario =
                    item.cantidad > 0 ? item.precio / item.cantidad : item.precio;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(item.nombre),
                    subtitle: item.cantidad != 1
                        ? Text(
                            'Cantidad: ${item.cantidad.toStringAsFixed(0)} · '
                            'Valor unitario: \$${precioUnitario.toStringAsFixed(0)} c/u')
                        : null,
                    trailing: Text('\$${item.precio.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _filaDocumento(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ),
          Expanded(child: Text(valor, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
