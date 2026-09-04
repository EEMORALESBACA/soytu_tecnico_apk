import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

const _tareaRastreoRespaldo = 'soytu_rastreo_respaldo';
const _clavePrefsUid = 'soytu_uid_activo';

/// Respaldo de rastreo cuando el técnico CIERRA la app desde recientes o
/// no la abre ese día — usa WorkManager de Android, que sigue vivo aunque
/// se elimine la app del multitarea, mientras no se desinstale ni se
/// "detenga forzosamente" desde Ajustes del celular.
///
/// No sustituye al rastreo en tiempo real de [UbicacionGlobal] (que sigue
/// siendo el más preciso mientras el técnico tiene la app abierta o
/// minimizada) — es la red de seguridad para cuando ese primero se cae.
///
/// Limitación honesta: Android solo permite que WorkManager corra como
/// mínimo cada 15 minutos — no es tiempo real, pero es mucho mejor que
/// perder al técnico por completo. Algunos celulares (Xiaomi, Huawei,
/// Oppo, Vivo) matan tareas en segundo plano de forma agresiva salvo que
/// el técnico quite manualmente la "optimización de batería" de la app
/// en Ajustes — coméntaselo a tus técnicos al darlos de alta.
class RastreoRespaldo {
  RastreoRespaldo._();

  static Future<void> registrarUnaVez(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clavePrefsUid, uid);

    await Workmanager().initialize(callbackDispatcherRespaldo);
    await Workmanager().registerPeriodicTask(
      _tareaRastreoRespaldo,
      _tareaRastreoRespaldo,
      frequency: const Duration(minutes: 15), // mínimo permitido por Android
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep, // no duplicar si ya existe
    );
  }

  static Future<void> cancelar() async {
    await Workmanager().cancelByUniqueName(_tareaRastreoRespaldo);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_clavePrefsUid);
  }
}

/// Punto de entrada que corre en un isolate aparte, sin UI — por eso no
/// puede usar Riverpod ni nada del árbol de widgets. Lee el uid guardado,
/// toma una posición y la publica directo en Firestore.
@pragma('vm:entry-point')
void callbackDispatcherRespaldo() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await Firebase.initializeApp();
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getString(_clavePrefsUid);
      if (uid == null) return true;

      final db = FirebaseFirestore.instance;
      final tecDoc = await db.collection('tecnicos').doc(uid).get();
      if (!tecDoc.exists || tecDoc.data()?['estadoAprobacion'] != 'aprobado') {
        return true;
      }

      // Solo gasta batería/datos si el técnico tiene algo asignado hoy —
      // igual que el aviso de privacidad promete ("durante tu turno").
      final tieneServicioActivo = await db
          .collection('servicios')
          .where('technicianId', isEqualTo: uid)
          .where('estadoAsignacion', whereIn: ['asignado', 'aceptado', 'enCamino', 'enSitio'])
          .limit(1)
          .get();
      if (tieneServicioActivo.docs.isEmpty) return true;

      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied ||
          permiso == LocationPermission.deniedForever) {
        return true;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 25),
        ),
      );

      await db.collection('tecnicos').doc(uid).update({
        'ubicacionRespaldo': {
          'lat': pos.latitude,
          'lng': pos.longitude,
          'actualizado': DateTime.now().toIso8601String(),
        },
      });
    } catch (_) {
      // Sin conexión, sin permiso o cualquier otro tropiezo: no truena la
      // tarea, Android la vuelve a intentar en el siguiente ciclo de 15 min.
    }
    return true;
  });
}
