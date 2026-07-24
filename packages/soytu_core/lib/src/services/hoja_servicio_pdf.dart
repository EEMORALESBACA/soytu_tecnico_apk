import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/orden_servicio.dart';

/// ============================================================
///  SOYTU — Creando Conexiones
///  Generador de Hoja de Servicio (PDF corporativo)
///  Semáforo: Completado 🟢 · Pendiente 🟡 · Cancelado 🔴
/// ============================================================
class HojaServicioPdf {
  // ------- Paleta corporativa SOYTU -------
  static const _indigo = PdfColor.fromInt(0xFF1A237E); // Índigo SOYTU
  static const _indigoLight = PdfColor.fromInt(0xFF3949AB);
  static const _grisFondo = PdfColor.fromInt(0xFFF4F5FA);
  static const _grisLinea = PdfColor.fromInt(0xFFD8DBE8);
  static const _grisTexto = PdfColor.fromInt(0xFF4A4F63);
  static const _verde = PdfColor.fromInt(0xFF2E7D32);
  static const _amarillo = PdfColor.fromInt(0xFFF9A825);
  static const _rojo = PdfColor.fromInt(0xFFC62828);

  /// Logo opcional (PNG). Si es null se dibuja el logotipo tipográfico.
  final Uint8List? logoBytes;

  HojaServicioPdf({this.logoBytes});

  PdfColor _colorEstado(EstadoServicio e) => switch (e) {
        EstadoServicio.completado => _verde,
        EstadoServicio.pendiente => _amarillo,
        EstadoServicio.cancelado => _rojo,
      };

