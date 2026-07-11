# Revisión de código — Luca

Registro de hallazgos de la revisión de código para el cliente. Cada área tiene una prioridad, el estado actual y la evidencia (archivo/línea) en la que se basa el hallazgo.

Estado: `Pendiente` · `En progreso` · `Resuelto` · `Descartado`

---

## 1. Cobertura de tests muy desbalanceada

- **Prioridad**: Alta
- **Estado**: Pendiente

Solo existen 4 archivos en `test/`: `ocr_service_test.dart`, `flujo_caja_calculator_test.dart`, `proveedores_test.dart` y el `widget_test.dart` por defecto.

- `lib/services/database_service.dart` no tiene ningún test, pese a manejar 9 versiones de migraciones de esquema encadenadas (`_upgradeDB`, líneas 59-90). Un error ahí corrompe la base de datos de usuarios existentes en producción, sin forma de detectarlo antes del release.
- `lib/services/oportunidades_watcher.dart` (deduplicación de notificaciones de licitaciones, núcleo del feature de Mercado Público) tampoco tiene tests.
- `lib/services/mercado_publico_service.dart` y `lib/services/export_service.dart` igual.

**Sugerencia**: priorizar tests de migraciones de DB (abrir cada versión intermedia y verificar el esquema resultante) y del flujo de dedup de oportunidades antes que ampliar el parser OCR, que ya está relativamente bien cubierto.

---

## 2. No hay CI configurado

- **Prioridad**: Alta
- **Estado**: Pendiente

No existe `.github/workflows/` ni ningún otro pipeline. `flutter analyze` y `flutter test` no corren automáticamente en push/PR, así que una regresión en migraciones de DB o en el parser OCR puede llegar directo a un build de release sin que nadie lo note.

**Sugerencia**: workflow mínimo de GitHub Actions con `flutter pub get`, `flutter analyze` y `flutter test` en cada PR.

---

## 3. Manejo de errores silencioso en el flujo de notificaciones en background

- **Prioridad**: Media-Alta
- **Estado**: Pendiente

En `lib/services/oportunidades_watcher.dart:26-29`, si falla la llamada al API de Mercado Público el error se traga sin logging ni backoff (`catch (_) { return 0; }`). Sumado a que en iOS el background fetch de Workmanager no está garantizado (ver comentario en `lib/services/background_tasks.dart:18-20`), el usuario puede dejar de recibir alertas de licitaciones por semanas sin ningún indicio.

**Sugerencia**: persistir timestamp/resultado del último chequeo (éxito, error, sin coincidencias) y mostrarlo en la pantalla de configuración de Mercado Público.

---

## 4. El parser OCR opera "a ciegas" en producción

- **Prioridad**: Media
- **Estado**: Pendiente

`lib/services/ocr_service.dart` (~950 líneas de heurísticas con regex) es la pieza más compleja del proyecto — y la que más impacta al usuario si falla, ya que es el corazón del producto. No hay telemetría ni logging de casos donde `descuadre = true` o el monto quedó en 0, así que no hay visibilidad de qué tan seguido falla con boletas reales.

**Sugerencia**: registrar (localmente o remoto, respetando privacidad) la tasa de `descuadre`/monto-cero para poder priorizar mejoras del parser con datos reales en vez de a ciegas.

---

## 5. El ticket de Mercado Público se guarda sin cifrar

- **Prioridad**: Media
- **Estado**: Pendiente

El ticket personal (ligado a la Clave Única del usuario) se persiste con `shared_preferences`, que en Android es un XML en texto plano. El propio `README.md` ya reconoce que es un dato sensible ("no se almacena en el código ni en este repositorio").

**Sugerencia**: migrar el almacenamiento del ticket a `flutter_secure_storage` (Keystore en Android / Keychain en iOS).

---

## 6. Fotos de boletas guardadas con la ruta temporal de `image_picker`

- **Prioridad**: Alta
- **Estado**: Pendiente

En `lib/screens/expense_review_screen.dart:290`, el `imagePath` que se guarda en SQLite es directamente `widget.imagePaths.first` — la ruta que devuelve `image_picker`, que apunta a un directorio de caché/temporal del sistema operativo (especialmente volátil en iOS; en Android puede limpiarse bajo poca memoria). Con el tiempo, `Image.file(File(expense.imagePath))` en `expense_detail_screen.dart` puede quedar apuntando a un archivo que ya no existe, mostrando un ícono roto y perdiendo la evidencia original de la boleta — justo el dato que un usuario necesita para respaldar el gasto ante una fiscalización.

