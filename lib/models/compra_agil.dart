import 'licitacion.dart';

/// Una oportunidad publicada en el mecanismo Compra Ágil, leída desde el
/// API dedicado de ChileCompra (api2.mercadopublico.cl/v2/compra-agil) —
/// una fuente de datos totalmente distinta al API general de licitaciones
/// (licitaciones.json), que no incluye procesos de Compra Ágil.
class CompraAgil {
  final String codigo;
  final String nombre;
  final String estadoCodigo;
  final String estadoGlosa;
  final DateTime? fechaPublicacion;
  final DateTime? fechaCierre;
  final double? montoDisponibleClp;
  final String? organismoComprador;
  final int? region;
  final String? nombreRegion;

  CompraAgil({
    required this.codigo,
    required this.nombre,
    required this.estadoCodigo,
    required this.estadoGlosa,
    this.fechaPublicacion,
    this.fechaCierre,
    this.montoDisponibleClp,
    this.organismoComprador,
    this.region,
    this.nombreRegion,
  });

  factory CompraAgil.fromJson(Map<String, dynamic> json) {
    final estado = json['estado'] as Map<String, dynamic>? ?? {};
    final fechas = json['fechas'] as Map<String, dynamic>? ?? {};
    final montos = json['montos'] as Map<String, dynamic>? ?? {};
    final institucion = json['institucion'] as Map<String, dynamic>? ?? {};

    return CompraAgil(
      codigo: (json['codigo'] ?? '').toString(),
      nombre: (json['nombre'] ?? 'Sin nombre').toString(),
      estadoCodigo: (estado['codigo'] ?? '').toString(),
      estadoGlosa: (estado['glosa'] ?? '').toString(),
      fechaPublicacion: DateTime.tryParse('${fechas['fecha_publicacion']}'),
      fechaCierre: DateTime.tryParse('${fechas['fecha_cierre']}'),
      montoDisponibleClp: (montos['monto_disponible_clp'] as num?)?.toDouble(),
      organismoComprador: institucion['organismo_comprador']?.toString(),
      region: institucion['region'] as int?,
      nombreRegion: institucion['nombre_region']?.toString(),
    );
  }

  int? get diasParaCierre {
    if (fechaCierre == null) return null;
    return fechaCierre!.difference(DateTime.now()).inDays;
  }

  /// Convierte a [Licitacion] para reutilizar, sin duplicar código, toda
  /// la pantalla de detalle y el flujo de cotización → orden de compra
  /// que ya funcionan con ese modelo.
  Licitacion toLicitacion() {
    return Licitacion(
      codigo: codigo,
      nombre: nombre,
      estado: estadoGlosa.isNotEmpty ? estadoGlosa : estadoCodigo,
      fechaCierre: fechaCierre,
      fechaPublicacion: fechaPublicacion,
      organismo: organismoComprador,
      rubro: nombreRegion,
      montoEstimado: montoDisponibleClp,
      esCompraAgilReal: true,
    );
  }
}
