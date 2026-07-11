import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/licitacion.dart';

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

    late final http.Response response;
    try {
      response = await http.get(uri).timeout(const Duration(seconds: 20));
    } catch (_) {
      throw MercadoPublicoException(
          'No se pudo conectar con Mercado Público. Revisa tu conexión.');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw MercadoPublicoException(
          'Tu ticket de Mercado Público no es válido o fue rechazado.');
    }
    if (response.statusCode == 429) {
      throw MercadoPublicoException(
          'Se alcanzó el límite diario de consultas al API (10.000/día).');
    }
    if (response.statusCode != 200) {
      throw MercadoPublicoException(
          'Mercado Público respondió con un error (${response.statusCode}).');
    }

    Map<String, dynamic> body;
    try {
      body = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw MercadoPublicoException(
          'No se pudo interpretar la respuesta de Mercado Público.');
    }

    final listado = body['Listado'];
    if (listado is! List) return [];

    return listado
        .whereType<Map<String, dynamic>>()
        .map((item) => Licitacion.fromJson(item))
        .where((licitacion) => licitacion.codigo.isNotEmpty)
        .toList();
  }
}
