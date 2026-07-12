import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Clave usada tanto en `shared_preferences` (donde se guardaba el ticket,
/// sin cifrar, antes de esta migración) como en el almacenamiento seguro
/// actual.
const String kMpTicketPrefKey = 'mp_ticket';

/// Pequeña interfaz sobre el almacenamiento seguro, para poder inyectar un
/// fake en los tests sin depender del canal de plataforma de
/// `flutter_secure_storage` (que no tiene una implementación disponible en
/// el entorno de test, a diferencia de `shared_preferences`).
abstract class TicketSecureStore {
  Future<String?> read();
  Future<void> write(String value);
}

class _FlutterTicketSecureStore implements TicketSecureStore {
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: kMpTicketPrefKey);

  @override
  Future<void> write(String value) =>
      _storage.write(key: kMpTicketPrefKey, value: value);
}

/// Lee el ticket personal de Mercado Público desde almacenamiento seguro
/// (Keystore en Android / Keychain en iOS / equivalentes en otras
/// plataformas). Si el usuario lo guardó con una versión anterior de la
/// app —en `shared_preferences`, en texto plano— lo migra a almacenamiento
/// seguro y borra la copia sin cifrar, la primera vez que se lee.
Future<String> leerTicketMercadoPublico({TicketSecureStore? store}) async {
  final secureStore = store ?? _FlutterTicketSecureStore();

  final valorSeguro = await secureStore.read();
  if (valorSeguro != null) return valorSeguro;

  final prefs = await SharedPreferences.getInstance();
  final valorLegado = prefs.getString(kMpTicketPrefKey);
  if (valorLegado == null || valorLegado.isEmpty) return '';

  await secureStore.write(valorLegado);
  await prefs.remove(kMpTicketPrefKey);
  return valorLegado;
}

Future<void> guardarTicketMercadoPublico(
  String ticket, {
  TicketSecureStore? store,
}) {
  final secureStore = store ?? _FlutterTicketSecureStore();
  return secureStore.write(ticket);
}
