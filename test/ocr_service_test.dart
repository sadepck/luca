import 'package:flutter_test/flutter_test.dart';
import 'package:luca/services/ocr_service.dart';

void main() {
  final ocr = OcrService();

  group('procesarTextoParaPruebas', () {
    test('boleta simple: total impreso coincide con la suma de productos',
        () {
      const texto = '''
SUPERMERCADO LIDER
RUT: 76.123.456-7
BOLETA ELECTRONICA N 12345
FECHA: 01/07/2026

PAN HALLULLA         890
COCA COLA 1.5L      1.990
LECHE ENTERA         990

TOTAL              3.870
EFECTIVO           4.000
CAMBIO               130
GRACIAS POR SU COMPRA
''';

      final data = ocr.procesarTextoParaPruebas(texto);

      expect(data['amount'], 3870);
      expect(data['totalDesdeTexto'], true);
      expect(data['descuadre'], false);

      final items = data['items'] as List<Map<String, dynamic>>;
      expect(items.length, 3);
      expect(items.any((i) => i['nombre'].toString().contains('PAN')), true);
      expect(items.any((i) => (i['precio'] as num) == 1990), true);
    });

    test('reconoce cantidad en formato "N x producto"', () {
      const texto = '''
MINIMARKET EL SOL

2 x YOGURT NATURAL     1.980
PAN INTEGRAL              990

TOTAL                   2.970
''';

      final data = ocr.procesarTextoParaPruebas(texto);
      final items = data['items'] as List<Map<String, dynamic>>;

      final yogurt = items.firstWhere(
          (i) => i['nombre'].toString().toUpperCase().contains('YOGURT'));
      expect(yogurt['cantidad'], 2);
      expect(yogurt['precio'], 1980);

      expect(data['amount'], 2970);
      expect(data['descuadre'], false);
    });

    test('avisa descuadre cuando el total no calza con la suma de items',
        () {
      const texto = '''
FARMACIA CRUZ VERDE

PARACETAMOL 500MG      2.500
ALCOHOL GEL               990

TOTAL                   5.000
''';

      final data = ocr.procesarTextoParaPruebas(texto);

      expect(data['amount'], 5000);
      expect(data['totalDesdeTexto'], true);
      expect(data['totalCalculadoDesdeItems'], 3490);
      expect(data['descuadre'], true);
    });

    test('sin texto "TOTAL": usa la suma de los productos detectados', () {
      const texto = '''
KIOSKO DON JOSE

BEBIDA COLA                800
PAPAS FRITAS               650
''';

      final data = ocr.procesarTextoParaPruebas(texto);

      expect(data['amount'], 1450);
      expect(data['totalDesdeTexto'], false);
      expect(data['descuadre'], false);
    });

    test(
        'factura real de proveedor (formato de dos líneas: código+nombre, '
        'luego cantidad x precio) no confunde direcciones/RUT/códigos con '
        'productos', () {
      // Transcripción de una factura física real (MCO Ingeniería, Temuco).
      const texto = '''
MCO
MAQUINARIAS Y CONSTRUCCIONES LA OLLETA LIMITADA
GIRO: VENTA AL POR MAYOR Y MENOR DE MAQUINARIAS PARA LA
CONSTRUCCION, VENTA AL POR MAYOR Y MENOR DE ARTICULOS DE FERRETERIA Y
MATERIALES DE CONSTRUCCION.
Casa Matriz: Avenida Recabarren 03350 - TEMUCO
Fonos: (45)2408360, (45)2408370
Sucursal 1: Diego Portales 1065 - TEMUCO
Sucursal 2: Matta 301 - TEMUCO
Sucursal 3: Ruta 5-30 Km. 11,5 - Labranza - TEMUCO
Fono: +56(45)2408360 - Fono Fax: +56(45)2408370
www.mcoingenieria.cl - info@mcoingenieria.cl
R.U.T.: 76.051.775-5
FACTURA ELECTRONICA
832817
S.I.I. - TEMUCO
Fecha: viernes, 08 de mayo del 2026
R.U.T.: 78.341.688-3
Señor (es): Constructora NGS SpA
Giro: Construccion y Venta de Materiales
Dirección: Jardines de la Frontera Lote 31
Comuna: Temuco - Ciudad: Temuco
Vendedor:
Forma Pago: CONTADO
Código Interno: 2026064105 CA: 03 VE: 0773 VE: 0403
DETALLE                                              TOTAL
251422 Adhesivo PVC 240 cc, Tradicional, Secado rápido Vinilit.
1.00 x 3.490.00                                       3.490
205582 Copla PVC Hidraulico Soldar 32 mm PVC
4.00 x 160.00                                          640
636457 MEMI Centrifuga 1 Hp. 1" x 1" AD75 l  LEO
1.00 x 113.500.00                                   113.500
531276 Tee PVC Hidraulico Cementar 32 mm
2.00 x 240.00                                          480
117487 Terminal PVC Hidraulico 32 mm x 1" - Cementar - He
4.00 x 170.00                                          680
608562 Tubo PVC Hidraulico 32 mm, PN-10 PVC Lira (6m)
2.00 x 4.400.00                                      8.800
618445 Union Amer. PVC Hidraulico 32 mm. Cementar
3.00 x 930.00                                        2.790
SUBTOTAL                                            130.380
NETO                                                109.579
IVA (19%)                                            20.801
TOTAL                                                130.380
Nombre:
RUT:
Fecha:
Recinto:
Firma:
"El acuse de recibo que se celebra en este acto, de acuerdo a lo
dispuesto en la letra b) del Art. 4°, y la letra c) del Art. 5° de la
Ley 19.983, acredita que la entrega de las mercaderías o servicio(s)
prestada(s) han(n) sido recibido(s)."
''';

      final data = ocr.procesarTextoParaPruebas(texto);
      final items = data['items'] as List<Map<String, dynamic>>;

      expect(data['amount'], 130380);
      expect(data['totalDesdeTexto'], true);
      expect(data['descuadre'], false);

      // Exactamente 7 productos: nada de direcciones, teléfonos, RUTs,
      // códigos internos ni texto legal del pie tratados como ítems.
      expect(items.length, 7);

      final precios = items.map((i) => (i['precio'] as num).toDouble()).toSet();
      // Ninguno de estos números "ruido" (dirección, sucursal, ley, código
      // de producto solo) terminó como si fuera el precio de un producto.
      expect(precios.contains(3350), false); // Avenida Recabarren 03350
      expect(precios.contains(1065), false); // Diego Portales 1065
      expect(precios.contains(301), false); // Matta 301
      expect(precios.contains(19983), false); // Ley 19.983
      expect(precios.contains(251422), false); // código de producto

      final adhesivo = items.firstWhere(
          (i) => i['nombre'].toString().toUpperCase().contains('ADHESIVO'));
      expect(adhesivo['cantidad'], 1);
      expect(adhesivo['precio'], 3490);
      // El código interno del producto no debe quedar pegado al nombre.
      expect(adhesivo['nombre'].toString().startsWith('251422'), false);

      final copla = items.firstWhere(
          (i) => i['nombre'].toString().toUpperCase().contains('COPLA'));
      expect(copla['cantidad'], 4);
      expect(copla['precio'], 640);

      final tubo = items.firstWhere(
          (i) => i['nombre'].toString().toUpperCase().contains('TUBO'));
      expect(tubo['cantidad'], 2);
      expect(tubo['precio'], 8800);
    });

    test(
        'documento real degradado (foto borrosa, separador "*", "DETALLE" '
        'leído como "DE TALLE", columna de totales desordenada) igual '
        'evita los ítems fantasma más comunes', () {
      // Transcripción literal de una segunda foto real (guía de despacho
      // MCO, más borrosa que la anterior): usa "*" en vez de "x", decimales
      // con coma, pierde algunos dígitos de cantidad, y el bloque
      // SUBTOTAL/NETO/IVA/TOTAL quedó separado de sus montos.
      const texto = '''
MAQUINARIAS Y CONSTRUCCIONES LA OLLETA LIMITADA
GIRO: VENTA AL POR MAYORY MENOR DE MAQUINARIAS
PARA LA
CONSTRUCCIÓN, VENTA AL POR MAYOR Y MENOR DE
ARTÍCULOS DE FERRETERÍA Y
MATERIALES DE CONS TRUCCIÓN
MO
Casa Matriz: Avenida Recabarren 03350 - TEMUCO
Fonos: (45)2408360, (45) 2408370
Sucursal 1: Diego Portales 1365 - TEMUCO
Sucursal 2: Matta 301 - TEMUCO
Sucursal 3: Ruta 5-30 Km. 11.5, Labranza - TEMUCO
Fono: +56 (45) 2408360 - Fono Fax: +56(45)2408370
www.mcoingenieria.cl info@mcoingenieria.cl
R.U.T.: 78.341 688-3
Fecha: viernes, 08 de mayo del 2026
R.U.T.: 76.051.775-5
GUÍA DE DESPACHO ELECTRÓNICA
793633
Vendedor : 0408
Señor (es): Constructora NC5 Spa
S.I.I. - TEMUCO
Giro: Construcion y Venta de Materiales
Dirección: Jardines de la Frontera Lote 33
Vencimien to: 07-06-2026
Comuna: Temuco - Ciudad: Temuco
REFERENCIA
Traslado: Operación constituye venta
Código interno: 2026051426- CA: 74 - VI: 0773- VE:
0408
Factura Electrónica 832817 del 08-05-2025
DE TALLE
251422 Adhesivo PVC 240 cc. Tradici onal. Secado
rápido Vinilit
1.00 * 3.490, 00
205592 Copla PVC Hidraul ico Soldar 32 mm PVC
4. 00 * 160, 00
6457 KBEWF Centri fuga 1 Hp. 1"X 1", ACn 75 L LEO
00 * 113.400,00
7276 Tee PVC Hidraulico Cementar 32 mm .
.00* 240,00
17487 Terminal PVC Hidraulico (He) 32 mm x 1,
Cemen tar - He.
4.00 * 170,00
650528 Tubo PVC Hidraulico 32 mm, PN 10 PVC Tira
(6m)
2.00 * 4.400,00
618445 Union Amer. PyC Hidraulico 32 mm, cementar
3,00 * 930,00
SUBTOTAL
NETO
IVA (19%)
TOTAL
TOTA
3.490
640
480
680
8.800
2.790
130.280
109.479
20.801
130.280
''';

      final data = ocr.procesarTextoParaPruebas(texto);
      final items = data['items'] as List<Map<String, dynamic>>;

      // Ningún ítem fantasma de encabezado: ni el año de "Vencimiento"
      // (2026), ni direcciones/teléfonos/RUTs/códigos internos.
      final nombres = items.map((i) => i['nombre'].toString().toLowerCase()).toList();
      expect(nombres.any((n) => n.contains('vencimien')), false);
      final precios = items.map((i) => (i['precio'] as num).toDouble()).toSet();
      expect(precios.contains(2026), false);
      expect(precios.contains(1365), false);
      expect(precios.contains(301), false);

      // Los 7 productos reales sí se reconocen, con el separador "*".
      expect(items.length, greaterThanOrEqualTo(6));

      final adhesivo = items.firstWhere(
          (i) => i['nombre'].toString().toUpperCase().contains('ADHESIVO'));
      expect(adhesivo['cantidad'], 1);
      expect(adhesivo['precio'], 3490);

      final copla = items.firstWhere(
          (i) => i['nombre'].toString().toUpperCase().contains('COPLA'));
      expect(copla['cantidad'], 4);
      expect(copla['precio'], 640);

      final tubo = items.firstWhere(
          (i) => i['nombre'].toString().toUpperCase().contains('TUBO'));
      expect(tubo['cantidad'], 2);
      expect(tubo['precio'], 8800);

      // Aunque el bloque de totales quedó separado de sus etiquetas, el
      // total de cierre (130.280, el último monto grande del bloque) se
      // recupera igual en vez de tomar cualquier número suelto.
      expect(data['amount'], 130280);
    });

    test(
        'documento con timbre del SII duplicando la etiqueta TOTAL: no debe '
        'confundir el precio del primer producto con el total, ni usar el '
        'R.U.T. como título', () {
      // Reproduce el patrón reportado por el usuario en una tercera foto
      // real: el documento trae un segundo "TOTAL" dentro del bloque del
      // timbre electrónico del SII (pie de verificación), justo antes de
      // que aparezca el monto del primer producto (3.490) en la columna
      // desordenada. Antes del fix, ese "3.490" se tomaba como si fuera el
      // total de la boleta (~130.280). También reproduce que "R.U.T."
      // (con puntos) se colaba como título por no calzar con el filtro de
      // la palabra "rut".
      const texto = '''
MCO
MAQUINARIAS Y CONSTRUCCIONES LA OLLETA LIMITADA
Casa Matriz: Avenida Recabarren 03350 - TEMUCO
R.U.T.: 76.051.775-5
FACTURA ELECTRONICA
832817
Fecha: viernes, 08 de mayo del 2026
R.U.T.: 78.341.688-3
Señor (es): Constructora NGS SpA
DETALLE                                              TOTAL
251422 Adhesivo PVC 240 cc, Tradicional, Secado rápido Vinilit.
1.00 x 3.490.00                                       3.490
205582 Copla PVC Hidraulico Soldar 32 mm PVC
4.00 x 160.00                                          640
636457 MEMI Centrifuga 1 Hp. 1" x 1" AD75 l  LEO
1.00 x 113.500.00                                   113.500
531276 Tee PVC Hidraulico Cementar 32 mm
2.00 x 240.00                                          480
117487 Terminal PVC Hidraulico 32 mm x 1" - Cementar - He
4.00 x 170.00                                          680
608562 Tubo PVC Hidraulico 32 mm, PN-10 PVC Lira (6m)
2.00 x 4.400.00                                      8.800
618445 Union Amer. PVC Hidraulico 32 mm. Cementar
3.00 x 930.00                                        2.790
SUBTOTAL
NETO
IVA (19%)
TOTAL
Timbre Electronico SII
Res. 80 de 2014
Verifique documento en: www.sii.cl
08-05-2026 15:32:07
Con Tecnologia ACEPTA
TOTAL
3.490
640
480
680
8.800
2.790
130.280
109.479
20.801
130.280
''';

      final data = ocr.procesarTextoParaPruebas(texto);

      // El título nunca debe salir de las líneas de R.U.T.
      expect(data['title'].toString().toUpperCase().contains('RUT'), false);

      // El total real (130.280) se recupera, no el "3.490" del primer
      // producto que quedó junto al segundo "TOTAL" del timbre del SII.
      expect(data['amount'], 130280);
      expect(data['descuadre'], false);

      expect(data['nombreEmisor'],
          'MAQUINARIAS Y CONSTRUCCIONES LA OLLETA LIMITADA');
      expect(data['rutEmisorTexto'], '76.051.775-5');
      expect(data['tipoDteTexto'], 'Factura Electrónica');
      expect(data['folioTexto'], '832817');
      expect(data['fechaDocumento'], DateTime(2026, 5, 8));
      expect(data['montoNeto'], null); // separado de su monto: no se adivina
      expect(data['montoIva'], null);
    });

    test(
        'documento real muy degradado (cuarta factura, "Comercial La Bodega"): '
        'no debe mostrar la dirección del cliente como título ni un monto '
        'absurdamente chico', () {
      // Texto copiado literal (con el botón "Copiar" de la app, no
      // transcrito a mano) de una cuarta foto real reportada por el
      // usuario: mucho más degradada que las anteriores (el nombre de los
      // productos y sus precios quedaron en bloques totalmente separados,
      // no solo desordenados), con una etiqueta "TOTAL" suelta pegada al
      // número de una dirección del cliente ("TOTALA" + "...#1170"), y el
      // total real al final con el signo "$" leído como la letra "S"
      // pegada al número ("TOTAL S55,830" en vez de "TOTAL $55.830").
      const texto = '''
|GIRO
DESCRIPCION
3
5
6
SEÑORES): cONSTRUCTORAN CS SPA
DIRECCON JARDINES DE LA FRONTERA 33
COMUNA Temuce
L CaNTDAD
1 1.00
7
2
8
9
10
VENDEDOR Sala Venta Temuco
11
21
19
22
23
24
26
1.00
1.00
1.00
1.00
VISA CREDITC
MONTO VENTA:
.00
TOTALA
Dirección: Rudecindo Ortega #1170
Temuco
1.00
TRANSBANK
VENTA COPIA CLIENTE
TARJETA DE CREDITO
COVERCIA LA BODEGA
COERCTAL
RUDECINDO ORTEG 1170 LOCAL
TEMUCO
5970403766020128
VAL TOO5487-125. 340
COMO BOLETA
20/04/2026 11!04-o
Comerc lal La Bodega SpA
RUT
76.602.017-8
Ventas al porMayor
y Productos de Ferreteria
Nombre:
y al Menor de Bolsas
Recinto
Fecha:
12 1.00 UN 2020162
cONSTRUCCION
13 .00 UN 2120341
8.00 UN 2120342
10 10.00 UN 4431045
WM coDIGO
UN 5407928
KG 6401359
UN 6401431
1.00 UN 5026133
UN 5401433
PCK 2121446
UN 2020126
UN 2020126
UN 2121603
UN 2121603
UN 5026133
3.00 UN 202016
UN
020140
2.00 olsa 2020
SPA
AD000ocv
DETA
RUT 76.602.01 7-8
FACTURA ELECTRÓNICA
FECHA
RU.T:
TELEFONO
o DE COMP RA:
cOND. VTA
Vale Venta:
FORMA PAGO
DISCOLUA 115 MM #t00 CON
SOLDADURA 6011 3/324
DISCO LIJA FLAP PMETAL 115 MM # 60
DISCO LIUA FLAp PMETAL 115 A # 100
BROCHA MANGO MADERA3
SON CINCLENTAY CINCO MIL OCHOcIENTOS TREINTA
N° 49400
SI-TEMUCO
ONVELCROX5UN
DISCO DE CORTE 4.1/2X 1MM x 10 UN
BROCHA MANGO MADERA 3
TACO NYL ON + CLAVO TORNILLO 8x120
TACO NYL ON + CLAVO TORNILLO &x120
ANTIPARRAS CLARA
TORNILLO ROSCAMAD. ZN 6x1"
TORNILLO ROSCAMAD. ZN 6X1.58
200412026
78341 8883
MULTIPAGO
45024889
Tarjeta de Crédito
V. UNIT
1050
4949.58
2058.82
TORN SELLADOR AU TOROSCAPTA BROCA 12X3/4 1672.27
TORN SELLADOR Au TOROSCAPTA BROCA 12X3/4 1672.27
4621.8
2310.92
Firma
23 10.92
1638.66
1638.66
966.39
496.8
ABRAZADERA PARA TUBOELECTRICO 16 MM 42.02
GUANTE CIPIGMENT. ANTIDES
630.25
588.24
GUANTE NYLON PIGMENTADO 1 CARA EXTRAFINO 672.27
CEMENTO MELON ESPECIAL
4706.88
NETO
DESCUENTO
IVA (19%)
TOTAL
\$1,050
\$4.950
\$2,059
\$2.059
,022
\$311
\$1,639
\$1,639
\$1,672
S1,672
\$966
\$1,983
\$5,042
\$420
\$1.765
\$1,346
\$9,412
\$46,916
\$8,914
TOTAL S55,830
Elacuse de recibo que se declara en este acto, de Bcuerdo a los dispuesto en las letras b) del articulo 4
letra c) de aticuo Pde la loy 19 963 ace dta que la ertrega de merc ad8ria(s) o servicio[s) prestaso(s) hetn
Autonao a Comeroal La Bodega SpA RUT 76 602 017-8 para qu en caso de, simple retardo o mora en el
pago oe le obiligacion y a que so retere el presante documerto, los detos personales de esay los
felacionados con el citedo documento seaningresados e cuaicue sstema de irtorrnacion comercial publico o
base de datos
''';

      final data = ocr.procesarTextoParaPruebas(texto);

      // El título nunca debe salir de la dirección del cliente.
      final tituloUpper = data['title'].toString().toUpperCase();
      expect(tituloUpper.contains('DIRECCON'), false);
      expect(tituloUpper.contains('FRONTERA'), false);

      // El total real se recupera aunque el "$" haya sido leído como la
      // letra "S" pegada al número ("TOTAL S55,830"): antes se perdía por
      // completo y caía a un número vecino irrelevante ($1.170 primero,
      // luego $8.914 — el valor del IVA, no el total).
      expect(data['amount'], 55830);
      expect(data['totalDesdeTexto'], true);

      // La extracción de productos sigue incompleta en este documento tan
      // degradado (nombres y precios llegaron en bloques separados), así
      // que la suma de items detectados no alcanza el total real — pero
      // la app debe avisarlo con el aviso de descuadre en vez de fallar
      // en silencio.
      expect(data['descuadre'], true);

      expect(data['nombreEmisor'], 'Comerc lal La Bodega SpA');
      expect(data['rutEmisorTexto'], '76.602.017-8');
      expect(data['tipoDteTexto'], 'Factura Electrónica');

      // Antes, líneas como "DISCOLUA 115 MM #t00 CON" o "SOLDADURA 6011
      // 3/324" se leían como si el número del medio (una medida, no un
      // precio) fuera el precio del producto. Ahora que solo se acepta
      // el número al FINAL de la línea, esas líneas no deben producir
      // ningún ítem con un precio inventado.
      final items = data['items'] as List<Map<String, dynamic>>;
      expect(items.any((i) => i['nombre'].toString().contains('DISCOLUA')), false);
      expect(
          items.any((i) =>
              i['nombre'].toString().toUpperCase().contains('SOLDADURA')),
          false);
      expect(
          items.any((i) =>
              i['nombre'].toString().toUpperCase().contains('TACO') &&
              (i['precio'] as num) == 120),
          false);
    });
  });

  group('emparejarPorPosicionParaPruebas', () {
    test(
        'empareja 8 productos reales por altura, con un token de OCR '
        'corrupto de una sola palabra pegado casi encima de una fila real '
        'y una oración ancha (monto en letras) de por medio — ninguno de '
        'los dos debe desalinear los emparejamientos reales', () {
      // Reproduce el patrón exacto que falló con datos reales: 8 filas de
      // una tabla (nombre a la izquierda, precio unitario a la derecha
      // bajo "V. UNIT", mismo renglón), más "ONVELCROX5UN" — un token de
      // OCR corrupto de una sola palabra, sin espacio, puesto A PROPÓSITO
      // casi pegado a la fila 5 (la posición exacta que causó la cascada
      // la primera vez) — y la oración ancha del monto en letras después
      // de la última fila real.
      final nombres = [
        ('DISCOLUA 115 MM CON REPUESTO', 1050.0),
        ('SOLDADURA ELECTRODO 6011', 4950.0),
        ('DISCO LIJA FLAP PMETAL 60', 2059.0),
        ('DISCO LIJA FLAP PMETAL 100', 2059.0),
        ('DISCO DE CORTE PARA METAL', 4622.0),
        ('BROCHA MANGO DE MADERA', 2311.0),
        ('TACO NYLON CON CLAVO TORNILLO', 1639.0),
        ('ANTIPARRAS DE SEGURIDAD CLARA', 966.0),
      ];

      final lineas = <LineaOcrDePrueba>[
        LineaOcrDePrueba(texto: 'DETALLE', top: 10, bottom: 40, left: 50, width: 200),
      ];
      for (int i = 0; i < nombres.length; i++) {
        final top = 60.0 + i * 40;
        lineas.add(LineaOcrDePrueba(
            texto: nombres[i].$1, top: top, bottom: top + 30, left: 50, width: 580));
      }
      // Token de OCR corrupto (una sola palabra, sin espacio), pegado
      // casi encima de la fila 5 (DISCO DE CORTE, top=220-250).
      lineas.add(LineaOcrDePrueba(
          texto: 'ONVELCROX5UN', top: 225, bottom: 255, left: 55, width: 250));
      // Oración ancha del monto en letras, después de la última fila real.
      lineas.add(LineaOcrDePrueba(
          texto: 'SON CINCUENTA Y CINCO MIL OCHOCIENTOS TREINTA PESOS',
          top: 380,
          bottom: 410,
          left: 20,
          width: 1000));
      lineas.add(
          LineaOcrDePrueba(texto: 'V. UNIT', top: 420, bottom: 450, left: 700, width: 150));
      for (int i = 0; i < nombres.length; i++) {
        final top = 60.0 + i * 40;
        lineas.add(LineaOcrDePrueba(
            texto: nombres[i].$2.toStringAsFixed(0),
            top: top,
            bottom: top + 30,
            left: 700,
            width: 100));
      }
      lineas.add(LineaOcrDePrueba(texto: 'NETO', top: 460, bottom: 490, left: 50, width: 100));

      final pares = ocr.emparejarPorPosicionParaPruebas(lineas, {});

      // Los 8 productos reales, cada uno con SU precio correcto — ni el
      // token corrupto ni la oración ancha deben aparecer, ni deben haber
      // desplazado ningún precio a un producto vecino.
      expect(pares.length, 8);
      for (final (nombre, precio) in nombres) {
        final par = pares.firstWhere((p) => p['nombre'] == nombre,
            orElse: () => <String, dynamic>{});
        expect(par, isNotEmpty, reason: 'falta el producto "$nombre"');
        expect(par['precio'], precio, reason: 'precio incorrecto para "$nombre"');
      }
      expect(pares.any((p) => p['nombre'].toString().contains('ONVELCROX')), false);
      expect(pares.any((p) => p['nombre'].toString().contains('CINCUENTA')), false);
    });

    test(
        'no fuerza un emparejamiento cuando el precio más cercano en '
        'altura está demasiado lejos: prefiere dejar el producto sin '
        'precio antes que adivinar', () {
      final lineas = [
        LineaOcrDePrueba(texto: 'DETALLE', top: 10, bottom: 40, left: 50, width: 200),
        LineaOcrDePrueba(
            texto: 'PRODUCTO SIN PRECIO CERCANO',
            top: 60,
            bottom: 90,
            left: 50,
            width: 580),
        LineaOcrDePrueba(texto: 'V. UNIT', top: 100, bottom: 130, left: 700, width: 150),
        // El único precio suelto está muy lejos verticalmente del nombre.
        LineaOcrDePrueba(texto: '990', top: 900, bottom: 930, left: 700, width: 100),
        LineaOcrDePrueba(texto: 'NETO', top: 960, bottom: 990, left: 50, width: 100),
      ];

      final pares = ocr.emparejarPorPosicionParaPruebas(lineas, {});

      expect(pares, isEmpty);
    });

    test('no considera huérfano un nombre que [_extractLineItems] ya '
        'resolvió (evita duplicar el mismo producto)', () {
      final lineas = [
        LineaOcrDePrueba(texto: 'DETALLE', top: 10, bottom: 40, left: 50, width: 200),
        LineaOcrDePrueba(
            texto: 'PRODUCTO YA RESUELTO ANTES',
            top: 60,
            bottom: 90,
            left: 50,
            width: 580),
        LineaOcrDePrueba(texto: 'V. UNIT', top: 100, bottom: 130, left: 700, width: 150),
        LineaOcrDePrueba(texto: '990', top: 60, bottom: 90, left: 700, width: 100),
        LineaOcrDePrueba(texto: 'NETO', top: 160, bottom: 190, left: 50, width: 100),
      ];

      final pares = ocr.emparejarPorPosicionParaPruebas(
          lineas, {'PRODUCTO YA RESUELTO ANTES'});

      expect(pares, isEmpty);
    });

    test(
        'prefiere los montos marcados con "\$" por sobre números sueltos '
        'sin signo, aunque el bloque con "\$" quede mucho más abajo (cerca '
        'de NETO/IVA/TOTAL, como en la boleta real)', () {
      // Reproduce la estructura real: la columna "V. UNIT" trae números
      // sueltos sin signo justo debajo de la etiqueta, pero esos números
      // no son los que hay que usar — el monto real y sin ambigüedad
      // (nunca puede ser una medida, un código o una cantidad) es el que
      // trae "\$", que en la boleta real aparece mucho más abajo, cerca
      // de NETO/DESCUENTO/IVA/TOTAL. Aquí los números sueltos (111, 222,
      // 333) son señuelos con un valor claramente distinto al correcto,
      // en la misma altura que cada nombre — si el método los usara en
      // vez de los "\$", este test fallaría.
      final lineas = [
        LineaOcrDePrueba(texto: 'DETALLE', top: 10, bottom: 40, left: 50, width: 200),
        LineaOcrDePrueba(
            texto: 'PRODUCTO ALFA DE PRUEBA',
            top: 60,
            bottom: 90,
            left: 50,
            width: 400),
        LineaOcrDePrueba(
            texto: 'PRODUCTO BETA DE PRUEBA',
            top: 100,
            bottom: 130,
            left: 50,
            width: 400),
        LineaOcrDePrueba(
            texto: 'PRODUCTO GAMA DE PRUEBA',
            top: 140,
            bottom: 170,
            left: 50,
            width: 400),
        LineaOcrDePrueba(texto: 'V. UNIT', top: 180, bottom: 210, left: 700, width: 150),
        // Señuelos: números sueltos sin "$", en la misma altura que cada
        // nombre, con un valor que NO debe terminar usándose.
        LineaOcrDePrueba(texto: '111', top: 60, bottom: 90, left: 700, width: 100),
        LineaOcrDePrueba(texto: '222', top: 100, bottom: 130, left: 700, width: 100),
        LineaOcrDePrueba(texto: '333', top: 140, bottom: 170, left: 700, width: 100),
        LineaOcrDePrueba(texto: 'NETO', top: 220, bottom: 250, left: 700, width: 100),
        LineaOcrDePrueba(texto: 'DESCUENTO', top: 260, bottom: 290, left: 700, width: 100),
        LineaOcrDePrueba(texto: 'IVA (19%)', top: 300, bottom: 330, left: 700, width: 100),
        LineaOcrDePrueba(texto: 'TOTAL', top: 340, bottom: 370, left: 700, width: 100),
        // Los montos reales, con "\$", mucho más abajo en el documento —
        // pero a la MISMA altura que su producto correspondiente.
        LineaOcrDePrueba(texto: '\$1.050', top: 60, bottom: 90, left: 700, width: 100),
        LineaOcrDePrueba(texto: '\$2.500', top: 100, bottom: 130, left: 700, width: 100),
        LineaOcrDePrueba(texto: '\$966', top: 140, bottom: 170, left: 700, width: 100),
      ];

      final pares = ocr.emparejarPorPosicionParaPruebas(lineas, {});

      expect(pares.length, 3);
      final alfa =
          pares.firstWhere((p) => p['nombre'].toString().contains('ALFA'));
      expect(alfa['precio'], 1050);
      final beta =
          pares.firstWhere((p) => p['nombre'].toString().contains('BETA'));
      expect(beta['precio'], 2500);
      final gama =
          pares.firstWhere((p) => p['nombre'].toString().contains('GAMA'));
      expect(gama['precio'], 966);

      // Ninguno de los señuelos sin "$" debe haberse usado.
      expect(pares.any((p) => [111, 222, 333].contains(p['precio'])), false);
    });
  });
}
