import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luca/screens/scan_screen.dart';

void main() {
  group('esErrorPermisoDenegado', () {
    test('reconoce camera_access_denied como permiso denegado', () {
      expect(
        esErrorPermisoDenegado(PlatformException(code: 'camera_access_denied')),
        isTrue,
      );
    });

    test('reconoce photo_access_denied como permiso denegado', () {
      expect(
        esErrorPermisoDenegado(PlatformException(code: 'photo_access_denied')),
        isTrue,
      );
    });

    test('no confunde otros códigos de error de plataforma con permiso denegado', () {
      expect(
        esErrorPermisoDenegado(PlatformException(code: 'invalid_image')),
        isFalse,
      );
    });
  });
}
