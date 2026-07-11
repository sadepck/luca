import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrService {
  final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  Future<Map<String, dynamic>> extractExpenseData(String imagePath) async {
    final recognizedText = await _recognizeFull(imagePath);
    return _procesarTexto(recognizedText.text,
        lineasConPosicion: _aplanarLineas(recognizedText));
  }

  /// Punto de entrada de solo-texto para pruebas unitarias: permite
  /// verificar la extracción de productos y el cálculo híbrido del total
  /// sin depender de la cámara ni del reconocimiento OCR real.
  @visibleForTesting
  Map<String, dynamic> procesarTextoParaPruebas(String text) =>
      _procesarTexto(text);

  /// Igual que [extractExpenseData], pero para un ticket largo capturado en
  /// varias fotos (de arriba hacia abajo). Reconoce el texto de cada
  /// segmento por separado y los une antes de buscar el total y los
  /// productos, para no perder el pie de la boleta si no cupo en una foto.
  Future<Map<String, dynamic>> extractExpenseDataFromSegments(
      List<String> imagePaths) async {
    final buffer = StringBuffer();
    final lineasConPosicion = <_LineaOcr>[];
    for (final path in imagePaths) {
      final recognizedText = await _recognizeFull(path);
      if (recognizedText.text.trim().isEmpty) continue;
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.write(recognizedText.text);
      lineasConPosicion.addAll(_aplanarLineas(recognizedText));
    }
    return _procesarTexto(buffer.toString(),
        lineasConPosicion: lineasConPosicion);
  }

  Future<RecognizedText> _recognizeFull(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    return textRecognizer.processImage(inputImage);
  }

  /// Junta las líneas de todos los bloques reconocidos en la imagen, con
  /// su posición (rectángulo) en la foto — a diferencia de
  /// [RecognizedText.text], que ya viene aplanado a una sola cadena y
  /// pierde esa posición. Sirve para [_emparejarPorPosicion].
  List<_LineaOcr> _aplanarLineas(RecognizedText recognizedText) {
    final lineas = <_LineaOcr>[];
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        lineas.add(_LineaOcr(
          texto: line.text,
          top: line.boundingBox.top,
          bottom: line.boundingBox.bottom,
          left: line.boundingBox.left,
          width: line.boundingBox.width,
        ));
      }
    }
    return lineas;
  }

  /// Calcula el monto de forma híbrida: si la boleta trae un texto "TOTAL"
  /// explícito lo usa como monto (más confiable que sumar líneas leídas por
  /// OCR), y compara contra la suma de los productos detectados para avisar
  /// si no calzan. Si no hay texto "TOTAL", usa la suma de productos. Si
  /// tampoco hay productos, recurre al último criterio: el número más
  /// grande cerca del final del ticket.
  ///
  /// También intenta identificar los datos generales del documento (nombre
  /// y RUT del emisor, fecha, folio, neto e IVA) para mostrarlos aparte del
  /// detalle de productos.
  Map<String, dynamic> _procesarTexto(String text,
      {List<_LineaOcr>? lineasConPosicion}) {
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    final items = _extractLineItems(lines);
    if (lineasConPosicion != null && lineasConPosicion.isNotEmpty) {
      // Cuando el nombre y el precio de un producto quedaron en bloques
      // totalmente separados del documento (columnas de una tabla que el
      // OCR aplanó por separado), no hay forma de emparejarlos solo con
      // el texto — se usa la posición real de cada línea en la foto.
      items.addAll(_emparejarPorPosicion(
          lineasConPosicion, items.map((i) => i['nombre'] as String).toSet()));
    }
    final totalCalculado =
        items.fold<double>(0, (sum, i) => sum + (i['precio'] as double));
    final totalExplicito = _extractTotalExplicito(lines, referencia: totalCalculado);

    double amount;
    bool totalDesdeTexto;
    bool descuadre = false;

    if (totalExplicito != null) {
      amount = totalExplicito;
      totalDesdeTexto = true;
      if (totalCalculado > 0) {
        final tolerancia =
            totalExplicito * 0.05 < 100 ? 100 : totalExplicito * 0.05;
        descuadre = (totalExplicito - totalCalculado).abs() > tolerancia;
      }
    } else if (totalCalculado > 0) {
      amount = totalCalculado;
      totalDesdeTexto = false;
    } else {
      amount = _extractTotalFallback(lines);
      totalDesdeTexto = false;
    }

    String category = _detectCategory(text);
    // Preferir el título desde los ítems ya extraídos (que respetan los
    // límites DETALLE/SUBTOTAL y los mismos filtros de ruido): evita que
    // direcciones, códigos o texto de encabezado que [_extractProducts]
    // no filtra (porque recorre todo el documento sin esos límites)
    // terminen mostrándose como si fueran el producto comprado.
    String title = items.isNotEmpty
        ? items.take(2).map((i) => i['nombre'] as String).join(', ')
        : _extractProducts(lines);

    return {
      'title': title,
      'amount': amount,
      'category': category,
      'rawText': text,
      'items': items,
      'totalCalculadoDesdeItems': totalCalculado,
      'totalDesdeTexto': totalDesdeTexto,
      'descuadre': descuadre,
      'nombreEmisor': _extractNombreEmisor(lines),
      'rutEmisorTexto': _extractRutEmisor(lines),
      'folioTexto': _extractFolio(lines),
      'tipoDteTexto': _extractTipoDocumento(lines),
      'fechaDocumento': _extractFechaDocumento(lines),
      'montoNeto': _extractMontoEtiqueta(lines, 'neto'),
      'montoIva': _extractMontoEtiqueta(lines, 'iva'),
    };
  }

  /// Quita puntos y espacios para comparar palabras clave sin que
  /// abreviaturas como "R.U.T." o títulos partidos por el OCR como
  /// "DE TALLE" (en vez de "DETALLE") escapen del filtro.
  String _normalizar(String texto) =>
      texto.toLowerCase().replaceAll(RegExp(r'[.\s]'), '');

  /// Frases de encabezado/pie que nunca son un producto: datos de la
  /// empresa, del cliente, del documento, o texto legal/del timbre del
  /// SII. Se compara contra la versión normalizada (sin puntos ni
  /// espacios) de cada línea.
  static final RegExp _ignoreLineas = RegExp(
    r'rut|total|subtotal|iva|boleta|factura|fecha|hora|caja|vendedor|'
    r'gracias|ticket|folio|direc|telefon|fono|www|local|sucursal|'
    r'efectivo|cambio|tarjeta|neto|descuento|giro|se[nñ]or|comuna|ciudad|'
    r'sii|c[oó]digointerno|formapago|acuse|recinto|firma|recib|'
    r'art\d|\bley\b|casamatriz|venc|traslado|referencia|despacho|'
    r'timbreelectronico|verifiquedocumento|contecnolog|res\d',
    caseSensitive: false,
  );

  bool _esLineaRuido(String line) => _ignoreLineas.hasMatch(_normalizar(line));

  static final RegExp _separadorCantidad = RegExp(r'[xX*]');

  /// ¿Esta línea, quitando el separador de cantidad, se queda sin ninguna
  /// letra? (o sea, es solo números/símbolos — candidata a ser una línea
  /// "cantidad x precio", nunca el nombre de un producto).
  bool _esLineaSoloNumerica(String line) {
    final sinSeparador = line.replaceAll(_separadorCantidad, ' ');
    return !RegExp(r'[a-zA-ZáéíóúÁÉÍÓÚñÑ]').hasMatch(sinSeparador);
  }

  /// Reconoce una línea "cantidad [x|*] precio_unitario" — el separador
  /// puede ser "x" o "*" según el software que emitió el documento — y
  /// devuelve cantidad y precio YA multiplicados. No se busca un precio
  /// total impreso aparte en la misma línea: en fotos de mala calidad esa
  /// columna suele leerse fuera de orden por el OCR, así que es más
  /// confiable calcularlo nosotros mismos.
  Map<String, double>? _detectarCantidadPrecio(String line) {
    if (!_esLineaSoloNumerica(line)) return null;
    final match = _separadorCantidad.firstMatch(line);
    if (match == null) return null;

    final antes = line.substring(0, match.start);
    final despues = line.substring(match.end);

    // Ojo: se toma solo el PRIMER número después del separador (el precio
    // unitario). Si se usara [_extractNumber] sobre toda la cadena, en
    // líneas que además traen el total de la línea más a la derecha
    // ("1.00 x 3.490.00      3.490") se podría tomar por error ese total
    // en vez del unitario, duplicando la cantidad al multiplicar.
    final unitario = _primerMonto(despues);
    if (unitario == null || unitario < 50) return null;

    // La cantidad suele venir como "N.00" (con espacio a veces, ej. "4. 00"
    // por errores de OCR); a veces el primer dígito se pierde del todo, en
    // cuyo caso queda en 1 por defecto.
    double cantidad = 1;
    final matchCantidad =
        RegExp(r'(\d{1,3})(?:[.,]\s?\d+)?\s*$').firstMatch(antes);
    if (matchCantidad != null) {
      final valor = int.tryParse(matchCantidad.group(1)!);
      if (valor != null && valor > 0 && valor < 1000) {
        cantidad = valor.toDouble();
      }
    }

    return {'cantidad': cantidad, 'precio': cantidad * unitario};
  }

  /// Toma solo el PRIMER número al inicio de [texto] (ignorando espacios
  /// iniciales), a diferencia de [_extractNumber] que busca el más grande
  /// en toda la cadena. Sirve para leer "el precio unitario" cuando puede
  /// haber otro número (el total de la línea) más adelante en el mismo
  /// texto.
  double? _primerMonto(String texto) {
    final match = RegExp(r'^\s*(\d[\d.,]*)').firstMatch(texto);
    if (match == null) return null;
    final partes = match.group(1)!.split(RegExp(r'[.,]'));
    // Descarta un sufijo de centavos final de 2 dígitos (".00"/", 00"),
    // que varias facturas de proveedores imprimen aunque el CLP no use
    // decimales.
    if (partes.length > 1 && partes.last.length == 2) {
      partes.removeLast();
    }
    return double.tryParse(partes.join(''));
  }

  /// Busca el texto "TOTAL" (o variantes) impreso en la boleta. Devuelve
  /// `null` si no lo encuentra, a diferencia de [_extractTotalFallback] que
  /// siempre entrega algún número como último recurso.
  ///
  /// [referencia] es la suma ya calculada de los productos detectados: si
  /// el número encontrado junto a una etiqueta "TOTAL" es mucho menor a
  /// esa referencia (por ejemplo, porque hay más de un "TOTAL" impreso en
  /// el documento — uno de cierre y otro del timbre del SII más abajo — y
  /// el de al lado resultó ser el precio de un producto), se descarta y se
  /// sigue buscando.
  double? _extractTotalExplicito(List<String> lines, {double referencia = 0}) {
    final totalKeywords = [
      'total a pagar',
      'total pagar',
      'a pagar',
      'total \$',
      'total',
      'monto total',
      'importe total',
      'neto total',
    ];

    bool esCandidatoValido(double valor) =>
        referencia <= 0 || valor >= referencia * 0.5;

    for (final keyword in totalKeywords) {
      // Un documento puede tener más de una línea que calce con la
      // palabra clave (una etiqueta suelta sin número cerca, un typo del
      // OCR como "TOTALA" pegado a un número irrelevante, y recién más
      // abajo la línea real). En vez de quedarse con el PRIMER calce (que
      // puede ser un falso positivo temprano), se evalúan todas las
      // líneas que calcen y se prefiere el candidato más grande entre
      // ellas — el total real casi siempre es el monto más grande de la
      // boleta, mientras que un calce espurio suele quedar pegado a un
      // número chico (una dirección, un código, etc.).
      double? mejorCandidato;
      for (int i = 0; i < lines.length; i++) {
        final compacta = _normalizar(lines[i]);
        // "SUBTOTAL" contiene "total" como substring: nunca debe tomarse
        // como si fuera el total final, aunque a veces coincidan en valor.
        // Tampoco sirve el encabezado de la tabla ("DETALLE ... TOTAL", a
        // veces leído "DE TALLE" con un espacio de más), que es solo el
        // nombre de la columna, no un monto.
        if (compacta.contains('subtotal') || compacta.contains('detalle')) {
          continue;
        }
        if (!compacta.contains(_normalizar(keyword))) continue;

        if (_tieneNumeroImplausible(lines[i])) {
          // Esta línea sí traía un monto pegado a la palabra clave, pero
          // salió con dígitos de más (corrupción del OCR, ej. "555,830" en
          // vez de "55.830") y quedó fuera de rango. Usar el número de una
          // línea vecina como si fuera el total sería adivinar a ciegas —
          // mejor seguir buscando en otra parte del documento.
          continue;
        }

        final candidatos = <double>[];
        final amount = _extractNumber(lines[i]);
        if (amount >= 100) candidatos.add(amount);
        if (i + 1 < lines.length) {
          final next = _extractNumber(lines[i + 1]);
          if (next >= 100) candidatos.add(next);
        }
        if (i > 0) {
          final prev = _extractNumber(lines[i - 1]);
          if (prev >= 100) candidatos.add(prev);
        }
        for (final c in candidatos) {
          if (esCandidatoValido(c)) {
            if (mejorCandidato == null || c > mejorCandidato) {
              mejorCandidato = c;
            }
            break; // ya se tomó el candidato prioritario de esta línea
          }
        }
      }
      if (mejorCandidato != null) return mejorCandidato;
    }

    // A veces la columna de montos de cierre queda separada de sus
    // etiquetas por el OCR (fotos borrosas o en ángulo, columnas muy
    // separadas, o texto del timbre del SII metido en medio): si hay una
    // etiqueta "TOTAL" pero sin número cerca, se busca el último monto
    // grande dentro de una ventana amplia de líneas siguientes — el total
    // de cierre suele quedar al final de ese bloque de números.
    final idxTotal = lines.indexWhere((l) {
      final compacta = _normalizar(l);
      return compacta.contains('total') &&
          !compacta.contains('subtotal') &&
          !compacta.contains('detalle');
    });
    if (idxTotal >= 0) {
      final finVentana = (idxTotal + 30).clamp(0, lines.length);
      double? ultimo;
      for (final l in lines.sublist(idxTotal, finVentana)) {
        final val = _extractNumber(l);
        if (val >= 1000 && esCandidatoValido(val)) ultimo = val;
      }
      if (ultimo != null) return ultimo;
    }

    return null;
  }

  /// Último recurso cuando no hay texto "TOTAL" ni productos detectados:
  /// el número más grande cerca del final del ticket (ahí suele estar el
  /// total en boletas chilenas).
  double _extractTotalFallback(List<String> lines) {
    final lastLines = lines.length > 10 ? lines.sublist(lines.length - 10) : lines;
    double max = 0;
    for (final line in lastLines) {
      final val = _extractNumber(line);
      if (val > max && val >= 100 && val <= 999999) max = val;
    }
    return max;
  }

  /// El OCR a veces lee el signo "$" como la letra "S" pegada al número
  /// (ej. "TOTAL S55,830" en vez de "TOTAL $55.830"). Como esa "S" es una
  /// letra, el número queda "pegado" a ella y el patrón de dígitos con
  /// borde de palabra (\b) no lo reconoce como número en absoluto — se
  /// pierde el monto entero en vez de solo leerse mal. Se quita esa "S"
  /// suelta antes de buscar números (solo cuando antecede directo a un
  /// dígito, para no tocar palabras reales como "SI-TEMUCO" o "SPA").
  String _normalizarSignoPeso(String text) =>
      text.replaceAllMapped(RegExp(r'(^|\s)S(\d)'), (m) => '${m[1]}${m[2]}');

  /// ¿Esta línea trae un número que se ve tan grande que claramente está
  /// corrupto (un dígito de más, dos montos pegados, etc.) en vez de
  /// simplemente no traer ningún monto? Sirve para no adivinar con un
  /// número de una línea vecina cuando ya sabemos que el de esta línea no
  /// se pudo leer bien.
  bool _tieneNumeroImplausible(String text) {
    final pattern = RegExp(r'\b\d{1,3}(?:[.,]\d{3})+\b|\b\d{3,6}\b');
    for (final m in pattern.allMatches(_normalizarSignoPeso(text))) {
      final val =
          double.tryParse(m.group(0)!.replaceAll(RegExp(r'[.,]'), '')) ?? 0;
      if (val > 500000) return true;
    }
    return false;
  }

  double _extractNumber(String text) {
    // Formato chileno: 1.990 / 12.500 / 1.234.567. Algunas fotos degradadas
    // hacen que el OCR confunda el separador de miles con una coma
    // (1,990 en vez de 1.990), así que se acepta cualquiera de los dos (a
    // veces con ", 00" o ".00" de decimales al final, que el patrón
    // simplemente ignora).
    final pattern =
        RegExp(r'\b\d{1,3}(?:[.,]\d{3})+\b|\b\d{3,6}\b');
    final matches = pattern.allMatches(_normalizarSignoPeso(text));
    double best = 0;
    for (final m in matches) {
      final val = double.tryParse(m.group(0)!.replaceAll(RegExp(r'[.,]'), '')) ?? 0;
      if (val > best && val <= 500000) best = val;
    }
    return best;
  }

  String _extractProducts(List<String> lines) {
    final products = <String>[];
    for (final line in lines) {
      if (_esLineaRuido(line)) continue;
      if (line.length < 3) continue;
      // Si la línea tiene texto y un número al lado, probablemente es un producto
      if (RegExp(r'[a-zA-ZáéíóúÁÉÍÓÚñÑ]').hasMatch(line) &&
          RegExp(r'\d').hasMatch(line)) {
        // Extraer solo el nombre (sin el número)
        final name = line.replaceAll(RegExp(r'[\d\$\.,]+'), '').trim();
        if (name.length > 2) products.add(name);
      }
    }

    if (products.isEmpty) return 'Compra';
    if (products.length == 1) return products.first;
    return products.take(2).join(', ');
  }

  static final RegExp _sufijoRazonSocial =
      RegExp(r'\b(s\.?p\.?a\.?|ltda\.?|limitada|e\.?i\.?r\.?l\.?|s\.?a\.?)\b',
          caseSensitive: false);

  /// El nombre de la empresa que emitió el documento. Las razones sociales
  /// chilenas casi siempre incluyen su forma legal (SpA, Ltda, S.A., EIRL)
  /// — es una señal mucho más confiable que la posición de la línea,
  /// porque en fotos degradadas el encabezado a veces trae primero el giro
  /// o la descripción del negocio en vez del nombre de la empresa (y ese
  /// texto igual puede parecer "sustancial" a simple vista). Si ninguna
  /// línea trae esa forma legal, se recurre a la primera línea sustancial
  /// no ignorada de las primeras líneas del documento.
  String? _extractNombreEmisor(List<String> lines) {
    for (final l in lines) {
      if (_sufijoRazonSocial.hasMatch(l) && !_esLineaRuido(l)) {
        return l.trim();
      }
    }
    for (final l in lines.take(6)) {
      if (l.trim().length > 8 &&
          !_esLineaRuido(l) &&
          RegExp(r'[a-zA-ZáéíóúÁÉÍÓÚñÑ]').hasMatch(l)) {
        return l.trim();
      }
    }
    return null;
  }

  static final RegExp _rutPattern = RegExp(r'\b(\d{1,2}\.?\d{3}\.?\d{3}-[\dkK])\b');

  /// El RUT del emisor suele imprimirse justo antes del nombre del tipo de
  /// documento ("FACTURA ELECTRÓNICA"/"GUÍA DE DESPACHO ELECTRÓNICA"),
  /// aunque el orden de las demás líneas varíe según la plantilla.
  String? _extractRutEmisor(List<String> lines) {
    final idxTipoDoc = lines.indexWhere((l) {
      final compacta = _normalizar(l);
      return compacta.contains('facturaelectr') ||
          compacta.contains('guiadedespacho') ||
          compacta.contains('boletaelectr');
    });
    if (idxTipoDoc > 0) {
      for (int k = idxTipoDoc - 1; k >= 0 && k >= idxTipoDoc - 3; k--) {
        final m = _rutPattern.firstMatch(lines[k]);
        if (m != null) return m.group(1);
      }
    }
    // Respaldo: el primer RUT que aparezca en el documento.
    for (final l in lines) {
      final m = _rutPattern.firstMatch(l);
      if (m != null) return m.group(1);
    }
    return null;
  }

  /// El folio suele imprimirse en la misma línea que el tipo de documento
  /// (al final) o en la línea inmediatamente siguiente, solo.
  String? _extractFolio(List<String> lines) {
    for (int i = 0; i < lines.length; i++) {
      final compacta = _normalizar(lines[i]);
      if (compacta.contains('facturaelectr') ||
          compacta.contains('guiadedespacho') ||
          compacta.contains('boletaelectr')) {
        final matchMismaLinea = RegExp(r'(\d{4,10})\s*$').firstMatch(lines[i]);
        if (matchMismaLinea != null) return matchMismaLinea.group(1);
        if (i + 1 < lines.length) {
          final soloNumero = RegExp(r'^\s*(\d{4,10})\s*$').firstMatch(lines[i + 1]);
          if (soloNumero != null) return soloNumero.group(1);
        }
      }
    }
    return null;
  }

  String? _extractTipoDocumento(List<String> lines) {
    for (final l in lines) {
      final compacta = _normalizar(l);
      if (compacta.contains('facturaelectr')) return 'Factura Electrónica';
      if (compacta.contains('guiadedespacho')) return 'Guía de Despacho Electrónica';
      if (compacta.contains('boletaelectr')) return 'Boleta Electrónica';
    }
    return null;
  }

  static const _mesesEs = {
    'enero': 1, 'febrero': 2, 'marzo': 3, 'abril': 4, 'mayo': 5, 'junio': 6,
    'julio': 7, 'agosto': 8, 'septiembre': 9, 'setiembre': 9, 'octubre': 10,
    'noviembre': 11, 'diciembre': 12,
  };

  /// Busca la fecha del documento junto a la etiqueta "Fecha" (evitando
  /// "Fecha de vencimiento"), en formato largo ("08 de mayo del 2026") o
  /// corto ("08-05-2026" / "08/05/2026").
  DateTime? _extractFechaDocumento(List<String> lines) {
    for (final linea in lines) {
      final lower = linea.toLowerCase();
      if (!lower.contains('fecha') || lower.contains('venc')) continue;

      final matchLarga =
          RegExp(r'(\d{1,2})\s+de\s+(\w+)\s+de[l]?\s+(\d{4})').firstMatch(lower);
      if (matchLarga != null) {
        final dia = int.tryParse(matchLarga.group(1)!);
        final mes = _mesesEs[matchLarga.group(2)!];
        final anio = int.tryParse(matchLarga.group(3)!);
        if (dia != null && mes != null && anio != null) {
          return DateTime(anio, mes, dia);
        }
      }

      final matchCorta =
          RegExp(r'(\d{1,2})[-/](\d{1,2})[-/](\d{4})').firstMatch(linea);
      if (matchCorta != null) {
        final dia = int.tryParse(matchCorta.group(1)!);
        final mes = int.tryParse(matchCorta.group(2)!);
        final anio = int.tryParse(matchCorta.group(3)!);
        if (dia != null && mes != null && anio != null && mes <= 12 && dia <= 31) {
          return DateTime(anio, mes, dia);
        }
      }
    }
    return null;
  }

  /// Monto junto a una etiqueta como "NETO" o "IVA": solo se entrega si el
  /// número está en la MISMA línea que la etiqueta. Si el bloque de
  /// totales quedó separado de sus montos (ver [_extractTotalExplicito]),
  /// se prefiere no adivinar aquí antes que arriesgar un número equivocado.
  double? _extractMontoEtiqueta(List<String> lines, String etiqueta) {
    for (final linea in lines) {
      final compacta = _normalizar(linea);
      if (compacta.contains('sub$etiqueta')) continue;
      if (!compacta.startsWith(etiqueta)) continue;
      final valor = _extractNumber(linea);
      if (valor >= 50) return valor;
    }
    return null;
  }

  /// Extrae cada línea de producto con su cantidad y precio.
  ///
  /// Busca un encabezado "DETALLE" (tolerante a que el OCR lo separe como
  /// "DE TALLE") y un cierre "SUBTOTAL/TOTAL/NETO/IVA": solo busca
  /// productos entre esos dos puntos, para que direcciones, teléfonos,
  /// RUTs o texto legal del pie (que también traen números) no se lean
  /// como si fueran productos.
  ///
  /// Soporta el formato de dos (o más) líneas por ítem que usan varias
  /// facturas de proveedores: "CODIGO Nombre del producto" (a veces
  /// partido en 2 líneas si el nombre es largo) seguido de
  /// "cantidad x precio_unitario".
  List<Map<String, dynamic>> _extractLineItems(List<String> lines) {
    final (desde, hasta) = _rangoDetalle(lines);
    final candidatas =
        lines.sublist(desde.clamp(0, lines.length), hasta.clamp(0, lines.length));

    final items = <Map<String, dynamic>>[];
    int i = 0;
    while (i < candidatas.length) {
      final line = candidatas[i];

      if (_esLineaRuido(line) ||
          line.length < 3 ||
          !RegExp(r'[a-zA-ZáéíóúÁÉÍÓÚñÑ]').hasMatch(line) ||
          _esLineaSoloNumerica(line)) {
        i++;
        continue;
      }

      // Junta hasta 2 líneas siguientes como continuación del nombre (las
      // descripciones largas a veces se cortan en 2 líneas) hasta
      // encontrar la línea de cantidad×precio.
      final nombrePartes = [line];
      int j = i + 1;
      Map<String, double>? cantidadPrecio;
      while (j < candidatas.length && j <= i + 3) {
        final candidata = candidatas[j];
        final detectado = _detectarCantidadPrecio(candidata);
        if (detectado != null) {
          cantidadPrecio = detectado;
          j++;
          break;
        }
        if (_esLineaRuido(candidata) || _esLineaSoloNumerica(candidata)) {
          break; // no sirve como continuación del nombre
        }
        nombrePartes.add(candidata);
        j++;
      }

      if (cantidadPrecio != null) {
        final nombre = _limpiarNombreProducto(nombrePartes.join(' '));
        if (_pareceNombreProducto(nombre)) {
          items.add({
            'nombre': nombre,
            'cantidad': cantidadPrecio['cantidad'],
            'precio': cantidadPrecio['precio'],
          });
        }
        i = j;
        continue;
      }

      // Formato de una sola línea: "Producto ... 990" o "2 x Producto ... 1.980".
      final analizada = _analizarLineaProducto(line);
      final precio = analizada['precio'] as double;
      if (precio >= 50) {
        final nombre = analizada['nombre'] as String;
        if (_pareceNombreProducto(nombre)) {
          items.add({
            'nombre': nombre,
            'cantidad': analizada['cantidad'],
            'precio': precio,
          });
        }
      }
      i++;
    }
    return items;
  }

  /// Encuentra el rango [desde, hasta) de líneas entre el encabezado
  /// "DETALLE" (tolerante a truncamiento: "DETA") y el cierre
  /// "SUBTOTAL/TOTAL/NETO/IVA", usado por [_extractLineItems] para acotar
  /// dónde buscar productos.
  (int, int) _rangoDetalle(List<String> textos) {
    final inicioDetalle =
        textos.indexWhere((l) => _normalizar(l).contains('deta'));
    final desde = inicioDetalle >= 0 ? inicioDetalle + 1 : 0;
    final finBusqueda = textos.indexWhere((l) {
      final compacta = _normalizar(l);
      return compacta.contains('subtotal') ||
          compacta.startsWith('total') ||
          compacta.startsWith('neto') ||
          compacta.contains('iva(');
    }, desde);
    final hasta = finBusqueda >= 0 ? finBusqueda : textos.length;
    return (desde, hasta);
  }

  static final RegExp _lineaSoloUnPrecio = RegExp(r'^\$?\d[\d.,]*$');

  /// Línea que es SOLO un monto marcado con "$" (ya normalizado el caso
  /// en que el OCR lo confunde con la letra "S", ver [_normalizarSignoPeso]).
  static final RegExp _lineaConSignoPeso = RegExp(r'^\$\d[\d.,]*$');

  /// Umbral de ancho relativo por encima del cual una línea se descarta
  /// como candidata a nombre de producto: una oración larga (el monto en
  /// letras, texto legal del pie) suele ocupar mucho más ancho de la foto
  /// que el nombre de un producto en su propia columna de una tabla.
  static const _anchoRelativoMaximo = 1.6;

  /// Distancia vertical máxima (relativa al alto típico de una línea)
  /// para considerar que un nombre y un precio están en la misma "fila"
  /// de la tabla.
  static const _distanciaVerticalMaxima = 2.5;

  /// Cuando el nombre de los productos y sus precios unitarios quedaron
  /// en dos bloques totalmente separados del texto (columnas de una
  /// tabla que el OCR aplanó por separado, en vez de línea por línea
  /// adyacente como espera [_extractLineItems]), se recurre a la
  /// POSICIÓN real de cada línea en la foto: un nombre y un precio que
  /// están a la misma altura (mismo "renglón" de la tabla) probablemente
  /// son del mismo producto, sin importar en qué orden los haya leído el
  /// OCR.
  ///
  /// Es deliberadamente conservador — la primera versión de este método
  /// emparejaba por "vecino más cercano" a secas, y una sola línea de
  /// ruido (un token de OCR corrupto, de una sola palabra, sin espacio)
  /// bastaba para desplazar todos los emparejamientos siguientes en un
  /// lugar, con resultados incorrectos. Ahora exige:
  /// - Una etiqueta de precio unitario explícita ("V. UNIT" o similar)
  ///   para activarse.
  /// - Que el candidato a nombre tenga al menos dos palabras: un token
  ///   corrupto de una sola palabra (ej. "ONVELCROX5UN") nunca es un
  ///   nombre de producto real en este tipo de boleta.
  /// - Que no sea mucho más ancho que el resto (oraciones largas, no
  ///   celdas de una tabla).
  /// - Emparejamiento MUTUO: un nombre y un precio solo se consideran
  ///   pareja si cada uno es, a la vez, el más cercano en altura del
  ///   otro — no solo "el precio más cercano a este nombre", sino
  ///   también "el nombre más cercano a este precio". Así, un candidato
  ///   espurio que quede cerca de una fila real no le "roba" su precio:
  ///   simplemente no logra el acuerdo mutuo y queda sin emparejar.
  /// - Una distancia vertical máxima: mejor dejar un producto sin precio
  ///   que inventar uno con el más cercano si igual está lejos.
  List<Map<String, dynamic>> _emparejarPorPosicion(
      List<_LineaOcr> lineas, Set<String> nombresYaUsados) {
    final textos = lineas.map((l) => l.texto).toList();
    final (desde, hasta) = _rangoDetalle(textos);
    if (hasta <= desde) return [];
    final candidatas = lineas.sublist(desde.clamp(0, lineas.length), hasta.clamp(0, lineas.length));

    final idxPrecioUnit = candidatas.indexWhere((l) {
      final compacta = _normalizar(l.texto);
      return compacta.contains('valorunit') ||
          compacta.contains('preciounit') ||
          compacta == 'vunit';
    });
    if (idxPrecioUnit < 0) return [];

    final nombresCandidatos = <_LineaOcr>[];
    for (final l in candidatas.sublist(0, idxPrecioUnit)) {
      final texto = l.texto.trim();
      if (_esLineaRuido(texto) ||
          texto.length < 10 ||
          texto.endsWith(':') ||
          !texto.contains(' ') || // exige 2+ palabras: descarta tokens sueltos
          !RegExp(r'[a-zA-ZáéíóúÁÉÍÓÚñÑ]').hasMatch(texto)) {
        continue;
      }
      final nombreLimpio = _limpiarNombreProducto(texto);
      // Si [_extractLineItems] ya convirtió esta línea en un ítem, no es
      // un nombre huérfano.
      if (nombresYaUsados.contains(nombreLimpio)) continue;
      if (!_pareceNombreProducto(nombreLimpio)) continue;
      nombresCandidatos.add(l);
    }
    if (nombresCandidatos.isEmpty) return [];

    // El signo "$" es la señal más confiable de que un número es un
    // precio (a diferencia de un código, una medida o una cantidad, que
    // nunca lo llevan) — se buscan primero esos montos, en una ventana
    // más amplia que el resto de la tabla, porque en varias facturas esa
    // columna con "$" queda más abajo, cerca de NETO/IVA/TOTAL, no justo
    // debajo de la etiqueta de precio unitario.
    final indiceVentanaAmpliada = (hasta + 40).clamp(0, lineas.length);
    final ventanaAmpliada = lineas.sublist(
        (desde + idxPrecioUnit + 1).clamp(0, lineas.length), indiceVentanaAmpliada);
    var preciosCandidatos = <_LineaOcr>[];
    for (final l in ventanaAmpliada) {
      final texto = _normalizarSignoPeso(l.texto.trim());
      if (!_lineaConSignoPeso.hasMatch(texto)) continue;
      if (_extractNumber(texto) < 50) continue;
      preciosCandidatos.add(l);
    }
    // Si el documento no marcó los montos con "$", se recurre a números
    // sueltos sin signo dentro de la tabla — menos confiable (podría ser
    // una medida o un código), pero mejor que no encontrar nada.
    if (preciosCandidatos.isEmpty) {
      for (final l in candidatas.sublist(idxPrecioUnit + 1)) {
        final texto = l.texto.trim();
        if (!_lineaSoloUnPrecio.hasMatch(texto)) continue;
        if (_extractNumber(texto) < 50) continue;
        preciosCandidatos.add(l);
      }
    }
    if (preciosCandidatos.isEmpty) return [];

    // Descarta nombres candidatos mucho más anchos que la mediana: son
    // probablemente oraciones (el monto en letras, texto legal), no el
    // nombre de un producto en su columna de la tabla.
    final anchos = nombresCandidatos.map((l) => l.width).toList()..sort();
    final anchoMediano = anchos[anchos.length ~/ 2];
    final nombresFiltrados = nombresCandidatos
        .where((l) => l.width <= anchoMediano * _anchoRelativoMaximo)
        .toList();
    if (nombresFiltrados.isEmpty) return [];

    final altos = candidatas.map((l) => l.bottom - l.top).where((h) => h > 0).toList()
      ..sort();
    final altoTipico = altos.isEmpty ? 20.0 : altos[altos.length ~/ 2];
    final distanciaMaxima = altoTipico * _distanciaVerticalMaxima;

    // Para cada nombre, el precio más cercano en altura (y viceversa).
    int? masCercanoA(_LineaOcr origen, List<_LineaOcr> candidatos) {
      if (candidatos.isEmpty) return null;
      var mejorIndice = 0;
      var mejorDistancia = (candidatos[0].centroY - origen.centroY).abs();
      for (int k = 1; k < candidatos.length; k++) {
        final distancia = (candidatos[k].centroY - origen.centroY).abs();
        if (distancia < mejorDistancia) {
          mejorDistancia = distancia;
          mejorIndice = k;
        }
      }
      return mejorDistancia <= distanciaMaxima ? mejorIndice : null;
    }

    final pares = <Map<String, dynamic>>[];
    for (int i = 0; i < nombresFiltrados.length; i++) {
      final nombreLinea = nombresFiltrados[i];
      final idxPrecio = masCercanoA(nombreLinea, preciosCandidatos);
      if (idxPrecio == null) continue;
      final precioLinea = preciosCandidatos[idxPrecio];
      // Acuerdo mutuo: este precio también debe considerar a este nombre
      // como el más cercano entre TODOS los nombres candidatos (no solo
      // entre los que ya se emparejaron), para que un candidato espurio
      // cercano a una fila real no le robe su precio.
      final idxNombreDesdeElPrecio = masCercanoA(precioLinea, nombresFiltrados);
      if (idxNombreDesdeElPrecio != i) continue;
      pares.add({
        'nombre': _limpiarNombreProducto(nombreLinea.texto.trim()),
        'cantidad': 1.0,
        'precio': _extractNumber(precioLinea.texto.trim()),
      });
    }
    return pares;
  }

  /// Punto de entrada para pruebas unitarias del emparejamiento por
  /// posición, sin depender de una imagen real: recibe directamente las
  /// líneas con su posición simulada.
  @visibleForTesting
  List<Map<String, dynamic>> emparejarPorPosicionParaPruebas(
          List<LineaOcrDePrueba> lineas, Set<String> nombresYaUsados) =>
      _emparejarPorPosicion(
          lineas.map((l) => l._aLineaOcr()).toList(), nombresYaUsados);

  /// Exige al menos 2 letras seguidas, no solo 2 caracteres cualquiera:
  /// evita que restos como "N°" (de un número de documento/folio que se
  /// coló en la sección de productos) o abreviaturas de una sola letra
  /// terminen agregados como si fueran el nombre de un producto real.
  bool _pareceNombreProducto(String nombre) =>
      RegExp(r'[a-zA-ZáéíóúÁÉÍÓÚñÑ]{2,}').hasMatch(nombre);

  /// Quita un código numérico inicial (ej. "251422 Adhesivo PVC..." ->
  /// "Adhesivo PVC...") y símbolos de precio, sin tocar el resto del texto.
  String _limpiarNombreProducto(String line) {
    var texto = line.replaceFirst(RegExp(r'^\s*\d{4,8}\s+'), '');
    texto = texto.replaceAll(RegExp(r'[\$]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return texto;
  }

  /// Separa cantidad, nombre y precio de una línea tipo
  /// "2 x Coca Cola 1.5L   1.980" o simplemente "Pan Hallulla   890"
  /// (cantidad implícita = 1). Es el respaldo cuando el producto no viene
  /// en el formato de dos líneas que maneja [_extractLineItems].
  Map<String, dynamic> _analizarLineaProducto(String line) {
    double cantidad = 1;
    // Por si el emparejamiento de dos líneas no aplicó: igual quita un
    // código inicial tipo "251422 " si le sigue una letra, para no leerlo
    // como si fuera el precio.
    String resto =
        line.replaceFirst(RegExp(r'^\s*\d{4,8}\s+(?=[a-zA-ZáéíóúÁÉÍÓÚñÑ])'), '');

    // Cubre "2 x Coca Cola ... 1.980" (cantidad antes del nombre) y
    // "Coca Cola ... 2 x 990   1.980" (cantidad antes del precio unitario).
    // Admite cantidades con decimales ("1.00 x", frecuente en facturas de
    // proveedores, a veces con un espacio de más por el OCR) y el
    // separador "*" además de "x"/"X".
    final matchCantidad =
        RegExp(r'(?:^|\s)(\d{1,3})(?:[.,]\s?\d+)?\s*[xX*]\s').firstMatch(resto);
    if (matchCantidad != null) {
      final valor = int.tryParse(matchCantidad.group(1)!);
      if (valor != null && valor > 0) {
        cantidad = valor.toDouble();
        resto = resto.replaceRange(matchCantidad.start, matchCantidad.end, ' ');
      }
    }

    final precio = _precioAlFinalDeLinea(resto) ?? 0;
    final nombre = resto
        .replaceAll(RegExp(r'[\d\$\.,]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return {'cantidad': cantidad, 'precio': precio, 'nombre': nombre};
  }

  /// El precio de un producto en una sola línea normalmente va al FINAL
  /// de esa línea ("... 1.980"): un número en medio del texto suele ser
  /// una medida (ej. "115 MM", el diámetro de un disco) o parte de un
  /// código, no el precio — usar el número más grande de toda la línea
  /// (como hacía antes) confundía esas medidas con precios reales.
  /// También descarta el número si viene pegado a una fracción ("3/32",
  /// "4.1/2") o a una medida tipo "8x120" (diámetro x largo de un
  /// tornillo/broca) — patrones comunes en facturas de ferretería que
  /// terminan en dígitos pero no son ningún precio.
  double? _precioAlFinalDeLinea(String texto) {
    final t = texto.trimRight();
    final match = RegExp(r'(\d[\d.,]*)$').firstMatch(t);
    if (match == null) return null;
    final antes = t.substring(0, match.start);
    if (antes.endsWith('/') || RegExp(r'[xX]$').hasMatch(antes)) return null;
    final valor = _extractNumber(match.group(1)!);
    return valor == 0 ? null : valor;
  }

  String _detectCategory(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('restaurant') || lower.contains('food') ||
        lower.contains('comida') || lower.contains('cafe') ||
        lower.contains('supermercado') || lower.contains('market')) {
      return 'Comida';
    } else if (lower.contains('taxi') || lower.contains('uber') ||
        lower.contains('bus') || lower.contains('metro') ||
        lower.contains('transport') || lower.contains('gasolina')) {
      return 'Transporte';
    } else if (lower.contains('farmacia') || lower.contains('clinica') ||
        lower.contains('doctor') || lower.contains('salud') ||
        lower.contains('hospital') || lower.contains('pharmacy')) {
      return 'Salud';
    } else if (lower.contains('cine') || lower.contains('teatro') ||
        lower.contains('netflix') || lower.contains('spotify') ||
        lower.contains('entretenimiento') || lower.contains('cinema')) {
      return 'Entretenimiento';
    }
    return 'Otros';
  }

  void dispose() {
    textRecognizer.close();
  }
}

/// Una línea reconocida por el OCR junto a su posición en la foto — a
/// diferencia del texto plano que usa el resto de este archivo, que no
/// distingue en qué parte de la imagen quedó cada línea.
class _LineaOcr {
  final String texto;
  final double top;
  final double bottom;
  final double left;
  final double width;

  _LineaOcr({
    required this.texto,
    required this.top,
    required this.bottom,
    required this.left,
    required this.width,
  });

  double get centroY => (top + bottom) / 2;
}

/// Versión pública de [_LineaOcr] para poder armar casos de prueba desde
/// fuera de este archivo (los tipos privados con guion bajo no se pueden
/// nombrar en otro archivo, ni siquiera en un test).
class LineaOcrDePrueba {
  final String texto;
  final double top;
  final double bottom;
  final double left;
  final double width;

  LineaOcrDePrueba({
    required this.texto,
    required this.top,
    required this.bottom,
    required this.left,
    required this.width,
  });

  _LineaOcr _aLineaOcr() =>
      _LineaOcr(texto: texto, top: top, bottom: bottom, left: left, width: width);
}
