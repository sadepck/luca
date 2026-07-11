/// Ítem individual detectado en una boleta/factura: producto, cuántas
/// unidades, y el precio de esa línea (ya viene como el subtotal de la
/// línea, no como precio unitario — así lo imprime la mayoría de las
/// boletas chilenas). El monto total del gasto se calcula aparte
/// (ver [OcrService]); estos ítems son el detalle de la compra.
class ItemGasto {
  final int? id;
  final int expenseId;
  final String nombre;
  final double cantidad;
  final double precio;

  ItemGasto({
    this.id,
    required this.expenseId,
    required this.nombre,
    this.cantidad = 1,
    required this.precio,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'expenseId': expenseId,
      'nombre': nombre,
      'cantidad': cantidad,
      'precio': precio,
    };
  }

  factory ItemGasto.fromMap(Map<String, dynamic> map) {
    return ItemGasto(
      id: map['id'],
      expenseId: map['expenseId'],
      nombre: map['nombre'],
      cantidad: (map['cantidad'] as num?)?.toDouble() ?? 1,
      precio: map['precio'],
    );
  }
}
