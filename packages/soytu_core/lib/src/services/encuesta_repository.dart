import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/encuesta_satisfaccion.dart';

/// Acceso a la colección `encuestas` (respuestas de satisfacción/NPS).
/// La escritura de creación también la usa la página web pública de
/// encuesta (vía Firebase JS SDK) — la lectura queda restringida al admin
/// por las reglas de Firestore, no por este repositorio.
class EncuestaRepository {
  EncuestaRepository({FirebaseFirestore? firestore})
      : _col = (firestore ?? FirebaseFirestore.instance).collection('encuestas');

  final CollectionReference<Map<String, dynamic>> _col;

  Future<void> registrar(EncuestaSatisfaccion encuesta) => _col.add(encuesta.toMap());

  Stream<List<EncuestaSatisfaccion>> observarTodas() => _col
      .orderBy('fecha', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => EncuestaSatisfaccion.fromMap(d.data())).toList());
}
