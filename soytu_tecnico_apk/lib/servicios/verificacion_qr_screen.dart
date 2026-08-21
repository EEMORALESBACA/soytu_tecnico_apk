import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soytu_core/soytu_core.dart';

import '../providers/providers.dart';
import 'formulario_servicio_screen.dart';

const _indigo = Color(0xFF1A237E);
const _gold = Color(0xFFF2B824);
const _verde = Color(0xFF2E7D32);

/// Paso OBLIGATORIO del protocolo SOYTU: antes de tocar el equipo del
/// cliente, el técnico debe mostrarle su verificación (QR que confirma su
/// identidad y que pertenece a la red SOYTU). No hay botón para saltarla —
/// es la única puerta hacia el formulario de servicio.
class VerificacionQrScreen extends ConsumerWidget {
  const VerificacionQrScreen({super.key, required this.servicio});

  final ServicioAsignado servicio;

  static const _urlBase = 'https://soytu.com.mx/soytu/verificar-tecnico.html';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tecnico = ref.watch(tecnicoActualProvider).value;
    final uid = tecnico?.uid ?? servicio.technicianId ?? '';
    final urlVerificacion = '$_urlBase?id=$uid';
    final urlQr =
        'https://api.qrserver.com/v1/create-qr-code/?size=340x340&margin=8&data=${Uri.encodeComponent(urlVerificacion)}';

    return PopScope(
      canPop: false, // No se puede regresar con el botón atrás: es obligatoria.
      child: Scaffold(
        backgroundColor: _indigo,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 12),
                const Icon(Icons.verified_user_outlined, color: _gold, size: 40),
                const SizedBox(height: 10),
                const Text('Verificación obligatoria',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text(
                  'Antes de iniciar el servicio, muéstrale este código al cliente '
                  'para que confirme que perteneces a la red SOYTU.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFC9CEF0), fontSize: 13),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                  child: Image.network(
                    urlQr,
                    width: 260,
                    height: 260,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const SizedBox(
                        width: 260,
                        height: 260,
                        child: Center(child: CircularProgressIndicator(color: _indigo)),
                      );
                    },
                    errorBuilder: (context, error, stack) => const SizedBox(
                      width: 260,
                      height: 260,
                      child: Center(
                        child: Text('Sin conexión para mostrar el QR.\nIntenta de nuevo con datos o WiFi.',
                            textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(tecnico?.nombre ?? 'Técnico SOYTU',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                const Text('Técnico de campo certificado',
                    style: TextStyle(color: _gold, fontSize: 12, fontWeight: FontWeight.w600)),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _verde,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => FormularioServicioScreen(servicio: servicio)),
                    ),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Ya se lo mostré al cliente',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Este paso es parte del protocolo SOYTU y no se puede omitir.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF8890C0), fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
