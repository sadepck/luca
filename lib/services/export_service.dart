import 'dart:convert';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import '../models/expense.dart';

/// Arma un CSV con el detalle de gastos (se abre en Excel/Sheets) y lo
/// comparte como archivo — no depende de ningún paquete de CSV externo,
/// el formato es simple y ya se controla el escape de comas/comillas acá.
Future<void> exportarGastosCsv(List<Expense> gastos) async {
  final buffer = StringBuffer();
  buffer.writeln([
    'Fecha',
    'Título',
    'Categoría',
    'Monto',
    'Empresa',
    'RUT emisor',
    'Tipo documento',
    'Folio',
    'Monto neto',
    'IVA',
  ].map(_csvEscape).join(','));

  for (final g in gastos) {
    buffer.writeln([
      '${g.date.year.toString().padLeft(4, '0')}-'
          '${g.date.month.toString().padLeft(2, '0')}-'
          '${g.date.day.toString().padLeft(2, '0')}',
      g.title,
      g.category,
      g.amount.toStringAsFixed(0),
      g.nombreEmisor ?? '',
      g.rutEmisor ?? '',
      g.tipoDte ?? '',
      g.folio ?? '',
      g.montoNeto?.toStringAsFixed(0) ?? '',
      g.montoIva?.toStringAsFixed(0) ?? '',
    ].map(_csvEscape).join(','));
  }

  final fecha = DateTime.now();
  final nombreArchivo = 'gastos_luca_'
      '${fecha.year}${fecha.month.toString().padLeft(2, '0')}${fecha.day.toString().padLeft(2, '0')}.csv';
  final archivo = File('${Directory.systemTemp.path}/$nombreArchivo');
  // BOM UTF-8 al inicio para que Excel reconozca tildes/ñ correctamente.
  await archivo.writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(buffer.toString())]);

  await SharePlus.instance.share(ShareParams(
    files: [XFile(archivo.path)],
    subject: 'Gastos exportados de Luca',
  ));
}

String _csvEscape(String valor) {
  if (valor.contains(',') || valor.contains('"') || valor.contains('\n')) {
    return '"${valor.replaceAll('"', '""')}"';
  }
  return valor;
}
