import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:signature/signature.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:soytu_core/soytu_core.dart';

import '../../providers/providers.dart';
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
  final _montoCtrl = TextEditingController();
  bool _esDeCargo = false;
  bool _procesando = false;

  @override
  void dispose() {
    _firmaCtrl.dispose();
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
        modelo: s.modelo,
        numeroSerie: s.numeroSerie,
        fallaReportada: s.fallaReportada,
        descripcionTecnico: widget.datos.descripcionTecnico,
        tiposFalla: widget.datos.tiposFalla.toList(),
        voltajes: widget.datos.voltajes,
        fotoEquipo: widget.datos.fotoEquipo,
        fotoPlaca: widget.datos.fotoPlaca,
        fotoFalla: widget.datos.fotoFalla,
        montoCobrado: _esDeCargo ? double.tryParse(_montoCtrl.text.trim()) : null,
        firmaCliente: firmaBytes,
      );

      final pdfBytes = await HojaServicioPdf().generar(orden);

      final storage = ref.read(storageServiceProvider);
      final pdfUrl = await storage.subirPdf(s.id, pdfBytes);
      if (widget.datos.videoFalla != null) {
        final videoUrl = await storage.subirVideoFalla(s.id, widget.datos.videoFalla!);
        await ref.read(servicioRepositoryProvider).actualizarVideoFalla(s.id, videoUrl);
      }

      await ref
          .read(servicioRepositoryProvider)
          .cerrar(s.id, estadoFinal: EstadoServicio.completado, pdfUrl: pdfUrl);

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

      if (mounted) volverAlInicioDeServicios(context);
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('¿Es un servicio de cargo?'),
              value: _esDeCargo,
              onChanged: (v) => setState(() => _esDeCargo = v),
            ),
            if (_esDeCargo)
              TextField(
                controller: _montoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Monto cobrado (MXN)', border: OutlineInputBorder()),
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
