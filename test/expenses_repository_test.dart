import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:luca/models/expense.dart';
import 'package:luca/services/database_service.dart';
import 'package:luca/services/expenses_repository.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('luca_expenses_repo_test_');
    await DatabaseService.instance.openForTesting(join(tempDir.path, 'repo.db'));
  });

  tearDown(() async {
    ExpensesRepository.resetForTesting();
    await DatabaseService.resetForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('cargar', () {
    test('antes de cargar, expenses está vacío y cargado es false', () {
      expect(ExpensesRepository.instance.expenses, isEmpty);
      expect(ExpensesRepository.instance.cargado, isFalse);
    });

    test('trae los gastos de la base de datos y marca cargado como true', () async {
      await DatabaseService.instance.createExpense(Expense(
        title: 'Bencina',
        amount: 15000,
        category: 'Transporte',
        date: DateTime(2026, 3, 1),
      ));

      await ExpensesRepository.instance.cargar();

      expect(ExpensesRepository.instance.cargado, isTrue);
      expect(ExpensesRepository.instance.expenses, hasLength(1));
      expect(ExpensesRepository.instance.expenses.first.title, 'Bencina');
    });

    test('notifica a los listeners', () async {
      var notificaciones = 0;
      ExpensesRepository.instance.addListener(() => notificaciones++);

      await ExpensesRepository.instance.cargar();

      expect(notificaciones, 1);
    });

    test('expenses es inmutable desde afuera (no se puede mutar el estado interno)', () async {
      await ExpensesRepository.instance.cargar();

      expect(() => ExpensesRepository.instance.expenses.add(Expense(
            title: 'x',
            amount: 1,
            category: 'Otros',
            date: DateTime.now(),
          )), throwsUnsupportedError);
    });
  });

  group('crear', () {
    test('guarda el gasto en la DB y actualiza expenses tras la creación', () async {
      final creado = await ExpensesRepository.instance.crear(Expense(
        title: 'Supermercado',
        amount: 8000,
        category: 'Otros',
        date: DateTime(2026, 3, 1),
      ));

      expect(creado.id, isNotNull);
      expect(ExpensesRepository.instance.cargado, isTrue);
      expect(ExpensesRepository.instance.expenses, hasLength(1));
      expect(ExpensesRepository.instance.porId(creado.id), isNotNull);
    });
  });

  group('eliminar', () {
    test('quita el gasto de expenses de forma optimista, antes de esperar la DB', () async {
      final creado = await ExpensesRepository.instance.crear(Expense(
        title: 'Gasto a borrar',
        amount: 100,
        category: 'Otros',
        date: DateTime(2026, 3, 1),
      ));
      expect(ExpensesRepository.instance.expenses, hasLength(1));

      final future = ExpensesRepository.instance.eliminar(creado.id!);
      // Inmediatamente después de llamar eliminar (antes de esperar el
      // Future), ya debería estar afuera de la lista en memoria.
      expect(ExpensesRepository.instance.porId(creado.id), isNull);

      await future;

      // Y confirmado también contra la base de datos.
      final todos = await DatabaseService.instance.getAllExpenses();
      expect(todos, isEmpty);
    });
  });

  group('porId', () {
    test('devuelve null si el id no existe', () async {
      await ExpensesRepository.instance.cargar();

      expect(ExpensesRepository.instance.porId(9999), isNull);
    });

    test('devuelve null si el id es null', () {
      expect(ExpensesRepository.instance.porId(null), isNull);
    });
  });
}
