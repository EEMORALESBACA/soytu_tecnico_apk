import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Rol de la cuenta autenticada, determinado por en qué colección de
/// Firestore existe un documento con el `uid` del usuario.
enum RolCuenta { tecnico, admin, desconocido }

/// Envoltura delgada sobre Firebase Auth. No contiene lógica de UI.
class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Stream<User?> get cambiosDeSesion => _auth.authStateChanges();

  User? get usuarioActual => _auth.currentUser;

  Future<UserCredential> iniciarSesion(String correo, String contrasena) =>
      _auth.signInWithEmailAndPassword(email: correo, password: contrasena);

  Future<UserCredential> registrar(String correo, String contrasena) =>
      _auth.createUserWithEmailAndPassword(email: correo, password: contrasena);

  Future<void> cerrarSesion() => _auth.signOut();

  Future<RolCuenta> obtenerRol(String uid) async {
    final tecnico = await _firestore.collection('tecnicos').doc(uid).get();
    if (tecnico.exists) return RolCuenta.tecnico;
    final admin = await _firestore.collection('admins').doc(uid).get();
    if (admin.exists) return RolCuenta.admin;
    return RolCuenta.desconocido;
  }
}
