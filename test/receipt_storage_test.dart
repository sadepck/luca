import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:luca/services/receipt_storage.dart';

void main() {
  late Directory tempDir;
  late Directory appDocsDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('luca_receipt_test_');
    appDocsDir = Directory(p.join(tempDir.path, 'app_docs'))..createSync();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('guardarFotoTicketPersistente', () {
    test('copia la foto a un subdirectorio "tickets" dentro del directorio de la app', () async {
      final origen = File(p.join(tempDir.path, 'temp_picker.jpg'))
        ..writeAsBytesSync([1, 2, 3, 4]);

      final destino = await guardarFotoTicketPersistente(origen.path, baseDir: appDocsDir);

      expect(p.dirname(destino), p.join(appDocsDir.path, 'tickets'));
      expect(await File(destino).exists(), isTrue);
      expect(await File(destino).readAsBytes(), [1, 2, 3, 4]);
    });

    test('preserva la extensión del archivo original', () async {
      final origen = File(p.join(tempDir.path, 'foto.png'))..writeAsBytesSync([9]);

      final destino = await guardarFotoTicketPersistente(origen.path, baseDir: appDocsDir);

      expect(p.extension(destino), '.png');
    });

    test('el archivo original no se modifica (se copia, no se mueve)', () async {
      final origen = File(p.join(tempDir.path, 'temp_picker.jpg'))
        ..writeAsBytesSync([1, 2, 3]);

      await guardarFotoTicketPersistente(origen.path, baseDir: appDocsDir);

      expect(await origen.exists(), isTrue);
    });

    test('dos fotos guardadas en el mismo instante lógico no se pisan entre sí', () async {
      final origenA = File(p.join(tempDir.path, 'a.jpg'))..writeAsBytesSync([1]);
      final origenB = File(p.join(tempDir.path, 'b.jpg'))..writeAsBytesSync([2]);

      final destinoA = await guardarFotoTicketPersistente(origenA.path, baseDir: appDocsDir);
      final destinoB = await guardarFotoTicketPersistente(origenB.path, baseDir: appDocsDir);

      expect(destinoA, isNot(destinoB));
      expect(await File(destinoA).readAsBytes(), [1]);
      expect(await File(destinoB).readAsBytes(), [2]);
    });

    test('una ráfaga de fotos guardadas en secuencia nunca genera nombres repetidos', () async {
      final origen = File(p.join(tempDir.path, 'ráfaga.jpg'))..writeAsBytesSync([7]);

      final destinos = <String>[];
      for (var i = 0; i < 50; i++) {
        destinos.add(await guardarFotoTicketPersistente(origen.path, baseDir: appDocsDir));
      }

      expect(destinos.toSet(), hasLength(50),
          reason: 'el contador de proceso debe evitar colisiones aunque el timestamp se repita');
    });

    test('con un archivo origen inexistente, propaga la excepción (el llamador decide el fallback)', () async {
      final origenInexistente = p.join(tempDir.path, 'no_existe.jpg');

      expect(
        () => guardarFotoTicketPersistente(origenInexistente, baseDir: appDocsDir),
        throwsA(isA<PathNotFoundException>()),
      );
    });
  });

  group('eliminarFotoTicket', () {
    test('elimina el archivo si existe', () async {
      final foto = File(p.join(tempDir.path, 'foto.jpg'))..writeAsBytesSync([1]);

      await eliminarFotoTicket(foto.path);

      expect(await foto.exists(), isFalse);
    });

    test('no falla si el path es null', () async {
      await eliminarFotoTicket(null);
    });

    test('no falla si el archivo ya no existe', () async {
      final pathInexistente = p.join(tempDir.path, 'no_existe.jpg');

      await eliminarFotoTicket(pathInexistente);
    });
  });
}
