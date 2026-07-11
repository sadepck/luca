# Luca

Aplicación Flutter para escanear tickets/boletas y registrar gastos automáticamente, con soporte adicional para monitorear licitaciones y Compras Ágiles del mercado público chileno (ChileCompra).

## Funcionalidades

- **Escaneo de tickets**: toma una o varias fotos de una boleta/factura (incluso tickets largos capturados en varias fotos) y extrae el monto, ítems y fecha mediante OCR (Google ML Kit).
- **Lectura del timbre electrónico (TED/PDF417)**: cuando la boleta lo trae, se leen los datos tributarios (folio, tipo de documento, RUT y nombre del emisor, montos neto/IVA) directamente del timbre del SII como complemento al OCR.
- **Registro y categorización de gastos**: guarda cada gasto con su detalle de ítems, categoría, fecha y la foto del ticket original.
- **Flujo de caja**: cálculo y visualización de ingresos/egresos esperados (`fl_chart`).
- **Mercado Público**: búsqueda de licitaciones activas, por fecha o por código, usando el ticket personal del usuario en el API de ChileCompra (`api.mercadopublico.cl`).
- **Compra Ágil**: búsqueda de oportunidades de Compra Ágil activas (`api2.mercadopublico.cl`), con filtro por palabra clave y región.
- **Cotizaciones y órdenes de compra**: generación de cotizaciones y órdenes de compra a partir de oportunidades guardadas.
- **Notificaciones en segundo plano**: revisión periódica de nuevas oportunidades que coincidan con palabras clave configuradas, usando `workmanager` y notificaciones locales.
- **Exportación**: exportar/compartir información generada (`share_plus`).

## Stack técnico

- [Flutter](https://flutter.dev/) / Dart (SDK `>=3.0.0 <4.0.0`)
- `sqflite` — persistencia local (SQLite)
- `google_mlkit_text_recognition` / `google_mlkit_barcode_scanning` — OCR y lectura del timbre PDF417
- `image_picker` — captura de fotos
- `workmanager` + `flutter_local_notifications` — tareas periódicas y notificaciones
- `fl_chart` — gráficos de flujo de caja
- `http` — consumo de los APIs públicos de ChileCompra
- `shared_preferences` — configuración local del usuario (ticket de API, palabras clave)

## Requisitos previos

- [Flutter SDK](https://docs.flutter.dev/get-started/install) instalado y configurado (`flutter doctor` sin errores).
- Un dispositivo/emulador Android o iOS, o soporte de escritorio/web habilitado según la plataforma en la que se quiera correr.

## Puesta en marcha

```bash
flutter pub get
flutter run
```

## Configuración del API de Mercado Público

Las funciones de licitaciones y Compra Ágil requieren un **ticket personal**, gratuito, que cada usuario obtiene con su Clave Única en:

https://api.mercadopublico.cl/modules/IniciarSesion.aspx

El ticket se ingresa dentro de la app (pantalla de configuración de Mercado Público) y se guarda localmente en el dispositivo con `shared_preferences`. **No se almacena en el código ni en este repositorio.**

## Tests

```bash
flutter test
```

## Estructura del proyecto

```
lib/
  main.dart
  models/      # Modelos de datos (Expense, Licitacion, CompraAgil, etc.)
  screens/     # Pantallas de la app
  services/    # OCR, base de datos, APIs de Mercado Público, notificaciones, etc.
test/          # Tests unitarios
```
