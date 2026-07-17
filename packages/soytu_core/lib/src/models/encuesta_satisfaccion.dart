/// Categoría NPS derivada de la pregunta "probabilidad de recomendar" (0-10).
enum CategoriaNps { promotor, pasivo, detractor }

/// Respuesta de la encuesta de satisfacción (máx. 5 preguntas) que el cliente
/// llena desde la página web de encuesta tras un servicio completado.
class EncuestaSatisfaccion {
  final String servicioId;
  final int calidadServicio; // 1-5
  final int tratoTecnico; // 1-5
  final bool cobroCorrecto;
  final double? montoPercibido;
  final int probabilidadRecomendar; // 0-10 (pregunta NPS)
  final String? comentario;
  final DateTime fecha;

  const EncuestaSatisfaccion({
    required this.servicioId,
    required this.calidadServicio,
    required this.tratoTecnico,
    required this.cobroCorrecto,
    this.montoPercibido,
    required this.probabilidadRecomendar,
    this.comentario,
    required this.fecha,
  });

  CategoriaNps get categoriaNps {
    if (probabilidadRecomendar >= 9) return CategoriaNps.promotor;
    if (probabilidadRecomendar >= 7) return CategoriaNps.pasivo;
    return CategoriaNps.detractor;
  }

  Map<String, dynamic> toMap() => {
        'servicioId': servicioId,
        'calidadServicio': calidadServicio,
        'tratoTecnico': tratoTecnico,
        'cobroCorrecto': cobroCorrecto,
        'montoPercibido': montoPercibido,
        'probabilidadRecomendar': probabilidadRecomendar,
        'comentario': comentario,
        'fecha': fecha.toIso8601String(),
      };

  factory EncuestaSatisfaccion.fromMap(Map<String, dynamic> map) => EncuestaSatisfaccion(
        servicioId: map['servicioId'] as String,
        calidadServicio: map['calidadServicio'] as int,
        tratoTecnico: map['tratoTecnico'] as int,
        cobroCorrecto: map['cobroCorrecto'] as bool,
        montoPercibido: (map['montoPercibido'] as num?)?.toDouble(),
        probabilidadRecomendar: map['probabilidadRecomendar'] as int,
        comentario: map['comentario'] as String?,
        fecha: DateTime.parse(map['fecha'] as String),
      );
}

/// Calcula el puntaje NPS clásico (-100 a 100) de un conjunto de encuestas.
double calcularNps(List<EncuestaSatisfaccion> encuestas) {
  if (encuestas.isEmpty) return 0;
  final promotores = encuestas.where((e) => e.categoriaNps == CategoriaNps.promotor).length;
  final detractores = encuestas.where((e) => e.categoriaNps == CategoriaNps.detractor).length;
  return ((promotores - detractores) / encuestas.length) * 100;
}
