import 'package:http/http.dart' as http;

import '../models/licitacion.dart';
import 'mercado_publico_http_client.dart';

/// Error específico del servicio de Mercado Público, con un mensaje ya
/// listo para mostrar al usuario en la UI.
class MercadoPublicoException implements Exception {
  final String message;
  MercadoPublicoException(this.message);

  @override
  String toString() => message;
}

/// Cliente del API pública de ChileCompra (api.mercadopublico.cl).
/// Requiere un ticket personal que el usuario obtiene gratis en
/// https://api.mercadopublico.cl/modules/IniciarSesion.aspx con Clave Única.
class MercadoPublicoService {
  static const _baseUrl = 'https://api.mercadopublico.cl/servicios/v1/publico';

  /// [client] permite inyectar un `http.Client` fake en los tests.
  final http.Client? _client;
  MercadoPublicoService({http.Client? client}) : _client = client;

  Future<List<Licitacion>> buscarActivas(String ticket) {
    return _buscarLicitaciones({'estado': 'activas', 'ticket': ticket});
  }

  Future<List<Licitacion>> buscarPorFecha(
    DateTime fecha,
    String ticket, {
    String estado = 'todos',
  }) {
    final fechaStr = '${fecha.day.toString().padLeft(2, '0')}'
        '${fecha.month.toString().padLeft(2, '0')}'
        '${fecha.year}';
    return _buscarLicitaciones(
        {'fecha': fechaStr, 'estado': estado, 'ticket': ticket});
  }

  Future<Licitacion?> buscarPorCodigo(String codigo, String ticket) async {
    final resultados =
        await _buscarLicitaciones({'codigo': codigo, 'ticket': ticket});
    return resultados.isEmpty ? null : resultados.first;
  }

  Future<List<Licitacion>> _buscarLicitaciones(
      Map<String, String> params) async {
    if ((params['ticket'] ?? '').trim().isEmpty) {
      throw MercadoPublicoException(
          'Falta configurar tu ticket de acceso al API de Mercado Público.');
    }

    final uri = Uri.parse('$_baseUrl/licitaciones.json')
        .replace(queryParameters: params);

    final body = await getJson(
      uri,
      nombreApi: 'Mercado Público',
      client: _client,
    );

    final listado = body['Listado'];
    if (listado is! List) return [];

    return listado
        .whereType<Map<String, dynamic>>()
        .map(Licitacion.fromJson)
        .where((licitacion) => licitacion.codigo.isNotEmpty)
        .toList();
  }
}
