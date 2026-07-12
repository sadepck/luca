import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/expense.dart';
import '../models/item_gasto.dart';
import '../services/database_service.dart';
import '../services/receipt_storage.dart';

/// Pantalla de revisión post-OCR: muestra la foto del ticket junto a los
/// campos extraídos, marca cuáles fueron editados por el usuario y avisa
/// si el gasto parece un duplicado de algo ya guardado hoy.
class ExpenseReviewScreen extends StatefulWidget {
  final List<String> imagePaths;
  final String initialTitle;
  final double initialAmount;
  final String initialCategory;
  final bool montoVerificadoPorSii;
  final List<Map<String, dynamic>> itemsDetectados;
  final double totalCalculadoDesdeItems;
  final bool totalDesdeTexto;
  final bool descuadre;
  final String? folio;
  final String? tipoDte;
  final String? rutEmisor;
  final String? nombreEmisor;
  final DateTime? fechaDocumento;
  final double? montoNeto;
  final double? montoIva;
  final String? rawText;

  const ExpenseReviewScreen({
    super.key,
    required this.imagePaths,
    required this.initialTitle,
    required this.initialAmount,
    required this.initialCategory,
    this.montoVerificadoPorSii = false,
    this.itemsDetectados = const [],
    this.totalCalculadoDesdeItems = 0,
    this.totalDesdeTexto = false,
    this.descuadre = false,
    this.folio,
    this.tipoDte,
    this.rutEmisor,
    this.nombreEmisor,
    this.fechaDocumento,
    this.montoNeto,
    this.montoIva,
    this.rawText,
  });

  @override
  State<ExpenseReviewScreen> createState() => _ExpenseReviewScreenState();
}

class _ExpenseReviewScreenState extends State<ExpenseReviewScreen> {
  static const _categorias = [
    'Comida',
    'Transporte',
    'Salud',
    'Entretenimiento',
    'Otros'
  ];

  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late String _categoria;
  late DateTime _fecha;

  bool _tituloEditado = false;
  bool _montoEditado = false;
  bool _fechaEditada = false;

  bool _buscandoDuplicado = true;
  Expense? _posibleDuplicado;
  bool _guardando = false;
  int _paginaFotoActual = 0;

  Map<String, _StatsCategoria> _statsPorCategoria = {};

  late List<Map<String, dynamic>> _items;

  double get _totalDesdeItems =>
      _items.fold(0, (sum, i) => sum + (i['precio'] as num).toDouble());

  /// Reactivo (no el [widget.descuadre] fijo del momento del escaneo):
  /// se recalcula cada vez que el usuario edita el monto o el detalle de
  /// productos, para que el aviso desaparezca apenas quede cuadrado.
  bool get _hayDescuadre {
    if (_items.isEmpty) return false;
    final monto = double.tryParse(_amountController.text) ?? 0;
    final totalItems = _totalDesdeItems;
    if (monto <= 0 || totalItems <= 0) return false;
    final tolerancia = monto * 0.05 < 100 ? 100 : monto * 0.05;
    return (monto - totalItems).abs() > tolerancia;
  }

  /// Un gasto muy por encima de lo habitual en su categoría, comparado
  /// contra tu propio historial — no es necesariamente un error del OCR
  /// (podría ser una compra grande legítima), pero vale la pena que lo
  /// confirmes antes de guardar.
  bool get _esGastoAnomalo {
    final stats = _statsPorCategoria[_categoria];
    if (stats == null || stats.cantidad < 3) return false;
    final monto = double.tryParse(_amountController.text) ?? 0;
    return monto > stats.promedio * 2.5 && monto - stats.promedio > 5000;
  }

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _amountController =
        TextEditingController(text: widget.initialAmount.toStringAsFixed(0));
    _categoria = widget.initialCategory;
    _fecha = widget.fechaDocumento ?? DateTime.now();
    _items = widget.itemsDetectados.map((m) => Map<String, dynamic>.from(m)).toList();
    _titleController.addListener(() {
      if (!_tituloEditado) setState(() => _tituloEditado = true);
    });
    _amountController.addListener(() {
      // Siempre reconstruye (no solo la primera vez): el aviso de
      // descuadre depende del monto actual en cada tecleo.
      setState(() => _montoEditado = true);
    });
    _buscarDuplicado();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _buscarDuplicado() async {
    final gastos = await DatabaseService.instance.getAllExpenses();
    final hoy = DateTime.now();
    Expense? encontrado;
    for (final g in gastos) {
      final mismoDia = g.date.year == hoy.year &&
          g.date.month == hoy.month &&
          g.date.day == hoy.day;
      if (mismoDia && (g.amount - widget.initialAmount).abs() < 1) {
        encontrado = g;
        break;
      }
    }

    final porCategoria = <String, List<double>>{};
    for (final g in gastos) {
      porCategoria.putIfAbsent(g.category, () => []).add(g.amount);
    }
    final stats = porCategoria.map((categoria, montos) => MapEntry(
        categoria,
        _StatsCategoria(
          promedio: montos.fold<double>(0, (s, m) => s + m) / montos.length,
          cantidad: montos.length,
        )));

    if (mounted) {
      setState(() {
        _posibleDuplicado = encontrado;
        _buscandoDuplicado = false;
        _statsPorCategoria = stats;
      });
    }
  }

