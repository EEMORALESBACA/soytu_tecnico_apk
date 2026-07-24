import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:soytu_core/soytu_core.dart';

import '../providers/providers.dart';
import '../services/notificaciones_locales.dart';
import 'formulario_servicio_screen.dart';
import 'reagendar_servicio.dart';

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

  /// Normaliza un teléfono de México a formato internacional para wa.me.
  String _telWa(String tel) {
    var t = tel.replaceAll(RegExp(r'[^0-9]'), '');
    if (t.length == 10) return '521$t';
    if (t.length == 12 && t.startsWith('52')) return '521${t.substring(2)}';
    return t;
  }

  Future<void> _confirmarPorWhatsApp(ServicioAsignado s) async {
    if (s.clienteTelefono == null) return;
    final msj = Uri.encodeComponent(
        'Hola ${s.clienteNombre}, soy su técnico SOYTU para el servicio ${s.folio} '
        '(${s.equipoTipo} ${s.marca}). ¿Me confirma que se encontrará en el domicilio '
        'para agendar mi visita? — SOYTU · Creando Conexiones');
    final uri = Uri.parse('https://wa.me/${_telWa(s.clienteTelefono!)}?text=$msj');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _confirmarPorLlamada(ServicioAsignado s) async {
    if (s.clienteTelefono == null) return;
    final uri = Uri(scheme: 'tel', path: s.clienteTelefono!);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Deja elegir Google Maps o Waze y (opcional) recuerda la elección
  /// en tecnicos/{uid}.navPreferida para no volver a preguntar.
  Future<String?> _elegirNavegador() async {
    final tecnico = ref.read(tecnicoActualProvider).value;
    if (tecnico?.navPreferida == 'maps' || tecnico?.navPreferida == 'waze') {
      return tecnico!.navPreferida;
    }
    bool recordar = true;
    return showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('¿Con qué app quieres navegar?'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.map, color: Color(0xFF34A853)),
              title: const Text('Google Maps'),
              onTap: () => Navigator.pop(c, 'maps'),
            ),
            ListTile(
              leading: const Icon(Icons.navigation, color: Color(0xFF33CCFF)),
              title: const Text('Waze'),
              onTap: () => Navigator.pop(c, 'waze'),
            ),
            CheckboxListTile(
              value: recordar,
              onChanged: (v) => setD(() => recordar = v ?? true),
              title: const Text('Recordar mi elección', style: TextStyle(fontSize: 13.5)),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ]),
        ),
      ),
    ).then((eleccion) async {
      if (eleccion != null && recordar && tecnico != null) {
        await ref.read(tecnicoRepositoryProvider).actualizarNavPreferida(tecnico.uid, eleccion);
      }
      return eleccion;
    });
  }

  Future<void> _abrirNavegacion(String app, double lat, double lng) async {
    final uri = app == 'waze'
        ? Uri.parse('https://waze.com/ul?ll=' '$lat,$lng&navigate=yes')
        : Uri.parse('google.navigation:q=' '$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(Uri.parse('geo:' '$lat,$lng?q=$lat,$lng'),
          mode: LaunchMode.externalApplication);
    }
  }

  /// Respaldo manual de la liga de rastreo (el envío principal es automático
  /// vía WhatsApp Cloud API desde el servidor SOYTU al pasar a "en camino").
  Future<void> _reenviarLiga(ServicioAsignado s) async {
    if (s.clienteTelefono == null) return;
    final mensaje = Uri.encodeComponent(
        'SOYTU — su técnico ya va en camino para el servicio ' '${s.folio}. '
        'Siga su ubicación en tiempo real: https://soytu.com.mx/soytu/tracking.html?id=' '${s.id}');
    await launchUrl(
        Uri.parse('https://wa.me/' '${_telWa(s.clienteTelefono!)}?text=$mensaje'),
        mode: LaunchMode.externalApplication);
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
    final navApp = await _elegirNavegador();
    if (navApp == null) return; // canceló el diálogo
    setState(() => _procesando = true);
    try {
      // Al pasar a "en camino", el servidor SOYTU envía automáticamente al
      // cliente el WhatsApp con la liga de rastreo, foto del técnico y placas.
      await ref.read(servicioRepositoryProvider).marcarEnCamino(s.id);

      if (s.clienteLat != null && s.clienteLng != null) {
        await _abrirNavegacion(navApp, s.clienteLat!, s.clienteLng!);
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
      await NotificacionesLocales.cancelarServicio(id);
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
                if (s.fechaProgramada != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                        color: const Color(0xFFEDEFFA), borderRadius: BorderRadius.circular(10)),
                    child: Text(
                        '📅 Programado para: '
                        '${s.fechaProgramada!.day}/${s.fechaProgramada!.month}/${s.fechaProgramada!.year}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600, color: _indigo)),
                  ),
                if (s.estadoAsignacion == EstadoAsignacion.asignado) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: _verde, foregroundColor: Colors.white),
                    onPressed: _procesando ? null : () => _aceptar(s.id),
                    icon: const Icon(Icons.check),
                    label: const Text('Aceptar servicio'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _procesando ? null : () => reagendarServicio(context, ref, s),
                    icon: const Icon(Icons.event_repeat),
                    label: const Text('Reagendar para otra fecha'),
                  ),
                ],
                if (s.estadoAsignacion == EstadoAsignacion.aceptado) ...[
                  if (s.clienteTelefono != null) ...[
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Text('Confirma el servicio con el cliente antes de salir:',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12.5, color: Color(0xFF4A4F63))),
                    ),
                    Row(children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white),
                          onPressed: _procesando ? null : () => _confirmarPorWhatsApp(s),
                          icon: const Icon(Icons.chat),
                          label: const Text('WhatsApp'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: _indigo, foregroundColor: Colors.white),
                          onPressed: _procesando ? null : () => _confirmarPorLlamada(s),
                          icon: const Icon(Icons.phone),
                          label: const Text('Llamar'),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                  ],
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: _indigo, foregroundColor: Colors.white),
                    onPressed: _procesando ? null : () => _acudir(s),
                    icon: const Icon(Icons.directions),
                    label: const Text('Acudir'),
                  ),
                ],
                if (s.estadoAsignacion == EstadoAsignacion.enCamino) ...[
                  const _EnCaminoAviso(),
                  const SizedBox(height: 8),
                  if (s.clienteTelefono != null)
                    OutlinedButton.icon(
                      onPressed: () => _reenviarLiga(s),
                      icon: const Icon(Icons.share_location),
                      label: const Text('Reenviar liga de rastreo al cliente'),
                    ),
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
            'Vas en camino. SOYTU envió automáticamente al cliente la liga de '
            'rastreo en vivo por WhatsApp, con tu foto y las placas de tu auto. '
            'En cuanto llegues al domicilio se habilitará "Iniciar servicio".',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: Color(0xFF4A4F63)),
          ),
        ],
      ),
    );
  }
}
