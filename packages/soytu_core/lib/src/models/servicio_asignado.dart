import 'orden_servicio.dart';

/// Ciclo de vida de una asignación de servicio, previo (y durante) el cierre.
/// El resultado final del servicio (completado/pendiente/cancelado) se
/// guarda en [EstadoServicio], no aquí.
enum EstadoAsignacion {
  pendienteAsignacion,
  asignado,
  aceptado,
  enCamino,
  enSitio,
  cerrado,
}

extension EstadoAsignacionX on EstadoAsignacion {
  String get etiqueta {
    switch (this) {
      case EstadoAsignacion.pendienteAsignacion:
        return 'Pendiente de asignación';
      case EstadoAsignacion.asignado:
        return 'Asignado';
      case EstadoAsignacion.aceptado:
        return 'Aceptado';
      case EstadoAsignacion.enCamino:
        return 'En camino';
      case EstadoAsignacion.enSitio:
        return 'En sitio';
      case EstadoAsignacion.cerrado:
        return 'Cerrado';
    }
  }

  static EstadoAsignacion desdeTexto(String texto) => EstadoAsignacion.values
      .firstWhere((e) => e.name == texto, orElse: () => EstadoAsignacion.pendienteAsignacion);
}

/// Documento de Firestore (colección `servicios`) que representa el ciclo de
/// vida de una asignación: creación, asignación a un técnico, aceptación,
/// traslado, llegada y cierre. Los datos ricos de cierre (fotos, voltajes,
/// firma) viven en memoria como [OrdenServicio] hasta generar el PDF; aquí
/// solo se persiste lo necesario para listas, notificaciones y el rastreo.
class ServicioAsignado {
  final String id;
  final String folio;
  final EstadoAsignacion estadoAsignacion;
  final EstadoServicio? estadoFinal;

  final String? technicianId;

  // Cliente y equipo (suficiente para mostrar resumen antes de llegar a sitio)
  final String clienteNombre;
  final String clienteDireccion;
  final String? clienteTelefono;
  final String? clienteCorreo;
  final double? clienteLat;
  final double? clienteLng;

  final String equipoTipo;
  final String marca;
  final String modelo;
  final String numeroSerie;
  final String fallaReportada;

  /// 'garantia' o 'cargo' (con costo al cliente).
  final String tipoServicio;

  final DateTime fechaCreacion;
  final DateTime? fechaAsignado;
  final DateTime? fechaAceptado;
  final DateTime? fechaEnCamino;
  final DateTime? fechaEnSitio;
  final DateTime? fechaCierre;

  final String? pdfUrl;
  final String? videoFallaUrl;

  const ServicioAsignado({
    required this.id,
    required this.folio,
    required this.estadoAsignacion,
    this.estadoFinal,
    this.technicianId,
    required this.clienteNombre,
    required this.clienteDireccion,
    this.clienteTelefono,
    this.clienteCorreo,
    this.clienteLat,
    this.clienteLng,
    required this.equipoTipo,
    required this.marca,
    required this.modelo,
    required this.numeroSerie,
    required this.fallaReportada,
    this.tipoServicio = 'garantia',
    required this.fechaCreacion,
    this.fechaAsignado,
    this.fechaAceptado,
    this.fechaEnCamino,
    this.fechaEnSitio,
    this.fechaCierre,
    this.pdfUrl,
    this.videoFallaUrl,
  });

  Map<String, dynamic> toMap() => {
        'folio': folio,
        'estadoAsignacion': estadoAsignacion.name,
        'estadoFinal': estadoFinal?.name,
        'technicianId': technicianId,
        'clienteNombre': clienteNombre,
        'clienteDireccion': clienteDireccion,
        'clienteTelefono': clienteTelefono,
        'clienteCorreo': clienteCorreo,
        'clienteLat': clienteLat,
        'clienteLng': clienteLng,
        'equipoTipo': equipoTipo,
        'marca': marca,
        'modelo': modelo,
        'numeroSerie': numeroSerie,
        'fallaReportada': fallaReportada,
        'tipoServicio': tipoServicio,
        'fechaCreacion': fechaCreacion.toIso8601String(),
        'fechaAsignado': fechaAsignado?.toIso8601String(),
        'fechaAceptado': fechaAceptado?.toIso8601String(),
        'fechaEnCamino': fechaEnCamino?.toIso8601String(),
        'fechaEnSitio': fechaEnSitio?.toIso8601String(),
        'fechaCierre': fechaCierre?.toIso8601String(),
        'pdfUrl': pdfUrl,
        'videoFallaUrl': videoFallaUrl,
      };

