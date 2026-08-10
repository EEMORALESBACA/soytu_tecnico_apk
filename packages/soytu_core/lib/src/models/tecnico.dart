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

/// Las 3 líneas de negocio en las que un técnico puede certificarse.
/// El id coincide con el nombre del examen (assets/examenes/{id}.json).
enum LineaNegocio { lineaBlanca, electronicaTv, refrigeracionAc }

extension LineaNegocioX on LineaNegocio {
  String get id => switch (this) {
        LineaNegocio.lineaBlanca => 'linea_blanca',
        LineaNegocio.electronicaTv => 'electronica_tv',
        LineaNegocio.refrigeracionAc => 'refrigeracion_ac',
      };

  String get etiqueta => switch (this) {
        LineaNegocio.lineaBlanca => 'Línea Blanca (lavadoras, estufas, microondas...)',
        LineaNegocio.electronicaTv => 'Electrónica y reparación de TV',
        LineaNegocio.refrigeracionAc => 'Refrigeración doméstica y aires acondicionados',
      };

  static LineaNegocio desdeId(String id) =>
      LineaNegocio.values.firstWhere((l) => l.id == id, orElse: () => LineaNegocio.lineaBlanca);
}

/// Resultado de un examen de certificación ya presentado por el técnico.
class ResultadoExamen {
  final int calificacion; // 0-100
  final int correctas;
  final int total;
  final Map<String, int> respuestas; // "1" -> índice de opción elegida
  final DateTime fecha;
  final int tiempoUsadoSeg;

  const ResultadoExamen({
    required this.calificacion,
    required this.correctas,
    required this.total,
    required this.respuestas,
    required this.fecha,
    required this.tiempoUsadoSeg,
  });

  bool get aprobado => calificacion >= 70;

  Map<String, dynamic> toMap() => {
        'calificacion': calificacion,
        'correctas': correctas,
        'total': total,
        'respuestas': respuestas,
        'fecha': fecha.toIso8601String(),
        'tiempoUsadoSeg': tiempoUsadoSeg,
      };

  factory ResultadoExamen.fromMap(Map<String, dynamic> map) => ResultadoExamen(
        calificacion: (map['calificacion'] as num).toInt(),
        correctas: (map['correctas'] as num).toInt(),
        total: (map['total'] as num).toInt(),
        respuestas: Map<String, int>.from((map['respuestas'] as Map).map(
          (k, v) => MapEntry(k.toString(), (v as num).toInt()),
        )),
        fecha: DateTime.parse(map['fecha'] as String),
        tiempoUsadoSeg: (map['tiempoUsadoSeg'] as num).toInt(),
      );
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

  /// Líneas de negocio que el técnico marcó que repara (ids de LineaNegocio).
  final List<String> lineasNegocio;

  /// Resultados de examen ya presentados, indexados por id de línea.
  final Map<String, ResultadoExamen> examenes;

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
    this.lineasNegocio = const [],
    this.examenes = const {},
  });

  /// true si ya eligió sus líneas Y ya presentó el examen de cada una.
  bool get examenesCompletos =>
      lineasNegocio.isNotEmpty && lineasNegocio.every((l) => examenes.containsKey(l));

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
        'lineasNegocio': lineasNegocio,
        'examenes': examenes.map((k, v) => MapEntry(k, v.toMap())),
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
        lineasNegocio: map['lineasNegocio'] != null
            ? List<String>.from(map['lineasNegocio'] as List)
            : const [],
        examenes: map['examenes'] != null
            ? (map['examenes'] as Map).map(
                (k, v) => MapEntry(k.toString(), ResultadoExamen.fromMap(Map<String, dynamic>.from(v as Map))))
            : const {},
      );
}
