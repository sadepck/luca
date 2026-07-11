import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/compra_agil.dart';
import 'mercado_publico_service.dart' show MercadoPublicoException;

/// Cliente del API dedicado de Compra Ágil de ChileCompra
/// (api2.mercadopublico.cl/v2/compra-agil) — un API totalmente distinto
/// al de licitaciones (licitaciones.json), publicado por ChileCompra en
/// mayo de 2026. El ticket se envía como header HTTP `ticket`, no como
/// parámetro de query como en el API de licitaciones.
class CompraAgilService {
  static const _baseUrl = 'https://api2.mercadopublico.cl/v2/compra-agil';

  /// Trae Compras Ágiles publicadas o con proveedor ya seleccionado,
  /// opcionalmente filtradas por palabra clave y/o región.
  Future<List<CompraAgil>> buscarActivas(
    String ticket, {
    String? q,
    List<int>? regiones,
  }) async {
    final params = <String, String>{
      'estado': 'publicada,proveedor_seleccionado',
      'tamano_pagina': '50',
    };
    if (q != null && q.trim().isNotEmpty) params['q'] = q.trim();
    if (regiones != null && regiones.isNotEmpty) {
      params['region'] = regiones.join(',');
    }

    final items = <CompraAgil>[];
    int pagina = 1;
    while (true) {
      params['numero_pagina'] = pagina.toString();
      final resultado = await _buscarPagina(ticket, params);
      items.addAll(resultado.$1);
      final totalPaginas = resultado.$2;
      if (pagina >= totalPaginas || totalPaginas == 0) break;
      pagina++;
      // No recorrer más de un par de páginas para no dejar a la pantalla
      // esperando mucho rato ni gastar la cuota diaria del ticket en una
      // sola carga.
      if (pagina > 2) break;
    }
    return items;
  }

  Future<(List<CompraAgil>, int)> _buscarPagina(
      String ticket, Map<String, String> params) async {
    if (ticket.trim().isEmpty) {
      throw MercadoPublicoException(
          'Falta configurar tu ticket de acceso al API de Mercado Público.');
    }

    final uri = Uri.parse(_baseUrl).replace(queryParameters: params);

    late final http.Response response;
    try {
      response = await http
          .get(uri, headers: {'ticket': ticket})
          .timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw MercadoPublicoException(
          'El API de Compra Ágil tardó demasiado en responder '
          '(api2.mercadopublico.cl). Puede que esté lento o inaccesible '
          'desde tu red — prueba con otra conexión o más tarde.');
    } on SocketException catch (e) {
      throw MercadoPublicoException(
          'No se pudo conectar con api2.mercadopublico.cl (${e.osError?.message ?? 'sin conexión'}). '
          'Revisa tu internet.');
    } catch (e) {
      throw MercadoPublicoException(
          'No se pudo conectar con el API de Compra Ágil: $e');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw MercadoPublicoException(
          'Tu ticket no tiene acceso al API de Compra Ágil. Puede que '
          'necesites solicitar uno específico en chilecompra.cl/api.');
    }
    if (response.statusCode == 429) {
      throw MercadoPublicoException(
          'Se alcanzó el límite diario de consultas al API de Compra Ágil.');
    }
    if (response.statusCode != 200) {
      throw MercadoPublicoException(
          'Compra Ágil respondió con un error (${response.statusCode}).');
    }

    Map<String, dynamic> body;
    try {
      body = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw MercadoPublicoException(
          'No se pudo interpretar la respuesta del API de Compra Ágil.');
    }

    if (body['success'] != 'OK') {
      final errores = body['errors'];
      final mensaje = (errores is List && errores.isNotEmpty)
          ? errores.first['mensaje']?.toString()
          : null;
      throw MercadoPublicoException(
          mensaje ?? 'El API de Compra Ágil devolvió un error.');
    }

    final payload = body['payload'] as Map<String, dynamic>?;
    final items = payload?['items'];
    final paginacion = payload?['paginacion'] as Map<String, dynamic>?;
    final totalPaginas = (paginacion?['total_paginas'] as num?)?.toInt() ?? 0;

    if (items is! List) return (<CompraAgil>[], 0);

    final resultado = items
        .whereType<Map<String, dynamic>>()
        .map((item) => CompraAgil.fromJson(item))
        .where((ca) => ca.codigo.isNotEmpty)
        .toList();
    return (resultado, totalPaginas);
  }
}
