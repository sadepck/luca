import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'mercado_publico_service.dart' show MercadoPublicoException;

/// Cliente HTTP compartido entre los distintos APIs de ChileCompra
/// (licitaciones y Compra Ágil): hace el `GET` con timeout, traduce
/// errores de conexión/timeout/HTTP a [MercadoPublicoException] con
/// mensajes consistentes entre ambos servicios, y decodifica el cuerpo
/// como JSON. Cada servicio conserva su propio parseo del payload (las
/// formas de respuesta de ambos APIs son distintas).
///
/// [nombreApi] se usa en los mensajes de error para que el usuario sepa
/// cuál de los dos APIs falló (ej. "Mercado Público" o "Compra Ágil").
/// [mensajeSinAcceso] permite personalizar el mensaje de 401/403, ya que
/// el ticket de Compra Ágil puede requerir un trámite aparte del de
/// licitaciones. [client] permite inyectar un `http.Client` fake en los
/// tests, sin red real.
Future<Map<String, dynamic>> getJson(
  Uri uri, {
  required String nombreApi,
  Map<String, String>? headers,
  Duration timeout = const Duration(seconds: 20),
  String? mensajeSinAcceso,
  http.Client? client,
}) async {
  final httpClient = client ?? http.Client();

  late final http.Response response;
  try {
    final request = headers == null
        ? httpClient.get(uri)
        : httpClient.get(uri, headers: headers);
    response = await request.timeout(timeout);
  } on TimeoutException {
    throw MercadoPublicoException(
        'El API de $nombreApi tardó demasiado en responder. Puede que esté '
        'lento o inaccesible desde tu red — prueba con otra conexión o más tarde.');
  } on SocketException catch (e) {
    throw MercadoPublicoException(
        'No se pudo conectar con el API de $nombreApi '
        '(${e.osError?.message ?? 'sin conexión'}). Revisa tu internet.');
  } catch (e) {
    throw MercadoPublicoException('No se pudo conectar con el API de $nombreApi: $e');
  }

  if (response.statusCode == 401 || response.statusCode == 403) {
    throw MercadoPublicoException(mensajeSinAcceso ??
        'Tu ticket no tiene acceso al API de $nombreApi, o no es válido.');
  }
  if (response.statusCode == 429) {
    throw MercadoPublicoException(
        'Se alcanzó el límite diario de consultas al API de $nombreApi.');
  }
  if (response.statusCode != 200) {
    throw MercadoPublicoException(
        'El API de $nombreApi respondió con un error (${response.statusCode}).');
  }

  try {
    return json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  } catch (_) {
    throw MercadoPublicoException(
        'No se pudo interpretar la respuesta del API de $nombreApi.');
  }
}
