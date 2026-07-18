import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// ══════════════════════════════════════════════════════════════
/// SOYTU — Notificaciones del alta de técnico
/// ──────────────────────────────────────────────────────────────
/// Cómo integrarlo en tu pantalla "Alta de técnico":
///
/// 1. Guarda este archivo en lib/services/alta_notificaciones.dart
/// 2. En tu pantalla de alta, importa:
///      import '../services/alta_notificaciones.dart';
/// 3. Justo DESPUÉS de que la solicitud se guardó con éxito en
///    Firestore (dentro del .then / await del botón
///    "Enviar a revisión"), agrega UNA línea:
///
///      await AltaNotificaciones.solicitudEnviada(context,
///          nombreTecnico: nombre);   // la variable de tu formulario
///
/// Eso hace las dos cosas: te avisa por WhatsApp al 2201600812
/// y le muestra al técnico el pop-up de confirmación.
/// ══════════════════════════════════════════════════════════════
class AltaNotificaciones {
  /// WhatsApp del administrador SOYTU (Eduardo).
  static const String adminWhatsApp = '2201600812';

  static Future<void> solicitudEnviada(
    BuildContext context, {
    required String nombreTecnico,
  }) async {
    // 1) Aviso por WhatsApp al administrador (no bloquea si falla).
    await _avisarAdmin(nombreTecnico);

    // 2) Pop-up de éxito para el técnico.
    if (!context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.check_circle,
            color: Color(0xFF2E7D32), size: 56),
        title: const Text('¡Solicitud enviada con éxito!'),
        content: const Text(
          'Tu solicitud de alta fue recibida. Un administrador de SOYTU '
          'revisará tu información y te avisará por WhatsApp cuando tu '
          'alta esté lista.',
          textAlign: TextAlign.center,
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF3B4CCA),
                minimumSize: const Size.fromHeight(48)),
            onPressed: () => Navigator.pop(c),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  /// Envía el aviso al WhatsApp del admin vía Meta Cloud API.
  /// Lee token y phoneNumberId de Firestore: config/whatsapp.
  static Future<bool> _avisarAdmin(String nombreTecnico) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('whatsapp')
          .get();
      final token = (doc.data()?['token'] ?? '').toString();
      final phoneId = (doc.data()?['phoneNumberId'] ?? '').toString();
      if (token.isEmpty || phoneId.isEmpty) return false;

      final r = await http.post(
        Uri.parse('https://graph.facebook.com/v20.0/$phoneId/messages'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'messaging_product': 'whatsapp',
          'to': '521$adminWhatsApp',
          'type': 'text',
          'text': {
            'body': '🔔 SOYTU Admin: nueva solicitud de alta de técnico '
                'de "$nombreTecnico". Entra al panel para revisarla y '
                'aprobarla: https://soytu.com.mx/soytu/admin-soytu.html'
          },
        }),
      );
      return r.statusCode >= 200 && r.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}
