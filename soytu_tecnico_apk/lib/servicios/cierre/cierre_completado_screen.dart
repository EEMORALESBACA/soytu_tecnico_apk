import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:signature/signature.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:soytu_core/soytu_core.dart';

import '../../providers/providers.dart';
import '../../services/reincidencia_aviso.dart';
import '../formulario_servicio_screen.dart';
import 'servicios_home_navigator.dart';

const _verde = Color(0xFF2E7D32);

class CierreCompletadoScreen extends ConsumerStatefulWidget {
  const CierreCompletadoScreen({super.key, required this.servicio, required this.datos});

  final ServicioAsignado servicio;
  final DatosDiagnostico datos;

  @override
  ConsumerState<CierreCompletadoScreen> createState() => _CierreCompletadoScreenState();
}

class _CierreCompletadoScreenState extends ConsumerState<CierreCompletadoScreen> {
  final _firmaCtrl = SignatureController(penStrokeWidth: 2, penColor: Colors.black);
  late final _modeloCtrl = TextEditingController(text: widget.servicio.modelo);
  late final _serieCtrl = TextEditingController(text: widget.servicio.numeroSerie);
  final _otraRefaccionCtrl = TextEditingController();
  final Set<String> _refaccionesUsadas = {};
  bool _procesando = false;

  String _etiquetaMetodoPago(String? m) {
    switch (m) {
      case 'tarjeta':
        return 'Tarjeta';
      case 'transferencia':
        return 'Transferencia';
      case 'efectivo':
        return 'Efectivo';
      default:
        return 'Sin especificar';
    }
  }

  List<String> get _refaccionesFinales =>
      [..._refaccionesUsadas, if (_otraRefaccionCtrl.text.trim().isNotEmpty) _otraRefaccionCtrl.text.trim()];

  @override
  void dispose() {
    _firmaCtrl.dispose();
    _modeloCtrl.dispose();
    _serieCtrl.dispose();
    _otraRefaccionCtrl.dispose();
    super.dispose();
  }

