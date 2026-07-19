import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:soytu_core/soytu_core.dart';

/// Publica la ubicación del técnico a Firestore (tecnicos/{uid}.ubicacion)
/// de forma CONTINUA, incluso con la app minimizada o la pantalla apagada.
///
/// Usa un servicio en primer plano de Android (vía geolocator): mientras el
/// técnico tenga sesión iniciada, Android mantiene vivo el rastreo y muestra
/// una notificación fija "SOYTU Técnico en servicio" que le indica que su
/// ubicación se está compartiendo con el centro de operaciones.
class UbicacionGlobal {
  UbicacionGlobal._();

  static StreamSubscription<Position>? _sub;
  static String? _uidActivo;

  static Future<void> iniciar(String uid, TecnicoRepository repo) async {
    if (_uidActivo == uid && _sub != null) return; // ya publicando
    await detener();
    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }
    if (permiso != LocationPermission.always &&
        permiso != LocationPermission.whileInUse) {
      return;
    }
    _uidActivo = uid;

    // Primera posición inmediata para aparecer en el mapa sin esperar.
    try {
      final p = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high));
      await repo.actualizarUbicacion(uid, p.latitude, p.longitude);
    } catch (_) {}

    // Stream con SERVICIO EN PRIMER PLANO: sigue publicando en background.
    _sub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 30, // publica al moverse ~30 m (cuida batería y cuota)
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'SOYTU Técnico en servicio',
          notificationText:
              'Compartiendo tu ubicación con el centro de operaciones SOYTU.',
          notificationIcon:
              AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
          enableWakeLock: true,
          setOngoing: true,
        ),
      ),
    ).listen((p) {
      repo.actualizarUbicacion(uid, p.latitude, p.longitude);
    });
  }

  static Future<void> detener() async {
    await _sub?.cancel();
    _sub = null;
    _uidActivo = null;
  }
}
