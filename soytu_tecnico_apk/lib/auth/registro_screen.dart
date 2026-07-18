import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:soytu_core/soytu_core.dart';

import '../providers/providers.dart';
import '../services/alta_notificaciones.dart';
import '../widgets/captura_camara.dart';
import 'espera_aprobacion_screen.dart';

const _indigo = Color(0xFF1A237E);

/// Alta de técnico: datos básicos + selfie (fondo blanco) + foto de INE.
/// La verificación de que ambas fotos correspondan a la misma persona la
/// hace un administrador manualmente desde el panel — no hay matching
/// biométrico automático en esta versión.
class RegistroScreen extends ConsumerStatefulWidget {
  const RegistroScreen({super.key});

  @override
  ConsumerState<RegistroScreen> createState() => _RegistroScreenState();
}

class _RegistroScreenState extends ConsumerState<RegistroScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();
  final _contrasenaCtrl = TextEditingController();

  Uint8List? _selfie;
  Uint8List? _ine;
  bool _cargando = false;
  String? _error;

  Future<void> _registrar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selfie == null || _ine == null) {
      setState(() => _error = 'Debes tomar la selfie y la foto de tu INE para continuar.');
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final auth = ref.read(authServiceProvider);
      final credencial = await auth.registrar(_correoCtrl.text.trim(), _contrasenaCtrl.text);
      final uid = credencial.user!.uid;

      final notificationService = ref.read(notificationServiceProvider);
      await notificationService.solicitarPermiso();
      final fcmToken = await notificationService.obtenerToken();

      final storage = ref.read(storageServiceProvider);
      final selfieUrl = await storage.subirFotoTecnico(uid, 'selfie.jpg', _selfie!);
      final ineUrl = await storage.subirFotoTecnico(uid, 'ine.jpg', _ine!);

      await ref.read(tecnicoRepositoryProvider).registrar(Tecnico(
            uid: uid,
            nombre: _nombreCtrl.text.trim(),
            telefono: _telefonoCtrl.text.trim(),
            correo: _correoCtrl.text.trim(),
            estadoAprobacion: EstadoAprobacion.pendiente,
            selfieUrl: selfieUrl,
            ineUrl: ineUrl,
            fcmToken: fcmToken,
            fechaRegistro: DateTime.now(),
          ));

      if (!mounted) return;
      await AltaNotificaciones.solicitudEnviada(context, nombreTecnico: _nombreCtrl.text.trim());

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const EsperaAprobacionScreen()),
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'No se pudo completar el registro.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _indigo,
        foregroundColor: Colors.white,
        title: const Text('Alta de técnico'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre completo', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telefonoCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Teléfono', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _correoCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Correo', border: OutlineInputBorder()),
                  validator: (v) => (v == null || !v.contains('@')) ? 'Correo inválido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _contrasenaCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Contraseña', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.length < 6) ? 'Mínimo 6 caracteres' : null,
                ),
                const SizedBox(height: 20),
                const Text('Verificación de identidad',
                    style: TextStyle(fontWeight: FontWeight.bold, color: _indigo)),
                const Text(
                  'Toma tu selfie con fondo blanco y bien iluminada, y una foto legible de tu INE. '
                  'Un administrador de SOYTU comparará ambas fotos manualmente antes de aprobar tu alta.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF4A4F63)),
                ),
                const SizedBox(height: 14),
                CapturaCamara(
                  etiqueta: 'Selfie (fondo blanco)',
                  obligatoria: true,
                  onCapturada: (bytes) => _selfie = bytes,
                ),
                const SizedBox(height: 14),
                CapturaCamara(
                  etiqueta: 'Foto de tu INE',
                  obligatoria: true,
                  onCapturada: (bytes) => _ine = bytes,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _indigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _cargando ? null : _registrar,
                  child: _cargando
                      ? const SizedBox(
                          height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Enviar a revisión'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
