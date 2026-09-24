import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:soytu_core/soytu_core.dart';

const _indigo = Color(0xFF1A237E);

/// Guarda una foto tomada con la cámara en la galería del celular
/// (álbum "SOYTU Servicios"). Nunca detiene el flujo si falla.
Future<void> guardarEnGaleria(Uint8List bytes) async {
  try {
    if (!await Gal.hasAccess(toAlbum: true)) {
      await Gal.requestAccess(toAlbum: true);
    }
    await Gal.putImageBytes(bytes, album: 'SOYTU Servicios');
  } catch (_) {}
}

/// Tarjeta "Fotos del servicio": el técnico toma fotos (se guardan también
/// en su galería) o las sube desde la galería. Se suben al momento a
/// Storage y quedan en `servicios/{id}.fotosServicio` para el panel.
class FotosServicioCard extends StatefulWidget {
  const FotosServicioCard({super.key, required this.servicioId, this.soloLectura = false});

  final String servicioId;
  final bool soloLectura;

  @override
  State<FotosServicioCard> createState() => _FotosServicioCardState();
}

class _FotosServicioCardState extends State<FotosServicioCard> {
  int _subiendo = 0;

  DocumentReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance.collection('servicios').doc(widget.servicioId);

  Future<void> _subir(Uint8List bytes, String origen) async {
    setState(() => _subiendo++);
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final url = await StorageService().subirFotoServicio(widget.servicioId, 'foto_$ts.jpg', bytes);
      await _ref.update({
        'fotosServicio': FieldValue.arrayUnion([
          {'url': url, 'fecha': DateTime.now().toIso8601String(), 'origen': origen}
        ])
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo subir la foto: $e')));
      }
    } finally {
      if (mounted) setState(() => _subiendo--);
    }
  }

  Future<void> _tomarFoto() async {
    final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 1600);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    await guardarEnGaleria(bytes);
    await _subir(bytes, 'camara');
  }

  Future<void> _desdeGaleria() async {
    final fotos = await ImagePicker().pickMultiImage(imageQuality: 85, maxWidth: 1600);
    for (final x in fotos) {
      await _subir(await x.readAsBytes(), 'galeria');
    }
  }

  void _ver(String url) => showDialog(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(10),
          child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD8DBE8)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _ref.snapshots(),
        builder: (context, snap) {
          final lista = (snap.data?.data()?['fotosServicio'] as List?) ?? const [];
          final urls = lista
              .map((e) => e is Map ? e['url'] as String? : null)
              .whereType<String>()
              .toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Text('FOTOS DEL SERVICIO',
                    style: TextStyle(color: _indigo, fontWeight: FontWeight.bold, letterSpacing: 1, fontSize: 12)),
                const Spacer(),
                if (_subiendo > 0) ...[
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 6),
                  Text('Subiendo $_subiendo…', style: const TextStyle(fontSize: 12)),
                ] else
                  Text('${urls.length}', style: const TextStyle(fontSize: 12, color: Color(0xFF4A4F63))),
              ]),
              const SizedBox(height: 10),
              if (urls.isNotEmpty)
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  children: urls
                      .map((u) => InkWell(
                            onTap: () => _ver(u),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(u, fit: BoxFit.cover),
                            ),
                          ))
                      .toList(),
                ),
              if (urls.isEmpty)
                const Text('Aún no hay fotos de este servicio.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF4A4F63))),
              if (!widget.soloLectura) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: _indigo, foregroundColor: Colors.white),
                      onPressed: _tomarFoto,
                      icon: const Icon(Icons.photo_camera),
                      label: const Text('Tomar foto'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _desdeGaleria,
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Galería'),
                    ),
                  ),
                ]),
              ],
            ],
          );
        },
      ),
    );
  }
}
