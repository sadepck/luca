import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:luca/services/mp_ticket_storage.dart';

/// Fake en memoria de [TicketSecureStore]: evita depender del canal de
/// plataforma de `flutter_secure_storage`, que no tiene implementación en
/// el entorno de test.
class _FakeTicketSecureStore implements TicketSecureStore {
  String? valor;
  _FakeTicketSecureStore([this.valor]);

  @override
  Future<String?> read() async => valor;

  @override
  Future<void> write(String value) async => valor = value;
}

void main() {
  group('leerTicketMercadoPublico', () {
    test('devuelve el valor ya guardado en almacenamiento seguro sin tocar shared_preferences', () async {
      SharedPreferences.setMockInitialValues({'mp_ticket': 'ticket-legado-que-no-debe-usarse'});
      final store = _FakeTicketSecureStore('ticket-seguro');

      final ticket = await leerTicketMercadoPublico(store: store);

      expect(ticket, 'ticket-seguro');
    });

    test('migra un ticket legado desde shared_preferences la primera vez que se lee', () async {
      SharedPreferences.setMockInitialValues({'mp_ticket': 'ticket-viejo-sin-cifrar'});
      final store = _FakeTicketSecureStore();

      final ticket = await leerTicketMercadoPublico(store: store);

      expect(ticket, 'ticket-viejo-sin-cifrar');
      expect(store.valor, 'ticket-viejo-sin-cifrar');
    });

    test('borra el ticket legado de shared_preferences después de migrarlo', () async {
      SharedPreferences.setMockInitialValues({'mp_ticket': 'ticket-viejo-sin-cifrar'});
      final store = _FakeTicketSecureStore();

      await leerTicketMercadoPublico(store: store);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('mp_ticket'), isNull);
    });

    test('sin ticket seguro ni legado, devuelve string vacío', () async {
      SharedPreferences.setMockInitialValues({});
      final store = _FakeTicketSecureStore();

      expect(await leerTicketMercadoPublico(store: store), '');
    });
  });

  group('guardarTicketMercadoPublico', () {
    test('escribe el ticket en el almacenamiento seguro', () async {
      final store = _FakeTicketSecureStore();

      await guardarTicketMercadoPublico('ticket-nuevo', store: store);

      expect(store.valor, 'ticket-nuevo');
    });
  });
}
