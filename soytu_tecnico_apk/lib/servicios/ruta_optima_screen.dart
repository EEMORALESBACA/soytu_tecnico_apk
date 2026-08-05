import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:soytu_core/soytu_core.dart';

import '../providers/providers.dart';
import 'detalle_servicio_screen.dart';

const _indigo = Color(0xFF1A237E);
const _gold = Color(0xFFF2B824);

/// Ordena los servicios activos del técnico por distancia a su ubicación
/// actual — del MÁS LEJANO al MÁS CERCANO (orden pedido explícitamente).
class RutaOptimaScreen extends ConsumerStatefulWidget {
  const RutaOptimaScreen({super.key});

  @override
  ConsumerState<RutaOptimaScreen> createState() => _RutaOptimaScreenState();
}

class _RutaOptimaScreenState extends ConsumerState<RutaOptimaScreen> {
  Position? _miPosicion;
  String? _error;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _obtenerUbicacion();
  }

  Future<void> _obtenerUbicacion() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }
      if (permiso == LocationPermission.denied || permiso == LocationPermission.deniedForever) {
        setState(() {
          _error = 'Activa el permiso de ubicación para calcular tu ruta.';
          _cargando = false;
        });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;
      setState(() {
        _miPosicion = pos;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo obtener tu ubicación: $e';
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final servicios = ref.watch(serviciosAsignadosProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _indigo,
        foregroundColor: Colors.white,
        title: const Text('Ruta del día'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _obtenerUbicacion,
            tooltip: 'Actualizar mi ubicación',
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_off_outlined, size: 48, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _obtenerUbicacion, child: const Text('Reintentar')),
                      ],
                    ),
                  ),
                )
              : servicios.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                  data: (lista) {
                    final conUbicacion = lista
                        .where((s) => s.clienteLat != null && s.clienteLng != null)
                        .toList();

                    if (conUbicacion.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Ninguno de tus servicios activos tiene ubicación registrada todavía.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF4A4F63)),
                          ),
                        ),
                      );
                    }

                    // Distancia de cada servicio a la posición actual del técnico.
                    final conDistancia = conUbicacion.map((s) {
                      final d = distanciaMetros(
                        _miPosicion!.latitude,
                        _miPosicion!.longitude,
                        s.clienteLat!,
                        s.clienteLng!,
                      );
                      return (servicio: s, distancia: d);
                    }).toList()
                      // Del más lejano al más cercano, como se pidió.
                      ..sort((a, b) => b.distancia.compareTo(a.distancia));

                    return ListView.builder(
                      padding: const EdgeInsets.all(14),
                      itemCount: conDistancia.length,
                      itemBuilder: (context, i) {
                        final item = conDistancia[i];
                        final km = (item.distancia / 1000).toStringAsFixed(1);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _indigo,
                              foregroundColor: Colors.white,
                              child: Text('${i + 1}'),
                            ),
                            title: Text('${item.servicio.folio} · ${item.servicio.clienteNombre}'),
                            subtitle: Text(
                                '${item.servicio.equipoTipo} ${item.servicio.marca}\n${item.servicio.clienteDireccion}'),
                            isThreeLine: true,
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _gold.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text('$km km',
                                  style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF8A6A00))),
                            ),
                            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => DetalleServicioScreen(servicioId: item.servicio.id))),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
