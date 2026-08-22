import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:soytu_core/soytu_core.dart';

import '../../providers/providers.dart';
import '../../widgets/captura_camara.dart';
import '../formulario_servicio_screen.dart';
import 'servicios_home_navigator.dart';

const _rojo = Color(0xFFC62828);

class CierreCanceladoScreen extends ConsumerStatefulWidget {
  const CierreCanceladoScreen({super.key, required this.servicio, required this.datos});

  final ServicioAsignado servicio;
  final DatosDiagnostico datos;

  @override
  ConsumerState<CierreCanceladoScreen> createState() => _CierreCanceladoScreenState();
}

class _CierreCanceladoScreenState extends ConsumerState<CierreCanceladoScreen> {
  final _motivoCtrl = TextEditingController();
  Uint8List? _fotoEvidencia;
  bool _procesando = false;

  Future<void> _cerrarServicio() async {
    if (_motivoCtrl.text.trim().isEmpty || _fotoEvidencia == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Escribe el motivo y toma la foto de evidencia antes de continuar.')));
      return;
    }
    setState(() => _procesando = true);
    try {
      final s = widget.servicio;
      final tecnico = ref.read(tecnicoActualProvider).value;

      final orden = OrdenServicio(
        folio: s.folio,
        fecha: DateTime.now(),
        estado: EstadoServicio.cancelado,
        tecnicoNombre: tecnico?.nombre ?? '',
        tecnicoId: tecnico?.uid ?? '',
        tecnicoTelefono: tecnico?.telefono,
        clienteNombre: s.clienteNombre,
        clienteDireccion: s.clienteDireccion,
        clienteTelefono: s.clienteTelefono,
        clienteCorreo: s.clienteCorreo,
        equipoTipo: s.equipoTipo,
        marca: s.marca,
        modelo: s.modelo,
        numeroSerie: s.numeroSerie,
        fallaReportada: s.fallaReportada,
        descripcionTecnico: widget.datos.descripcionTecnico,
        tiposFalla: widget.datos.tiposFalla.toList(),
        voltajes: widget.datos.voltajes,
        fotoEquipo: widget.datos.fotoEquipo,
        fotoPlaca: widget.datos.fotoPlaca,
        fotoFalla: widget.datos.fotoFalla,
        fotoEvidenciaCancelacion: _fotoEvidencia,
        esDeCargo: s.tipoServicio == 'cargo',
        motivoCancelacion: _motivoCtrl.text.trim(),
      );

      final pdfBytes = await HojaServicioPdf().generar(orden);
      final storage = ref.read(storageServiceProvider);
      final pdfUrl = await storage.subirPdf(s.id, pdfBytes);
      if (widget.datos.videoFalla != null) {
        final videoUrl = await storage.subirVideoFalla(s.id, widget.datos.videoFalla!);
        await ref.read(servicioRepositoryProvider).actualizarVideoFalla(s.id, videoUrl);
      }

      await ref.read(servicioRepositoryProvider).cerrar(s.id, estadoFinal: EstadoServicio.cancelado, pdfUrl: pdfUrl);

      final dir = await getApplicationDocumentsDirectory();
      final archivo = File('${dir.path}/HojaServicio_${s.folio}.pdf');
      await archivo.writeAsBytes(pdfBytes);
      await Share.shareXFiles(
        [XFile(archivo.path, mimeType: 'application/pdf')],
        text: 'SOYTU — Servicio ${s.folio} cancelado/rechazado. soytu.com.mx',
      );

      if (s.clienteTelefono != null) {
        final mensaje = Uri.encodeComponent(
            'Su servicio ${s.folio} fue CANCELADO. Motivo: ${_motivoCtrl.text.trim()}. — SOYTU');
        final uri = Uri.parse('https://wa.me/${s.clienteTelefono}?text=$mensaje');
        if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
      }

      if (mounted) volverAlInicioDeServicios(context);
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: _rojo, foregroundColor: Colors.white, title: const Text('Cancelado / Rechazado')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _motivoCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Motivo de cancelación / rechazo *',
                hintText: 'Ej. Cliente ausente en el domicilio',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            CapturaCamara(
              etiqueta: 'Foto de evidencia (p. ej. domicilio, cliente ausente)',
              obligatoria: true,
              onCapturada: (b) => setState(() => _fotoEvidencia = b),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _rojo, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _procesando ? null : _cerrarServicio,
              icon: const Icon(Icons.cancel),
              label: _procesando ? const Text('Generando PDF...') : const Text('Generar PDF y cerrar servicio'),
            ),
          ],
        ),
      ),
    );
  }
}