  factory ServicioAsignado.fromMap(String id, Map<String, dynamic> map) {
    DateTime? fecha(String clave) =>
        map[clave] == null ? null : DateTime.parse(map[clave] as String);
    return ServicioAsignado(
      id: id,
      folio: map['folio'] as String,
      estadoAsignacion: EstadoAsignacionX.desdeTexto(map['estadoAsignacion'] as String),
      estadoFinal: map['estadoFinal'] == null
          ? null
          : EstadoServicio.values.firstWhere((e) => e.name == map['estadoFinal']),
      technicianId: map['technicianId'] as String?,
      clienteNombre: map['clienteNombre'] as String,
      clienteDireccion: map['clienteDireccion'] as String,
      clienteTelefono: map['clienteTelefono'] as String?,
      clienteCorreo: map['clienteCorreo'] as String?,
      clienteLat: (map['clienteLat'] as num?)?.toDouble(),
      clienteLng: (map['clienteLng'] as num?)?.toDouble(),
      equipoTipo: map['equipoTipo'] as String,
      marca: map['marca'] as String,
      modelo: map['modelo'] as String,
      numeroSerie: map['numeroSerie'] as String,
      fallaReportada: map['fallaReportada'] as String,
      tipoServicio: map['tipoServicio'] as String? ?? 'garantia',
      fechaCreacion: DateTime.parse(map['fechaCreacion'] as String),
      fechaAsignado: fecha('fechaAsignado'),
      fechaAceptado: fecha('fechaAceptado'),
      fechaEnCamino: fecha('fechaEnCamino'),
      fechaEnSitio: fecha('fechaEnSitio'),
      fechaCierre: fecha('fechaCierre'),
      pdfUrl: map['pdfUrl'] as String?,
      videoFallaUrl: map['videoFallaUrl'] as String?,
    );
  }

  ServicioAsignado copyWith({
    EstadoAsignacion? estadoAsignacion,
    EstadoServicio? estadoFinal,
    String? technicianId,
    DateTime? fechaAsignado,
    DateTime? fechaAceptado,
    DateTime? fechaEnCamino,
    DateTime? fechaEnSitio,
    DateTime? fechaCierre,
    String? pdfUrl,
    String? videoFallaUrl,
  }) {
    return ServicioAsignado(
      id: id,
      folio: folio,
      estadoAsignacion: estadoAsignacion ?? this.estadoAsignacion,
      estadoFinal: estadoFinal ?? this.estadoFinal,
      technicianId: technicianId ?? this.technicianId,
      clienteNombre: clienteNombre,
      clienteDireccion: clienteDireccion,
      clienteTelefono: clienteTelefono,
      clienteCorreo: clienteCorreo,
      clienteLat: clienteLat,
      clienteLng: clienteLng,
      equipoTipo: equipoTipo,
      marca: marca,
      modelo: modelo,
      numeroSerie: numeroSerie,
      fallaReportada: fallaReportada,
      tipoServicio: tipoServicio,
      fechaCreacion: fechaCreacion,
      fechaAsignado: fechaAsignado ?? this.fechaAsignado,
      fechaAceptado: fechaAceptado ?? this.fechaAceptado,
      fechaEnCamino: fechaEnCamino ?? this.fechaEnCamino,
      fechaEnSitio: fechaEnSitio ?? this.fechaEnSitio,
      fechaCierre: fechaCierre ?? this.fechaCierre,
      pdfUrl: pdfUrl ?? this.pdfUrl,
      videoFallaUrl: videoFallaUrl ?? this.videoFallaUrl,
    );
  }
}
