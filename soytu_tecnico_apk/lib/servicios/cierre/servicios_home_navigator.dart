import 'package:flutter/material.dart';

/// Tras cerrar un servicio (cualquiera de los 3 estados), regresa hasta la
/// primera ruta de la pila — normalmente la lista de servicios asignados.
void volverAlInicioDeServicios(BuildContext context) {
  Navigator.of(context).popUntil((route) => route.isFirst);
}
