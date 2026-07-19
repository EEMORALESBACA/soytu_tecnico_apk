import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:soytu_core/soytu_core.dart';

import 'auth/login_screen.dart';
import 'auth/espera_aprobacion_screen.dart';
import 'providers/providers.dart';
import 'services/notificaciones_locales.dart';
import 'services/ubicacion_global.dart';
import 'servicios/home_tabs.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_MX'); // fechas en español
  await Firebase.initializeApp();
  await NotificacionesLocales.inicializar();

  // Push FCM recibido con la app abierta → alerta insistente local.
  FirebaseMessaging.onMessage.listen((mensaje) {
    final datos = mensaje.data;
    if (datos['tipo'] == 'nuevo_servicio') {
      NotificacionesLocales.nuevoServicio(
        datos['servicioId'] ?? mensaje.messageId ?? 'srv',
        mensaje.notification?.title ?? '🔔 Nuevo servicio SOYTU',
        mensaje.notification?.body ??
            'Tienes un servicio nuevo. Entra y acéptalo para detener la alerta.',
      );
    }
  });

  runApp(const ProviderScope(child: SoytuApp()));
}

class SoytuApp extends StatelessWidget {
  const SoytuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SOYTU Técnico',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A237E)),
        useMaterial3: true,
      ),
      home: const _RaizApp(),
    );
  }
}

/// Decide qué pantalla mostrar según el estado de sesión y de aprobación
/// del técnico: Login → Espera de aprobación → Lista de servicios.
class _RaizApp extends ConsumerStatefulWidget {
  const _RaizApp();

  @override
  ConsumerState<_RaizApp> createState() => _RaizAppState();
}

class _RaizAppState extends ConsumerState<_RaizApp> {
  @override
  Widget build(BuildContext context) {
    final sesion = ref.watch(sesionProvider);

    // Vigila los servicios del técnico: cada servicio en estado "asignado"
    // dispara la alerta insistente; al aceptarse (o reasignarse) se apaga.
    ref.listen(serviciosAsignadosProvider, (previo, actual) {
      final lista = actual.value;
      if (lista == null) return;
      for (final s in lista) {
        if (s.estadoAsignacion == EstadoAsignacion.asignado) {
          final tipo = s.tipoServicio == 'cargo' ? 'CARGO' : 'GARANTÍA';
          NotificacionesLocales.nuevoServicio(
            s.id,
            '🔔 Nuevo servicio SOYTU',
            'Folio ${s.folio}: ${s.clienteNombre} · ${s.equipoTipo} ${s.marca} · $tipo. '
                'Entra y acéptalo para detener la alerta.',
          );
        } else {
          NotificacionesLocales.cancelarServicio(s.id);
        }
      }
      final anteriores = previo?.value ?? const <ServicioAsignado>[];
      for (final p in anteriores) {
        if (!lista.any((s) => s.id == p.id)) {
          NotificacionesLocales.cancelarServicio(p.id);
        }
      }
    });

    return sesion.when(
      loading: () => const _Cargando(),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (usuario) {
        if (usuario == null) {
          UbicacionGlobal.detener();
          return const LoginScreen();
        }

        final tecnico = ref.watch(tecnicoActualProvider);
        return tecnico.when(
          loading: () => const _Cargando(),
          error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
          data: (t) {
            if (t == null || t.estadoAprobacion != EstadoAprobacion.aprobado) {
              return const EsperaAprobacionScreen();
            }

            WidgetsBinding.instance.addPostFrameCallback((_) async {
              final notificationService = ref.read(notificationServiceProvider);
              await notificationService.solicitarPermiso();
              final token = await notificationService.obtenerToken();
              if (token != null && token.isNotEmpty) {
                await ref.read(tecnicoRepositoryProvider).actualizarFcmToken(t.uid, token);
              }
              await notificationService.suscribirATema('admins');
              // Publica la ubicación del técnico para el mapa del panel admin.
              await UbicacionGlobal.iniciar(t.uid, ref.read(tecnicoRepositoryProvider));
            });

            return const HomeTabs();
          },
        );
      },
    );
  }
}

class _Cargando extends StatelessWidget {
  const _Cargando();

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}
