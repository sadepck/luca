import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:luca/services/compra_agil_service.dart';
import 'package:luca/services/mercado_publico_service.dart' show MercadoPublicoException;

Map<String, dynamic> _paginaOk({
  required List<Map<String, dynamic>> items,
  required int totalPaginas,
}) {
  return {
    'success': 'OK',
    'payload': {
      'items': items,
      'paginacion': {'total_paginas': totalPaginas},
    },
  };
}

/// Sin un header `content-type` explícito, `http.Response` codifica el
/// body como `latin1` (ver `response.dart` del paquete `http`); como el
/// cliente decodifica la respuesta como UTF-8 (igual que una API real),
/// hay que declarar el content-type acá para que las tildes de los datos
/// de prueba no rompan el parseo.
http.Response _jsonResponse(Object body, int statusCode) {
  return http.Response(json.encode(body), statusCode,
      headers: {'content-type': 'application/json'});
}

void main() {
  group('buscarActivas', () {
    test('con ticket vacío, lanza MercadoPublicoException sin hacer ningún request', () async {
      var seLlamoAlApi = false;
      final client = MockClient((request) async {
        seLlamoAlApi = true;
        return http.Response('', 200);
      });

      await expectLater(
        CompraAgilService(client: client).buscarActivas(''),
        throwsA(isA<MercadoPublicoException>()),
      );
      expect(seLlamoAlApi, isFalse);
    });

    test('envía el ticket como header, no como parámetro de query', () async {
      http.Request? requestRecibida;
      final client = MockClient((request) async {
        requestRecibida = request;
        return _jsonResponse(_paginaOk(items: [], totalPaginas: 1), 200);
      });

      await CompraAgilService(client: client).buscarActivas('mi-ticket');

      expect(requestRecibida!.headers['ticket'], 'mi-ticket');
      expect(requestRecibida!.url.queryParameters.containsKey('ticket'), isFalse);
    });

    test('con una sola página, no pide una segunda', () async {
      var llamadas = 0;
      final client = MockClient((request) async {
        llamadas++;
        return _jsonResponse(
          _paginaOk(
            items: [
              {
                'codigo': 'CA-1',
                'nombre': 'Compra ágil de prueba',
                'estado': {'codigo': 'publicada', 'glosa': 'Publicada'},
              }
            ],
            totalPaginas: 1,
          ),
          200,
        );
      });

      final resultado = await CompraAgilService(client: client).buscarActivas('ticket');

      expect(llamadas, 1);
      expect(resultado, hasLength(1));
      expect(resultado.first.codigo, 'CA-1');
    });

    test('recorre páginas hasta total_paginas, sin pasar del límite de 2', () async {
      final llamadasPorPagina = <int>[];
      final client = MockClient((request) async {
        final pagina = int.parse(request.url.queryParameters['numero_pagina']!);
        llamadasPorPagina.add(pagina);
        return _jsonResponse(
          _paginaOk(
            items: [
              {
                'codigo': 'CA-$pagina',
                'nombre': 'Item página $pagina',
                'estado': {'codigo': 'publicada', 'glosa': 'Publicada'},
              }
            ],
            // Simula muchas más páginas de las que el servicio debe recorrer.
            totalPaginas: 5,
          ),
          200,
        );
      });

      final resultado = await CompraAgilService(client: client).buscarActivas('ticket');

      expect(llamadasPorPagina, [1, 2]);
      expect(resultado.map((c) => c.codigo), ['CA-1', 'CA-2']);
    });

    test('success != OK lanza el mensaje de error específico del payload', () async {
      final client = MockClient((request) async {
        return _jsonResponse({
          'success': 'ERROR',
          'errors': [
            {'mensaje': 'Ticket sin permiso para Compra Ágil'},
          ],
        }, 200);
      });

      await expectLater(
        CompraAgilService(client: client).buscarActivas('ticket'),
        throwsA(isA<MercadoPublicoException>().having(
          (e) => e.message,
          'message',
          'Ticket sin permiso para Compra Ágil',
        )),
      );
    });

    test('403 propaga el mensaje específico de Compra Ágil sobre solicitar ticket aparte', () async {
      final client = MockClient((request) async => http.Response('', 403));

      await expectLater(
        CompraAgilService(client: client).buscarActivas('ticket'),
        throwsA(isA<MercadoPublicoException>().having(
          (e) => e.message,
          'message',
          contains('chilecompra.cl/api'),
        )),
      );
    });
  });
}
