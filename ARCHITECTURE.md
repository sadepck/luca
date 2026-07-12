# Arquitectura — Luca

## Patrón de repositorio para estado compartido

Hasta ahora, cada pantalla llamaba a `DatabaseService.instance` directo y
mantenía su propia copia del estado en un `StatefulWidget`. Eso significa que
dos pantallas mostrando el mismo dato (por ejemplo, la lista de gastos en
`home_screen` mientras se guarda uno nuevo desde el flujo de escaneo) no se
enteran de los cambios entre sí — cada una necesita que alguien se acuerde de
llamar a su método de recarga manualmente.

`ExpensesRepository` (`lib/services/expenses_repository.dart`) es la primera
pantalla piloto de un patrón para resolver esto sin sumar un paquete de
manejo de estado externo (`provider`, `riverpod`, etc.) — usa
`ChangeNotifier`, que ya viene con Flutter.

### Cómo funciona

- El repositorio es un singleton (`ExpensesRepository.instance`) que envuelve
  `DatabaseService` para una tabla específica (en este caso, `expenses`).
- Expone un getter con el estado actual (`expenses`) y un método por
  operación de escritura (`crear`, `eliminar`), cada uno terminando en
  `notifyListeners()`.
- Las pantallas que necesitan esos datos se envuelven en un
  `ListenableBuilder` (o `AnimatedBuilder`) escuchando esa instancia, y leen
  el estado directo del repositorio en cada rebuild — no mantienen su propia
  copia en un campo `List<T> _items` local.
- Como todas las pantallas escuchan la misma instancia, un cambio hecho
  desde cualquiera de ellas (o desde un flujo de navegación distinto, como
  `ExpenseReviewScreen`) se refleja en todas sin coordinación manual.

### Piloto actual

Migrados a este patrón: `home_screen.dart` (lista y totales) y
`expense_detail_screen.dart` (lee la versión más actual del gasto desde el
repositorio, con `widget.expense` como snapshot inicial de respaldo).
`expense_review_screen.dart` crea el gasto a través de
`ExpensesRepository.instance.crear(...)`, que es lo que hace que
`home_screen` se actualice solo al volver del flujo de escaneo, sin un
`_loadExpenses()` explícito.

`expense_review_screen.dart` sigue llamando a `DatabaseService.instance`
directo para el chequeo de posibles duplicados (`_buscarDuplicado`) y para
guardar los ítems del detalle (`guardarItemsGasto`) — son lecturas/escrituras
puntuales que no necesitan reactividad, así que no se migraron; seguir
usando `DatabaseService` directo ahí es una decisión válida, no una omisión.

### Cómo migrar otra tabla (licitaciones, cotizaciones, órdenes de compra, ingresos)

1. Crear un repositorio análogo para esa tabla, con la misma forma:
   `ChangeNotifier` + `DatabaseService` por debajo, un getter con la lista
   actual, un `cargar()`, y un método por operación de escritura.
2. En la pantalla, reemplazar el `List<T> _items` + `setState` manual por un
   `ListenableBuilder` que escuche esa instancia.
3. Para tests, exponer un `resetForTesting()` (como el de
   `ExpensesRepository`) que reemplace la instancia por una nueva y limpia —
   evita que el estado de un test se filtre al siguiente.
4. No hace falta migrar toda la app de una vez: cada tabla se puede mover a
   su propio ritmo, y el resto de las pantallas puede seguir usando
   `DatabaseService.instance` directo hasta que le toque.