  Future<void> _cerrarServicio() async {
    if (_firmaCtrl.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Se requiere la firma de conformidad del cliente.')));
      return;
    }
    setState(() => _procesando = true);
    try {
      final s = widget.servicio;
      final modelo = _modeloCtrl.text.trim().isEmpty ? s.modelo : _modeloCtrl.text.trim();
      final serie = _serieCtrl.text.trim().isEmpty ? s.numeroSerie : _serieCtrl.text.trim();
      final tecnico = ref.read(tecnicoActualProvider).value;
      final firmaBytes = await _firmaCtrl.toPngBytes();

      final orden = OrdenServicio(
        folio: s.folio,
        fecha: DateTime.now(),
        estado: EstadoServicio.completado,
        tecnicoNombre: tecnico?.nombre ?? '',
        tecnicoId: tecnico?.uid ?? '',
        tecnicoTelefono: tecnico?.telefono,
        clienteNombre: s.clienteNombre,
        clienteDireccion: s.clienteDireccion,
        clienteTelefono: s.clienteTelefono,
        clienteCorreo: s.clienteCorreo,
        equipoTipo: s.equipoTipo,
        marca: s.marca,
        modelo: modelo,
        numeroSerie: serie,
        fallaReportada: s.fallaReportada,
        refaccionesUsadas: _refaccionesFinales,
        descripcionTecnico: widget.datos.descripcionTecnico,
        tiposFalla: widget.datos.tiposFalla.toList(),
        voltajes: widget.datos.voltajes,
        fotoEquipo: widget.datos.fotoEquipo,
        fotoPlaca: widget.datos.fotoPlaca,
        fotoFalla: widget.datos.fotoFalla,
        montoCobrado: widget.datos.montoCobrado,
        firmaCliente: firmaBytes,
      );

      final pdfBytes = await HojaServicioPdf().generar(orden);

      final storage = ref.read(storageServiceProvider);
      final pdfUrl = await storage.subirPdf(s.id, pdfBytes);
      if (widget.datos.videoFalla != null) {
        final videoUrl = await storage.subirVideoFalla(s.id, widget.datos.videoFalla!);
        await ref.read(servicioRepositoryProvider).actualizarVideoFalla(s.id, videoUrl);
      }
      String? urlEquipo, urlPlaca, urlFalla;
      if (widget.datos.fotoEquipo != null) {
        urlEquipo = await storage.subirFotoServicio(s.id, 'equipo.jpg', widget.datos.fotoEquipo!);
      }
      if (widget.datos.fotoPlaca != null) {
        urlPlaca = await storage.subirFotoServicio(s.id, 'placa.jpg', widget.datos.fotoPlaca!);
      }
      if (widget.datos.fotoFalla != null) {
        urlFalla = await storage.subirFotoServicio(s.id, 'falla.jpg', widget.datos.fotoFalla!);
      }
      String? urlTicket;
      if (widget.datos.fotoTicketCompra != null) {
        urlTicket = await storage.subirFotoServicio(s.id, 'ticket_compra.jpg', widget.datos.fotoTicketCompra!);
      }

      final svcRepo = ref.read(servicioRepositoryProvider);
      await svcRepo.cerrar(
        s.id,
        estadoFinal: EstadoServicio.completado,
        pdfUrl: pdfUrl,
        refaccionesUsadas: _refaccionesFinales,
        fotoEquipoUrl: urlEquipo,
        fotoPlacaUrl: urlPlaca,
        fotoFallaUrl: urlFalla,
        fotoTicketCompraUrl: urlTicket,
        montoCobrado: widget.datos.montoCobrado,
        metodoPago: widget.datos.metodoPago,
        modelo: modelo,
        numeroSerie: serie,
      );

      // Aviso de reincidencia: mismo número de serie ya reparado antes.
      final reincidencias = await svcRepo.contarReincidencias(serie, excluirId: s.id);

      final dir = await getApplicationDocumentsDirectory();
      final archivo = File('${dir.path}/HojaServicio_${s.folio}.pdf');
      await archivo.writeAsBytes(pdfBytes);
      await Share.shareXFiles(
        [XFile(archivo.path, mimeType: 'application/pdf')],
        text: 'SOYTU — Hoja de servicio ${s.folio}. Gracias por su confianza. soytu.com.mx',
      );

      if (s.clienteTelefono != null) {
        final mensaje = Uri.encodeComponent(
            'Su servicio ${s.folio} ha sido COMPLETADO ✅. Le compartimos su hoja de servicio en PDF. '
            'Nos ayudaría mucho si responde esta breve encuesta de satisfacción: '
            'https://soytu.com.mx/encuesta.html?servicio=${s.id} — SOYTU');
        final uri = Uri.parse('https://wa.me/${s.clienteTelefono}?text=$mensaje');
        if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
      }

      if (mounted) {
        if (reincidencias > 0) {
          await mostrarAvisoReincidencia(context, reincidencias);
        }
        volverAlInicioDeServicios(context);
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: _verde, foregroundColor: Colors.white, title: const Text('Completado')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Confirma o corrige modelo y número de serie',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _modeloCtrl,
              decoration: const InputDecoration(labelText: 'Modelo', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _serieCtrl,
              decoration: const InputDecoration(labelText: 'Número de serie', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 18),
            const Text('Refacciones utilizadas en la reparación',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: catalogoParaEquipo(widget.servicio.equipoTipo)
                  .map((r) => FilterChip(
                        label: Text(r),
                        selected: _refaccionesUsadas.contains(r),
                        onSelected: (v) => setState(
                            () => v ? _refaccionesUsadas.add(r) : _refaccionesUsadas.remove(r)),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _otraRefaccionCtrl,
              decoration: const InputDecoration(
                  labelText: 'Otra refacción (si no está en la lista)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 18),
            if (widget.servicio.tipoServicio == 'cargo')
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFEDEFFA), borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.payments_outlined, color: Color(0xFF1A237E)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        'Cobro: \$${widget.datos.montoCobrado?.toStringAsFixed(2) ?? '0.00'} · '
                        '${_etiquetaMetodoPago(widget.datos.metodoPago)}',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1A237E))),
                  ),
                ]),
              ),
            const SizedBox(height: 20),
            const Text('Firma de conformidad del cliente', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Container(
              height: 180,
              decoration: BoxDecoration(border: Border.all(color: const Color(0xFFD8DBE8)), borderRadius: BorderRadius.circular(8)),
              child: Signature(controller: _firmaCtrl, backgroundColor: Colors.white),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => _firmaCtrl.clear(), child: const Text('Borrar firma')),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: _verde, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _procesando ? null : _cerrarServicio,
              icon: const Icon(Icons.check_circle),
              label: _procesando ? const Text('Generando PDF...') : const Text('Generar PDF y cerrar servicio'),
            ),
          ],
        ),
      ),
    );
  }
}
