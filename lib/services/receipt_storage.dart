import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Se combina con el timestamp para armar el nombre del archivo destino:
/// la resolución real del reloj del sistema varía por plataforma, así que
/// el timestamp solo no garantiza nombres únicos si se guardan dos fotos
/// en el mismo tick.
int _contadorNombres = 0;

/// Copia la foto de un ticket desde la ruta temporal que entrega
/// `image_picker` (caché del sistema operativo, que puede limpiarse) a un
/// subdirectorio propio de la app dentro de `getApplicationDocumentsDirectory()`,
/// para que la evidencia del gasto no se pierda con el tiempo. Devuelve la
/// ruta persistente que debe guardarse en `Expense.imagePath`.
///
/// [baseDir] permite inyectar el directorio base en los tests, sin
/// depender del canal de plataforma de `path_provider`.
Future<String> guardarFotoTicketPersistente(
  String rutaTemporal, {
  Directory? baseDir,
}) async {
  final base = baseDir ?? await getApplicationDocumentsDirectory();
  final ticketsDir = Directory(p.join(base.path, 'tickets'));
  if (!await ticketsDir.exists()) {
    await ticketsDir.create(recursive: true);
  }
  final nombreArchivo = '${DateTime.now().microsecondsSinceEpoch}'
      '_${_contadorNombres++}${p.extension(rutaTemporal)}';
  final destino = p.join(ticketsDir.path, nombreArchivo);
  await File(rutaTemporal).copy(destino);
  return destino;
}

/// Elimina el archivo de foto de un gasto, si existe. No falla si [path]
/// es null o el archivo ya no está (para no romper el flujo de borrado
/// por una foto que ya se perdió).
Future<void> eliminarFotoTicket(String? path) async {
  if (path == null) return;
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}
