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
- **Prioridad**: Alta · **Esfuerzo**: S · **Estado**: Hecho
- **Origen**: [REVISION_CODIGO.md #6](REVISION_CODIGO.md)
- **Descripción**: `imagePath` guarda la ruta temporal que devuelve `image_picker`, que el SO puede limpiar. Se pierde la evidencia original del ticket.
- **Criterios de aceptación**:
  - [x] Al confirmar un gasto, la(s) foto(s) se copian a un subdirectorio dentro de `getApplicationDocumentsDirectory()`. Ver `lib/services/receipt_storage.dart` (`guardarFotoTicketPersistente`), usado desde `expense_review_screen.dart`.
  - [x] `Expense.imagePath` guarda la ruta persistente, no la de `image_picker`.
  - [x] Al eliminar un gasto, se borra también su archivo de imagen (evitar huérfanos que acumulen espacio). Implementado en `home_screen.dart` (`_eliminarGasto`), con cuidado de no borrar el archivo si el usuario presiona "Deshacer" (se espera a que se cierre el SnackBar sin la acción de deshacer).
  - [x] Migración simple: gastos existentes con ruta rota se detectan y no rompen la UI (mostrar placeholder en vez de excepción). `expense_detail_screen.dart` ahora distingue "sin foto" de "foto perdida" y muestra un placeholder con ícono en el segundo caso.
  - **Nota de verificación**: cubierto con 10 tests unitarios (`test/receipt_storage_test.dart`) para la lógica de copiar/eliminar. No se pudo probar manualmente el flujo end-to-end en la app real (escanear → guardar → eliminar → deshacer) porque el entorno de desarrollo no tiene emulador Android/iOS ni cámara disponible — solo Windows desktop y navegador.
  - **Hallazgos de la revisión final**:
    1. Si la foto temporal de `image_picker` ya no existe al guardar (justo el escenario que B1 previene), `guardarFotoTicketPersistente` lanzaba una excepción no capturada que bloqueaba el guardado completo del gasto — peor que el comportamiento anterior. Se agregó un fallback en `expense_review_screen.dart` que guarda el gasto sin foto en ese caso, en vez de fallar.
    2. El nombre del archivo destino se basaba solo en `microsecondsSinceEpoch`, cuya resolución real varía por plataforma; dos fotos guardadas en el mismo tick de reloj se habrían pisado entre sí. Se agregó un contador de proceso como desempate.

### B2. Cifrar el ticket de Mercado Público
- **Prioridad**: Media · **Esfuerzo**: S · **Estado**: Hecho
- **Origen**: [REVISION_CODIGO.md #5](REVISION_CODIGO.md)
- **Descripción**: el ticket (ligado a la Clave Única del usuario) se guarda con `shared_preferences`, texto plano en Android.
- **Criterios de aceptación**:
  - [x] Migrar el guardado/lectura del ticket de `shared_preferences` a `flutter_secure_storage`. Ver `lib/services/mp_ticket_storage.dart` (`leerTicketMercadoPublico`/`guardarTicketMercadoPublico`), usado desde `mercado_publico_config_screen.dart`, `mercado_publico_screen.dart` y `oportunidades_watcher.dart`.
  - [x] Migración automática: si existe un ticket viejo en `shared_preferences`, se mueve a secure storage y se borra el original la primera vez que se abre la app. Cubierto con tests en `test/mp_ticket_storage_test.dart` (lectura desde secure storage, migración desde legado, borrado del legado post-migración, caso sin ticket).
  - **Nota**: `flutter_secure_storage` requirió subir a `^10.3.1` (en vez de `^9.x`) por un conflicto de versión de `win32` con `share_plus`; `flutter pub get` resolvió limpio con esa versión.

---

## Épica C — Confiabilidad del feature de Mercado Público

### C1. Visibilidad del estado de la verificación en background
- **Prioridad**: Media · **Esfuerzo**: M · **Estado**: Hecho
- **Origen**: [REVISION_CODIGO.md #3](REVISION_CODIGO.md)
- **Descripción**: si falla el API o Workmanager no corre (frecuente en iOS), el usuario no tiene forma de saber que dejó de recibir alertas.
- **Criterios de aceptación**:
  - [x] `verificarNuevasOportunidades()` persiste resultado del último chequeo (éxito/error/sin coincidencias + timestamp). Ver `lib/services/verificacion_status.dart`.
  - [x] Ya no se traga el error silenciosamente (`catch (_)`): se registra la causa (al menos en logs locales). `oportunidades_watcher.dart` ahora usa `catch (e)` y guarda `e.toString()` (el mensaje de `MercadoPublicoException` ya es legible).
  - [x] Pantalla de configuración de Mercado Público muestra "Última verificación: [fecha] — [resultado]". Ver `_buildUltimaVerificacion` en `mercado_publico_config_screen.dart`.
  - **Nota técnica**: para poder testear los 3 estados (éxito/sin coincidencias/error) sin red ni el plugin real de notificaciones, se agregaron parámetros opcionales inyectables a `verificarNuevasOportunidades` (`service`, `notificar`), siguiendo el mismo patrón ya usado para `ticketStore`. Cubierto con tests en `test/verificacion_status_test.dart` y el nuevo grupo en `test/oportunidades_watcher_test.dart`.

### C2. Unificar el cliente HTTP de Mercado Público y Compra Ágil
- **Prioridad**: Media · **Esfuerzo**: M · **Estado**: Hecho
- **Origen**: [REVISION_CODIGO.md #7](REVISION_CODIGO.md)
- **Descripción**: `mercado_publico_service.dart` y `compra_agil_service.dart` duplican la lógica de request/timeout/parseo de errores y ya divergieron en calidad de mensajes de error.
- **Criterios de aceptación**:
  - [x] Extraer un helper/cliente HTTP compartido (timeout, `SocketException`, `TimeoutException`, parseo JSON, mapeo a `MercadoPublicoException`). Ver `lib/services/mercado_publico_http_client.dart` (`getJson`).
  - [x] Ambos servicios lo usan; los mensajes de error quedan consistentes entre licitaciones y Compra Ágil. `mercado_publico_service.dart` ahora distingue timeout/conexión/otro igual de bien que `compra_agil_service.dart` (antes tenía un `catch (_)` genérico y pobre). Cada servicio conserva su parseo propio del payload (las formas de respuesta de ambos APIs son distintas) y su mensaje específico de 401/403 vía `mensajeSinAcceso`.
  - [x] Sin regresión: tests existentes (si los hay) o manuales de ambos flujos siguen pasando. Ambos servicios ahora aceptan un `http.Client` inyectable; se agregaron tests con `package:http/testing.dart` (`MockClient`) cubriendo el cliente compartido y el parseo específico de cada servicio (paginación de Compra Ágil incluida) — 21 tests nuevos en total.
  - **Nota de la revisión**: los primeros tests con datos de prueba acentuados ("página", "Ágil") fallaban porque `http.Response` sin un header `content-type` explícito codifica el body como `latin1`, y el cliente decodifica como UTF-8. Se corrigió declarando `content-type: application/json` en las respuestas de prueba — es una particularidad del mock de test, no un bug de producción (una API real sí envía el charset correcto).

### C3. Manejo de permisos de cámara/galería denegados
- **Prioridad**: Media · **Esfuerzo**: S · **Estado**: Hecho
- **Origen**: [REVISION_CODIGO.md #10](REVISION_CODIGO.md)
- **Descripción**: en `scan_screen.dart`, las llamadas a `image_picker` no están protegidas; un permiso denegado permanentemente puede mostrar un error genérico o crashear.
- **Criterios de aceptación**:
  - [x] `try/catch` alrededor de `pickImage`/`pickMultiImage` capturando `PlatformException`.
  - [x] Si el permiso está denegado permanentemente, diálogo con botón a `openAppSettings()` (`permission_handler`). Ver `_manejarErrorDeSeleccion` en `scan_screen.dart`.
  - [ ] Probado manualmente en Android denegando el permiso desde ajustes. **Pendiente**: el entorno de desarrollo no tiene emulador Android/iOS ni cámara disponible (solo Windows desktop y navegador), así que esto no se pudo verificar de forma manual. La lógica de detección de códigos de error (`esErrorPermisoDenegado`) está cubierta con tests unitarios.

---

## Épica D — Arquitectura y mantenibilidad (mediano plazo)

### D1. Introducir capa de repositorio / estado compartido para gastos
- **Prioridad**: Media · **Esfuerzo**: L · **Estado**: Hecho
- **Origen**: [REVISION_CODIGO.md #8](REVISION_CODIGO.md)
- **Descripción**: 25 llamadas directas a `DatabaseService.instance` repartidas en 10 pantallas, sin estado compartido ni notificación de cambios entre ellas.
- **Criterios de aceptación**:
  - [x] `ExpensesRepository` (o `ChangeNotifier`/`Provider`) como único punto de acceso a los gastos. Se usó `ChangeNotifier` nativo de Flutter (sin sumar `provider`/`riverpod` como dependencia nueva). Ver `lib/services/expenses_repository.dart`.
  - [x] `home_screen.dart` y `expense_detail_screen.dart` migrados a consumirlo (piloto antes de extender al resto). Ambos envueltos en `ListenableBuilder`; `expense_detail_screen.dart` lee la versión más actual del gasto vía `porId(...)`, con el `widget.expense` original como respaldo.
  - [x] Guardar un gasto desde el flujo de escaneo refresca `home_screen` sin recarga manual. `expense_review_screen.dart` crea el gasto vía `ExpensesRepository.instance.crear(...)`; se quitó el `_loadExpenses()` explícito que hacía `home_screen.dart` al volver de `ScanScreen` — el refresco ahora es 100% reactivo.
  - [x] Documentar el patrón para que el resto de las pantallas (licitaciones, cotizaciones) lo vayan adoptando de forma incremental. Ver `ARCHITECTURE.md`.
  - **Decisión de alcance**: `expense_review_screen.dart` sigue usando `DatabaseService.instance` directo para el chequeo de duplicados (`_buscarDuplicado`, una lectura puntual sin necesidad de reactividad) y para `guardarItemsGasto` (el detalle de ítems queda fuera del alcance de D1, que es específicamente sobre "gastos"). Documentado en `ARCHITECTURE.md` para que no se lea como una omisión.
  - **Cobertura de tests**: 9 tests nuevos en `test/expenses_repository_test.dart` (carga, notificación a listeners, inmutabilidad del getter, creación, eliminación optimista, búsqueda por id). `widget_test.dart` confirma que la app sigue arrancando con el `HomeScreen` migrado.

### D2. Telemetría de calidad del parser OCR
- **Prioridad**: Baja · **Esfuerzo**: M · **Estado**: Hecho
- **Origen**: [REVISION_CODIGO.md #4](REVISION_CODIGO.md)
- **Descripción**: no hay visibilidad de qué tan seguido el parser falla (`descuadre = true`, monto en 0) con boletas reales.
- **Criterios de aceptación**:
  - [x] Registrar localmente (con opt-in del usuario, sin subir la foto ni datos sensibles) tasa de `descuadre`/monto-cero. Ver `lib/services/ocr_telemetry.dart`: solo cuenta agregados (total de escaneos, con descuadre, con monto $0) en `shared_preferences`, nunca la foto ni el texto del OCR. Desactivada por defecto.
  - [x] Pantalla o export simple para revisar esas métricas durante el período de prueba con usuarios reales. Nueva `OcrTelemetriaScreen` (menú ⋮ de `home_screen.dart` → "Calidad del escaneo (OCR)"): switch de opt-in, métricas con sus tasas, botón "Compartir resumen" (texto plano vía `share_plus`) y "Reiniciar métricas".
  - [x] Definir con el cliente si esto se sube a un backend propio o queda solo local por ahora. **Decisión**: solo local por ahora — el proyecto no tiene backend propio.

### D3. Actualizar y endurecer reglas de lint
- **Prioridad**: Baja · **Esfuerzo**: S · **Estado**: Hecho
- **Origen**: [REVISION_CODIGO.md #9](REVISION_CODIGO.md)
- **Descripción**: `flutter_lints` está en `^3.0.0` (desactualizado) y `analysis_options.yaml` no agrega reglas propias.
- **Criterios de aceptación**:
  - [x] Actualizar `flutter_lints` a la última versión compatible con el SDK del proyecto. `^3.0.0` → `^6.0.0`.
  - [x] Sumar `avoid_print`, `always_declare_return_types` y otras reglas acordadas con el equipo. También `prefer_single_quotes`, `unnecessary_lambdas`, `unnecessary_this`, `prefer_final_locals`.
  - [x] `flutter analyze` pasa sin warnings nuevos tras el cambio (o se resuelven los que aparezcan). Se resolvieron los 24 issues que aparecieron: 8 de `unintended_html_in_doc_comment` (un doc comment con `<TED>...` en `ted_service.dart` que el nuevo set de reglas interpreta como HTML) y 16 entre `unnecessary_lambdas`/`prefer_final_locals`.

### D4. Limpieza del `CREATE TABLE` de `ordenes_compra`
- **Prioridad**: Baja · **Esfuerzo**: S · **Estado**: Hecho
- **Origen**: [REVISION_CODIGO.md — hallazgos menores](REVISION_CODIGO.md)
- **Descripción**: `fechaPagoEsperada` se agrega con un `ALTER TABLE` aparte inmediatamente después del `CREATE TABLE` en `_createDB`, en vez de estar declarada directamente en la tabla.
- **Criterios de aceptación**:
  - [x] Columna `fechaPagoEsperada` incluida directo en `_createOrdenesCompraTable`.
  - [x] Se quita el `ALTER TABLE` redundante de `_createDB`.
  - **Ajuste sobre el criterio original**: seguir el criterio al pie de la letra (dejar intacto el `ALTER TABLE` de `oldVersion < 9`) habría reintroducido el mismo bug de columna duplicada corregido en A1 — cualquier usuario saltando de antes de v8 a v9+ en una pasada habría chocado con `fechaPagoEsperada` duplicada, igual que pasó con `cantidad`. Se aplicó el mismo guard (`if (oldVersion >= 8)`) antes del `ALTER TABLE`, con test de regresión dedicado (`test/database_service_test.dart`, esquema v8 reconstruido) que cubre tanto el esquema como la preservación de datos de una orden de compra cargada antes de la migración.

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
