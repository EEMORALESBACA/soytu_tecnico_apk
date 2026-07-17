import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

const _indigo = Color(0xFF1A237E);

/// Botón que abre SIEMPRE la cámara del dispositivo (nunca la galería) y
/// muestra una miniatura de la foto tomada. Usado en alta de técnico
/// (selfie/INE) y en el formulario de servicio (equipo/placa/falla).
class CapturaCamara extends StatefulWidget {
  const CapturaCamara({
    super.key,
    required this.etiqueta,
    required this.onCapturada,
    this.bytesIniciales,
    this.obligatoria = false,
  });

  final String etiqueta;
  final ValueChanged<Uint8List> onCapturada;
  final Uint8List? bytesIniciales;
  final bool obligatoria;

  @override
  State<CapturaCamara> createState() => _CapturaCamaraState();
}

class _CapturaCamaraState extends State<CapturaCamara> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = widget.bytesIniciales;
  }

  Future<void> _tomarFoto() async {
    final picker = ImagePicker();
    final archivo = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (archivo == null) return;
    final bytes = await archivo.readAsBytes();
    setState(() => _bytes = bytes);
    widget.onCapturada(bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.obligatoria ? '${widget.etiqueta} *' : widget.etiqueta,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: _tomarFoto,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 140,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFF4F5FA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFD8DBE8)),
            ),
            child: _bytes == null
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.camera_alt_outlined, color: _indigo, size: 32),
                        SizedBox(height: 6),
                        Text('Tomar foto', style: TextStyle(color: _indigo)),
                      ],
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(_bytes!, fit: BoxFit.cover),
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.black.withValues(alpha: 0.55),
                            child: const Icon(Icons.refresh, color: Colors.white, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
