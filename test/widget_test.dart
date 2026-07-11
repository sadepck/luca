import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:luca/main.dart';

void main() {
  setUpAll(() {
    // HomeScreen consulta sqflite en initState; en el entorno de test no hay
    // una implementación nativa de plataforma, así que usamos la versión FFI.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('La app arranca y muestra la pantalla principal',
      (WidgetTester tester) async {
    await tester.pumpWidget(const LucaApp());
    await tester.pump();

    expect(find.text('Luca'), findsOneWidget);
    expect(find.text('Escanear ticket'), findsOneWidget);
  });
}
