import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soytu_core/soytu_core.dart';

import '../providers/providers.dart';
import 'detalle_servicio_screen.dart';

const _indigo = Color(0xFF1A237E);
const _verde = Color(0xFF2E7D32);
const _ambar = Color(0xFFF9A825);
const _rojo = Color(0xFFC62828);
const _azul = Color(0xFF1565C0);

/// Historial completo de servicios del técnico logueado.
final historialServiciosProvider = StreamProvider((ref) {
  final tecnico = ref.watch(tecnicoActualProvider).value;
  if (tecnico == null) return const Stream<List<ServicioAsignado>>.empty();
  return ref.watch(servicioRepositoryProvider).observarHistorial(tecnico.uid);
});

/// 📊 Productividad: KPIs del técnico + estatus de cada servicio asignado.
class ProductividadScreen extends ConsumerWidget {
  const ProductividadScreen({super.key});

  (String, Color) _estado(ServicioAsignado s) {
    if (s.estadoAsignacion == EstadoAsignacion.cerrado) {
      return switch (s.estadoFinal) {
        EstadoServicio.completado => ('COMPLETADO', _verde),
        EstadoServicio.pendiente => ('FALTANTE REFACCIÓN', _ambar),
        EstadoServicio.cancelado => ('CANCELADO', _rojo),
        _ => ('CERRADO', Colors.grey),
      };
    }
    return switch (s.estadoAsignacion) {
      EstadoAsignacion.asignado => ('ASIGNADO', _indigo),
      EstadoAsignacion.aceptado => ('ACEPTADO', _indigo),
      EstadoAsignacion.enCamino => ('EN CAMINO', _azul),
      EstadoAsignacion.enSitio => ('EN SITIO', _azul),
      _ => ('PENDIENTE', Colors.grey),
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historial = ref.watch(historialServiciosProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _indigo,
        foregroundColor: Colors.white,
        title: const Text('Mi productividad'),
      ),
      body: historial.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (lista) {
          final total = lista.length;
          final completados = lista
              .where((s) => s.estadoFinal == EstadoServicio.completado)
              .length;
          final refaccion = lista
              .where((s) => s.estadoFinal == EstadoServicio.pendiente)
              .length;
          final cancelados = lista
              .where((s) => s.estadoFinal == EstadoServicio.cancelado)
              .length;
          final activos = lista
              .where((s) => s.estadoAsignacion != EstadoAsignacion.cerrado)
              .length;
          final efectividad =
              total == 0 ? 0 : ((completados / total) * 100).round();
          final ordenados = [...lista]..sort((a, b) =>
              b.fechaCreacion.compareTo(a.fechaCreacion));

          return ListView(
            padding: const EdgeInsets.all(14),
            children: [
              // ── KPIs ──
              Row(children: [
                _kpi('$total', 'TOTALES', _indigo),
                const SizedBox(width: 10),
                _kpi('$completados', 'COMPLETADOS', _verde),
                const SizedBox(width: 10),
                _kpi('$efectividad%', 'EFECTIVIDAD', _azul),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                _kpi('$activos', 'ACTIVOS', _indigo),
                const SizedBox(width: 10),
                _kpi('$refaccion', 'REFACCIÓN', _ambar),
                const SizedBox(width: 10),
                _kpi('$cancelados', 'CANCELADOS', _rojo),
              ]),
              const SizedBox(height: 18),
              const Text('ESTATUS DE MIS SERVICIOS',
                  style: TextStyle(
                      color: _indigo,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      fontSize: 12)),
              const SizedBox(height: 8),
              if (ordenados.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Aún no tienes servicios en tu historial.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF4A4F63))),
                ),
              ...ordenados.map((s) {
                final (etiqueta, color) = _estado(s);
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text('${s.folio} · ${s.clienteNombre}'),
                    subtitle: Text(
                        '${s.equipoTipo} ${s.marca} · ${s.tipoServicio == 'cargo' ? '💰 CARGO' : '🛡️ GARANTÍA'}'),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color),
                      ),
                      child: Text(etiqueta,
                          style: TextStyle(
                              color: color,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800)),
                    ),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            DetalleServicioScreen(servicioId: s.id))),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Widget _kpi(String valor, String etiqueta, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border(top: BorderSide(color: color, width: 4)),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2))
            ],
          ),
          child: Column(children: [
            Text(valor,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(etiqueta,
                style: const TextStyle(
                    fontSize: 9.5,
                    color: Color(0xFF6B7080),
                    fontWeight: FontWeight.w700,
                    letterSpacing: .5)),
          ]),
        ),
      );
}
