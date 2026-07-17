import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soytu_core/soytu_core.dart';

import '../providers/providers.dart';

const _indigo = Color(0xFF1A237E);

/// Se muestra mientras `estadoAprobacion != aprobado`. En cuanto el admin
/// aprueba desde su panel, el stream de `tecnicoActualProvider` cambia y el
/// widget raíz de la app navega solo a la lista de servicios.
class EsperaAprobacionScreen extends ConsumerWidget {
  const EsperaAprobacionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tecnico = ref.watch(tecnicoActualProvider).value;
    final rechazado = tecnico?.estadoAprobacion == EstadoAprobacion.rechazado;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _indigo,
        foregroundColor: Colors.white,
        title: const Text('SOYTU Técnico'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authServiceProvider).cerrarSesion(),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(rechazado ? Icons.cancel_outlined : Icons.hourglass_top_rounded,
                  size: 64, color: rechazado ? Colors.red : Colors.amber[700]),
              const SizedBox(height: 16),
              Text(
                rechazado ? 'Tu alta fue rechazada' : 'Tu alta está en revisión',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                rechazado
                    ? (tecnico?.motivoRechazo ?? 'Contacta a SOYTU para más información.')
                    : 'Un administrador de SOYTU está comparando tu selfie con tu INE. '
                        'Te notificaremos en cuanto tu cuenta esté aprobada.',
                style: const TextStyle(color: Color(0xFF4A4F63)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
