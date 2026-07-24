import 'package:flutter/material.dart';

const _indigo = Color(0xFF1A237E);

/// Aviso visible al técnico cuando el equipo (mismo número de serie) ya fue
/// reparado antes por SOYTU — ayuda a detectar fallas recurrentes en sitio.
Future<void> mostrarAvisoReincidencia(BuildContext context, int veces) {
  return showDialog(
    context: context,
    builder: (c) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      icon: const Icon(Icons.history, color: Color(0xFFF9A825), size: 40),
      title: const Text('Equipo reincidente'),
      content: Text(
        'Este número de serie ya fue reparado $veces ${veces == 1 ? "vez" : "veces"} '
        'anteriormente por SOYTU. Se registró como reincidencia para dar seguimiento.',
        textAlign: TextAlign.center,
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _indigo, minimumSize: const Size.fromHeight(46)),
          onPressed: () => Navigator.pop(c),
          child: const Text('Entendido'),
        ),
      ],
    ),
  );
}
