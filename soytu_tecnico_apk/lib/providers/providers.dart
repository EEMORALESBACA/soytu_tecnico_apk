import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soytu_core/soytu_core.dart';

final authServiceProvider = Provider((ref) => AuthService());
final tecnicoRepositoryProvider = Provider((ref) => TecnicoRepository());
final servicioRepositoryProvider = Provider((ref) => ServicioRepository());
final storageServiceProvider = Provider((ref) => StorageService());
final notificationServiceProvider = Provider((ref) => NotificationService());

/// Sesión de Firebase Auth (null si no hay usuario logueado).
final sesionProvider = StreamProvider((ref) => ref.watch(authServiceProvider).cambiosDeSesion);

/// Documento del técnico logueado (null mientras no exista sesión o el doc).
final tecnicoActualProvider = StreamProvider((ref) {
  final sesion = ref.watch(sesionProvider).value;
  if (sesion == null) return const Stream<Tecnico?>.empty();
  return ref.watch(tecnicoRepositoryProvider).observar(sesion.uid);
});

/// Servicios asignados al técnico logueado, en cualquier estado activo
/// (asignado/aceptado/en camino/en sitio).
final serviciosAsignadosProvider = StreamProvider((ref) {
  final tecnico = ref.watch(tecnicoActualProvider).value;
  if (tecnico == null) return const Stream<List<ServicioAsignado>>.empty();
  return ref.watch(servicioRepositoryProvider).observarPorTecnico(tecnico.uid);
});
