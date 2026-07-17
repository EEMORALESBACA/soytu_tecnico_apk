import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:soytu_core/soytu_core.dart';

/// Ejemplo de cierre de servicio COMPLETADO desde la app del técnico.
/// Llama a esto al presionar el botón verde "COMPLETADO",
/// después de capturar firma y (si aplica) monto.
Future<void> cerrarServicioCompletado({
  required OrdenServicio orden,
  required String whatsappCliente, // Ej. "5215512345678" (con 521)
  required String whatsappAdmin, // Tu número registrado
}) async {
  // 1. Generar el PDF corporativo
  final generador = HojaServicioPdf(/* logoBytes: await _cargarLogo() */);
  final bytes = await generador.generar(orden);

  // 2. Guardarlo localmente
  final dir = await getApplicationDocumentsDirectory();
  final archivo = File('${dir.path}/HojaServicio_${orden.folio}.pdf');
  await archivo.writeAsBytes(bytes);

  // 3. Compartir el PDF (el técnico elige WhatsApp en el share sheet)
  await Share.shareXFiles(
    [XFile(archivo.path, mimeType: 'application/pdf')],
    text: 'SOYTU — Hoja de servicio ${orden.folio}. '
        'Gracias por su confianza. soytu.com.mx',
  );

  // 4. (Opcional) Abrir chat de WhatsApp del cliente con mensaje prellenado.
  //    NOTA: wa.me no adjunta archivos; el adjunto real del PDF debe ir por
  //    WhatsApp Cloud API desde una Cloud Function (envío automático servidor).
  final uri = Uri.parse(
      'https://wa.me/$whatsappCliente?text=${Uri.encodeComponent("Su servicio ${orden.folio} ha sido COMPLETADO ✅. En breve recibirá su hoja de servicio en PDF y una breve encuesta de satisfacción. — SOYTU")}');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // 5. Vista previa / impresión (útil para pruebas en el S25 Ultra)
  // await Printing.layoutPdf(onLayout: (_) async => bytes);
}

/// Datos de ejemplo para probar el diseño del PDF sin backend.
OrdenServicio ordenDemo() => OrdenServicio(
      folio: 'SOYTU-2026-000147',
      fecha: DateTime.now(),
      estado: EstadoServicio.completado,
      tecnicoNombre: 'Juan Carlos Ramírez López',
      tecnicoId: 'TEC-0021',
      tecnicoTelefono: '55 1234 5678',
      clienteNombre: 'María Fernanda Gutiérrez',
      clienteDireccion:
          'Av. Primero de Mayo 123, Col. Centro, Tlalnepantla de Baz, Méx.',
      clienteTelefono: '55 8765 4321',
      clienteCorreo: 'maria.gtz@example.com',
      equipoTipo: 'Televisión',
      marca: 'TCL',
      modelo: '55C645',
      numeroSerie: 'TCL55C645MX2025001',
      fallaReportada: 'No enciende, LED de standby parpadea',
      descripcionTecnico:
          'El equipo se encontró conectado a un multicontacto en mal estado. '
          'Se detectó fuente de alimentación con capacitores inflados en la '
          'etapa primaria. Se reemplazó la fuente y se verificó encendido, '
          'imagen y audio correctos. Equipo entregado funcionando al 100%.',
      tiposFalla: [TipoFalla.tarjetaMain],
      voltajes: [
        LecturaVoltaje(punto: 'Línea del hogar (toma corriente)', valor: '127.3 V'),
        LecturaVoltaje(punto: 'VCC Main 12V', valor: '11.9 V'),
        LecturaVoltaje(punto: 'Standby 3.3V', valor: '3.28 V'),
      ],
      montoCobrado: 1850.00,
    );
