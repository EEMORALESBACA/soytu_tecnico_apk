import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soytu_core/soytu_core.dart';

import '../providers/providers.dart';
import 'examen_screen.dart';

const _indigo = Color(0xFF1A237E);
const _verde = Color(0xFF2E7D32);
const _gold = Color(0xFFF2B824);

/// Lista las líneas de negocio que el técnico marcó, con su estatus:
/// pendiente de presentar, o ya enviado (con su calificación). Una vez
/// que todas están enviadas, queda esperando a que el admin las revise
/// junto con su selfie/INE en "Revisión de Altas".
class ExamenesPendientesScreen extends ConsumerWidget {
  const ExamenesPendientesScreen({super.key, required this.tecnico});

  final Tecnico tecnico;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lineas = tecnico.lineasNegocio.map(LineaNegocioX.desdeId).toList();
    final todasEnviadas = tecnico.examenesCompletos;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5FB),
      appBar: AppBar(
        backgroundColor: _indigo,
        foregroundColor: Colors.white,
        title: const Text('Tus exámenes de certificación'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authServiceProvider).cerrarSesion(),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              if (todasEnviadas) _bannerCompleto() else _bannerPendiente(lineas.length),
              const SizedBox(height: 18),
              Expanded(
                child: ListView.separated(
                  itemCount: lineas.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _tarjetaExamen(context, ref, lineas[i]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bannerPendiente(int total) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: _gold.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
        child: const Text(
          'Presenta el examen de cada línea que marcaste. Tiene tiempo límite, así que busca un momento sin distracciones antes de empezar.',
          style: TextStyle(fontSize: 12.5, color: Color(0xFF8A6A00)),
        ),
      );

  Widget _bannerCompleto() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: _verde.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
        child: const Row(
          children: [
            Icon(Icons.check_circle, color: _verde),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Ya enviaste todos tus exámenes. Un administrador va a revisar tus resultados junto con tu identificación — te avisamos en cuanto tu cuenta quede autorizada.',
                style: TextStyle(fontSize: 12.5, color: _verde, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );

  Widget _tarjetaExamen(BuildContext context, WidgetRef ref, LineaNegocio linea) {
    final resultado = tecnico.examenes[linea.id];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3E5F0)),
      ),
      child: Row(
        children: [
          Icon(
            resultado != null ? Icons.check_circle : Icons.pending_outlined,
            color: resultado != null ? _verde : Colors.grey,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(linea.etiqueta, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                const SizedBox(height: 3),
                Text(
                  resultado != null
                      ? 'Enviado · Calificación: ${resultado.calificacion}/100'
                      : 'Pendiente de presentar',
                  style: TextStyle(fontSize: 11.5, color: resultado != null ? _verde : Colors.grey[600]),
                ),
              ],
            ),
          ),
          if (resultado == null)
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _indigo, foregroundColor: Colors.white),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ExamenScreen(tecnico: tecnico, linea: linea)),
              ),
              child: const Text('Comenzar'),
            ),
        ],
      ),
    );
  }
}
