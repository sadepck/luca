import 'licitacion.dart';

/// Oportunidad de Mercado Público / Compra Ágil que el usuario decidió
/// seguir localmente (guardada en SQLite, no requiere conexión).
class OportunidadGuardada {
  final String codigo;
  final String nombre;
  final String? organismo;
  final DateTime? fechaCierre;
  final double? montoEstimado;
  final DateTime fechaGuardado;

  OportunidadGuardada({
    required this.codigo,
    required this.nombre,
    this.organismo,
    this.fechaCierre,
    this.montoEstimado,
    DateTime? fechaGuardado,
  }) : fechaGuardado = fechaGuardado ?? DateTime.now();

  factory OportunidadGuardada.fromLicitacion(Licitacion licitacion) {
    return OportunidadGuardada(
      codigo: licitacion.codigo,
      nombre: licitacion.nombre,
      organismo: licitacion.organismo,
      fechaCierre: licitacion.fechaCierre,
      montoEstimado: licitacion.montoEstimado,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'codigo': codigo,
      'nombre': nombre,
      'organismo': organismo,
      'fechaCierre': fechaCierre?.toIso8601String(),
      'montoEstimado': montoEstimado,
      'fechaGuardado': fechaGuardado.toIso8601String(),
    };
  }

  factory OportunidadGuardada.fromMap(Map<String, dynamic> map) {
    return OportunidadGuardada(
      codigo: map['codigo'],
      nombre: map['nombre'],
      organismo: map['organismo'],
      fechaCierre:
          map['fechaCierre'] != null ? DateTime.parse(map['fechaCierre']) : null,
      montoEstimado: map['montoEstimado'],
      fechaGuardado: DateTime.parse(map['fechaGuardado']),
    );
  }
}
