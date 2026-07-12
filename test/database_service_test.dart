import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:luca/models/expense.dart';
import 'package:luca/models/item_gasto.dart';
import 'package:luca/services/database_service.dart';

/// Esquema de la versión 1 de la app, reconstruido a partir de
/// `_upgradeDB`: antes de la primera migración (`oldVersion < 2`) la única
/// tabla existente era `expenses`, y sin las columnas que se agregaron
/// recién en las migraciones a v6/v7 (folio, tipoDte, rutEmisor,
/// nombreEmisor, montoNeto, montoIva).
const _esquemaV1 = '''
  CREATE TABLE expenses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    amount REAL NOT NULL,
    category TEXT NOT NULL,
    date TEXT NOT NULL,
    imagePath TEXT
  )
''';

/// Esquema de la versión 5 tal como quedaba una instalación real en ese
/// momento: `expense_items` sin la columna `cantidad` (se agregó recién
/// en la migración a v6). Reproduce el escenario exacto del bug de
/// migración corregido en `_upgradeDB` (`duplicate column name: cantidad`
/// al saltar de una versión pre-5 a v6+ en una sola pasada).
Future<void> _crearEsquemaV5(Database db, int version) async {
  await db.execute(_esquemaV1);
  await db.execute('''
    CREATE TABLE oportunidades (
      codigo TEXT PRIMARY KEY,
      nombre TEXT NOT NULL,
      organismo TEXT,
      fechaCierre TEXT,
      montoEstimado REAL,
      fechaGuardado TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE oportunidades_vistas (
      codigo TEXT PRIMARY KEY,
      fechaVista TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE ingresos_esperados (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      descripcion TEXT NOT NULL,
      monto REAL NOT NULL,
      diaDelMes INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE expense_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      expenseId INTEGER NOT NULL,
      nombre TEXT NOT NULL,
      precio REAL NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE cotizacion_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      codigoOportunidad TEXT NOT NULL,
      nombre TEXT NOT NULL,
      cantidad REAL NOT NULL,
      precioUnitario REAL NOT NULL
    )
  ''');
}

/// Esquema de la versión 8 tal como quedaba una instalación real en ese
/// momento: `ordenes_compra` sin la columna `fechaPagoEsperada` (se agregó
/// recién en la migración a v9). Reproduce el mismo escenario de bug que
/// `_crearEsquemaV5`, pero para la migración `oldVersion < 9`.
Future<void> _crearEsquemaV8(Database db, int version) async {
  await db.execute('''
    CREATE TABLE expenses (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      amount REAL NOT NULL,
      category TEXT NOT NULL,
      date TEXT NOT NULL,
      imagePath TEXT,
      folio TEXT,
      tipoDte TEXT,
      rutEmisor TEXT,
      nombreEmisor TEXT,
      montoNeto REAL,
      montoIva REAL
    )
  ''');
  await db.execute('''
    CREATE TABLE oportunidades (
      codigo TEXT PRIMARY KEY,
      nombre TEXT NOT NULL,
      organismo TEXT,
      fechaCierre TEXT,
      montoEstimado REAL,
      fechaGuardado TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE oportunidades_vistas (
      codigo TEXT PRIMARY KEY,
      fechaVista TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE ingresos_esperados (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      descripcion TEXT NOT NULL,
      monto REAL NOT NULL,
      diaDelMes INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE expense_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      expenseId INTEGER NOT NULL,
      nombre TEXT NOT NULL,
      cantidad REAL NOT NULL DEFAULT 1,
      precio REAL NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE cotizacion_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      codigoOportunidad TEXT NOT NULL,
      nombre TEXT NOT NULL,
      cantidad REAL NOT NULL,
      precioUnitario REAL NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE ordenes_compra (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      codigoOportunidad TEXT NOT NULL,
      nombreOportunidad TEXT NOT NULL,
      proveedorNombre TEXT,
      proveedorRut TEXT,
      montoCompra REAL NOT NULL,
      montoIngreso REAL NOT NULL,
      fecha TEXT NOT NULL
    )
  ''');
}

const _tablasEsperadas = {
  'expenses',
  'oportunidades',
  'oportunidades_vistas',
  'ingresos_esperados',
  'expense_items',
  'cotizacion_items',
  'ordenes_compra',
};

Future<Set<String>> _tablas(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'",
  );
  return rows.map((r) => r['name'] as String).toSet();
}

Future<Set<String>> _columnasDe(Database db, String tabla) async {
  final rows = await db.rawQuery('PRAGMA table_info($tabla)');
  return rows.map((r) => r['name'] as String).toSet();
}

