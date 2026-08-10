import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soytu_core/soytu_core.dart';

import '../providers/providers.dart';
import 'banco_examen.dart';

const _indigo = Color(0xFF1A237E);
const _gold = Color(0xFFF2B824);
const _rojo = Color(0xFFC62828);
const _verde = Color(0xFF2E7D32);

class ExamenScreen extends ConsumerStatefulWidget {
  const ExamenScreen({super.key, required this.tecnico, required this.linea});

  final Tecnico tecnico;
  final LineaNegocio linea;

  @override
  ConsumerState<ExamenScreen> createState() => _ExamenScreenState();
}

class _ExamenScreenState extends ConsumerState<ExamenScreen> {
  BancoExamen? _banco;
  int _indice = 0;
  final Map<int, int> _respuestas = {}; // preguntaId -> índice elegido
  Timer? _timer;
  int _segundosRestantes = 0;
  int _segundosTotales = 0;
  bool _enviando = false;
  bool _yaEnviado = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final banco = await cargarExamen(widget.linea.id);
    if (!mounted) return;
    setState(() {
      _banco = banco;
      _segundosTotales = banco.tiempoMinutos * 60;
      _segundosRestantes = _segundosTotales;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_segundosRestantes <= 1) {
        _timer?.cancel();
        setState(() => _segundosRestantes = 0);
        _entregar(porTiempo: true);
      } else {
        setState(() => _segundosRestantes--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _tiempoFormato {
    final m = _segundosRestantes ~/ 60;
    final s = _segundosRestantes % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<bool> _confirmarSalida() async {
    final salir = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('¿Salir del examen?'),
        content: const Text('Si sales ahora perderás tu progreso y el cronómetro seguirá corriendo hasta que vuelvas a entrar.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Seguir en el examen')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Salir')),
        ],
      ),
    );
    return salir ?? false;
  }

  Future<void> _entregar({bool porTiempo = false}) async {
    if (_yaEnviado || _banco == null) return;
    if (!porTiempo) {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿Entregar examen?'),
          content: Text(
            'Contestaste ${_respuestas.length} de ${_banco!.preguntas.length} preguntas. '
            'Una vez entregado no podrás modificar tus respuestas.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Seguir contestando')),
            TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Entregar ahora')),
          ],
        ),
      );
      if (confirmar != true) return;
    }

    setState(() {
      _enviando = true;
      _yaEnviado = true;
    });
    _timer?.cancel();

    int correctas = 0;
    final respuestasStr = <String, int>{};
    for (final p in _banco!.preguntas) {
      final elegida = _respuestas[p.id];
      respuestasStr[p.id.toString()] = elegida ?? -1;
      if (elegida == p.respuestaCorrecta) correctas++;
    }
    final total = _banco!.preguntas.length;
    final calificacion = ((correctas / total) * 100).round();
    final tiempoUsado = _segundosTotales - _segundosRestantes;

    final resultado = ResultadoExamen(
      calificacion: calificacion,
      correctas: correctas,
      total: total,
      respuestas: respuestasStr,
      fecha: DateTime.now(),
      tiempoUsadoSeg: tiempoUsado,
    );

    try {
      await ref.read(tecnicoRepositoryProvider).guardarResultadoExamen(widget.tecnico.uid, widget.linea.id, resultado);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(porTiempo ? '⏱️ Tiempo agotado' : '✅ Examen entregado'),
          content: Text(
            porTiempo
                ? 'Se acabó el tiempo y tu examen se envió automáticamente con lo que alcanzaste a contestar.\n\nRespuestas correctas: $correctas de $total'
                : 'Tu examen fue enviado para revisión del administrador.\n\nRespuestas correctas: $correctas de $total',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop(); // vuelve a la lista de exámenes pendientes
              },
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _yaEnviado = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al enviar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_banco == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final pregunta = _banco!.preguntas[_indice];
    final urgente = _segundosRestantes <= 300; // últimos 5 min en rojo

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmarSalida() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F5FB),
        appBar: AppBar(
          backgroundColor: _indigo,
          foregroundColor: Colors.white,
          title: Text(_banco!.titulo, style: const TextStyle(fontSize: 15)),
          actions: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: urgente ? _rojo : Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.timer_outlined, size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Text(_tiempoFormato, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ]),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              LinearProgressIndicator(
                value: (_indice + 1) / _banco!.preguntas.length,
                backgroundColor: const Color(0xFFE3E5F0),
                color: _gold,
                minHeight: 5,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pregunta ${_indice + 1} de ${_banco!.preguntas.length} · ${pregunta.tema}',
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFF6B7080), fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(pregunta.pregunta, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.3)),
                      const SizedBox(height: 18),
                      ...List.generate(pregunta.opciones.length, (i) {
                        final elegida = _respuestas[pregunta.id] == i;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => setState(() => _respuestas[pregunta.id] = i),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: elegida ? _indigo.withValues(alpha: 0.08) : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: elegida ? _indigo : const Color(0xFFE3E5F0), width: elegida ? 1.5 : 1),
                              ),
                              child: Row(
                                children: [
                                  Icon(elegida ? Icons.radio_button_checked : Icons.radio_button_off,
                                      color: elegida ? _indigo : const Color(0xFFB0B4C4), size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(child: Text(pregunta.opciones[i], style: const TextStyle(fontSize: 13.5))),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, -2))],
                ),
                child: Row(
                  children: [
                    if (_indice > 0)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setState(() => _indice--),
                          child: const Text('Anterior'),
                        ),
                      ),
                    if (_indice > 0) const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: _indice < _banco!.preguntas.length - 1
                          ? ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: _indigo, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                              onPressed: () => setState(() => _indice++),
                              child: const Text('Siguiente'),
                            )
                          : ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: _verde, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                              onPressed: _enviando ? null : () => _entregar(),
                              child: _enviando
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Text('Entregar examen'),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
