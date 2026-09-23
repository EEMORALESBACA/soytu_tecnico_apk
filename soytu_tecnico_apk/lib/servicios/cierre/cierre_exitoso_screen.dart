import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:soytu_core/soytu_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/reincidencia_aviso.dart';
import 'servicios_home_navigator.dart';

/// Pantalla que aparece en cuanto se cierra un servicio como completado:
/// muestra la hoja de servicio (con la marca del servicio: SOYTU o VMX Lab)
/// y deja a la mano la encuesta "¿Cómo te atendí?".
class CierreExitosoScreen extends StatefulWidget {
  const CierreExitosoScreen({
    super.key,
    required this.servicio,
    required this.marca,
    required this.pdfBytes,
    required this.pdfUrl,
    this.reincidencias = 0,
  });

  final ServicioAsignado servicio;
  final MarcaServicio marca;
  final Uint8List pdfBytes;
  final String? pdfUrl;
  final int reincidencias;

  @override
  State<CierreExitosoScreen> createState() => _CierreExitosoScreenState();
}

class _CierreExitosoScreenState extends State<CierreExitosoScreen> {
  bool _encuestaAbierta = false;

  Color get _primario => Color(widget.marca.colorPrimario);

  @override
  void initState() {
    super.initState();
    if (widget.reincidencias > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) mostrarAvisoReincidencia(context, widget.reincidencias);
      });
    }
  }

  String _liga(String modo) =>
      'https://soytu.com.mx/encuesta.html?servicio=${widget.servicio.id}&modo=$modo';

  String _telWa(String tel) {
    var t = tel.replaceAll(RegExp(r'[^0-9]'), '');
    if (t.length == 10) return '521$t';
    if (t.length == 12 && t.startsWith('52')) return '521${t.substring(2)}';
    return t;
  }

  void _aviso(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _encuestaEnEsteCelular() async {
    final uri = Uri.parse(_liga('presencial'));
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {}
    if (!ok) {
      try {
        ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
    if (!mounted) return;
    if (ok) {
      setState(() => _encuestaAbierta = true);
    } else {
      _aviso('No se pudo abrir la encuesta. Revisa que el celular tenga internet.');
    }
  }

  Future<void> _enviarWhatsApp() async {
    final tel = widget.servicio.clienteTelefono;
    if (tel == null || tel.trim().isEmpty) {
      _aviso('Este servicio no tiene teléfono del cliente.');
      return;
    }
    final s = widget.servicio;
    final texto = 'Hola ${s.clienteNombre}, su servicio ${s.folio} con ${widget.marca.nombre} '
        'quedó COMPLETADO ✅\n'
        '${widget.pdfUrl != null ? '📄 Su hoja de servicio: ${widget.pdfUrl}\n' : ''}'
        '⭐ ¿Cómo lo atendí? Califique mi servicio en 1 minuto: ${_liga('whatsapp')}';
    final uri = Uri.parse('https://wa.me/${_telWa(tel)}?text=${Uri.encodeComponent(texto)}');
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && mounted) _aviso('No se pudo abrir WhatsApp en este celular.');
  }

  Future<void> _compartirPdf() async {
    try {
      final dir = await getTemporaryDirectory();
      final archivo = File('${dir.path}/HojaServicio_${widget.servicio.folio}.pdf');
      await archivo.writeAsBytes(widget.pdfBytes);
      await Share.shareXFiles(
        [XFile(archivo.path, mimeType: 'application/pdf')],
        text: '${widget.marca.nombre} — Hoja de servicio ${widget.servicio.folio}.',
      );
    } catch (e) {
      if (mounted) _aviso('No se pudo compartir el PDF: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: _primario,
          foregroundColor: Colors.white,
          title: Text('Servicio ${widget.servicio.folio} completado ✅',
              style: const TextStyle(fontSize: 17)),
        ),
        body: Column(
          children: [
            // Hoja de servicio del cliente, tal como se le entrega.
            Expanded(
              child: PdfPreview(
                build: (_) async => widget.pdfBytes,
                useActions: false,
                canChangeOrientation: false,
                canChangePageFormat: false,
                canDebug: false,
                pdfFileName: 'HojaServicio_${widget.servicio.folio}.pdf',
              ),
            ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  boxShadow: const [BoxShadow(blurRadius: 8, color: Color(0x22000000))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _primario,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      onPressed: _encuestaEnEsteCelular,
                      icon: Icon(_encuestaAbierta ? Icons.check_circle : Icons.star_rate_rounded),
                      label: Text(
                        _encuestaAbierta
                            ? 'Encuesta abierta — volver a abrir'
                            : 'Que el cliente califique aquí',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _enviarWhatsApp,
                          icon: const Icon(Icons.chat),
                          label: const Text('WhatsApp'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _compartirPdf,
                          icon: const Icon(Icons.share),
                          label: const Text('Compartir PDF'),
                        ),
                      ),
                    ]),
                    TextButton(
                      onPressed: () => volverAlInicioDeServicios(context),
                      child: const Text('Terminar y volver a mis servicios'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
