import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/orden_servicio.dart';
import '../models/servicio_asignado.dart';

/// Acceso a la colección `servicios` de Firestore: alta, asignación, ciclo de
/// vida (aceptar/en camino/en sitio/cerrar) y el sub-documento de rastreo en
/// vivo usado por la página web de tracking.
class ServicioRepository {
  ServicioRepository({FirebaseFirestore? firestore})
      : _col = (firestore ?? FirebaseFirestore.instance).collection('servicios');

  final CollectionReference<Map<String, dynamic>> _col;

  Future<String> crear(ServicioAsignado servicio) async {
    final doc = await _col.add(servicio.toMap());
    return doc.id;
  }

  Stream<List<ServicioAsignado>> observarPorTecnico(String technicianId) => _col
      .where('technicianId', isEqualTo: technicianId)
      .where('estadoAsignacion', whereIn: [
        EstadoAsignacion.asignado.name,
        EstadoAsignacion.aceptado.name,
        EstadoAsignacion.enCamino.name,
        EstadoAsignacion.enSitio.name,
      ])
      .snapshots()
      .map((s) => s.docs.map((d) => ServicioAsignado.fromMap(d.id, d.data())).toList());

  /// TODOS los servicios del técnico (activos y cerrados) para la pestaña
  /// de productividad. Un solo filtro de igualdad: no requiere índice.
  Stream<List<ServicioAsignado>> observarHistorial(String technicianId) => _col
      .where('technicianId', isEqualTo: technicianId)
      .snapshots()
      .map((s) => s.docs.map((d) => ServicioAsignado.fromMap(d.id, d.data())).toList());

  Stream<List<ServicioAsignado>> observarTodos() => _col
      .orderBy('fechaCreacion', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => ServicioAsignado.fromMap(d.id, d.data())).toList());

  Stream<ServicioAsignado?> observarUno(String id) => _col.doc(id).snapshots().map(
        (doc) => doc.exists ? ServicioAsignado.fromMap(doc.id, doc.data()!) : null,
      );

  Future<void> asignar(String id, String technicianId) => _col.doc(id).update({
        'technicianId': technicianId,
        'estadoAsignacion': EstadoAsignacion.asignado.name,
        'fechaAsignado': DateTime.now().toIso8601String(),
      });

  Future<void> aceptar(String id) => _col.doc(id).update({
        'estadoAsignacion': EstadoAsignacion.aceptado.name,
        'fechaAceptado': DateTime.now().toIso8601String(),
      });

  Future<void> marcarEnCamino(String id) => _col.doc(id).update({
        'estadoAsignacion': EstadoAsignacion.enCamino.name,
        'fechaEnCamino': DateTime.now().toIso8601String(),
      });

  Future<void> marcarEnSitio(String id) => _col.doc(id).update({
        'estadoAsignacion': EstadoAsignacion.enSitio.name,
        'fechaEnSitio': DateTime.now().toIso8601String(),
      });

  Future<void> actualizarVideoFalla(String id, String videoUrl) =>
      _col.doc(id).update({'videoFallaUrl': videoUrl});

  Future<void> cerrar(
    String id, {
    required EstadoServicio estadoFinal,
    String? pdfUrl,
    String? motivoPendiente,
    List<String> refaccionesFaltantes = const [],
  }) =>
      _col.doc(id).update({
        'estadoAsignacion': EstadoAsignacion.cerrado.name,
        'estadoFinal': estadoFinal.name,
        'pdfUrl': pdfUrl,
        'motivoPendiente': motivoPendiente,
        'refaccionesFaltantes': refaccionesFaltantes,
        'fechaCierre': DateTime.now().toIso8601String(),
      });

  /// Escribe la posición en vivo del técnico mientras va "en camino".
  /// Se llama con [Geolocator.getPositionStream] con `distanceFilter`
  /// (15-20m) del lado de la app — nunca con un timer fijo — para no gastar
  /// batería ni cuota de Firestore de más.
  Future<void> actualizarTracking(String servicioId, double lat, double lng) =>
      _col.doc(servicioId).collection('tracking').doc('actual').set({
        'lat': lat,
        'lng': lng,
        'actualizado': DateTime.now().toIso8601String(),
      });

  Stream<Map<String, dynamic>?> observarTracking(String servicioId) => _col
      .doc(servicioId)
      .collection('tracking')
      .doc('actual')
      .snapshots()
      .map((d) => d.data());
}
