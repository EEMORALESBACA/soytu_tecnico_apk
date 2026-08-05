import 'package:cloud_firestore/cloud_firestore.dart';

/// Una refacción del inventario vivo (colección `almacen_refacciones`,
/// la misma que administra el panel web). Es distinto del catálogo
/// estático de [refaccion_catalogo.dart]: este sí refleja stock real.
class RefaccionInventario {
  RefaccionInventario({
    required this.sku,
    required this.nombre,
    required this.stock,
    this.costoPromedio,
    this.marca,
    this.tipoEquipo,
  });

  final String sku;
  final String nombre;
  final int stock;
  final double? costoPromedio;
  final String? marca;
  final String? tipoEquipo;

  factory RefaccionInventario.fromMap(String id, Map<String, dynamic> m) => RefaccionInventario(
        sku: id,
        nombre: (m['nombre'] as String?) ?? id,
        stock: (m['stock'] as num?)?.toInt() ?? 0,
        costoPromedio: (m['costoPromedio'] as num?)?.toDouble(),
        marca: m['marca'] as String?,
        tipoEquipo: m['tipoEquipo'] as String?,
      );
}

/// Crédito de almacén asignado a un técnico (colección `almacen_creditos`,
/// el mismo que asigna el administrador desde el panel web).
class CreditoAlmacen {
  CreditoAlmacen({
    required this.id,
    required this.monto,
    required this.fechaVencimiento,
    required this.activo,
  });

  final String id;
  final double monto;
  final DateTime fechaVencimiento;
  final bool activo;

  bool get vigente => activo && fechaVencimiento.isAfter(DateTime.now());
  int get diasRestantes =>
      vigente ? fechaVencimiento.difference(DateTime.now()).inDays.clamp(0, 999) : 0;

  factory CreditoAlmacen.fromMap(String id, Map<String, dynamic> m) => CreditoAlmacen(
        id: id,
        monto: (m['monto'] as num?)?.toDouble() ?? 0,
        fechaVencimiento: DateTime.tryParse(m['fechaVencimiento'] as String? ?? '') ?? DateTime.now(),
        activo: (m['activo'] as bool?) ?? true,
      );
}

/// Acceso a `almacen_refacciones` y `almacen_creditos` para la app del
/// técnico: mismo inventario y mismo crédito que ve el administrador.
class AlmacenRepository {
  AlmacenRepository({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Refacciones sugeridas para un servicio: primero las que coinciden
  /// exactamente con marca + tipo de equipo, luego las genéricas
  /// (sin marca/equipo definidos, es decir, sirven para cualquiera).
  Stream<List<RefaccionInventario>> observarSugeridas({
    required String marca,
    required String tipoEquipo,
  }) {
    return _db.collection('almacen_refacciones').snapshots().map((snap) {
      final todas = snap.docs.map((d) => RefaccionInventario.fromMap(d.id, d.data())).toList();
      final exactas = todas.where((r) =>
          r.marca != null &&
          r.marca!.toLowerCase() == marca.toLowerCase() &&
          r.tipoEquipo != null &&
          r.tipoEquipo!.toLowerCase() == tipoEquipo.toLowerCase());
      final porTipo = todas.where((r) =>
          r.marca == null &&
          r.tipoEquipo != null &&
          r.tipoEquipo!.toLowerCase() == tipoEquipo.toLowerCase());
      final genericas = todas.where((r) => r.marca == null && r.tipoEquipo == null);
      return [...exactas, ...porTipo, ...genericas].take(12).toList();
    });
  }

  /// El crédito de almacén activo del técnico (si tiene alguno vigente).
  Stream<CreditoAlmacen?> observarCreditoActivo(String technicianId) {
    return _db
        .collection('almacen_creditos')
        .where('technicianId', isEqualTo: technicianId)
        .snapshots()
        .map((snap) {
      final creditos =
          snap.docs.map((d) => CreditoAlmacen.fromMap(d.id, d.data())).where((c) => c.vigente).toList();
      if (creditos.isEmpty) return null;
      creditos.sort((a, b) => b.fechaVencimiento.compareTo(a.fechaVencimiento));
      return creditos.first;
    });
  }

  /// Cuánto ha consumido el técnico de un crédito dado (suma de sus
  /// salidas de almacén dentro de la vigencia del crédito).
  Future<double> consumoDeCredito(String technicianId, CreditoAlmacen credito) async {
    final snap = await _db
        .collection('almacen_movimientos')
        .where('personaId', isEqualTo: technicianId)
        .where('tipo', isEqualTo: 'salida')
        .get();
    double total = 0;
    for (final doc in snap.docs) {
      final m = doc.data();
      final fecha = DateTime.tryParse(m['fecha'] as String? ?? '');
      if (fecha == null) continue;
      if (fecha.isAfter(credito.fechaVencimiento)) continue;
      total += ((m['costoUnitario'] as num?)?.toDouble() ?? 0) * ((m['cantidad'] as num?)?.toDouble() ?? 0);
    }
    return total;
  }
}
