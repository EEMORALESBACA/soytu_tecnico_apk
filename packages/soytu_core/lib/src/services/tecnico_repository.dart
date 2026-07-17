import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/tecnico.dart';

/// Acceso a la colección `tecnicos` de Firestore.
class TecnicoRepository {
  TecnicoRepository({FirebaseFirestore? firestore})
      : _col = (firestore ?? FirebaseFirestore.instance).collection('tecnicos');

  final CollectionReference<Map<String, dynamic>> _col;

  Future<void> registrar(Tecnico tecnico) => _col.doc(tecnico.uid).set(tecnico.toMap());

  Stream<Tecnico?> observar(String uid) => _col.doc(uid).snapshots().map(
        (doc) => doc.exists ? Tecnico.fromMap(doc.id, doc.data()!) : null,
      );

  Stream<List<Tecnico>> observarPendientes() => _col
      .where('estadoAprobacion', isEqualTo: EstadoAprobacion.pendiente.name)
      .orderBy('fechaRegistro')
      .snapshots()
      .map((s) => s.docs.map((d) => Tecnico.fromMap(d.id, d.data())).toList());

  Stream<List<Tecnico>> observarAprobados() => _col
      .where('estadoAprobacion', isEqualTo: EstadoAprobacion.aprobado.name)
      .snapshots()
      .map((s) => s.docs.map((d) => Tecnico.fromMap(d.id, d.data())).toList());

  Future<void> aprobar(String uid) => _col.doc(uid).update({
        'estadoAprobacion': EstadoAprobacion.aprobado.name,
        'motivoRechazo': null,
      });

  Future<void> rechazar(String uid, String motivo) => _col.doc(uid).update({
        'estadoAprobacion': EstadoAprobacion.rechazado.name,
        'motivoRechazo': motivo,
      });

  Future<void> actualizarFcmToken(String uid, String token) =>
      _col.doc(uid).update({'fcmToken': token});
}
