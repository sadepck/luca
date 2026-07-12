# Backlog técnico — Luca

Backlog derivado de la revisión de código en [REVISION_CODIGO.md](REVISION_CODIGO.md). Cada ítem es una tarea accionable con criterio de aceptación, para poder estimarla y planificarla con el cliente.

Leyenda:
- **Prioridad**: Alta · Media · Baja
- **Esfuerzo**: S (< 1 día) · M (1-3 días) · L (> 3 días)
- **Estado**: `Backlog` · `En progreso` · `En review` · `Hecho`

---

## Épica A — Red de seguridad (tests + CI)

### A1. Suite de tests para migraciones de `DatabaseService`
- **Prioridad**: Alta · **Esfuerzo**: M · **Estado**: Hecho
- **Origen**: [REVISION_CODIGO.md #1](REVISION_CODIGO.md)
- **Descripción**: hoy no hay ningún test sobre `lib/services/database_service.dart`, que maneja 9 versiones de esquema encadenadas en `_upgradeDB`. Un error en una migración corrompe la base de datos de usuarios que actualizan la app.
- **Criterios de aceptación**:
  - [x] Test que crea la DB desde `version 1` y aplica todas las migraciones hasta la actual, verificando el esquema final (columnas y tablas esperadas). Ver `test/database_service_test.dart`.
  - [x] Test de instalación limpia (`onCreate` directo en la última versión) que verifica que el esquema resultante es idéntico al de la ruta migrada.
  - [x] Tests de los métodos CRUD más usados (`createExpense`, `guardarItemsGasto`, `filtrarNoVistas`) usando `sqflite_common_ffi` (ya está en `dev_dependencies`).
  - [x] Tests de preservación de datos durante la migración: se insertan filas reales antes de migrar (un `expenses` cargado en v1, un `expense_items` cargado en v5) y se verifica después de migrar que los datos originales quedan intactos, que las columnas nuevas sin dato quedan en `null` (la migración no debe inventar valores) y que las columnas con `DEFAULT` explícito en el `ALTER TABLE` (como `cantidad`) se backfillean con ese default, no con `null`. Esto es lo que realmente protege contra corrupción de datos de usuarios reales, más allá de que el esquema "se vea" correcto.
  - **Hallazgo durante la implementación**: el test de migración v1→v9 detectó un bug real — cualquier usuario que actualizara desde antes de v5 directo a v6+ crasheaba al abrir la DB (`duplicate column name: cantidad`), porque `_createExpenseItemsTable` ya incluía esa columna y el paso `oldVersion < 6` la volvía a agregar. Corregido en `database_service.dart` (`_upgradeDB`), con un test de regresión dedicado que reconstruye el esquema real de una instalación varada en v5.

### A2. Tests de `oportunidades_watcher.dart` (dedup de notificaciones)
- **Prioridad**: Alta · **Esfuerzo**: S · **Estado**: Hecho
- **Origen**: [REVISION_CODIGO.md #1](REVISION_CODIGO.md)
- **Descripción**: la lógica que decide qué oportunidades son "nuevas" (`filtrarNoVistas` + `marcarComoVistas`) no tiene cobertura, pese a ser el corazón del feature de alertas.
- **Criterios de aceptación**:
  - [x] Test: oportunidades ya vistas no vuelven a notificarse.
  - [x] Test: sin ticket o sin palabras clave configuradas, no se llama al API (`return 0` temprano).
  - [x] Test: coincidencia de palabra clave case-insensitive y contra `nombre`+`descripcion`. Se extrajo `coincideConPalabrasClave` como función pura para poder testearla sin red (ver `test/oportunidades_watcher_test.dart`).

### A3. Pipeline de CI (GitHub Actions)
- **Prioridad**: Alta · **Esfuerzo**: S · **Estado**: Hecho
- **Origen**: [REVISION_CODIGO.md #2](REVISION_CODIGO.md)
- **Descripción**: no existe `.github/workflows/`. Nada corre `flutter analyze` ni `flutter test` en push/PR.
- **Criterios de aceptación**:
  - [x] Workflow que corre en cada PR y push a `main`: `flutter pub get`, `flutter analyze`, `flutter test`. Ver `.github/workflows/ci.yml`.
  - [ ] El PR queda bloqueado (branch protection) si el workflow falla. **Pendiente**: se configura desde GitHub (Settings → Branches → Branch protection rules), no desde el repo — requiere acción manual del dueño del repo.
  - [x] README actualizado con el badge de estado del workflow.

---

## Épica B — Integridad de datos y seguridad

### B1. Persistir fotos de boletas en almacenamiento propio de la app
- **Prioridad**: Alta · **Esfuerzo**: S · **Estado**: Backlog
- **Origen**: [REVISION_CODIGO.md #6](REVISION_CODIGO.md)
- **Descripción**: `imagePath` guarda la ruta temporal que devuelve `image_picker`, que el SO puede limpiar. Se pierde la evidencia original del ticket.
- **Criterios de aceptación**:
  - [ ] Al confirmar un gasto, la(s) foto(s) se copian a un subdirectorio dentro de `getApplicationDocumentsDirectory()`.
  - [ ] `Expense.imagePath` guarda la ruta persistente, no la de `image_picker`.
  - [ ] Al eliminar un gasto, se borra también su archivo de imagen (evitar huérfanos que acumulen espacio).
  - [ ] Migración simple: gastos existentes con ruta rota se detectan y no rompen la UI (mostrar placeholder en vez de excepción).

### B2. Cifrar el ticket de Mercado Público
- **Prioridad**: Media · **Esfuerzo**: S · **Estado**: Backlog
- **Origen**: [REVISION_CODIGO.md #5](REVISION_CODIGO.md)
- **Descripción**: el ticket (ligado a la Clave Única del usuario) se guarda con `shared_preferences`, texto plano en Android.
- **Criterios de aceptación**:
  - [ ] Migrar el guardado/lectura del ticket de `shared_preferences` a `flutter_secure_storage`.
  - [ ] Migración automática: si existe un ticket viejo en `shared_preferences`, se mueve a secure storage y se borra el original la primera vez que se abre la app.

---

## Épica C — Confiabilidad del feature de Mercado Público

### C1. Visibilidad del estado de la verificación en background
- **Prioridad**: Media · **Esfuerzo**: M · **Estado**: Backlog
- **Origen**: [REVISION_CODIGO.md #3](REVISION_CODIGO.md)
- **Descripción**: si falla el API o Workmanager no corre (frecuente en iOS), el usuario no tiene forma de saber que dejó de recibir alertas.
- **Criterios de aceptación**:
  - [ ] `verificarNuevasOportunidades()` persiste resultado del último chequeo (éxito/error/sin coincidencias + timestamp).
  - [ ] Ya no se traga el error silenciosamente (`catch (_)`): se registra la causa (al menos en logs locales).
  - [ ] Pantalla de configuración de Mercado Público muestra "Última verificación: [fecha] — [resultado]".

### C2. Unificar el cliente HTTP de Mercado Público y Compra Ágil
- **Prioridad**: Media · **Esfuerzo**: M · **Estado**: Backlog
- **Origen**: [REVISION_CODIGO.md #7](REVISION_CODIGO.md)
- **Descripción**: `mercado_publico_service.dart` y `compra_agil_service.dart` duplican la lógica de request/timeout/parseo de errores y ya divergieron en calidad de mensajes de error.
- **Criterios de aceptación**:
  - [ ] Extraer un helper/cliente HTTP compartido (timeout, `SocketException`, `TimeoutException`, parseo JSON, mapeo a `MercadoPublicoException`).
  - [ ] Ambos servicios lo usan; los mensajes de error quedan consistentes entre licitaciones y Compra Ágil.
  - [ ] Sin regresión: tests existentes (si los hay) o manuales de ambos flujos siguen pasando.

### C3. Manejo de permisos de cámara/galería denegados
- **Prioridad**: Media · **Esfuerzo**: S · **Estado**: Backlog
- **Origen**: [REVISION_CODIGO.md #10](REVISION_CODIGO.md)
- **Descripción**: en `scan_screen.dart`, las llamadas a `image_picker` no están protegidas; un permiso denegado permanentemente puede mostrar un error genérico o crashear.
- **Criterios de aceptación**:
  - [ ] `try/catch` alrededor de `pickImage`/`pickMultiImage` capturando `PlatformException`.
  - [ ] Si el permiso está denegado permanentemente, diálogo con botón a `openAppSettings()` (`permission_handler`).
  - [ ] Probado manualmente en Android denegando el permiso desde ajustes.

---

## Épica D — Arquitectura y mantenibilidad (mediano plazo)

### D1. Introducir capa de repositorio / estado compartido para gastos
- **Prioridad**: Media · **Esfuerzo**: L · **Estado**: Backlog
- **Origen**: [REVISION_CODIGO.md #8](REVISION_CODIGO.md)
- **Descripción**: 25 llamadas directas a `DatabaseService.instance` repartidas en 10 pantallas, sin estado compartido ni notificación de cambios entre ellas.
- **Criterios de aceptación**:
  - [ ] `ExpensesRepository` (o `ChangeNotifier`/`Provider`) como único punto de acceso a los gastos.
  - [ ] `home_screen.dart` y `expense_detail_screen.dart` migrados a consumirlo (piloto antes de extender al resto).
  - [ ] Guardar un gasto desde el flujo de escaneo refresca `home_screen` sin recarga manual.
  - [ ] Documentar el patrón para que el resto de las pantallas (licitaciones, cotizaciones) lo vayan adoptando de forma incremental.

### D2. Telemetría de calidad del parser OCR
- **Prioridad**: Baja · **Esfuerzo**: M · **Estado**: Backlog
- **Origen**: [REVISION_CODIGO.md #4](REVISION_CODIGO.md)
- **Descripción**: no hay visibilidad de qué tan seguido el parser falla (`descuadre = true`, monto en 0) con boletas reales.
- **Criterios de aceptación**:
  - [ ] Registrar localmente (con opt-in del usuario, sin subir la foto ni datos sensibles) tasa de `descuadre`/monto-cero.
  - [ ] Pantalla o export simple para revisar esas métricas durante el período de prueba con usuarios reales.
  - [ ] Definir con el cliente si esto se sube a un backend propio o queda solo local por ahora.

### D3. Actualizar y endurecer reglas de lint
- **Prioridad**: Baja · **Esfuerzo**: S · **Estado**: Backlog
- **Origen**: [REVISION_CODIGO.md #9](REVISION_CODIGO.md)
- **Descripción**: `flutter_lints` está en `^3.0.0` (desactualizado) y `analysis_options.yaml` no agrega reglas propias.
- **Criterios de aceptación**:
  - [ ] Actualizar `flutter_lints` a la última versión compatible con el SDK del proyecto.
  - [ ] Sumar `avoid_print`, `always_declare_return_types` y otras reglas acordadas con el equipo.
  - [ ] `flutter analyze` pasa sin warnings nuevos tras el cambio (o se resuelven los que aparezcan).

### D4. Limpieza del `CREATE TABLE` de `ordenes_compra`
- **Prioridad**: Baja · **Esfuerzo**: S · **Estado**: Backlog
- **Origen**: [REVISION_CODIGO.md — hallazgos menores](REVISION_CODIGO.md)
- **Descripción**: `fechaPagoEsperada` se agrega con un `ALTER TABLE` aparte inmediatamente después del `CREATE TABLE` en `_createDB`, en vez de estar declarada directamente en la tabla.
- **Criterios de aceptación**:
  - [ ] Columna `fechaPagoEsperada` incluida directo en `_createOrdenesCompraTable`.
  - [ ] Se quita el `ALTER TABLE` redundante de `_createDB` (la migración `oldVersion < 9` en `_upgradeDB` se mantiene intacta, es la que corre en updates reales).

---

## Resumen por prioridad

| Prioridad | Ítems |
|---|---|
| Alta | A1, A2, A3, B1 |
| Media | B2, C1, C2, C3, D1 |
| Baja | D2, D3, D4 |

## Orden sugerido de ejecución

1. **A3** (CI) primero — barato y protege todo lo que viene después.
2. **A1 + A2** (tests de DB y watcher) — red de seguridad antes de tocar arquitectura.
3. **B1** (fotos persistentes) — bug de datos con impacto directo en el usuario, fix acotado.
4. **C3** (permisos) y **B2** (ticket cifrado) — quick wins de robustez/seguridad.
5. **C1 + C2** — confiabilidad del feature de Mercado Público.
6. **D1** — arquitectura, más grande, encararlo cuando el resto esté estable.
7. **D2, D3, D4** — mejoras de calidad sin urgencia.
