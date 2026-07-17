import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../providers/providers.dart';
import 'registro_screen.dart';

const _indigo = Color(0xFF1A237E);

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _correoCtrl = TextEditingController();
  final _contrasenaCtrl = TextEditingController();
  bool _cargando = false;
  String? _error;

  Future<void> _iniciarSesion() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await ref
          .read(authServiceProvider)
          .iniciarSesion(_correoCtrl.text.trim(), _contrasenaCtrl.text);
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'No se pudo iniciar sesión.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('SOYTU',
                      style: TextStyle(
                          color: _indigo, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  const Text('CREANDO CONEXIONES',
                      style: TextStyle(color: Colors.amber, fontSize: 11, letterSpacing: 3)),
                  const SizedBox(height: 32),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Acceso Técnico', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 16),
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
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _cargando ? null : _iniciarSesion,
                      child: _cargando
                          ? const SizedBox(
                              height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Entrar'),
                    ),
                  ),
                  TextButton(
                    onPressed: _cargando
                        ? null
                        : () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const RegistroScreen())),
                    child: const Text('¿Eres técnico nuevo? Regístrate'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
