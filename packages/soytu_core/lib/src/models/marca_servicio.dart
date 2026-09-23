import 'dart:typed_data';

/// Identidad visual con la que se emite la hoja de servicio y la encuesta.
/// SOYTU para servicios propios; la empresa que renta la plataforma
/// (p. ej. VMX Lab) cuando el servicio trae `empresaId`.
class MarcaServicio {
  final String? empresaId;
  final String nombre;
  final String lema;
  final int colorPrimario; // ARGB, ej. 0xFF033649
  final int colorSecundario;
  final Uint8List? logoBytes;
  final String pie; // Línea de contacto al pie del PDF

  const MarcaServicio({
    this.empresaId,
    required this.nombre,
    this.lema = '',
    required this.colorPrimario,
    required this.colorSecundario,
    this.logoBytes,
    required this.pie,
  });

  bool get esSoytu => empresaId == null;

  static const soytu = MarcaServicio(
    nombre: 'SOYTU',
    lema: 'CREANDO CONEXIONES',
    colorPrimario: 0xFF1A237E,
    colorSecundario: 0xFF3949AB,
    pie: 'soytu.com.mx  ·  Estado de México / CDMX  ·  Contacto: 56 5359 6451',
  );

  /// '#033649' → 0xFF033649. Devuelve null si no es un color válido.
  static int? colorDesdeHex(String? hex) {
    if (hex == null) return null;
    var h = hex.replaceAll('#', '').trim();
    if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
    if (h.length != 6) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : 0xFF000000 | v;
  }
}
