import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notificaciones locales de SOYTU Técnico.
///
/// La alerta de nuevo servicio es INSISTENTE: usa el flag nativo de Android
/// FLAG_INSISTENT, así que el sonido se repite sin parar hasta que el técnico
/// la atiende (entra a la app y acepta el servicio, o la desliza).
class NotificacionesLocales {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _inicializado = false;
  static final Set<int> _activas = {};

  static const AndroidNotificationChannel _canal = AndroidNotificationChannel(
    'servicios_soytu',
    'Servicios SOYTU',
    description: 'Avisos de nuevos servicios asignados',
    importance: Importance.max,
    playSound: true,
  );

  static Future<void> inicializar() async {
    if (_inicializado) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidInit),
    );
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(_canal);
    await androidImpl?.requestNotificationsPermission();
    _inicializado = true;
  }

  /// Muestra la alerta de nuevo servicio con el logo SOYTU en la barra
  /// superior. No vuelve a dispararla si ya está activa para ese servicio.
  static Future<void> nuevoServicio(
      String servicioId, String titulo, String cuerpo) async {
    final idNotif = servicioId.hashCode & 0x7fffffff;
    if (_activas.contains(idNotif)) return;
    await inicializar();
    _activas.add(idNotif);
    await _plugin.show(
      idNotif,
      titulo,
      cuerpo,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _canal.id,
          _canal.name,
          channelDescription: _canal.description,
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          ongoing: true,
          autoCancel: false,
          icon: '@mipmap/ic_launcher',
          largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          // FLAG_INSISTENT: el sonido se repite hasta atender la alerta.
          additionalFlags: Int32List.fromList(const <int>[4]),
          styleInformation: BigTextStyleInformation(cuerpo),
        ),
      ),
    );
  }

  static Future<void> cancelarServicio(String servicioId) async {
    final idNotif = servicioId.hashCode & 0x7fffffff;
    _activas.remove(idNotif);
    await _plugin.cancel(idNotif);
  }

  static Future<void> cancelarTodas() async {
    _activas.clear();
    await _plugin.cancelAll();
  }
}
