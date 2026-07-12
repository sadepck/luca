import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:luca/services/mercado_publico_http_client.dart';
import 'package:luca/services/mercado_publico_service.dart' show MercadoPublicoException;

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
  final uri = Uri.parse('https://ejemplo.test/api');

  test('200 con JSON válido devuelve el body decodificado', () async {
    final client = MockClient((request) async {
      return _jsonResponse({'ok': true}, 200);
    });

    final body = await getJson(uri, nombreApi: 'Prueba', client: client);

    expect(body, {'ok': true});
  });

  test('pasa los headers al request', () async {
    Map<String, String>? headersRecibidos;
    final client = MockClient((request) async {
      headersRecibidos = request.headers;
      return _jsonResponse({}, 200);
    });

    await getJson(uri, nombreApi: 'Prueba', headers: {'ticket': 'abc'}, client: client);

    expect(headersRecibidos!['ticket'], 'abc');
  });

  test('401 lanza MercadoPublicoException con mensaje por defecto', () async {
    final client = MockClient((request) async => http.Response('', 401));

    await expectLater(
      getJson(uri, nombreApi: 'Prueba', client: client),
      throwsA(isA<MercadoPublicoException>().having(
        (e) => e.message,
        'message',
        contains('Prueba'),
      )),
    );
  });

  test('403 lanza el mensaje personalizado cuando se provee mensajeSinAcceso', () async {
    final client = MockClient((request) async => http.Response('', 403));

    await expectLater(
      getJson(
        uri,
        nombreApi: 'Prueba',
        mensajeSinAcceso: 'mensaje a medida',
        client: client,
      ),
      throwsA(isA<MercadoPublicoException>()
          .having((e) => e.message, 'message', 'mensaje a medida')),
    );
  });

  test('429 lanza MercadoPublicoException mencionando el límite diario', () async {
    final client = MockClient((request) async => http.Response('', 429));

    await expectLater(
      getJson(uri, nombreApi: 'Prueba', client: client),
      throwsA(isA<MercadoPublicoException>()
          .having((e) => e.message, 'message', contains('límite diario'))),
    );
  });

  test('otro código de error HTTP incluye el código en el mensaje', () async {
    final client = MockClient((request) async => http.Response('', 500));

    await expectLater(
      getJson(uri, nombreApi: 'Prueba', client: client),
      throwsA(isA<MercadoPublicoException>()
          .having((e) => e.message, 'message', contains('500'))),
    );
  });

  test('JSON inválido en el body lanza "no se pudo interpretar"', () async {
    final client = MockClient((request) async => http.Response('esto no es json', 200));

    await expectLater(
      getJson(uri, nombreApi: 'Prueba', client: client),
      throwsA(isA<MercadoPublicoException>()
          .having((e) => e.message, 'message', contains('interpretar'))),
    );
  });

  test('timeout lanza MercadoPublicoException mencionando que tardó demasiado', () async {
    final client = MockClient((request) async {
      await Future.delayed(const Duration(milliseconds: 200));
      return http.Response(json.encode({}), 200);
    });

    await expectLater(
      getJson(
        uri,
        nombreApi: 'Prueba',
        timeout: const Duration(milliseconds: 20),
        client: client,
      ),
      throwsA(isA<MercadoPublicoException>()
          .having((e) => e.message, 'message', contains('tardó demasiado'))),
    );
  });

  test('SocketException lanza MercadoPublicoException mencionando la conexión', () async {
    final client = MockClient((request) async {
      throw const SocketException('fallo de red simulado');
    });

    await expectLater(
      getJson(uri, nombreApi: 'Prueba', client: client),
      throwsA(isA<MercadoPublicoException>()
          .having((e) => e.message, 'message', contains('No se pudo conectar'))),
    );
  });

  test('cualquier otra excepción también se mapea a MercadoPublicoException', () async {
    final client = MockClient((request) async {
      throw Exception('algo inesperado');
    });

    await expectLater(
      getJson(uri, nombreApi: 'Prueba', client: client),
      throwsA(isA<MercadoPublicoException>()),
    );
  });
}
