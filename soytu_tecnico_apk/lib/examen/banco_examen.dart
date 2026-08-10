import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class PreguntaExamen {
  final int id;
  final String tema;
  final String pregunta;
  final List<String> opciones;
  final int respuestaCorrecta;

  const PreguntaExamen({
    required this.id,
    required this.tema,
    required this.pregunta,
    required this.opciones,
    required this.respuestaCorrecta,
  });

  factory PreguntaExamen.fromMap(Map<String, dynamic> m) => PreguntaExamen(
        id: (m['id'] as num).toInt(),
        tema: m['tema'] as String? ?? '',
        pregunta: m['pregunta'] as String,
        opciones: List<String>.from(m['opciones'] as List),
        respuestaCorrecta: (m['respuestaCorrecta'] as num).toInt(),
      );
}

class BancoExamen {
  final String examen;
  final String titulo;
  final int tiempoMinutos;
  final List<PreguntaExamen> preguntas;

  const BancoExamen({
    required this.examen,
    required this.titulo,
    required this.tiempoMinutos,
    required this.preguntas,
  });

  factory BancoExamen.fromMap(Map<String, dynamic> m) => BancoExamen(
        examen: m['examen'] as String,
        titulo: m['titulo'] as String,
        tiempoMinutos: (m['tiempoMinutos'] as num).toInt(),
        preguntas: (m['preguntas'] as List)
            .map((p) => PreguntaExamen.fromMap(Map<String, dynamic>.from(p as Map)))
            .toList(),
      );
}

/// Carga el banco de preguntas de una línea de negocio desde los assets
/// empaquetados en la app (assets/examenes/{lineaId}.json).
Future<BancoExamen> cargarExamen(String lineaId) async {
  final texto = await rootBundle.loadString('assets/examenes/$lineaId.json');
  return BancoExamen.fromMap(json.decode(texto) as Map<String, dynamic>);
}
