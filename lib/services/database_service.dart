import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/expense.dart';
import '../models/ingreso_esperado.dart';
import '../models/item_cotizacion.dart';
import '../models/item_gasto.dart';
import '../models/oportunidad_guardada.dart';
import '../models/orden_compra_generada.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('luca.db');
    return _database!;
  }

  static const int _dbVersion = 9;

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  /// Abre (o migra) la base de datos en [path] usando el mismo [onCreate]/
  /// [onUpgrade] reales de la app. Permite a los tests ejercitar el
  /// esquema resultante de una instalación limpia o de una cadena de
  /// migraciones sin depender de `getDatabasesPath()` (que requiere un
  /// canal de plataforma no disponible en el entorno de test).
  @visibleForTesting
  Future<Database> openForTesting(String path, {int version = _dbVersion}) async {
    await _database?.close();
    _database = await openDatabase(
      path,
      version: version,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
    return _database!;
  }

  /// Cierra la base de datos en memoria del singleton, si hay una abierta.
  /// Los tests deben llamarlo en `tearDown` para no filtrar estado (una
  /// base de datos ya abierta) entre casos de test.
  @visibleForTesting
  static Future<void> resetForTesting() async {
    await _database?.close();
    _database = null;
  }

  Future _createDB(Database db, int version) async {
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
    await _createOportunidadesTable(db);
    await _createOportunidadesVistasTable(db);
    await _createIngresosTable(db);
    await _createExpenseItemsTable(db);
    await _createCotizacionItemsTable(db);
    await _createOrdenesCompraTable(db);
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createOportunidadesTable(db);
    }
    if (oldVersion < 3) {
      await _createOportunidadesVistasTable(db);
    }
    if (oldVersion < 4) {
      await _createIngresosTable(db);
    }
    if (oldVersion < 5) {
      await _createExpenseItemsTable(db);
      await _createCotizacionItemsTable(db);
    }
    if (oldVersion < 6) {
      if (oldVersion >= 5) {
        // Si oldVersion < 5, expense_items recién se creó arriba con
        // _createExpenseItemsTable, que ya incluye la columna `cantidad`
        // en su CREATE TABLE — agregarla de nuevo aquí duplicaría la
        // columna y rompería la migración.
        await db.execute('ALTER TABLE expense_items ADD COLUMN cantidad REAL NOT NULL DEFAULT 1');
      }
      await db.execute('ALTER TABLE expenses ADD COLUMN folio TEXT');
      await db.execute('ALTER TABLE expenses ADD COLUMN tipoDte TEXT');
      await db.execute('ALTER TABLE expenses ADD COLUMN rutEmisor TEXT');
    }
    if (oldVersion < 7) {
      await db.execute('ALTER TABLE expenses ADD COLUMN nombreEmisor TEXT');
      await db.execute('ALTER TABLE expenses ADD COLUMN montoNeto REAL');
      await db.execute('ALTER TABLE expenses ADD COLUMN montoIva REAL');
    }
    if (oldVersion < 8) {
      await _createOrdenesCompraTable(db);
    }
    if (oldVersion < 9) {
      if (oldVersion >= 8) {
        // Si oldVersion < 8, ordenes_compra recién se creó arriba con
        // _createOrdenesCompraTable, que ya incluye la columna
        // `fechaPagoEsperada` en su CREATE TABLE — agregarla de nuevo
        // aquí duplicaría la columna y rompería la migración (mismo caso
        // que `expense_items.cantidad` más arriba).
        await db.execute('ALTER TABLE ordenes_compra ADD COLUMN fechaPagoEsperada TEXT');
      }
    }
  }

  Future _createOportunidadesTable(Database db) async {
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
  }

  Future _createOportunidadesVistasTable(Database db) async {
    await db.execute('''
      CREATE TABLE oportunidades_vistas (
        codigo TEXT PRIMARY KEY,
        fechaVista TEXT NOT NULL
      )
    ''');
  }

  Future _createIngresosTable(Database db) async {
    await db.execute('''
      CREATE TABLE ingresos_esperados (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        descripcion TEXT NOT NULL,
        monto REAL NOT NULL,
        diaDelMes INTEGER NOT NULL
      )
    ''');
  }

  Future _createExpenseItemsTable(Database db) async {
    await db.execute('''
      CREATE TABLE expense_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        expenseId INTEGER NOT NULL,
        nombre TEXT NOT NULL,
        cantidad REAL NOT NULL DEFAULT 1,
        precio REAL NOT NULL
      )
    ''');
  }

  Future _createCotizacionItemsTable(Database db) async {
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

  Future _createOrdenesCompraTable(Database db) async {
    await db.execute('''
      CREATE TABLE ordenes_compra (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        codigoOportunidad TEXT NOT NULL,
        nombreOportunidad TEXT NOT NULL,
        proveedorNombre TEXT,
        proveedorRut TEXT,
        montoCompra REAL NOT NULL,
        montoIngreso REAL NOT NULL,
        fecha TEXT NOT NULL,
        fechaPagoEsperada TEXT
      )
    ''');
  }

  Future<OrdenCompraGenerada> crearOrdenCompra(
      OrdenCompraGenerada orden) async {
    final db = await instance.database;
    final id = await db.insert('ordenes_compra', orden.toMap());
    return OrdenCompraGenerada(
      id: id,
      codigoOportunidad: orden.codigoOportunidad,
      nombreOportunidad: orden.nombreOportunidad,
      proveedorNombre: orden.proveedorNombre,
      proveedorRut: orden.proveedorRut,
      montoCompra: orden.montoCompra,
      montoIngreso: orden.montoIngreso,
      fecha: orden.fecha,
      fechaPagoEsperada: orden.fechaPagoEsperada,
    );
  }

  Future<List<OrdenCompraGenerada>> getOrdenesCompra() async {
    final db = await instance.database;
    final result = await db.query('ordenes_compra', orderBy: 'fecha DESC');
    return result.map(OrdenCompraGenerada.fromMap).toList();
  }

  Future<void> eliminarOrdenCompra(int id) async {
    final db = await instance.database;
    await db.delete('ordenes_compra', where: 'id = ?', whereArgs: [id]);
  }

  Future<Expense> createExpense(Expense expense) async {
    final db = await instance.database;
    final id = await db.insert('expenses', expense.toMap());
    return Expense(
      id: id,
      title: expense.title,
      amount: expense.amount,
      category: expense.category,
      date: expense.date,
      imagePath: expense.imagePath,
      folio: expense.folio,
      tipoDte: expense.tipoDte,
      rutEmisor: expense.rutEmisor,
      nombreEmisor: expense.nombreEmisor,
      montoNeto: expense.montoNeto,
      montoIva: expense.montoIva,
    );
  }

  Future<List<Expense>> getAllExpenses() async {
    final db = await instance.database;
    final result = await db.query('expenses', orderBy: 'date DESC');
    return result.map(Expense.fromMap).toList();
  }

  Future<int> deleteExpense(int id) async {
    final db = await instance.database;
    return await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> guardarOportunidad(OportunidadGuardada oportunidad) async {
    final db = await instance.database;
    await db.insert(
      'oportunidades',
      oportunidad.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<OportunidadGuardada>> getOportunidadesGuardadas() async {
    final db = await instance.database;
    final result = await db.query('oportunidades', orderBy: 'fechaCierre ASC');
    return result.map(OportunidadGuardada.fromMap).toList();
  }

  Future<void> eliminarOportunidad(String codigo) async {
    final db = await instance.database;
    await db.delete('oportunidades', where: 'codigo = ?', whereArgs: [codigo]);
  }

  Future<bool> estaOportunidadGuardada(String codigo) async {
    final db = await instance.database;
    final result = await db
        .query('oportunidades', where: 'codigo = ?', whereArgs: [codigo]);
    return result.isNotEmpty;
  }

  /// Dado un listado de códigos, devuelve los que nunca se han marcado
  /// como vistos (es decir, oportunidades genuinamente nuevas).
  Future<List<String>> filtrarNoVistas(List<String> codigos) async {
    if (codigos.isEmpty) return [];
    final db = await instance.database;
    final placeholders = List.filled(codigos.length, '?').join(',');
    final result = await db.query(
      'oportunidades_vistas',
      columns: ['codigo'],
      where: 'codigo IN ($placeholders)',
      whereArgs: codigos,
    );
    final vistos = result.map((m) => m['codigo'] as String).toSet();
    return codigos.where((c) => !vistos.contains(c)).toList();
  }

  Future<void> marcarComoVistas(List<String> codigos) async {
    if (codigos.isEmpty) return;
    final db = await instance.database;
    final batch = db.batch();
    final ahora = DateTime.now().toIso8601String();
    for (final codigo in codigos) {
      batch.insert(
        'oportunidades_vistas',
        {'codigo': codigo, 'fechaVista': ahora},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> crearIngreso(IngresoEsperado ingreso) async {
    final db = await instance.database;
    await db.insert('ingresos_esperados', ingreso.toMap());
  }

  Future<List<IngresoEsperado>> getIngresos() async {
    final db = await instance.database;
    final result = await db.query('ingresos_esperados', orderBy: 'diaDelMes ASC');
    return result.map(IngresoEsperado.fromMap).toList();
  }

  Future<void> eliminarIngreso(int id) async {
    final db = await instance.database;
    await db.delete('ingresos_esperados', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> guardarItemsGasto(int expenseId, List<ItemGasto> items) async {
    if (items.isEmpty) return;
    final db = await instance.database;
    final batch = db.batch();
    for (final item in items) {
      batch.insert('expense_items', {
        'expenseId': expenseId,
        'nombre': item.nombre,
        'cantidad': item.cantidad,
        'precio': item.precio,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<ItemGasto>> getItemsDeGasto(int expenseId) async {
    final db = await instance.database;
    final result = await db
        .query('expense_items', where: 'expenseId = ?', whereArgs: [expenseId]);
    return result.map(ItemGasto.fromMap).toList();
  }

  Future<void> guardarItemCotizacion(ItemCotizacion item) async {
    final db = await instance.database;
    await db.insert('cotizacion_items', item.toMap());
  }

  Future<List<ItemCotizacion>> getItemsCotizacion(String codigoOportunidad) async {
    final db = await instance.database;
    final result = await db.query(
      'cotizacion_items',
      where: 'codigoOportunidad = ?',
      whereArgs: [codigoOportunidad],
    );
    return result.map(ItemCotizacion.fromMap).toList();
  }

  Future<void> eliminarItemCotizacion(int id) async {
    final db = await instance.database;
    await db.delete('cotizacion_items', where: 'id = ?', whereArgs: [id]);
  }
}
