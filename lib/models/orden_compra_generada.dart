/// Una orden de compra ya generada y guardada: registra tanto lo que se
/// le pagará al proveedor (montoCompra, calculado desde la cotización)
/// como lo que se le cobrará al cliente por cumplir esa oportunidad
/// (montoIngreso, ingresado a mano), para llevar el ingreso esperado por
/// ese trabajo aparte de los gastos de la compra.
class OrdenCompraGenerada {
  final int? id;
  final String codigoOportunidad;
  final String nombreOportunidad;
  final String? proveedorNombre;
  final String? proveedorRut;
  final double montoCompra;
  final double montoIngreso;
  final DateTime fecha;

  /// Cuándo se espera recibir el pago del cliente por este trabajo
  /// (opcional: en Mercado Público suele demorar semanas o meses después
  /// de generada la orden). Sirve para proyectar este ingreso en el día
  /// correcto dentro del Flujo de Caja — sin ella, el ingreso se muestra
  /// como pendiente pero no se ubica en una fecha específica.
  final DateTime? fechaPagoEsperada;

  OrdenCompraGenerada({
    this.id,
    required this.codigoOportunidad,
    required this.nombreOportunidad,
    this.proveedorNombre,
    this.proveedorRut,
    required this.montoCompra,
    required this.montoIngreso,
    required this.fecha,
    this.fechaPagoEsperada,
  });

  double get margen => montoIngreso - montoCompra;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'codigoOportunidad': codigoOportunidad,
      'nombreOportunidad': nombreOportunidad,
      'proveedorNombre': proveedorNombre,
      'proveedorRut': proveedorRut,
      'montoCompra': montoCompra,
      'montoIngreso': montoIngreso,
      'fecha': fecha.toIso8601String(),
      'fechaPagoEsperada': fechaPagoEsperada?.toIso8601String(),
    };
  }

  factory OrdenCompraGenerada.fromMap(Map<String, dynamic> map) {
    return OrdenCompraGenerada(
      id: map['id'],
      codigoOportunidad: map['codigoOportunidad'],
      nombreOportunidad: map['nombreOportunidad'],
      proveedorNombre: map['proveedorNombre'],
      proveedorRut: map['proveedorRut'],
      montoCompra: map['montoCompra'],
      montoIngreso: map['montoIngreso'],
      fecha: DateTime.parse(map['fecha']),
      fechaPagoEsperada: map['fechaPagoEsperada'] != null
          ? DateTime.parse(map['fechaPagoEsperada'])
          : null,
    );
  }
}
