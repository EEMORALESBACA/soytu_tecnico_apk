import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'lista_servicios_screen.dart';
import 'productividad_screen.dart';
import 'perfil_screen.dart';

const _indigo = Color(0xFF1A237E);

/// Pantalla principal del técnico con tres pestañas:
/// 🧾 Mis servicios, 📊 Mi productividad y 👤 Mi perfil.
class HomeTabs extends StatefulWidget {
  const HomeTabs({super.key});

  @override
  State<HomeTabs> createState() => _HomeTabsState();
}

class _HomeTabsState extends State<HomeTabs> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revisarSiDebeCambiarContrasena());
  }

  Future<void> _revisarSiDebeCambiarContrasena() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('tecnicos').doc(uid).get();
      if (doc.exists && doc.data()?['debeCambiarContrasena'] == true) {
        if (!mounted) return;
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const _DialogoCambiarContrasenaObligatorio(),
        );
      }
    } catch (_) {
      // Si falla la revisión (sin internet, etc.), no bloqueamos al técnico;
      // se vuelve a intentar la próxima vez que abra la app.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [
          ListaServiciosScreen(),
          ProductividadScreen(),
          PerfilScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        indicatorColor: _indigo.withValues(alpha: 0.15),
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.build_circle_outlined),
            selectedIcon: Icon(Icons.build_circle, color: _indigo),
            label: 'Servicios',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights, color: _indigo),
            label: 'Productividad',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: _indigo),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}

/// Aviso obligatorio (no se puede cerrar sin completar) que pide al técnico
/// su contraseña actual y una nueva, cuando el administrador SOYTU marcó
/// "Restablecer contraseña" desde el panel de admin.
class _DialogoCambiarContrasenaObligatorio extends StatefulWidget {
  const _DialogoCambiarContrasenaObligatorio();

  @override
  State<_DialogoCambiarContrasenaObligatorio> createState() => _DialogoCambiarContrasenaObligatorioState();
}

class _DialogoCambiarContrasenaObligatorioState extends State<_DialogoCambiarContrasenaObligatorio> {
  final _actualCtrl = TextEditingController();
  final _nuevaCtrl = TextEditingController();
  final _confirmarCtrl = TextEditingController();
  bool _procesando = false;
  String? _error;

  @override
  void dispose() {
    _actualCtrl.dispose();
    _nuevaCtrl.dispose();
    _confirmarCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    setState(() => _error = null);
    final actual = _actualCtrl.text;
    final nueva = _nuevaCtrl.text;
    final confirmar = _confirmarCtrl.text;

    if (actual.isEmpty) {
      setState(() => _error = 'Escribe tu contraseña actual.');
      return;
    }
    if (nueva.length < 6) {
      setState(() => _error = 'La contraseña nueva debe tener al menos 6 caracteres.');
      return;
    }
    if (nueva != confirmar) {
      setState(() => _error = 'La confirmación no coincide con la contraseña nueva.');
      return;
    }

    setState(() => _procesando = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        throw FirebaseAuthException(code: 'no-user', message: 'No hay sesión activa.');
      }
      final credencial = EmailAuthProvider.credential(email: user.email!, password: actual);
      await user.reauthenticateWithCredential(credencial);
      await user.updatePassword(nueva);
      await FirebaseFirestore.instance
          .collection('tecnicos')
          .doc(user.uid)
          .update({'debeCambiarContrasena': false});
      if (mounted) Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      String msj;
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
          msj = 'Tu contraseña actual no es correcta.';
          break;
        case 'weak-password':
          msj = 'Esa contraseña es demasiado débil. Usa una más segura.';
          break;
        case 'too-many-requests':
          msj = 'Demasiados intentos. Espera unos minutos e inténtalo de nuevo.';
          break;
        default:
          msj = 'No se pudo cambiar la contraseña: ${e.message ?? e.code}';
      }
      setState(() => _error = msj);
    } catch (e) {
      setState(() => _error = 'Ocurrió un error: $e');
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Restablece tu contraseña'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SOYTU te pidió restablecer tu contraseña. Escribe tu contraseña '
                'actual y elige una nueva para seguir usando la app.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _actualCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Contraseña actual'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _nuevaCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Contraseña nueva'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _confirmarCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirmar contraseña nueva'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Color(0xFFC62828), fontSize: 12.5)),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _indigo),
            onPressed: _procesando ? null : _confirmar,
            child: _procesando
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Guardar nueva contraseña'),
          ),
        ],
      ),
    );
  }
}
