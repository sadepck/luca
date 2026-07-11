import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ocr_service.dart';
import '../services/ted_service.dart';
import 'expense_review_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final OcrService _ocrService = OcrService();
  final TedService _tedService = TedService();
  final ImagePicker _picker = ImagePicker();
  bool _processing = false;
  int _scansUsed = 0;
  static const int _freeLimit = 10;

  /// Fotos acumuladas del ticket que se está capturando. Un ticket largo
  /// (ej. boleta de supermercado) se puede armar con varias fotos, de
  /// arriba hacia abajo, antes de procesar todo junto.
  final List<String> _segmentos = [];

  @override
  void initState() {
    super.initState();
    _loadScanCount();
  }

  @override
  void dispose() {
    _ocrService.dispose();
    _tedService.dispose();
    super.dispose();
  }

  Future<void> _loadScanCount() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _scansUsed = prefs.getInt('scans_used') ?? 0;
    });
  }

  Future<void> _incrementScanCount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('scans_used', _scansUsed + 1);
    setState(() => _scansUsed++);
  }

  Future<void> _tomarFoto() async {
    if (_scansUsed >= _freeLimit) {
      _showPremiumDialog();
      return;
    }

    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image == null) return;

    setState(() => _segmentos.add(image.path));
  }

  /// Permite elegir una o varias fotos ya guardadas en el celular (por
  /// ejemplo, una factura que llegó por WhatsApp o correo) en vez de tener
  /// que sacarle una foto nueva con la cámara.
  Future<void> _elegirDeGaleria() async {
    if (_scansUsed >= _freeLimit) {
      _showPremiumDialog();
      return;
    }

    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isEmpty) return;

    setState(() => _segmentos.addAll(images.map((img) => img.path)));
  }

  void _descartarSegmentos() {
    setState(() => _segmentos.clear());
  }

  Future<void> _procesarTicket() async {
    if (_segmentos.isEmpty) return;
    setState(() => _processing = true);

    try {
      final data = _segmentos.length == 1
          ? await _ocrService.extractExpenseData(_segmentos.first)
          : await _ocrService.extractExpenseDataFromSegments(_segmentos);

      TedData? ted;
      for (final path in _segmentos) {
        ted = await _tedService.extraerTed(path);
        if (ted != null) break;
      }
      if (ted?.monto != null) {
        data['amount'] = ted!.monto;
        data['montoVerificadoSii'] = true;
        // El timbre del SII ya es el monto autoritativo: no tiene sentido
        // avisar de un descuadre contra la lectura OCR de los productos.
        data['descuadre'] = false;
        data['folio'] = ted.folio;
        data['tipoDte'] = TedData.nombreTipoDte(ted.tipoDte);
        data['rutEmisor'] = ted.rutEmisor;
      } else {
        data['montoVerificadoSii'] = false;
        // Sin timbre del SII: se usan como respaldo los datos que el OCR
        // haya podido leer directamente del texto del documento.
        data['folio'] = data['folioTexto'];
        data['tipoDte'] = data['tipoDteTexto'];
        data['rutEmisor'] = data['rutEmisorTexto'];
      }

      await _incrementScanCount();
      final segmentosCapturados = List<String>.from(_segmentos);

      if (mounted) {
        setState(() {
          _processing = false;
          _segmentos.clear();
        });
        _abrirRevision(data, segmentosCapturados);
      }
    } catch (e) {
      setState(() => _processing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al procesar la imagen')),
        );
      }
    }
  }

  Future<void> _abrirRevision(
      Map<String, dynamic> data, List<String> imagePaths) async {
    final guardado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseReviewScreen(
          imagePaths: imagePaths,
          initialTitle: data['title'] as String,
          initialAmount: (data['amount'] as num).toDouble(),
          initialCategory: data['category'] as String,
          montoVerificadoPorSii: data['montoVerificadoSii'] as bool? ?? false,
          itemsDetectados:
              (data['items'] as List<Map<String, dynamic>>?) ?? const [],
          totalCalculadoDesdeItems:
              (data['totalCalculadoDesdeItems'] as num?)?.toDouble() ?? 0,
          totalDesdeTexto: data['totalDesdeTexto'] as bool? ?? false,
          descuadre: data['descuadre'] as bool? ?? false,
          folio: data['folio'] as String?,
          tipoDte: data['tipoDte'] as String?,
          rutEmisor: data['rutEmisor'] as String?,
          nombreEmisor: data['nombreEmisor'] as String?,
          fechaDocumento: data['fechaDocumento'] as DateTime?,
          montoNeto: (data['montoNeto'] as num?)?.toDouble(),
          montoIva: (data['montoIva'] as num?)?.toDouble(),
          rawText: data['rawText'] as String?,
        ),
      ),
    );
    if (guardado == true && mounted) {
      Navigator.pop(context);
    }
  }

  void _showPremiumDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Límite alcanzado'),
        content: const Text(
            'Has usado tus 10 escaneos gratuitos. Obtén Luca Premium para escaneos ilimitados.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF)),
            child: const Text('Obtener Premium',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear ticket'),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: _processing
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Analizando ticket...'),
                ],
              )
            : _segmentos.isEmpty
                ? _buildEstadoInicial()
                : _buildEstadoCapturando(),
      ),
    );
  }

  Widget _buildEstadoInicial() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.document_scanner, size: 80, color: Colors.grey[400]),
        const SizedBox(height: 24),
        Text('Escaneos usados: $_scansUsed / $_freeLimit',
            style: TextStyle(color: Colors.grey[600])),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _tomarFoto,
          icon: const Icon(Icons.camera_alt),
          label: const Text('Tomar foto del ticket'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6C63FF),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _elegirDeGaleria,
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Subir imagen de la galería'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF6C63FF),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildEstadoCapturando() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${_segmentos.length} parte(s) capturada(s)',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            '¿El ticket sigue más abajo? Toma otra foto de la parte '
            'siguiente antes de procesarlo.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _segmentos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(_segmentos[index]),
                  width: 90,
                  height: 140,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _tomarFoto,
              icon: const Icon(Icons.add_a_photo),
              label: const Text('Agregar la parte de más abajo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _elegirDeGaleria,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Agregar desde la galería'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6C63FF),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _procesarTicket,
              icon: const Icon(Icons.check),
              label: const Text('Listo, procesar ticket'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6C63FF),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _descartarSegmentos,
            child: const Text('Descartar y empezar de nuevo'),
          ),
        ],
      ),
    );
  }
}
