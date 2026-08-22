import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:soytu_core/soytu_core.dart';

import '../../providers/providers.dart';
import '../formulario_servicio_screen.dart';
import 'servicios_home_navigator.dart';

const _amarillo = Color(0xFFF9A825);

class CierrePendienteScreen extends ConsumerStatefulWidget {
  const CierrePendienteScreen({super.key, required this.servicio, required this.datos});

  final ServicioAsignado servicio;
  final DatosDiagnostico datos;

  @override
  ConsumerState<CierrePendienteScreen> createState() => _CierrePendienteScreenState();
}

class _CierrePendienteScreenState extends ConsumerState<CierrePendienteScreen> {
  String _motivo = 'Refacción';
  final Set<String> _refaccionesSeleccionadas = {};
  final _otraRefaccionCtrl = TextEditingController();
  bool _procesando = false;

  List<String> get _refaccionesFinales => [
        ..._refaccionesSeleccionadas,
        if (_otraRefaccionCtrl.text.trim().isNotEmpty)
          _otraRefaccionCtrl.text.trim(),
      ];

  String _telWa(String tel) {
    var t = tel.replaceAll(RegExp(r'[^0-9]'), '');
    if (t.length == 10) return '521$t';
    if (t.length == 12 && t.startsWith('52')) return '521${t.substring(2)}';
    return t;
  }

  Future<void> _cerrarServicio() async {
    if (_motivo == 'Refacción' && _refaccionesFinales.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Selecciona al menos una refacción faltante (o escríbela en "Otra refacción").')));
      return;
    }
    setState(() => _procesando = true);
    try {
      final s = widget.servicio;
      final tecnico = ref.read(tecnicoActualProvider).value;

      final orden = OrdenServicio(
        folio: s.folio,
        fecha: DateTime.now(),
        estado: EstadoServicio.pendiente,
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
        motivoPendiente: _motivo,
        esDeCargo: s.tipoServicio == 'cargo',
        refaccionesFaltantes: _motivo == 'Refacción' ? _refaccionesFinales : const [],
      );

      final pdfBytes = await HojaServicioPdf().generar(orden);
      final storage = ref.read(storageServiceProvider);
      final pdfUrl = await storage.subirPdf(s.id, pdfBytes);
      if (widget.datos.videoFalla != null) {
        final videoUrl = await storage.subirVideoFalla(s.id, widget.datos.videoFalla!);
        await ref.read(servicioRepositoryProvider).actualizarVideoFalla(s.id, videoUrl);
      }

      await ref.read(servicioRepositoryProvider).cerrar(
            s.id,
            estadoFinal: EstadoServicio.pendiente,
            pdfUrl: pdfUrl,
            motivoPendiente: _motivo,
            refaccionesFaltantes:
                _motivo == 'Refacción' ? _refaccionesFinales : const [],
          );

      final dir = await getApplicationDocumentsDirectory();
      final archivo = File('${dir.path}/HojaServicio_${s.folio}.pdf');
      await archivo.writeAsBytes(pdfBytes);
      await Share.shareXFiles(
        [XFile(archivo.path, mimeType: 'application/pdf')],
        text: 'SOYTU — Servicio ${s.folio}: faltante de refacción/software. soytu.com.mx',
      );

      if (s.clienteTelefono != null) {
        final mensaje = Uri.encodeComponent(
            'Su servicio ${s.folio} quedó PENDIENTE por $_motivo. Le compartimos la hoja de servicio con el detalle. — SOYTU');
        final uri = Uri.parse('https://wa.me/${_telWa(s.clienteTelefono!)}?text=$mensaje');
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
      appBar: AppBar(backgroundColor: _amarillo, foregroundColor: Colors.black, title: const Text('Pendiente')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Motivo', style: TextStyle(fontWeight: FontWeight.w600)),
            RadioGroup<String>(
              groupValue: _motivo,
              onChanged: (v) => setState(() => _motivo = v!),
              child: const Column(
                children: [
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Refacción'),
                    value: 'Refacción',
                  ),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Software'),
                    value: 'Software',
                  ),
                ],
              ),
            ),
            if (_motivo == 'Refacción') ...[
              const SizedBox(height: 8),
              const Text('Refacciones faltantes', style: TextStyle(fontWeight: FontWeight.w600)),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: catalogoParaEquipo(widget.servicio.equipoTipo)
                    .map((r) => FilterChip(
                          label: Text(r),
                          selected: _refaccionesSeleccionadas.contains(r),
                          onSelected: (v) =>
                              setState(() => v ? _refaccionesSeleccionadas.add(r) : _refaccionesSeleccionadas.remove(r)),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _otraRefaccionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Otra refacción (escríbela si no está en la lista)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _amarillo, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _procesando ? null : _cerrarServicio,
              icon: const Icon(Icons.pending_outlined),
              label: _procesando ? const Text('Generando PDF...') : const Text('Generar PDF y cerrar servicio'),
            ),
          ],
        ),
      ),
    );
  }
}