void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('luca_db_test_');
  });

  tearDown(() async {
    await DatabaseService.resetForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('esquema', () {
    test('instalación limpia (onCreate) crea todas las tablas y columnas actuales', () async {
      final path = join(tempDir.path, 'limpia.db');
      final db = await DatabaseService.instance.openForTesting(path);

      expect(await _tablas(db), _tablasEsperadas);
      expect(await _columnasDe(db, 'ordenes_compra'), contains('fechaPagoEsperada'));
      expect(
        await _columnasDe(db, 'expenses'),
        containsAll(['folio', 'tipoDte', 'rutEmisor', 'nombreEmisor', 'montoNeto', 'montoIva']),
      );
    });

    test('la ruta migrada desde la versión 1 llega al mismo esquema que una instalación limpia', () async {
      // DB "limpia" en la versión actual, usada como referencia: se
      // registran las columnas de TODAS sus tablas, no solo un par.
      final pathLimpia = join(tempDir.path, 'limpia.db');
      final dbLimpia = await DatabaseService.instance.openForTesting(pathLimpia);
      final tablasLimpias = await _tablas(dbLimpia);
      final columnasLimpias = {
        for (final tabla in tablasLimpias) tabla: await _columnasDe(dbLimpia, tabla),
      };
      await DatabaseService.resetForTesting();

      // DB creada en la versión 1 histórica, luego reabierta pidiendo la
      // versión actual: esto dispara la cadena real de `_upgradeDB`.
      final pathMigrada = join(tempDir.path, 'migrada.db');
      final dbV1 = await openDatabase(
        pathMigrada,
        version: 1,
        onCreate: (db, version) => db.execute(_esquemaV1),
      );
      await dbV1.close();

      final dbMigrada = await DatabaseService.instance.openForTesting(pathMigrada);
      final tablasMigradas = await _tablas(dbMigrada);

      expect(tablasMigradas, tablasLimpias);
      for (final tabla in tablasLimpias) {
        expect(await _columnasDe(dbMigrada, tabla), columnasLimpias[tabla],
            reason: 'columnas de "$tabla" difieren entre instalación limpia y ruta migrada');
      }
    });

    test(
        'una instalación real varada en v5 (expense_items sin `cantidad`) migra sin '
        'error de columna duplicada al saltar directo a la versión actual', () async {
      final path = join(tempDir.path, 'desde_v5.db');
      final dbV5 = await openDatabase(path, version: 5, onCreate: _crearEsquemaV5);
      await dbV5.close();

      final db = await DatabaseService.instance.openForTesting(path);

      expect(await _columnasDe(db, 'expense_items'), contains('cantidad'));
    });

    test(
        'una instalación real varada en v8 (ordenes_compra sin `fechaPagoEsperada`) migra sin '
        'error de columna duplicada al saltar directo a la versión actual', () async {
      final path = join(tempDir.path, 'desde_v8.db');
      final dbV8 = await openDatabase(path, version: 8, onCreate: _crearEsquemaV8);
      await dbV8.close();

      final db = await DatabaseService.instance.openForTesting(path);

      expect(await _columnasDe(db, 'ordenes_compra'), contains('fechaPagoEsperada'));
    });

    test(
        'un gasto real cargado en v1 sobrevive intacto tras migrar a la versión actual, '
        'y las columnas tributarias nuevas quedan en null (sin datos que inventar)', () async {
      final path = join(tempDir.path, 'con_datos_v1.db');
      final dbV1 = await openDatabase(
        path,
        version: 1,
        onCreate: (db, version) => db.execute(_esquemaV1),
      );
      await dbV1.insert('expenses', {
        'title': 'Bencina Copec',
        'amount': 25000.0,
        'category': 'Transporte',
        'date': '2020-05-10T00:00:00.000',
        'imagePath': '/data/tmp/foto1.jpg',
      });
      await dbV1.close();

      final dbMigrada = await DatabaseService.instance.openForTesting(path);
      final filas = await dbMigrada.query('expenses');

      expect(filas, hasLength(1));
      final fila = filas.single;
      // Los datos originales no se tocan con la migración.
      expect(fila['title'], 'Bencina Copec');
      expect(fila['amount'], 25000.0);
      expect(fila['category'], 'Transporte');
      expect(fila['date'], '2020-05-10T00:00:00.000');
      expect(fila['imagePath'], '/data/tmp/foto1.jpg');
      // Las columnas tributarias no existían cuando se cargó el gasto: la
      // migración no debe inventar valores, deben quedar en null.
      expect(fila['folio'], isNull);
      expect(fila['tipoDte'], isNull);
      expect(fila['rutEmisor'], isNull);
      expect(fila['nombreEmisor'], isNull);
      expect(fila['montoNeto'], isNull);
      expect(fila['montoIva'], isNull);
    });

    test(
        'un ítem de gasto cargado en v5 (sin `cantidad`) sobrevive la migración y la '
        'columna nueva se backfillea con el DEFAULT declarado en el ALTER TABLE (1), no null', () async {
      final path = join(tempDir.path, 'con_datos_v5.db');
      final dbV5 = await openDatabase(path, version: 5, onCreate: _crearEsquemaV5);
      final expenseId = await dbV5.insert('expenses', {
        'title': 'Ferretería',
        'amount': 5000.0,
        'category': 'Otros',
        'date': '2021-02-01T00:00:00.000',
      });
      await dbV5.insert('expense_items', {
        'expenseId': expenseId,
        'nombre': 'Tornillos',
        'precio': 5000.0,
      });
      await dbV5.close();

      final dbMigrada = await DatabaseService.instance.openForTesting(path);
      final items = await dbMigrada.query('expense_items');

      expect(items, hasLength(1));
      final item = items.single;
      expect(item['nombre'], 'Tornillos');
      expect(item['precio'], 5000.0);
      // ALTER TABLE ... ADD COLUMN cantidad REAL NOT NULL DEFAULT 1
      // backfillea las filas ya existentes con el DEFAULT, no con null.
      expect(item['cantidad'], 1.0);
    });

    test(
        'una orden de compra cargada en v8 (sin `fechaPagoEsperada`) sobrevive la migración '
        'y la columna nueva queda en null (sin fecha de pago que inventar)', () async {
      final path = join(tempDir.path, 'con_datos_v8.db');
      final dbV8 = await openDatabase(path, version: 8, onCreate: _crearEsquemaV8);
      await dbV8.insert('ordenes_compra', {
        'codigoOportunidad': 'OC-1',
        'nombreOportunidad': 'Suministro de prueba',
        'montoCompra': 100000.0,
        'montoIngreso': 250000.0,
        'fecha': '2022-08-01T00:00:00.000',
      });
      await dbV8.close();

      final dbMigrada = await DatabaseService.instance.openForTesting(path);
      final ordenes = await dbMigrada.query('ordenes_compra');

      expect(ordenes, hasLength(1));
      final orden = ordenes.single;
      expect(orden['codigoOportunidad'], 'OC-1');
      expect(orden['montoCompra'], 100000.0);
      expect(orden['montoIngreso'], 250000.0);
      expect(orden['fechaPagoEsperada'], isNull);
    });
  });

  group('CRUD', () {
    setUp(() async {
      final path = join(tempDir.path, 'crud.db');
      await DatabaseService.instance.openForTesting(path);
    });

    test('createExpense guarda el gasto y le asigna un id', () async {
      final creado = await DatabaseService.instance.createExpense(Expense(
        title: 'Bencina',
        amount: 15000,
        category: 'Transporte',
        date: DateTime(2026, 3, 1),
      ));

      expect(creado.id, isNotNull);

      final todos = await DatabaseService.instance.getAllExpenses();
      expect(todos, hasLength(1));
      expect(todos.first.title, 'Bencina');
      expect(todos.first.amount, 15000);
    });

    test('guardarItemsGasto persiste los items asociados al gasto', () async {
      final gasto = await DatabaseService.instance.createExpense(Expense(
        title: 'Supermercado',
        amount: 8000,
        category: 'Otros',
        date: DateTime(2026, 3, 1),
      ));

      await DatabaseService.instance.guardarItemsGasto(gasto.id!, [
        ItemGasto(expenseId: gasto.id!, nombre: 'Pan', cantidad: 2, precio: 1500),
        ItemGasto(expenseId: gasto.id!, nombre: 'Leche', cantidad: 1, precio: 1200),
      ]);

      final items = await DatabaseService.instance.getItemsDeGasto(gasto.id!);
      expect(items, hasLength(2));
      expect(items.map((i) => i.nombre), containsAll(['Pan', 'Leche']));
    });

    test('guardarItemsGasto con lista vacía no falla ni inserta nada', () async {
      final gasto = await DatabaseService.instance.createExpense(Expense(
        title: 'Sin items',
        amount: 100,
        category: 'Otros',
        date: DateTime(2026, 3, 1),
      ));

      await DatabaseService.instance.guardarItemsGasto(gasto.id!, []);

      expect(await DatabaseService.instance.getItemsDeGasto(gasto.id!), isEmpty);
    });

    test('filtrarNoVistas devuelve solo los códigos que nunca se marcaron como vistos', () async {
      await DatabaseService.instance.marcarComoVistas(['A', 'B']);

      final noVistas = await DatabaseService.instance.filtrarNoVistas(['A', 'B', 'C']);

      expect(noVistas, ['C']);
    });

    test('filtrarNoVistas con lista vacía devuelve lista vacía sin tocar la DB', () async {
      expect(await DatabaseService.instance.filtrarNoVistas([]), isEmpty);
    });

    test('marcarComoVistas es idempotente (no falla al repetir un código ya visto)', () async {
      await DatabaseService.instance.marcarComoVistas(['A']);
      await DatabaseService.instance.marcarComoVistas(['A', 'B']);

      expect(await DatabaseService.instance.filtrarNoVistas(['A', 'B']), isEmpty);
    });
  });
}
