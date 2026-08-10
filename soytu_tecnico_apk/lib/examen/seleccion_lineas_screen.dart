import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soytu_core/soytu_core.dart';

import '../providers/providers.dart';

const _indigo = Color(0xFF1A237E);
const _gold = Color(0xFFF2B824);

/// Se muestra una sola vez, justo después del registro, antes de mandar
/// al técnico a presentar el examen de certificación de cada línea que
/// elija. No se puede saltar: hay que marcar al menos una línea.
class SeleccionLineasScreen extends ConsumerStatefulWidget {
  const SeleccionLineasScreen({super.key, required this.tecnico});

  final Tecnico tecnico;

  @override
  ConsumerState<SeleccionLineasScreen> createState() => _SeleccionLineasScreenState();
}

class _SeleccionLineasScreenState extends ConsumerState<SeleccionLineasScreen> {
  final Set<LineaNegocio> _seleccion = {};
  bool _guardando = false;
  String? _error;

  Future<void> _continuar() async {
    if (_seleccion.isEmpty) {
      setState(() => _error = 'Marca al menos una línea de negocio para continuar.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await ref.read(tecnicoRepositoryProvider).guardarLineasNegocio(
            widget.tecnico.uid,
            _seleccion.map((l) => l.id).toList(),
          );
      // El stream de tecnicoActualProvider se actualiza solo y _RaizApp
      // navega automáticamente a la pantalla de exámenes pendientes.
    } catch (e) {
      setState(() {
        _error = 'No se pudo guardar: $e';
        _guardando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5FB),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(26),
              constraints: const BoxConstraints(maxWidth: 460),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 20, offset: Offset(0, 8))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: _indigo, borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.handyman_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 16),
                  const Text('¿Qué líneas de negocio reparas?',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _indigo)),
                  const SizedBox(height: 8),
                  const Text(
                    'Marca todas las que apliquen. Vas a presentar un examen corto de cada una '
                    'antes de que tu cuenta quede autorizada — así garantizamos la calidad de nuestros técnicos.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF6B7080), height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  ...LineaNegocio.values.map((linea) => _tarjetaLinea(linea)),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12.5)),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _guardando ? null : _continuar,
                      child: _guardando
                          ? const SizedBox(
                              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Continuar al examen', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tarjetaLinea(LineaNegocio linea) {
    final activo = _seleccion.contains(linea);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() {
          if (activo) {
            _seleccion.remove(linea);
          } else {
            _seleccion.add(linea);
          }
        }),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: activo ? _indigo.withValues(alpha: 0.06) : const Color(0xFFF7F8FC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: activo ? _indigo : const Color(0xFFE3E5F0), width: activo ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Icon(activo ? Icons.check_circle : Icons.circle_outlined,
                  color: activo ? _gold : const Color(0xFFB0B4C4)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(linea.etiqueta,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: activo ? _indigo : const Color(0xFF4A4F63))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
