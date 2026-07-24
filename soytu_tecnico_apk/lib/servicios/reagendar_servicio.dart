import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soytu_core/soytu_core.dart';

import '../providers/providers.dart';

const _indigo = Color(0xFF1A237E);

/// Deja al técnico elegir una fecha futura para atender el servicio (por
/// petición del cliente, o porque no se pudo el día original). El servicio
/// vuelve al estado "asignado" con `fechaProgramada` para que quede visible
/// en su lista y en el panel de administración.
Future<void> reagendarServicio(
    BuildContext context, WidgetRef ref, ServicioAsignado s) async {
  final ahora = DateTime.now();
  final fecha = await showDatePicker(
    context: context,
    initialDate: ahora.add(const Duration(days: 1)),
    firstDate: ahora,
    lastDate: ahora.add(const Duration(days: 180)),
    helpText: 'Elige la nueva fecha del servicio',
    cancelText: 'Cancelar',
    confirmText: 'Reagendar',
    builder: (c, child) => Theme(
      data: Theme.of(c).copyWith(colorScheme: Theme.of(c).colorScheme.copyWith(primary: _indigo)),
      child: child!,
    ),
  );
  if (fecha == null) return;

  final motivo = await showDialog<String>(
    context: context,
    builder: (c) {
      final ctrl = TextEditingController();
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Motivo del cambio (opcional)'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
              hintText: 'Ej. el cliente lo pidió para el fin de semana',
              border: OutlineInputBorder()),
          maxLines: 2,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, ''), child: const Text('Omitir')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _indigo),
            onPressed: () => Navigator.pop(c, ctrl.text.trim()),
            child: const Text('Confirmar'),
          ),
        ],
      );
    },
  );
  if (motivo == null) return;

  await ref.read(servicioRepositoryProvider).reprogramar(s.id, fecha);

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          'Servicio reagendado para el ${fecha.day}/${fecha.month}/${fecha.year}.'),
    ));
  }
}
