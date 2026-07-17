import 'package:firebase_messaging/firebase_messaging.dart';

/// Envoltura sobre Firebase Cloud Messaging: pedir permiso, obtener el token
/// del dispositivo y suscribirse a temas (p. ej. `admins` para que el panel
/// de administración reciba avisos de alta de técnicos nuevos).
class NotificationService {
  NotificationService({FirebaseMessaging? mensajeria})
      : _mensajeria = mensajeria ?? FirebaseMessaging.instance;

  final FirebaseMessaging _mensajeria;

  Future<void> solicitarPermiso() => _mensajeria.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

  Future<String?> obtenerToken() => _mensajeria.getToken();

  Stream<String> get cambiosDeToken => _mensajeria.onTokenRefresh;

  Future<void> suscribirATema(String tema) => _mensajeria.subscribeToTopic(tema);

  Stream<RemoteMessage> get mensajesEnPrimerPlano => FirebaseMessaging.onMessage;
}