**Sugerencia**: al crear el gasto, copiar la foto a un directorio persistente de la app (`getApplicationDocumentsDirectory()` de `path_provider`) y guardar esa ruta en vez de la original.

---

## 7. Duplicación e inconsistencia entre los clientes de Mercado Público y Compra Ágil

- **Prioridad**: Media
- **Estado**: Pendiente

`lib/services/mercado_publico_service.dart` y `lib/services/compra_agil_service.dart` implementan la misma lógica (armar query, hacer `http.get` con timeout, interpretar JSON, mapear errores HTTP a `MercadoPublicoException`) de forma independiente y ya divergieron: `compra_agil_service.dart` distingue `TimeoutException`/`SocketException` con mensajes específicos y útiles para el usuario, mientras que `mercado_publico_service.dart` usa un `catch (_)` genérico con un mensaje más pobre. Cualquier mejora futura (reintentos, logging, nuevos códigos de error) hay que aplicarla dos veces o se vuelve a desalinear.

**Sugerencia**: extraer un cliente HTTP compartido (manejo de timeout/conexión/parseo de errores) del que ambos servicios hereden o delegen.

---

## 8. Sin capa de repositorio — 25 llamadas directas a `DatabaseService.instance` repartidas en 10 pantallas

- **Prioridad**: Media
- **Estado**: Pendiente

Cada `Screen` es un `StatefulWidget` que llama directo a `DatabaseService.instance` y mantiene su propia copia del estado (ver `home_screen.dart:29-35` como ejemplo). No hay un único punto de verdad ni notificación de cambios entre pantallas: por ejemplo, al guardar un gasto desde el flujo de escaneo, `home_screen.dart` no se entera solo — depende de que cada pantalla recargue manualmente al volver a mostrarse. A medida que crezca la app esto va a generar bugs de datos desactualizados y lógica de carga duplicada.

**Sugerencia**: introducir una capa de repositorio/estado compartido (`ChangeNotifier`, `Provider`/`Riverpod`, o similar) por encima de `DatabaseService`, aunque sea de forma incremental empezando por `expenses`.

---

## 9. Reglas de lint por defecto, sin personalizar

- **Prioridad**: Baja
- **Estado**: Pendiente

`analysis_options.yaml` solo incluye `package:flutter_lints/flutter.yaml` sin agregar ninguna regla adicional, y `flutter_lints` está fijado en `^3.0.0` en `pubspec.yaml` (versión antigua; ya existen releases 5.x con más reglas y compatibilidad con Dart más reciente). No hay reglas que fuercen, por ejemplo, evitar `print` en producción, preferir `const`, o limitar el uso de tipos dinámicos — relevante en un proyecto con tanta lógica de parsing basada en `Map<String, dynamic>` como `ocr_service.dart`.

**Sugerencia**: actualizar `flutter_lints` y evaluar sumar `avoid_print`, `always_declare_return_types` y reglas de estilo consistentes con lo que ya sigue el equipo (el código ya es prolijo, esto solo lo formaliza).

---

## 10. Sin manejo explícito de permisos de cámara/galería denegados

- **Prioridad**: Media
- **Estado**: Pendiente

En `lib/screens/scan_screen.dart`, las llamadas a `image_picker` (`pickImage`/`pickMultiImage`, alrededor de las líneas 64-80) no están envueltas en `try/catch`. Si el usuario denegó permanentemente el permiso de cámara o galería, `image_picker` puede lanzar una `PlatformException` que no se captura ahí (el único `try/catch` de la pantalla envuelve `_procesarTicket`, no la selección de imágenes) — el usuario ve un error genérico o un crash en vez de una guía clara para habilitar el permiso desde ajustes del sistema.

**Sugerencia**: envolver la selección de imágenes en su propio manejo de errores y, si el permiso está denegado, mostrar un diálogo que dirija a la configuración de la app (`permission_handler` ofrece `openAppSettings()` para esto).

---

## Otros hallazgos menores (no priorizados)

- `lib/services/database_service.dart:55-56`: en `_createDB` se crea `ordenes_compra` y luego se le agrega la columna `fechaPagoEsperada` con un `ALTER TABLE` aparte, en vez de incluirla directo en el `CREATE TABLE`. No es un bug (no hay instalación limpia con columna duplicada), pero es una fuente de confusión a futuro — más simple declarar la columna en la creación.
