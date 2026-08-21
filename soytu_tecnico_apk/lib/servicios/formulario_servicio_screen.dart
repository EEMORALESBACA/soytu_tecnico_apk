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
  Uint8List? fotoTicketCompra; // Obligatoria solo si tipoServicio == 'garantia'
  String descripcionTecnico = '';
  final Set<TipoFalla> tiposFalla = {};
  final List<LecturaVoltaje> voltajes = [];
  // Datos adicionales del equipo (opcionales, se integran al reporte).
  String antiguedad = '';
  String capacidad = '';
  String color = '';
  String accesorios = '';
  // Solo se llenan cuando el servicio es de cargo (formulario simplificado).
  double? montoCobrado;
  String? metodoPago; // 'tarjeta' | 'transferencia' | 'efectivo'
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
  final _antiguedadCtrl = TextEditingController();
  final _capacidadCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  final _accesoriosCtrl = TextEditingController();
  final _voltajeHogarCtrl = TextEditingController();
  Uint8List? _fotoVoltajeHogar;
  final _voltajeMain12Ctrl = TextEditingController();
  final _voltajeStandbyCtrl = TextEditingController();
  bool _grabandoVideo = false;

  // ── Flujo simplificado de CARGO ──
  final _montoCargoCtrl = TextEditingController();
  String? _metodoPagoCargo; // 'tarjeta' | 'transferencia' | 'efectivo'

  bool get _esCargo => widget.servicio.tipoServicio == 'cargo';

  @override
  void dispose() {
    _descripcionCtrl.dispose();
    _antiguedadCtrl.dispose();
    _capacidadCtrl.dispose();
    _colorCtrl.dispose();
    _accesoriosCtrl.dispose();
    _voltajeHogarCtrl.dispose();
    _voltajeMain12Ctrl.dispose();
    _voltajeStandbyCtrl.dispose();
    _montoCargoCtrl.dispose();
    super.dispose();
  }

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

  bool get _puedeCerrar {
    if (_esCargo) {
      final monto = double.tryParse(_montoCargoCtrl.text.trim());
      return monto != null && monto > 0 && _metodoPagoCargo != null;
    }
    return _datos.fotoEquipo != null &&
        _datos.fotoPlaca != null &&
        (_datos.fotoFalla != null || _datos.videoFalla != null) &&
        _datos.fotoTicketCompra != null &&
        _descripcionCtrl.text.trim().isNotEmpty &&
        _voltajeHogarCtrl.text.trim().isNotEmpty;
  }

  void _irACierre(Widget Function(ServicioAsignado, DatosDiagnostico) pantalla) {
    if (!_puedeCerrar) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_esCargo
              ? 'Captura el monto a cobrar y la forma de pago antes de continuar.'
              : 'Completa fotos de equipo/placa/falla/ticket de compra, descripción y voltaje de línea antes de cerrar.')));
      return;
    }
    if (_esCargo) {
      _datos.montoCobrado = double.parse(_montoCargoCtrl.text.trim());
      _datos.metodoPago = _metodoPagoCargo;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => pantalla(widget.servicio, _datos)));
      return;
    }
    _datos.descripcionTecnico = _descripcionCtrl.text.trim();
    _datos.antiguedad = _antiguedadCtrl.text.trim();
    _datos.capacidad = _capacidadCtrl.text.trim();
    _datos.color = _colorCtrl.text.trim();
    _datos.accesorios = _accesoriosCtrl.text.trim();
    final extra = <String>[
      if (_datos.antiguedad.isNotEmpty) 'Antigüedad: ${_datos.antiguedad}',
      if (_datos.capacidad.isNotEmpty) 'Capacidad: ${_datos.capacidad}',
      if (_datos.color.isNotEmpty) 'Color: ${_datos.color}',
      if (_datos.accesorios.isNotEmpty) 'Accesorios: ${_datos.accesorios}',
    ];
    if (extra.isNotEmpty) {
      _datos.descripcionTecnico = '${_datos.descripcionTecnico}\n\nDatos del equipo:\n${extra.join('\n')}';
    }
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
        child: _esCargo ? _buildCargo(context) : _buildGarantia(context),
      ),
    );
  }

  /// Servicio de CARGO: sin diagnóstico, directo a cobrar. El cliente ya
  /// sabe que es un servicio de paga, así que no se le vuelve a preguntar
  /// nada del equipo — solo el monto y cómo va a pagar.
  Widget _buildCargo(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFEDEFFA), borderRadius: BorderRadius.circular(10)),
          child: const Row(children: [
            Icon(Icons.payments_outlined, color: _indigo),
            SizedBox(width: 10),
            Expanded(
              child: Text('Servicio de cargo — captura el cobro para cerrar.',
                  style: TextStyle(color: _indigo, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _montoCargoCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Monto a cobrar (MXN) *',
            prefixText: '\$ ',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 18),
        const Text('Forma de pago *', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chipPago('tarjeta', 'Tarjeta', Icons.credit_card),
            _chipPago('transferencia', 'Transferencia', Icons.swap_horiz),
            _chipPago('efectivo', 'Efectivo', Icons.payments),
          ],
        ),
        const SizedBox(height: 28),
        const Divider(),
        const SizedBox(height: 8),
        const Text('Cerrar servicio', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: _verde, foregroundColor: Colors.white),
          onPressed: () => _irACierre((s, d) => CierreCompletadoScreen(servicio: s, datos: d)),
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Cobrar y cerrar'),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: _rojo, foregroundColor: Colors.white),
          onPressed: () => _irACierre((s, d) => CierreCanceladoScreen(servicio: s, datos: d)),
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('Cancelado / Rechazado'),
        ),
      ],
    );
  }

  Widget _chipPago(String valor, String etiqueta, IconData icono) {
    final seleccionado = _metodoPagoCargo == valor;
    return ChoiceChip(
      label: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icono, size: 16, color: seleccionado ? Colors.white : _indigo),
        const SizedBox(width: 6),
        Text(etiqueta),
      ]),
      selected: seleccionado,
      selectedColor: _indigo,
      labelStyle: TextStyle(color: seleccionado ? Colors.white : _indigo, fontWeight: FontWeight.w600),
      onSelected: (_) => setState(() => _metodoPagoCargo = valor),
    );
  }

  /// Servicio de GARANTÍA: diagnóstico completo, incluyendo evidencia
  /// fotográfica del ticket de compra que ampara la garantía.
  Widget _buildGarantia(BuildContext context) {
    return Column(
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
            CapturaCamara(
              etiqueta: 'Foto del ticket / factura de compra',
              obligatoria: true,
              onCapturada: (b) => setState(() => _datos.fotoTicketCompra = b),
            ),
            const SizedBox(height: 16),
            const Text('Datos adicionales del equipo', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('Opcional, pero ayuda mucho a diagnosticar reincidencias y a la administración.',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF6B7080))),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _antiguedadCtrl,
                  decoration: const InputDecoration(labelText: 'Antigüedad aprox.', border: OutlineInputBorder(), isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _capacidadCtrl,
                  decoration: const InputDecoration(labelText: 'Capacidad (Ej. 18 pies, 15kg)', border: OutlineInputBorder(), isDense: true),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _colorCtrl,
                  decoration: const InputDecoration(labelText: 'Color', border: OutlineInputBorder(), isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _accesoriosCtrl,
                  decoration: const InputDecoration(labelText: 'Accesorios (control, manguera...)', border: OutlineInputBorder(), isDense: true),
                ),
              ),
            ]),
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
            const SizedBox(height: 18),
            _TarjetaRefaccionesSugeridas(marca: widget.servicio.marca, tipoEquipo: widget.servicio.equipoTipo),
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

/// Muestra las refacciones del almacén sugeridas para la marca y tipo de
/// equipo de este servicio — mismo inventario que administra el panel web.
class _TarjetaRefaccionesSugeridas extends StatelessWidget {
  const _TarjetaRefaccionesSugeridas({required this.marca, required this.tipoEquipo});

  final String marca;
  final String tipoEquipo;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RefaccionInventario>>(
      stream: AlmacenRepository().observarSugeridas(marca: marca, tipoEquipo: tipoEquipo),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final refs = snap.data!;
        if (refs.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFF7F8FC), borderRadius: BorderRadius.circular(10)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('📦 Refacciones sugeridas para $marca · $tipoEquipo',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: _indigo)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: refs
                    .map((r) => Chip(
                          label: Text('${r.nombre} (${r.stock})', style: const TextStyle(fontSize: 11.5)),
                          backgroundColor: r.stock > 0 ? const Color(0xFFEDEFFA) : const Color(0xFFFDEDED),
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}
