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
/// Filtrable por mes: null = todo el histórico.
class ProductividadScreen extends ConsumerStatefulWidget {
  const ProductividadScreen({super.key});

  @override
  ConsumerState<ProductividadScreen> createState() => _ProductividadScreenState();
}

class _ProductividadScreenState extends ConsumerState<ProductividadScreen> {
  DateTime? _mesSeleccionado; // null = ver todo el histórico

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

  List<DateTime> _mesesDisponibles(List<ServicioAsignado> lista) {
    final vistos = <String>{};
    final meses = <DateTime>[];
    for (final s in lista) {
      final m = DateTime(s.fechaCreacion.year, s.fechaCreacion.month);
      final key = '${m.year}-${m.month}';
      if (vistos.add(key)) meses.add(m);
    }
    meses.sort((a, b) => b.compareTo(a));
    return meses;
  }

  static const _nombresMes = [
    '', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
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
        data: (listaCompleta) {
          final mesesDisponibles = _mesesDisponibles(listaCompleta);
          final lista = _mesSeleccionado == null
              ? listaCompleta
              : listaCompleta
                  .where((s) =>
                      s.fechaCreacion.year == _mesSeleccionado!.year &&
                      s.fechaCreacion.month == _mesSeleccionado!.month)
                  .toList();

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
              // ── Selector de mes ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE3E5F0)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<DateTime?>(
                    isExpanded: true,
                    value: _mesSeleccionado,
                    hint: const Text('🗓️ Ver todo el histórico'),
                    items: [
                      const DropdownMenuItem<DateTime?>(
                        value: null,
                        child: Text('🗓️ Ver todo el histórico'),
                      ),
                      ...mesesDisponibles.map((m) => DropdownMenuItem<DateTime?>(
                            value: m,
                            child: Text('${_nombresMes[m.month]} ${m.year}'),
                          )),
                    ],
                    onChanged: (v) => setState(() => _mesSeleccionado = v),
                  ),
                ),
              ),
              const SizedBox(height: 14),
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
                _kpi('$activos', 'PENDIENTES', _indigo),
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
                  child: Text('Sin servicios en este periodo.',
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
