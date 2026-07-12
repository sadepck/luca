import 'package:flutter/foundation.dart';

import '../models/expense.dart';
import 'database_service.dart';

/// Único punto de acceso a los gastos guardados. Envuelve
/// [DatabaseService] y notifica (vía [ChangeNotifier]) a quien esté
/// escuchando cada vez que la lista cambia, para que las pantallas no
/// tengan que coordinarse manualmente entre sí — por ejemplo, guardar un
/// gasto desde el flujo de escaneo actualiza `home_screen` solo, sin que
/// haga falta un `_loadExpenses()` explícito al volver de la navegación.
///
/// ## Patrón para adoptar en el resto de las pantallas
///
/// Esta es la primera pantalla piloto de este patrón (`home_screen.dart`
/// y `expense_detail_screen.dart`); el resto de las tablas (licitaciones,
/// cotizaciones, órdenes de compra, ingresos) siguen accediendo a
/// `DatabaseService.instance` directo. Para migrarlas de forma
/// incremental, cada una a su propio ritmo:
///
/// 1. Crear un repositorio análogo (`ChangeNotifier` + `DatabaseService`
///    por debajo) para esa tabla, con la misma forma que este: un
///    getter con la lista actual, un `cargar()`, y un método por
///    operación de escritura (crear/eliminar/actualizar) que termine
///    en `notifyListeners()`.
/// 2. En la pantalla, reemplazar el `List<T> _items` + `setState`
///    manual por un `ListenableBuilder` (o `AnimatedBuilder`) que
///    escuche esa instancia y lea la lista directo del repositorio en
///    cada rebuild.
/// 3. Cualquier otra pantalla que necesite los mismos datos escucha la
///    misma instancia — no hace falta pasar callbacks de refresco entre
///    pantallas ni acordarse de recargar al volver de una navegación.
/// 4. Para tests, exponer un `resetForTesting()` como el de acá, que
///    reemplaza la instancia por una nueva y limpia — evita que el
///    estado de un test se filtre al siguiente.
class ExpensesRepository extends ChangeNotifier {
  static ExpensesRepository instance = ExpensesRepository._();
  ExpensesRepository._();

  List<Expense> _expenses = [];
  bool _cargado = false;

  /// Snapshot inmutable de los gastos ya cargados. Vacío hasta el primer
  /// [cargar].
  List<Expense> get expenses => List.unmodifiable(_expenses);

  /// `true` una vez que [cargar] corrió al menos una vez.
  bool get cargado => _cargado;

  Expense? porId(int? id) {
    if (id == null) return null;
    for (final expense in _expenses) {
      if (expense.id == id) return expense;
    }
    return null;
  }

  Future<void> cargar() async {
    _expenses = await DatabaseService.instance.getAllExpenses();
    _cargado = true;
    notifyListeners();
  }

  Future<Expense> crear(Expense expense) async {
    final creado = await DatabaseService.instance.createExpense(expense);
    await cargar();
    return creado;
  }

  /// Elimina el gasto de forma optimista (lo saca de [expenses] y notifica
  /// antes de esperar la escritura en la base de datos), para que la UI
  /// (ej. un `Dismissible`) no tenga que esperar el viaje a la DB para
  /// reflejar el cambio.
  Future<void> eliminar(int id) async {
    _expenses = _expenses.where((e) => e.id != id).toList();
    notifyListeners();
    await DatabaseService.instance.deleteExpense(id);
  }

  /// Reemplaza la instancia por una nueva y limpia. Los tests deben
  /// llamarlo en `tearDown` para no filtrar estado entre casos de test.
  @visibleForTesting
  static void resetForTesting() {
    instance = ExpensesRepository._();
  }
}
