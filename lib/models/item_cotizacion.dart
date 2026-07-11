/// Ítem que el usuario agrega a mano al cotizar una oportunidad de Mercado
/// Público / Compra Ágil, antes de generar la orden de compra.
class ItemCotizacion {
  final int? id;
  final String codigoOportunidad;
  final String nombre;
  final double cantidad;
  final double precioUnitario;

  ItemCotizacion({
    this.id,
    required this.codigoOportunidad,
    required this.nombre,
    required this.cantidad,
    required this.precioUnitario,
  });

  double get subtotal => cantidad * precioUnitario;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'codigoOportunidad': codigoOportunidad,
      'nombre': nombre,
      'cantidad': cantidad,
      'precioUnitario': precioUnitario,
    };
  }

  factory ItemCotizacion.fromMap(Map<String, dynamic> map) {
    return ItemCotizacion(
      id: map['id'],
      codigoOportunidad: map['codigoOportunidad'],
      nombre: map['nombre'],
      cantidad: map['cantidad'],
      precioUnitario: map['precioUnitario'],
    );
  }
}
