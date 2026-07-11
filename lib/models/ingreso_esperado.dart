/// Ingreso que el usuario espera recibir regularmente (ej. sueldo), cargado
/// a mano porque luca no tiene conexión bancaria. Es la base para poder
/// proyectar el flujo de caja aunque todavía no haya historial de ingresos.
class IngresoEsperado {
  final int? id;
  final String descripcion;
  final double monto;

  /// Día del mes en que normalmente llega (1-28, para que aplique en
  /// cualquier mes sin importar cuántos días tenga).
  final int diaDelMes;

  IngresoEsperado({
    this.id,
    required this.descripcion,
    required this.monto,
    required this.diaDelMes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'descripcion': descripcion,
      'monto': monto,
      'diaDelMes': diaDelMes,
    };
  }

  factory IngresoEsperado.fromMap(Map<String, dynamic> map) {
    return IngresoEsperado(
      id: map['id'],
      descripcion: map['descripcion'],
      monto: map['monto'],
      diaDelMes: map['diaDelMes'],
    );
  }
}
