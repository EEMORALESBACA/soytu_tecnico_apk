import 'dart:typed_data';

/// Estados posibles de una orden de servicio SOYTU.
enum EstadoServicio { completado, pendiente, cancelado }

extension EstadoServicioX on EstadoServicio {
  String get etiqueta {
    switch (this) {
      case EstadoServicio.completado:
        return 'COMPLETADO';
      case EstadoServicio.pendiente:
        return 'FALTANTE DE REFACCIÓN';
      case EstadoServicio.cancelado:
        return 'CANCELADO / RECHAZADO';
    }
  }
}

/// Tipo de falla detectada por el técnico.
enum TipoFalla { tarjetaMain, software, panel }

extension TipoFallaX on TipoFalla {
  String get etiqueta {
    switch (this) {
      case TipoFalla.tarjetaMain:
        return 'Tarjeta Main';
      case TipoFalla.software:
        return 'Software';
      case TipoFalla.panel:
        return 'Panel';
    }
  }
}

/// Lectura de voltaje capturada por el técnico (con foto de evidencia).
class LecturaVoltaje {
  final String punto; // Ej. "Línea del hogar (toma corriente)", "VCC Main 12V"
  final String valor; // Ej. "127.4 V"
  final Uint8List? foto;

  const LecturaVoltaje({required this.punto, required this.valor, this.foto});
}

/// Orden de servicio completa. Es el objeto que alimenta el PDF.
class OrdenServicio {
  // Identificación
  final String folio; // Ej. SOYTU-2026-000123
  final DateTime fecha;
  final EstadoServicio estado;

  // Técnico asignado
  final String tecnicoNombre;
  final String tecnicoId;
  final String? tecnicoTelefono;

  // Cliente
  final String clienteNombre;
  final String clienteDireccion;
  final String? clienteTelefono;
  final String? clienteCorreo;

  // Equipo
  final String equipoTipo; // Ej. "Televisión"
  final String marca;
  final String modelo;
  final String numeroSerie;

  // Diagnóstico
  final String fallaReportada; // La que viene en la orden
  final String descripcionTecnico; // Falla + condiciones en que encontró el equipo
  final List<TipoFalla> tiposFalla;
  final List<LecturaVoltaje> voltajes;

  // Evidencia fotográfica (bytes JPG/PNG tomados con la cámara)
  final Uint8List? fotoEquipo;
  final Uint8List? fotoPlaca;
  final Uint8List? fotoFalla;
  final Uint8List? fotoEvidenciaCancelacion; // Obligatoria si cliente ausente

  // Cierre
  final double? montoCobrado; // Solo si el servicio es de cargo
  final List<String> refaccionesFaltantes; // Solo estado pendiente
  final List<String> refaccionesUsadas; // Solo estado completado
  final String? motivoPendiente; // "Refacción" o "Software"
  final String? motivoCancelacion; // Solo estado cancelado
  final Uint8List? firmaCliente; // PNG de la firma

  const OrdenServicio({
    required this.folio,
    required this.fecha,
    required this.estado,
    required this.tecnicoNombre,
    required this.tecnicoId,
    this.tecnicoTelefono,
    required this.clienteNombre,
    required this.clienteDireccion,
    this.clienteTelefono,
    this.clienteCorreo,
    required this.equipoTipo,
    required this.marca,
    required this.modelo,
    required this.numeroSerie,
    required this.fallaReportada,
    required this.descripcionTecnico,
    this.tiposFalla = const [],
    this.voltajes = const [],
    this.fotoEquipo,
    this.fotoPlaca,
    this.fotoFalla,
    this.fotoEvidenciaCancelacion,
    this.montoCobrado,
    this.refaccionesFaltantes = const [],
    this.refaccionesUsadas = const [],
    this.motivoPendiente,
    this.motivoCancelacion,
    this.firmaCliente,
  });
}
