import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soytu_core/soytu_core.dart';

import '../providers/providers.dart';
import '../services/ubicacion_global.dart';
import 'detalle_servicio_screen.dart';
import 'ruta_optima_screen.dart';

const _indigo = Color(0xFF1A237E);
const _verde = Color(0xFF2E7D32);
const _amarillo = Color(0xFFF9A825);

Color _colorAsignacion(EstadoAsignacion e) => switch (e) {
      EstadoAsignacion.asignado => _amarillo,
      EstadoAsignacion.aceptado || EstadoAsignacion.enCamino || EstadoAsignacion.enSitio => _verde,
      _ => Colors.grey,
    };

/// Lista en vivo (stream de Firestore) de los servicios asignados al técnico
/// logueado, en cualquier estado activo.
class ListaServiciosScreen extends ConsumerWidget {
  const ListaServiciosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicios = ref.watch(serviciosAsignadosProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _indigo,
        foregroundColor: Colors.white,
        title: const Text('Mis servicios'),
        actions: [
          IconButton(
            icon: const Icon(Icons.alt_route),
            tooltip: 'Ruta del día',
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RutaOptimaScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await UbicacionGlobal.detener();
              await ref.read(authServiceProvider).cerrarSesion();
            },
          ),
        ],
      ),
      body: servicios.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (lista) {
          if (lista.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No tienes servicios asignados por el momento.',
                    textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF4A4F63))),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: lista.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final s = lista[i];
              return Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _colorAsignacion(s.estadoAsignacion),
                    child: const Icon(Icons.build, color: Colors.white, size: 18),
                  ),
                  title: Text('${s.equipoTipo} ${s.marca} · ${s.folio}'),
                  subtitle: Text(
                      '${s.clienteNombre}\n${s.tipoServicio == 'cargo' ? '💰 CARGO' : '🛡️ GARANTÍA'} · ${s.estadoAsignacion.etiqueta}'),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => DetalleServicioScreen(servicioId: s.id))),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
