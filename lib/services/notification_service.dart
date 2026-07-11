import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Envoltorio simple sobre flutter_local_notifications para avisar de
/// nuevas oportunidades de Mercado Público / Compra Ágil que calzan con
/// el rubro del usuario. Las notificaciones se disparan localmente,
/// ya sea desde la app abierta o desde la tarea periódica de Workmanager.
class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _channelId = 'mercado_publico';
  static const _channelName = 'Mercado Público';
  static const _channelDescription =
      'Avisos de nuevas licitaciones y oportunidades de Compra Ágil';

  Future<void> init() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );
    await _plugin.initialize(settings: initSettings);

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  Future<bool> solicitarPermiso() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final granted = await ios.requestPermissions(alert: true, sound: true);
      return granted ?? false;
    }
    return true;
  }

  Future<void> mostrarNuevasOportunidades(int cantidad) async {
    await init();
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );
    final texto = cantidad == 1
        ? 'Hay 1 oportunidad nueva que calza con tu rubro'
        : 'Hay $cantidad oportunidades nuevas que calzan con tu rubro';
    await _plugin.show(
      id: 1001,
      title: 'Mercado Público',
      body: texto,
      notificationDetails: details,
    );
  }
}
