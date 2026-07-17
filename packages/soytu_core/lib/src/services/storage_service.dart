import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

/// Sube evidencia (fotos, firma, PDF) a Firebase Storage y regresa la URL de
/// descarga para guardarla en Firestore.
class StorageService {
  StorageService({FirebaseStorage? storage}) : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  Future<String> subirFotoTecnico(String uid, String nombreArchivo, Uint8List bytes) =>
      _subir('tecnicos/$uid/$nombreArchivo', bytes, 'image/jpeg');

  Future<String> subirFotoServicio(String servicioId, String nombreArchivo, Uint8List bytes) =>
      _subir('servicios/$servicioId/$nombreArchivo', bytes, 'image/jpeg');

  Future<String> subirVideoFalla(String servicioId, Uint8List bytes) =>
      _subir('servicios/$servicioId/video_falla.mp4', bytes, 'video/mp4');

  Future<String> subirFirma(String servicioId, Uint8List bytes) =>
      _subir('servicios/$servicioId/firma.png', bytes, 'image/png');

  Future<String> subirPdf(String servicioId, Uint8List bytes) =>
      _subir('servicios/$servicioId/hoja_servicio.pdf', bytes, 'application/pdf');

  Future<String> _subir(String ruta, Uint8List bytes, String contentType) async {
    final ref = _storage.ref(ruta);
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return ref.getDownloadURL();
  }
}