  Future<void> _elegirFecha() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (elegida != null) {
      setState(() {
        _fecha = elegida;
        _fechaEditada = true;
      });
    }
  }

  /// Abre un diálogo con nombre, cantidad y precio unitario ya cargados
  /// para corregir un producto que el OCR haya leído mal — más confiable
  /// que reintentar la lectura automática en una foto degradada.
  Future<void> _editarItem(int index) async {
    final item = _items[index];
    final cantidadActual = (item['cantidad'] as num?)?.toDouble() ?? 1;
    final precioActual = (item['precio'] as num).toDouble();
    final unitarioActual =
        cantidadActual > 0 ? precioActual / cantidadActual : precioActual;
    final resultado = await _mostrarDialogoItem(
      titulo: 'Editar producto',
      nombreInicial: item['nombre'] as String,
      cantidadInicial: cantidadActual,
      unitarioInicial: unitarioActual,
    );
    if (resultado == null) return;
    setState(() => _items[index] = resultado);
  }

  Future<void> _agregarItemManual() async {
    final resultado = await _mostrarDialogoItem(titulo: 'Agregar producto');
    if (resultado == null) return;
    setState(() => _items.add(resultado));
  }

  void _eliminarItem(int index) {
    setState(() => _items.removeAt(index));
  }

  Future<Map<String, dynamic>?> _mostrarDialogoItem({
    required String titulo,
    String nombreInicial = '',
    double cantidadInicial = 1,
    double unitarioInicial = 0,
  }) async {
    final nombreController = TextEditingController(text: nombreInicial);
    final cantidadController = TextEditingController(
        text: cantidadInicial == cantidadInicial.roundToDouble()
            ? cantidadInicial.toStringAsFixed(0)
            : cantidadInicial.toString());
    final unitarioController = TextEditingController(
        text: unitarioInicial > 0 ? unitarioInicial.toStringAsFixed(0) : '');

    final guardar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreController,
              decoration: const InputDecoration(labelText: 'Producto'),
              autofocus: nombreInicial.isEmpty,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: cantidadController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Cantidad'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: unitarioController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Precio unitario', prefixText: '\$ '),
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
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C63FF)),
            child: const Text('Guardar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (guardar != true) return null;
    final nombre = nombreController.text.trim();
    final cantidad = double.tryParse(cantidadController.text) ?? 1;
    final unitario = double.tryParse(unitarioController.text) ?? 0;
    if (nombre.isEmpty || cantidad <= 0 || unitario <= 0) return null;

    return {
      'nombre': nombre,
      'cantidad': cantidad,
      'precio': cantidad * unitario,
    };
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    String? imagePathPersistente;
    try {
      imagePathPersistente =
          await guardarFotoTicketPersistente(widget.imagePaths.first);
    } catch (_) {
      // La foto temporal ya no está disponible (el SO la limpió antes de
      // que el usuario guardara). Mejor guardar el gasto sin foto que
      // bloquear el guardado completo por esto.
      imagePathPersistente = null;
    }
    final expense = Expense(
      title: _titleController.text.trim().isEmpty
          ? 'Compra'
          : _titleController.text.trim(),
      amount: double.tryParse(_amountController.text) ?? 0,
      category: _categoria,
      date: _fecha,
      imagePath: imagePathPersistente,
      folio: widget.folio,
      tipoDte: widget.tipoDte,
      rutEmisor: widget.rutEmisor,
      nombreEmisor: widget.nombreEmisor,
      montoNeto: widget.montoNeto,
      montoIva: widget.montoIva,
    );
    final guardado = await DatabaseService.instance.createExpense(expense);

    if (_items.isNotEmpty) {
      final items = _items
          .map((m) => ItemGasto(
                expenseId: guardado.id!,
                nombre: m['nombre'] as String,
                cantidad: (m['cantidad'] as num?)?.toDouble() ?? 1,
                precio: (m['precio'] as num).toDouble(),
              ))
          .toList();
      await DatabaseService.instance.guardarItemsGasto(guardado.id!, items);
    }

    if (mounted) Navigator.pop(context, true);
  }

  void _verFoto([int indiceInicial = 0]) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            PageView.builder(
              controller: PageController(initialPage: indiceInicial),
              itemCount: widget.imagePaths.length,
              itemBuilder: (context, index) => InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                    child: Image.file(File(widget.imagePaths[index]))),
              ),
            ),
            Positioned(
              top: 32,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirmar gasto'),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFotoPreview(),
            const SizedBox(height: 16),
            if (!_buscandoDuplicado && _posibleDuplicado != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Posible duplicado: ya tienes un gasto de '
                        '\$${_posibleDuplicado!.amount.toStringAsFixed(0)} hoy '
                        '("${_posibleDuplicado!.title}"). Revisa antes de guardar.',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            if (_hayDescuadre)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.rule, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'El monto (\$${(double.tryParse(_amountController.text) ?? 0).toStringAsFixed(0)}) '
                        'no calza con la suma de los productos '
                        '(\$${_totalDesdeItems.toStringAsFixed(0)}). '
                        'Corrige el detalle de productos de abajo o ajusta el monto.',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            if (_esGastoAnomalo)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: Colors.deepPurple.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.trending_up, color: Colors.deepPurple),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Este monto es bastante más alto que tu promedio en '
                        '$_categoria (\$${_statsPorCategoria[_categoria]!.promedio.toStringAsFixed(0)}). '
                        'Puede ser normal (una compra grande), solo revísalo antes de guardar.',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            _campoLabel('Título', _tituloEditado),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            _campoLabel('Monto', _montoEditado,
                verificadoSii: widget.montoVerificadoPorSii,
                calculadoDesdeItems: !widget.montoVerificadoPorSii &&
                    !widget.totalDesdeTexto &&
                    _items.isNotEmpty),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(), prefixText: '\$ '),
            ),
            const SizedBox(height: 16),
            _campoLabel('Fecha', _fechaEditada,
                calculadoDesdeItems:
                    !_fechaEditada && widget.fechaDocumento != null),
            InkWell(
              onTap: _elegirFecha,
              child: InputDecorator(
                decoration: const InputDecoration(border: OutlineInputBorder()),
                child: Text(
                    '${_fecha.day.toString().padLeft(2, '0')}/'
                    '${_fecha.month.toString().padLeft(2, '0')}/'
                    '${_fecha.year}'),
              ),
            ),
            const SizedBox(height: 16),
            _campoLabel('Categoría', _categoria != widget.initialCategory),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categorias.map((c) {
                final seleccionada = c == _categoria;
                return ChoiceChip(
                  label: Text(c),
                  selected: seleccionada,
                  selectedColor: const Color(0xFF6C63FF),
                  labelStyle: TextStyle(
                      color: seleccionada ? Colors.white : Colors.black87),
                  onSelected: (_) => setState(() => _categoria = c),
                );
              }).toList(),
            ),
            if (widget.folio != null ||
                widget.tipoDte != null ||
                widget.rutEmisor != null ||
                widget.nombreEmisor != null ||
                widget.montoNeto != null ||
                widget.montoIva != null) ...[
              const SizedBox(height: 24),
              const Text('Datos del documento',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                widget.montoVerificadoPorSii
                    ? 'Leído directamente del timbre electrónico del SII.'
                    : 'Detectado automáticamente del texto del documento.',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              if (widget.nombreEmisor != null)
                _filaDocumento('Empresa', widget.nombreEmisor!),
              if (widget.tipoDte != null)
                _filaDocumento('Tipo de documento', widget.tipoDte!),
              if (widget.folio != null) _filaDocumento('Folio', widget.folio!),
              if (widget.rutEmisor != null)
                _filaDocumento('RUT emisor', widget.rutEmisor!),
              if (widget.montoNeto != null)
                _filaDocumento(
                    'Monto neto', '\$${widget.montoNeto!.toStringAsFixed(0)}'),
              if (widget.montoIva != null)
                _filaDocumento(
                    'IVA', '\$${widget.montoIva!.toStringAsFixed(0)}'),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Detalle de productos',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                TextButton.icon(
                  onPressed: _agregarItemManual,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Agregar'),
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF6C63FF),
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32)),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              _items.isEmpty
                  ? 'Sin productos detectados — agrega uno si quieres llevar el detalle.'
                  : 'Toca un producto para corregir su precio unitario. Solo de '
                      'referencia: el monto de arriba es el que se usa para tus cálculos.',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            ..._items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final cantidad = (item['cantidad'] as num?)?.toDouble() ?? 1;
              final precio = (item['precio'] as num).toDouble();
              final precioUnitario = cantidad > 0 ? precio / cantidad : precio;
              return InkWell(
                onTap: () => _editarItem(index),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (cantidad != 1)
                        Container(
                          margin: const EdgeInsets.only(right: 6, top: 1),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6C63FF).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('x${cantidad.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF6C63FF))),
                        ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item['nombre'] as String,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(
                              'Valor unitario: \$${precioUnitario.toStringAsFixed(0)} c/u',
                              style:
                                  TextStyle(fontSize: 11, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                      Text('\$${precio.toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        color: Colors.grey,
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.only(left: 8),
                        onPressed: () => _eliminarItem(index),
                      ),
                    ],
                  ),
                ),
              );
            }),
            if (widget.rawText != null && widget.rawText!.trim().isNotEmpty) ...[
              const SizedBox(height: 24),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Ver texto detectado (para reportar errores)',
                    style: TextStyle(fontSize: 13)),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      widget.rawText!,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: widget.rawText!));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Copiado al portapapeles')),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copiar'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _guardando ? null : _guardar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _guardando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Guardar gasto'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFotoPreview() {
    final multiples = widget.imagePaths.length > 1;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          SizedBox(
            height: 220,
            width: double.infinity,
            child: PageView.builder(
              itemCount: widget.imagePaths.length,
              onPageChanged: (i) => setState(() => _paginaFotoActual = i),
              itemBuilder: (context, index) => GestureDetector(
                onTap: () => _verFoto(index),
                child: Image.file(
                  File(widget.imagePaths[index]),
                  width: double.infinity,
                  height: 220,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.zoom_in, color: Colors.white, size: 16),
                const SizedBox(width: 4),
                Text(
                  multiples
                      ? 'Ver ticket · ${_paginaFotoActual + 1}/${widget.imagePaths.length}'
                      : 'Ver ticket',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
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

  Widget _campoLabel(
    String label,
    bool editado, {
    bool verificadoSii = false,
    bool calculadoDesdeItems = false,
  }) {
    final mostrarVerificado = verificadoSii && !editado;
    final String texto;
    final Color color;
    if (editado) {
      texto = 'Editado por ti';
      color = const Color(0xFF6C63FF);
    } else if (mostrarVerificado) {
      texto = 'Verificado por el SII';
      color = Colors.green;
    } else if (calculadoDesdeItems) {
      texto = 'Calculado desde los productos';
      color = Colors.deepOrange;
    } else {
      texto = 'Detectado automáticamente';
      color = Colors.grey;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          if (mostrarVerificado) ...[
            Icon(Icons.verified, size: 13, color: color),
            const SizedBox(width: 2),
          ],
          Text(
            texto,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

/// Promedio y cantidad de gastos guardados en una categoría, para detectar
/// si un gasto nuevo se sale mucho de lo habitual.
class _StatsCategoria {
  final double promedio;
  final int cantidad;
  _StatsCategoria({required this.promedio, required this.cantidad});
}
