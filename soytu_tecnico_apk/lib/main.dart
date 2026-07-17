import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:soytu_core/soytu_core.dart';

import 'auth/login_screen.dart';
import 'auth/espera_aprobacion_screen.dart';
import 'providers/providers.dart';
import 'servicios/lista_servicios_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_MX'); // fechas en español
  await Firebase.initializeApp();
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

    return sesion.when(
      loading: () => const _Cargando(),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (usuario) {
        if (usuario == null) return const LoginScreen();

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
            });

            return const ListaServiciosScreen();
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
