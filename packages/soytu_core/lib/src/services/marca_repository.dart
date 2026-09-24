import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show consolidateHttpClientResponseBytes;
import 'package:flutter/services.dart' show rootBundle;

import '../models/marca_servicio.dart';

/// Resuelve la marca de un servicio a partir de su `empresaId`.
/// Lee primero `marcasPublicas/{id}` (la mantiene una Cloud Function) y,
/// si no existe, `empresas_licencia/{id}`. Nunca lanza error: si algo
/// falla, regresa la mejor marca posible para no frenar el cierre.
class MarcaRepository {
  static const _logoVmxAsset = 'assets/images/vmxlab_logo.png';
  static final Map<String, MarcaServicio> _cache = {};

  static Future<MarcaServicio> cargar(String? empresaId) async {
    if (empresaId == null || empresaId.isEmpty) return MarcaServicio.soytu;
    if (_cache.containsKey(empresaId)) return _cache[empresaId]!;

    final db = FirebaseFirestore.instance;
    Map<String, dynamic>? datos;
    for (final ruta in ['marcasPublicas', 'empresas_licencia']) {
      try {
        final d = await db.collection(ruta).doc(empresaId).get();
        if (d.exists) {
          final m = d.data()!;
          // empresas_licencia guarda los colores dentro de "branding"
          final b = (m['branding'] as Map?)?.cast<String, dynamic>() ?? {};
          datos = {
            'nombre': m['nombreMostrado'] ?? b['nombreMostrado'] ?? m['nombre'],
            'colorPrimario': m['colorPrimario'] ?? b['colorPrimario'],
            'colorSecundario': m['colorSecundario'] ?? b['colorSecundario'],
            'logoUrl': m['logoUrl'] ?? b['logoUrl'],
            'telefono': m['telefono'] ?? b['telefono'],
          };
          break;
        }
      } catch (_) {}
    }

    final nombre = (datos?['nombre'] as String?)?.trim();
    final esVmx = RegExp('vmx', caseSensitive: false).hasMatch(nombre ?? '');
    // Colores por defecto del formulario de marca = índigo SOYTU; se ignoran.
    int? color(String k) {
      final c = MarcaServicio.colorDesdeHex(datos?[k] as String?);
      if (c == 0xFF1A237E || c == 0xFF3B4CCA) return null;
      return c;
    }

    Uint8List? logo;
    final url = (datos?['logoUrl'] as String?)?.trim();
    if (url != null && url.startsWith('http')) logo = await _descargar(url);
    if (logo == null && esVmx) {
      try {
        logo = (await rootBundle.load(_logoVmxAsset)).buffer.asUint8List();
      } catch (_) {}
    }

    final tel = (datos?['telefono'] as String?)?.trim();
    final nombreFinal = (nombre == null || nombre.isEmpty) ? 'Servicio técnico' : nombre;
    final marca = MarcaServicio(
      empresaId: empresaId,
      nombre: nombreFinal,
      lema: 'SERVICIO TÉCNICO',
      colorPrimario: color('colorPrimario') ?? (esVmx ? 0xFF033649 : 0xFF263238),
      colorSecundario: color('colorSecundario') ?? (esVmx ? 0xFF176B87 : 0xFF455A64),
      logoBytes: logo,
      pie: tel == null || tel.isEmpty
          ? '$nombreFinal  ·  Estado de México / CDMX'
          : '$nombreFinal  ·  Estado de México / CDMX  ·  Contacto: $tel',
    );
    _cache[empresaId] = marca;
    return marca;
  }

  static Future<Uint8List?> _descargar(String url) async {
    try {
      final cliente = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final req = await cliente.getUrl(Uri.parse(url));
      final res = await req.close().timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final bytes = await consolidateHttpClientResponseBytes(res);
      cliente.close();
      return bytes;
    } catch (_) {
      return null;
    }
  }
}
