class Expense {
  final int? id;
  final String title;
  final double amount;
  final String category;
  final DateTime date;
  final String? imagePath;

  /// Datos del documento tributario (boleta/factura). Cuando se pudo leer
  /// el timbre electrónico (PDF417) del SII vienen de ahí; si no, se
  /// completan por respaldo a partir del texto reconocido por OCR.
  final String? folio;
  final String? tipoDte;
  final String? rutEmisor;
  final String? nombreEmisor;
  final double? montoNeto;
  final double? montoIva;

  Expense({
    this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
    this.imagePath,
    this.folio,
    this.tipoDte,
    this.rutEmisor,
    this.nombreEmisor,
    this.montoNeto,
    this.montoIva,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'amount': amount,
      'category': category,
      'date': date.toIso8601String(),
      'imagePath': imagePath,
      'folio': folio,
      'tipoDte': tipoDte,
      'rutEmisor': rutEmisor,
      'nombreEmisor': nombreEmisor,
      'montoNeto': montoNeto,
      'montoIva': montoIva,
    };
  }

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'],
      title: map['title'],
      amount: map['amount'],
      category: map['category'],
      date: DateTime.parse(map['date']),
      imagePath: map['imagePath'],
      folio: map['folio'],
      tipoDte: map['tipoDte'],
      rutEmisor: map['rutEmisor'],
      nombreEmisor: map['nombreEmisor'],
      montoNeto: map['montoNeto'],
      montoIva: map['montoIva'],
    );
  }
}
