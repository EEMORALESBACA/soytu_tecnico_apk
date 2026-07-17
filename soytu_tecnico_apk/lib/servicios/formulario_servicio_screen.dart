import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:soytu_core/soytu_core.dart';

import '../widgets/captura_camara.dart';
import 'cierre/cierre_completado_screen.dart';
import 'cierre/cierre_pendiente_screen.dart';
import 'cierre/cierre_cancelado_screen.dart';

const _indigo = Color(0xFF1A237E);
const _verde = Color(0xFF2E7D32);
const _amarillo = Color(0xFFF9A825);
const _rojo = Color(0xFFC62828);

/// Datos de diagnóstico capturados en sitio. Se pasan tal cual a la
/// pantalla de cierre elegida (Completado/Pendiente/Cancelado), que agrega
/// lo que falte (monto, firma, motivo) y genera el PDF con [HojaServicioPdf].
class DatosDiagnostico {
  Uint8List? fotoEquipo;
  Uint8List? fotoPlaca;
  Uint8List? fotoFalla;
  Uint8List? videoFalla;
  String descripcionTecnico = '';
  final Set<TipoFalla> tiposFalla = {};
  final List<LecturaVoltaje> voltajes = [];
}

class FormularioServicioScreen extends StatefulWidget {
  const FormularioServicioScreen({super.key, required this.servicio});

  final ServicioAsignado servicio;

  @override
  State<FormularioServicioScreen> createState() => _FormularioServicioScreenState();
}

class _FormularioServicioScreenState extends State<FormularioServicioScreen> {
  final _datos = DatosDiagnostico();
  final _descripcionCtrl = TextEditingController();
  final _voltajeHogarCtrl = TextEditingController();
  Uint8List? _fotoVoltajeHogar;
  final _voltajeMain12Ctrl = TextEditingController();
  final _voltajeStandbyCtrl = TextEditingController();
  bool _grabandoVideo = false;

  bool get _tarjetaMainMarcada => _datos.tiposFalla.contains(TipoFalla.tarjetaMain);

  Future<void> _grabarVideoFalla() async {
    setState(() => _grabandoVideo = true);
    try {
      final picker = ImagePicker();
      final archivo = await picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(seconds: 30));
      if (archivo == null) return;
      final bytes = await archivo.readAsBytes();
      setState(() {
        _datos.videoFalla = bytes;
        _datos.fotoFalla = null;
      });
    } finally {
      if (mounted) setState(() => _grabandoVideo = false);
    }
  }

  void _construirVoltajes() {
    _datos.voltajes
      ..clear()
      ..add(LecturaVoltaje(
        punto: 'Línea del hogar (toma corriente)',
        valor: _voltajeHogarCtrl.text.trim(),
        foto: _fotoVoltajeHogar,
      ));
    if (_tarjetaMainMarcada) {
      if (_voltajeMain12Ctrl.text.trim().isNotEmpty) {
        _datos.voltajes.add(LecturaVoltaje(punto: 'VCC Main 12V', valor: _voltajeMain12Ctrl.text.trim()));
      }
      if (_voltajeStandbyCtrl.text.trim().isNotEmpty) {
        _datos.voltajes.add(LecturaVoltaje(punto: 'Standby 3.3V', valor: _voltajeStandbyCtrl.text.trim()));
      }
    }
  }

  bool get _puedeCerrar =>
      _datos.fotoEquipo != null &&
      _datos.fotoPlaca != null &&
      (_datos.fotoFalla != null || _datos.videoFalla != null) &&
      _descripcionCtrl.text.trim().isNotEmpty &&
      _voltajeHogarCtrl.text.trim().isNotEmpty;

  void _irACierre(Widget Function(ServicioAsignado, DatosDiagnostico) pantalla) {
    if (!_puedeCerrar) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Completa fotos de equipo/placa/falla, descripción y voltaje de línea antes de cerrar.')));
      return;
    }
    _datos.descripcionTecnico = _descripcionCtrl.text.trim();
    _construirVoltajes();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => pantalla(widget.servicio, _datos)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _indigo,
        foregroundColor: Colors.white,
        title: Text('Servicio ${widget.servicio.folio}'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CapturaCamara(
              etiqueta: 'Foto del equipo',
              obligatoria: true,
              onCapturada: (b) => setState(() => _datos.fotoEquipo = b),
            ),
            const SizedBox(height: 14),
            CapturaCamara(
              etiqueta: 'Foto de la placa / no. de serie',
              obligatoria: true,
              onCapturada: (b) => setState(() => _datos.fotoPlaca = b),
            ),
            const SizedBox(height: 14),
            const Text('Evidencia de la falla *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            if (_datos.videoFalla == null)
              CapturaCamara(
                etiqueta: 'Foto de la falla',
                onCapturada: (b) => setState(() => _datos.fotoFalla = b),
              )
            else
              Container(
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0xFFF4F5FA), borderRadius: BorderRadius.circular(10)),
                child: const Text('Video de falla capturado ✓'),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _grabandoVideo ? null : _grabarVideoFalla,
                icon: const Icon(Icons.videocam_outlined),
                label: Text(_datos.videoFalla == null ? 'O grabar video en su lugar' : 'Volver a grabar video'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descripcionCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Descripción de la falla y condiciones del equipo *',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            const Text('Tipo de falla', style: TextStyle(fontWeight: FontWeight.w600)),
            Wrap(
              spacing: 8,
              children: TipoFalla.values
                  .map((t) => FilterChip(
                        label: Text(t.etiqueta),
                        selected: _datos.tiposFalla.contains(t),
                        onSelected: (v) => setState(() => v ? _datos.tiposFalla.add(t) : _datos.tiposFalla.remove(t)),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            const Text('Voltajes', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _filaVoltaje('Línea del hogar (toma corriente) *', _voltajeHogarCtrl,
                onFoto: (b) => _fotoVoltajeHogar = b),
            if (_tarjetaMainMarcada) ...[
              const SizedBox(height: 8),
              _filaVoltaje('VCC Main 12V', _voltajeMain12Ctrl),
              const SizedBox(height: 8),
              _filaVoltaje('Standby 3.3V', _voltajeStandbyCtrl),
            ],
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            const Text('Cerrar servicio', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: _verde, foregroundColor: Colors.white),
              onPressed: () => _irACierre((s, d) => CierreCompletadoScreen(servicio: s, datos: d)),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Completado'),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: _amarillo, foregroundColor: Colors.black),
              onPressed: () => _irACierre((s, d) => CierrePendienteScreen(servicio: s, datos: d)),
              icon: const Icon(Icons.pending_outlined),
              label: const Text('Pendiente'),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: _rojo, foregroundColor: Colors.white),
              onPressed: () => _irACierre((s, d) => CierreCanceladoScreen(servicio: s, datos: d)),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancelado / Rechazado'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filaVoltaje(String etiqueta, TextEditingController ctrl, {ValueChanged<Uint8List>? onFoto}) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: ctrl,
            decoration: InputDecoration(labelText: etiqueta, border: const OutlineInputBorder(), isDense: true),
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (onFoto != null) ...[
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined, color: _indigo),
            onPressed: () async {
              final archivo = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 80);
              if (archivo != null) onFoto(await archivo.readAsBytes());
            },
          ),
        ],
      ],
    );
  }
}