  /// Genera el PDF y devuelve los bytes listos para guardar,
  /// compartir por WhatsApp o adjuntar en correo.
  Future<Uint8List> generar(OrdenServicio orden) async {
    final doc = pw.Document(
      title: 'Hoja de Servicio ${orden.folio}',
      author: 'SOYTU — Creando Conexiones',
      creator: 'SOYTU App Técnico',
    );

    final base = await PdfGoogleFonts.interRegular();
    final bold = await PdfGoogleFonts.interBold();
    final semi = await PdfGoogleFonts.interSemiBold();
    final theme = pw.ThemeData.withFont(base: base, bold: bold);

    final fmtFecha =
        DateFormat("d 'de' MMMM 'de' y — HH:mm 'hrs'", 'es_MX');
    final colorEstado = _colorEstado(orden.estado);

    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(36, 130, 36, 60),
        header: (ctx) => _header(orden, colorEstado, semi, fmtFecha),
        footer: (ctx) => _footer(ctx, orden),
        build: (ctx) => [
          pw.SizedBox(height: 6),

          // ---- Cliente y Técnico ----
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _card('CLIENTE', [
                  _dato('Nombre', orden.clienteNombre),
                  _dato('Dirección', orden.clienteDireccion),
                  if (orden.clienteTelefono != null)
                    _dato('Teléfono', orden.clienteTelefono!),
                  if (orden.clienteCorreo != null)
                    _dato('Correo', orden.clienteCorreo!),
                ]),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: _card('TÉCNICO ASIGNADO', [
                  _dato('Nombre', orden.tecnicoNombre),
                  _dato('ID Técnico', orden.tecnicoId),
                  if (orden.tecnicoTelefono != null)
                    _dato('Teléfono', orden.tecnicoTelefono!),
                  _dato('Verificado por', 'SOYTU · Identidad validada ✓'),
                ]),
              ),
            ],
          ),
          pw.SizedBox(height: 12),

          // ---- Equipo ----
          _card('EQUIPO', [
            pw.Row(children: [
              pw.Expanded(child: _dato('Tipo', orden.equipoTipo)),
              pw.Expanded(child: _dato('Marca', orden.marca)),
            ]),
            pw.Row(children: [
              pw.Expanded(child: _dato('Modelo', orden.modelo)),
              pw.Expanded(child: _dato('No. de serie', orden.numeroSerie)),
            ]),
            if (orden.tiposFalla.isNotEmpty)
              _dato('Tipo de falla',
                  orden.tiposFalla.map((f) => f.etiqueta).join('  ·  ')),
          ]),
          pw.SizedBox(height: 12),

          // ---- Diagnóstico ----
          _card('DIAGNÓSTICO DEL TÉCNICO', [
            _dato('Falla reportada', orden.fallaReportada),
            pw.SizedBox(height: 4),
            pw.Text('Descripción y condiciones del equipo',
                style: pw.TextStyle(
                    fontSize: 7.5,
                    color: _grisTexto,
                    letterSpacing: 0.4)),
            pw.SizedBox(height: 2),
            pw.Text(orden.descripcionTecnico,
                style: const pw.TextStyle(fontSize: 9.5, lineSpacing: 2)),
          ]),
          pw.SizedBox(height: 12),

          // ---- Voltajes ----
          if (orden.voltajes.isNotEmpty) ...[
            _card('LECTURAS DE VOLTAJE', [_tablaVoltajes(orden.voltajes)]),
            pw.SizedBox(height: 12),
          ],

          // ---- Refacciones utilizadas (completado) ----
          if (orden.estado == EstadoServicio.completado &&
              orden.refaccionesUsadas.isNotEmpty)
            _cardColor(
              'REFACCIONES UTILIZADAS',
              _verde,
              [
                pw.Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: orden.refaccionesUsadas
                      .map((r) => _chip(r, _verde))
                      .toList(),
                ),
              ],
            ),

          // ---- Refacciones faltantes (pendiente) ----
          if (orden.estado == EstadoServicio.pendiente) ...[
            _cardColor(
              'SERVICIO PENDIENTE — ${orden.motivoPendiente ?? "Refacción"}'
                  .toUpperCase(),
              _amarillo,
              [
                if (orden.refaccionesFaltantes.isNotEmpty)
                  pw.Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: orden.refaccionesFaltantes
                        .map((r) => _chip(r, _amarillo))
                        .toList(),
                  )
                else
                  pw.Text(
                      orden.motivoPendiente == 'Software'
                          ? 'Pendiente por actualización de software.'
                          : 'Pendiente por refacción (ver detalle con el técnico).',
                      style: const pw.TextStyle(fontSize: 9.5)),
              ],
            ),
            pw.SizedBox(height: 12),
          ],

          // ---- Motivo de cancelación ----
          if (orden.estado == EstadoServicio.cancelado) ...[
            _cardColor('MOTIVO DE CANCELACIÓN / RECHAZO', _rojo, [
              pw.Text(orden.motivoCancelacion ?? 'No especificado',
                  style: const pw.TextStyle(fontSize: 9.5, lineSpacing: 2)),
            ]),
            pw.SizedBox(height: 12),
          ],

          // ---- Evidencia fotográfica ----
          _card('EVIDENCIA FOTOGRÁFICA', [
            pw.Text(
                'Todas las imágenes fueron capturadas en sitio con la cámara '
                'del dispositivo del técnico. No se permite el uso de galería.',
                style: pw.TextStyle(
                    fontSize: 7, color: _grisTexto, fontStyle: pw.FontStyle.italic)),
            pw.SizedBox(height: 8),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _foto('Equipo', orden.fotoEquipo),
                pw.SizedBox(width: 10),
                _foto('Placa / No. serie', orden.fotoPlaca),
                pw.SizedBox(width: 10),
                _foto('Falla', orden.fotoFalla),
              ],
            ),
            if (orden.fotoEvidenciaCancelacion != null) ...[
              pw.SizedBox(height: 10),
              pw.Row(children: [
                _foto('Evidencia de visita (cliente ausente)',
                    orden.fotoEvidenciaCancelacion, ancho: 160),
              ]),
            ],
          ]),
          pw.SizedBox(height: 12),

          // ---- Monto + Firma ----
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (orden.montoCobrado != null)
                pw.Expanded(
                  child: _cardColor('SERVICIO DE CARGO', _indigo, [
                    pw.Text(
                      NumberFormat.currency(locale: 'es_MX', symbol: '\$')
                          .format(orden.montoCobrado),
                      style: pw.TextStyle(
                          font: bold, fontSize: 18, color: _indigo),
                    ),
                    pw.Text('Monto total cobrado al cliente (MXN)',
                        style: pw.TextStyle(fontSize: 7.5, color: _grisTexto)),
                  ]),
                ),
              if (orden.montoCobrado != null) pw.SizedBox(width: 12),
              pw.Expanded(
                child: _card('CONFORMIDAD DEL CLIENTE', [
                  pw.Container(
                    height: 60,
                    alignment: pw.Alignment.center,
                    child: orden.firmaCliente != null
                        ? pw.Image(pw.MemoryImage(orden.firmaCliente!),
                            fit: pw.BoxFit.contain)
                        : pw.Text('Sin firma registrada',
                            style: pw.TextStyle(
                                fontSize: 8, color: _grisTexto)),
                  ),
                  pw.Divider(color: _grisLinea, thickness: 0.7),
                  pw.Center(
                    child: pw.Text(orden.clienteNombre,
                        style: pw.TextStyle(font: semi, fontSize: 9)),
                  ),
                  pw.Center(
                    child: pw.Text('Nombre y firma de conformidad',
                        style: pw.TextStyle(fontSize: 7, color: _grisTexto)),
                  ),
                ]),
              ),
            ],
          ),
          pw.SizedBox(height: 14),

          // ---- Leyenda de garantía / confianza ----
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: _grisFondo,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(
              'Este documento es el respaldo oficial de su servicio y conserva '
              'validez ante SOYTU — Creando Conexiones. Nuestros técnicos están '
              'verificados con identificación oficial y validación biométrica. '
              'Conserve esta hoja para cualquier aclaración o seguimiento de garantía.',
              style: pw.TextStyle(
                  fontSize: 7.5, color: _grisTexto, lineSpacing: 2),
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  // ==================== COMPONENTES ====================

  pw.Widget _header(OrdenServicio o, PdfColor colorEstado, pw.Font semi,
      DateFormat fmtFecha) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Column(children: [
        // Banda índigo superior
        pw.Container(
          padding:
              const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: pw.BoxDecoration(
            gradient: const pw.LinearGradient(
              colors: [_indigo, _indigoLight],
              begin: pw.Alignment.centerLeft,
              end: pw.Alignment.centerRight,
            ),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Logo o logotipo tipográfico
              if (logoBytes != null)
                pw.Container(
                    height: 34,
                    child: pw.Image(pw.MemoryImage(logoBytes!)))
              else
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('SOYTU',
                        style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 20,
                            font: semi,
                            letterSpacing: 2)),
                    pw.Text('CREANDO CONEXIONES',
                        style: const pw.TextStyle(
                            color: PdfColor.fromInt(0xFFC5CAE9),
                            fontSize: 6.5,
                            letterSpacing: 3)),
                  ],
                ),
              pw.Spacer(),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('HOJA DE SERVICIO',
                      style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 11,
                          font: semi,
                          letterSpacing: 1.5)),
                  pw.SizedBox(height: 2),
                  pw.Text('Folio  ${o.folio}',
                      style: const pw.TextStyle(
                          color: PdfColor.fromInt(0xFFC5CAE9), fontSize: 9)),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 8),
        // Fecha + badge de estado
        pw.Row(children: [
          pw.Text(fmtFecha.format(o.fecha),
              style: const pw.TextStyle(fontSize: 8.5, color: _grisTexto)),
          pw.Spacer(),
          pw.Container(
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: pw.BoxDecoration(
              color: colorEstado,
              borderRadius: pw.BorderRadius.circular(20),
            ),
            child: pw.Text(o.estado.etiqueta,
                style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 8.5,
                    font: semi,
                    letterSpacing: 1)),
          ),
        ]),
      ]),
    );
  }

  pw.Widget _footer(pw.Context ctx, OrdenServicio o) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 8),
        decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: _grisLinea))),
        child: pw.Row(children: [
          pw.Text('soytu.com.mx  ·  Estado de México / CDMX',
              style: const pw.TextStyle(fontSize: 7, color: _grisTexto)),
          pw.Spacer(),
          pw.Text('Folio ${o.folio}  ·  Página ${ctx.pageNumber} de ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 7, color: _grisTexto)),
        ]),
      );

  pw.Widget _card(String titulo, List<pw.Widget> hijos) =>
      _cardColor(titulo, _indigo, hijos);

  pw.Widget _cardColor(
          String titulo, PdfColor acento, List<pw.Widget> hijos) =>
      pw.Container(
        width: double.infinity,
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          border: pw.Border.all(color: _grisLinea, width: 0.7),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: double.infinity,
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: pw.BoxDecoration(
                color: _grisFondo,
                borderRadius: const pw.BorderRadius.only(
                    topLeft: pw.Radius.circular(8),
                    topRight: pw.Radius.circular(8)),
                border: pw.Border(
                    left: pw.BorderSide(color: acento, width: 3)),
              ),
              child: pw.Text(titulo,
                  style: pw.TextStyle(
                      fontSize: 8.5,
                      color: acento,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 1.2)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(12),
              child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: hijos),
            ),
          ],
        ),
      );

  pw.Widget _dato(String etiqueta, String valor) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 5),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(etiqueta.toUpperCase(),
                style: pw.TextStyle(
                    fontSize: 6.5, color: _grisTexto, letterSpacing: 0.8)),
            pw.Text(valor, style: const pw.TextStyle(fontSize: 9.5)),
          ],
        ),
      );

  pw.Widget _chip(String texto, PdfColor color) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: pw.BoxDecoration(
          color: PdfColor(color.red, color.green, color.blue, 0.12),
          border: pw.Border.all(color: color, width: 0.7),
          borderRadius: pw.BorderRadius.circular(12),
        ),
        child: pw.Text(texto,
            style: pw.TextStyle(fontSize: 8, color: color)),
      );

  pw.Widget _tablaVoltajes(List<LecturaVoltaje> lecturas) => pw.Table(
        border: pw.TableBorder.all(color: _grisLinea, width: 0.5),
        columnWidths: {
          0: const pw.FlexColumnWidth(3),
          1: const pw.FlexColumnWidth(1.2),
          2: const pw.FlexColumnWidth(1.6),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _grisFondo),
            children: ['PUNTO DE MEDICIÓN', 'LECTURA', 'EVIDENCIA']
                .map((t) => pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(t,
                          style: pw.TextStyle(
                              fontSize: 7,
                              color: _indigo,
                              fontWeight: pw.FontWeight.bold,
                              letterSpacing: 0.8)),
                    ))
                .toList(),
          ),
          ...lecturas.map((l) => pw.TableRow(children: [
                pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text(l.punto,
                        style: const pw.TextStyle(fontSize: 8.5))),
                pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text(l.valor,
                        style: const pw.TextStyle(fontSize: 8.5))),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(4),
                  child: l.foto != null
                      ? pw.Container(
                          height: 42,
                          child: pw.Image(pw.MemoryImage(l.foto!),
                              fit: pw.BoxFit.contain))
                      : pw.Text('—',
                          style: const pw.TextStyle(fontSize: 8.5)),
                ),
              ])),
        ],
      );

  pw.Widget _foto(String titulo, Uint8List? bytes, {double ancho = 155}) =>
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              height: 105,
              width: ancho,
              alignment: pw.Alignment.center,
              decoration: pw.BoxDecoration(
                color: _grisFondo,
                border: pw.Border.all(color: _grisLinea, width: 0.7),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: bytes != null
                  ? pw.ClipRRect(
                      horizontalRadius: 6,
                      verticalRadius: 6,
                      child: pw.Image(pw.MemoryImage(bytes),
                          fit: pw.BoxFit.cover),
                    )
                  : pw.Text('Sin imagen',
                      style: pw.TextStyle(fontSize: 7.5, color: _grisTexto)),
            ),
            pw.SizedBox(height: 3),
            pw.Text(titulo,
                style: pw.TextStyle(fontSize: 7.5, color: _grisTexto)),
          ],
        ),
      );
}
