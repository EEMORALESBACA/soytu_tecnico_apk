/// Estado de revisión de identidad de un técnico (selfie vs INE), validado
/// manualmente por un administrador — sin matching biométrico automático.
enum EstadoAprobacion { pendiente, aprobado, rechazado }

extension EstadoAprobacionX on EstadoAprobacion {
  String get etiqueta {
    switch (this) {
      case EstadoAprobacion.pendiente:
        return 'Pendiente de revisión';
      case EstadoAprobacion.aprobado:
        return 'Aprobado';
      case EstadoAprobacion.rechazado:
        return 'Rechazado';
    }
  }

  static EstadoAprobacion desdeTexto(String texto) => EstadoAprobacion.values
      .firstWhere((e) => e.name == texto, orElse: () => EstadoAprobacion.pendiente);
}

/// Documento de Firestore (colección `tecnicos`), indexado por el `uid` de
/// Firebase Auth del técnico.
class Tecnico {
  final String uid;
  final String nombre;
  final String telefono;
  final String? correo;
  final EstadoAprobacion estadoAprobacion;
  final String? selfieUrl;
  final String? ineUrl;
  final String? fcmToken;
  final DateTime fechaRegistro;
  final String? motivoRechazo;

  /// Placas del vehículo con el que acude a los servicios.
  final String? placas;

  /// App de navegación preferida al acudir: 'maps' o 'waze'.
  final String? navPreferida;

  const Tecnico({
    required this.uid,
    required this.nombre,
    required this.telefono,
    this.correo,
    required this.estadoAprobacion,
    this.selfieUrl,
    this.ineUrl,
    this.fcmToken,
    required this.fechaRegistro,
    this.motivoRechazo,
    this.placas,
    this.navPreferida,
  });

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'telefono': telefono,
        'correo': correo,
        'estadoAprobacion': estadoAprobacion.name,
        'selfieUrl': selfieUrl,
        'ineUrl': ineUrl,
        'fcmToken': fcmToken,
        'fechaRegistro': fechaRegistro.toIso8601String(),
        'motivoRechazo': motivoRechazo,
        'placas': placas,
        'navPreferida': navPreferida,
      };

  factory Tecnico.fromMap(String uid, Map<String, dynamic> map) => Tecnico(
        uid: uid,
        nombre: map['nombre'] as String,
        telefono: map['telefono'] as String,
        correo: map['correo'] as String?,
        estadoAprobacion: EstadoAprobacionX.desdeTexto(map['estadoAprobacion'] as String),
        selfieUrl: map['selfieUrl'] as String?,
        ineUrl: map['ineUrl'] as String?,
        fcmToken: map['fcmToken'] as String?,
        fechaRegistro: DateTime.parse(map['fechaRegistro'] as String),
        motivoRechazo: map['motivoRechazo'] as String?,
        placas: map['placas'] as String?,
        navPreferida: map['navPreferida'] as String?,
      );
}
