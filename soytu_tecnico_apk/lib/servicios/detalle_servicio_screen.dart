import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:soytu_core/soytu_core.dart';

import '../providers/providers.dart';
import 'formulario_servicio_screen.dart';

const _indigo = Color(0xFF1A237E);
const _verde = Color(0xFF2E7D32);
const _amarillo = Color(0xFFF9A825);

/// Umbral de llegada: dentro de este radio del domicilio del cliente se
/// habilita "Iniciar servicio".
const double _umbralLlegadaMetros = 100;

class DetalleServicioScreen extends ConsumerStatefulWidget {
  const DetalleServicioScreen({super.key, required this.servicioId});

  final String servicioId;

  @override
  ConsumerState<DetalleServicioScreen> createState() => _DetalleServicioScreenState();
}

class _DetalleServicioScreenState extends ConsumerState<DetalleServicioScreen> {
  StreamSubscription<Position>? _posicionSub;
  double? _distanciaMetros;
  bool _procesando = false;

  @override
  void dispose() {
    _posicionSub?.cancel();
    super.dispose();
  }

  Future<bool> _asegurarPermisoUbicacion() async {
    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }
    return permiso == LocationPermission.always || permiso == LocationPermission.whileInUse;
  }

  Future<void> _acudir(ServicioAsignado s) async {
    if (!await _asegurarPermisoUbicacion()) return;
    setState(() => _procesando = true);
    try {
      await ref.read(servicioRepositoryProvider).marcarEnCamino(s.id);

      if (s.clienteLat != null && s.clienteLng != null) {
        final uriNavegacion = Uri.parse('geo:${s.clienteLat},${s.clienteLng}?q=${s.clienteLat},${s.clienteLng}');
        if (await canLaunchUrl(uriNavegacion)) {
          await launchUrl(uriNavegacion, mode: LaunchMode.externalApplication);
        }
      }

      if (s.clienteTelefono != null) {
        final mensaje = Uri.encodeComponent(
            'SOYTU — su técnico ya va en camino a su domicilio para el servicio ${s.folio}. '
            'En breve podrá ver su ubicación en tiempo real aquí: '
            'https://soytu.com.mx/tracking.html?servicio=${s.id}');
        final uriWhatsapp = Uri.parse('https://wa.me/${s.clienteTelefono}?text=$mensaje');
        if (await canLaunchUrl(uriWhatsapp)) {
          await launchUrl(uriWhatsapp, mode: LaunchMode.externalApplication);
        }
      }

      _iniciarRastreo(s.id, s.clienteLat, s.clienteLng);
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  void _iniciarRastreo(String servicioId, double? clienteLat, double? clienteLng) {
    _posicionSub?.cancel();
    _posicionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 18),
    ).listen((posicion) async {
      await ref.read(servicioRepositoryProvider).actualizarTracking(servicioId, posicion.latitude, posicion.longitude);

      if (clienteLat == null || clienteLng == null) return;
      final distancia = distanciaMetros(posicion.latitude, posicion.longitude, clienteLat, clienteLng);
      if (mounted) setState(() => _distanciaMetros = distancia);

      if (distancia <= _umbralLlegadaMetros) {
        await ref.read(servicioRepositoryProvider).marcarEnSitio(servicioId);
        await _posicionSub?.cancel(); // se detiene por completo, no solo se oculta
      }
    });
  }

  Future<void> _aceptar(String id) async {
    setState(() => _procesando = true);
    try {
      await ref.read(servicioRepositoryProvider).aceptar(id);
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final servicioAsync = ref.watch(servicioRepositoryProvider).observarUno(widget.servicioId);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _indigo,
        foregroundColor: Colors.white,
        title: const Text('Detalle de servicio'),
      ),
      body: StreamBuilder<ServicioAsignado?>(
        stream: servicioAsync,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final s = snap.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _tarjeta('CLIENTE', [
                  _dato('Nombre', s.clienteNombre),
                  _dato('Dirección', s.clienteDireccion),
                  if (s.clienteTelefono != null) _dato('Teléfono', s.clienteTelefono!),
                ]),
                const SizedBox(height: 10),
                _tarjeta('EQUIPO Y FALLA', [
                  _dato('Equipo', '${s.equipoTipo} ${s.marca} ${s.modelo}'),
                  _dato('No. serie', s.numeroSerie),
                  _dato('Falla reportada', s.fallaReportada),
                ]),
                const SizedBox(height: 16),
                if (s.estadoAsignacion == EstadoAsignacion.asignado)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: _verde, foregroundColor: Colors.white),
                    onPressed: _procesando ? null : () => _aceptar(s.id),
                    icon: const Icon(Icons.check),
                    label: const Text('Aceptar servicio'),
                  ),
                if (s.estadoAsignacion == EstadoAsignacion.aceptado)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: _indigo, foregroundColor: Colors.white),
                    onPressed: _procesando ? null : () => _acudir(s),
                    icon: const Icon(Icons.directions),
                    label: const Text('Acudir'),
                  ),
                if (s.estadoAsignacion == EstadoAsignacion.enCamino) ...[
                  const _EnCaminoAviso(),
                  if (_distanciaMetros != null) ...[
                    const SizedBox(height: 8),
                    Text('Distancia al domicilio: ${_distanciaMetros!.toStringAsFixed(0)} m',
                        textAlign: TextAlign.center),
                  ],
                ],
                if (s.estadoAsignacion == EstadoAsignacion.enSitio)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: _amarillo, foregroundColor: Colors.black),
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => FormularioServicioScreen(servicio: s))),
                    icon: const Icon(Icons.assignment_turned_in),
                    label: const Text('Iniciar servicio'),
                  ),
                if (s.estadoAsignacion == EstadoAsignacion.cerrado)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Este servicio ya fue cerrado.', textAlign: TextAlign.center),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _tarjeta(String titulo, List<Widget> hijos) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFD8DBE8)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo,
                style: const TextStyle(color: _indigo, fontWeight: FontWeight.bold, letterSpacing: 1, fontSize: 12)),
            const SizedBox(height: 8),
            ...hijos,
          ],
        ),
      );

  Widget _dato(String etiqueta, String valor) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: RichText(
          text: TextSpan(
            style: const DefaultTextStyle.fallback().style.copyWith(color: Colors.black87, fontSize: 13.5),
            children: [
              TextSpan(text: '$etiqueta: ', style: const TextStyle(fontWeight: FontWeight.w600)),
              TextSpan(text: valor),
            ],
          ),
        ),
      );
}

class _EnCaminoAviso extends StatelessWidget {
  const _EnCaminoAviso();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF4F5FA), borderRadius: BorderRadius.circular(8)),
      child: const Column(
        children: [
          Icon(Icons.local_shipping_outlined, color: _indigo),
          SizedBox(height: 6),
          Text(
            'Vas en camino. El cliente ya recibió la liga de rastreo en vivo. '
            'En cuanto llegues al domicilio se habilitará "Iniciar servicio".',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: Color(0xFF4A4F63)),
          ),
        ],
      ),
    );
  }
}
