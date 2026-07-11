/// Representa una oportunidad publicada en Mercado Público (licitación,
/// convenio marco o Compra Ágil). El API de ChileCompra no documenta
/// públicamente un esquema único, así que el parseo prueba varios nombres
/// de campo conocidos y tolera campos ausentes.
class Licitacion {
  final String codigo;
  final String nombre;
  final String? descripcion;
  final String estado;
  final DateTime? fechaCierre;
  final DateTime? fechaPublicacion;
  final String? organismo;
  final String? rubro;
  final double? montoEstimado;

  /// true cuando esta [Licitacion] fue construida a partir de un
  /// resultado real del API dedicado de Compra Ágil (ver
  /// [CompraAgil.toLicitacion]) — a diferencia de [esCompraAgil], que es
  /// solo una aproximación por texto sobre licitaciones normales.
  final bool esCompraAgilReal;

  Licitacion({
    required this.codigo,
    required this.nombre,
    this.descripcion,
    required this.estado,
    this.fechaCierre,
    this.fechaPublicacion,
    this.organismo,
    this.rubro,
    this.montoEstimado,
    this.esCompraAgilReal = false,
  });

  factory Licitacion.fromJson(Map<String, dynamic> json) {
    return Licitacion(
      codigo: _pick(json, ['CodigoExterno', 'Codigo']) ?? '',
      nombre: _pick(json, ['Nombre']) ?? 'Sin nombre',
      descripcion: _pick(json, ['Descripcion']),
      estado: _pick(json, ['Estado', 'EstadoLicitacion']) ?? '',
      fechaCierre:
          _parseDate(_pick(json, ['FechaCierre', 'FechaCierrePropuesta'])),
      fechaPublicacion:
          _parseDate(_pick(json, ['FechaPublicacion', 'FechaCreacion'])),
      organismo:
          _pick(json, ['Organismo', 'NombreOrganismo', 'RazonSocialOrganismo']),
      rubro: _pick(json, ['RubroN1', 'Rubro']),
      montoEstimado: _pickDouble(json, ['MontoEstimado']),
    );
  }

  static String? _pick(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return null;
  }

  static double? _pickDouble(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value == null) continue;
      if (value is num) return value.toDouble();
      final parsed = double.tryParse(value.toString());
      if (parsed != null) return parsed;
    }
    return null;
  }

  static DateTime? _parseDate(String? raw) {
    if (raw == null) return null;
    // El API a veces entrega fechas en formato /Date(epochMillis)/
    final epochMatch = RegExp(r'/Date\((\d+)').firstMatch(raw);
    if (epochMatch != null) {
      return DateTime.fromMillisecondsSinceEpoch(
          int.parse(epochMatch.group(1)!));
    }
    return DateTime.tryParse(raw);
  }

  /// Si vino del API dedicado de Compra Ágil, ya se sabe con certeza. Si
  /// no, se recurre a una heurística por texto sobre licitaciones
  /// normales — poco confiable, porque ese endpoint no incluye procesos
  /// de Compra Ágil en la práctica (ver [CompraAgil]).
  bool get esCompraAgil {
    if (esCompraAgilReal) return true;
    final texto = '$nombre ${descripcion ?? ''}'.toLowerCase();
    return texto.contains('compra ágil') || texto.contains('compra agil');
  }

  int? get diasParaCierre {
    if (fechaCierre == null) return null;
    return fechaCierre!.difference(DateTime.now()).inDays;
  }
}
