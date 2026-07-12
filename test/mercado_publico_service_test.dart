import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:luca/services/mercado_publico_service.dart';

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
        MercadoPublicoService(client: client).buscarActivas(''),
        throwsA(isA<MercadoPublicoException>()),
      );
      expect(seLlamoAlApi, isFalse);
    });

    test('envía el ticket como parámetro de query', () async {
      Uri? uriRecibida;
      final client = MockClient((request) async {
        uriRecibida = request.url;
        return _jsonResponse({'Listado': []}, 200);
      });

      await MercadoPublicoService(client: client).buscarActivas('mi-ticket');

      expect(uriRecibida!.queryParameters['ticket'], 'mi-ticket');
      expect(uriRecibida!.queryParameters['estado'], 'activas');
    });

    test('parsea el Listado y descarta ítems sin código', () async {
      final client = MockClient((request) async {
        return _jsonResponse({
          'Listado': [
            {'CodigoExterno': 'LIC-1', 'Nombre': 'Compra de insumos', 'Estado': 'Activa'},
            {'CodigoExterno': '', 'Nombre': 'Sin código', 'Estado': 'Activa'},
          ],
        }, 200);
      });

      final resultado = await MercadoPublicoService(client: client).buscarActivas('ticket');

      expect(resultado, hasLength(1));
      expect(resultado.first.codigo, 'LIC-1');
      expect(resultado.first.nombre, 'Compra de insumos');
    });

    test('Listado ausente o con forma inesperada devuelve lista vacía en vez de fallar', () async {
      final client = MockClient((request) async {
        return _jsonResponse({'otraCosa': 1}, 200);
      });

      expect(await MercadoPublicoService(client: client).buscarActivas('ticket'), isEmpty);
    });

    test('401 propaga un error mencionando Mercado Público', () async {
      final client = MockClient((request) async => http.Response('', 401));

      await expectLater(
        MercadoPublicoService(client: client).buscarActivas('ticket'),
        throwsA(isA<MercadoPublicoException>().having(
          (e) => e.message,
          'message',
          contains('Mercado Público'),
        )),
      );
    });
  });
}
