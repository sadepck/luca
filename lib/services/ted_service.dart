import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

/// Datos extraídos del Timbre Electrónico (TED) de un documento tributario
/// electrónico chileno (boleta/factura).
class TedData {
  final double? monto;
  final DateTime? fechaEmision;
  final String? rutEmisor;
  final String? primerItem;
  final String? folio;
  final String? tipoDte;

  TedData({
    this.monto,
    this.fechaEmision,
    this.rutEmisor,
    this.primerItem,
    this.folio,
    this.tipoDte,
  });

  /// Nombre legible del tipo de documento (código TD del TED).
  /// https://www.sii.cl - códigos de tipo de DTE más comunes.
  static String? nombreTipoDte(String? codigo) {
    switch (codigo) {
      case '33':
        return 'Factura electrónica';
      case '34':
        return 'Factura no afecta o exenta electrónica';
      case '39':
        return 'Boleta electrónica';
      case '41':
        return 'Boleta exenta electrónica';
      case '52':
        return 'Guía de despacho electrónica';
      case '56':
        return 'Nota de débito electrónica';
      case '61':
        return 'Nota de crédito electrónica';
      default:
        return codigo == null ? null : 'Documento tipo $codigo';
    }
  }
}

/// Decodifica el código de barras PDF417 (Timbre Electrónico del SII) que
/// traen algunas boletas y facturas chilenas. Es una sección XML firmada
/// pero NO cifrada (formato `<TED><DD><RE>...</RE><MNT>...</MNT>...</DD>
/// <FRMT>...</FRMT></TED>`), así que sus campos se pueden leer directamente
/// sin validar la firma digital.
///
/// Nota: desde el 1 de enero de 2026 (Resolución Exenta SII N°207) imprimir
/// este timbre en la representación impresa de la boleta pasó a ser
/// opcional, así que cada vez más tickets no lo traerán. Por eso esto debe
/// tratarse siempre como un complemento del OCR, nunca como reemplazo.
class TedService {
  final _scanner = BarcodeScanner(formats: [BarcodeFormat.pdf417]);

  Future<TedData?> extraerTed(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    List<Barcode> barcodes;
    try {
      barcodes = await _scanner.processImage(inputImage);
    } catch (_) {
      return null;
    }

    for (final barcode in barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || !raw.contains('<TED')) continue;
      final ted = _parseTed(raw);
      if (ted != null) return ted;
    }
    return null;
  }

  TedData? _parseTed(String xml) {
    final monto = _extraerTag(xml, 'MNT');
    if (monto == null) return null;

    final montoNum = double.tryParse(monto);
    if (montoNum == null) return null;

    final fecha = _extraerTag(xml, 'FE');
    return TedData(
      monto: montoNum,
      fechaEmision: fecha != null ? DateTime.tryParse(fecha) : null,
      rutEmisor: _extraerTag(xml, 'RE'),
      primerItem: _extraerTag(xml, 'IT1'),
      folio: _extraerTag(xml, 'F'),
      tipoDte: _extraerTag(xml, 'TD'),
    );
  }

  String? _extraerTag(String xml, String tag) {
    final match = RegExp('<$tag>([^<]*)</$tag>').firstMatch(xml);
    return match?.group(1);
  }

  void dispose() {
    _scanner.close();
  }
}
