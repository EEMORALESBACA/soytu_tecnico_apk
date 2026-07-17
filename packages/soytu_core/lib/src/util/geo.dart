import 'dart:math';

/// Distancia en metros entre dos coordenadas (fórmula de Haversine).
/// Se usa para detectar la llegada del técnico al domicilio del cliente
/// sin depender de ninguna API de mapas de pago.
double distanciaMetros(double lat1, double lng1, double lat2, double lng2) {
  const radioTierraM = 6371000.0;
  final dLat = _gradosARadianes(lat2 - lat1);
  final dLng = _gradosARadianes(lng2 - lng1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_gradosARadianes(lat1)) *
          cos(_gradosARadianes(lat2)) *
          sin(dLng / 2) *
          sin(dLng / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return radioTierraM * c;
}

double _gradosARadianes(double grados) => grados * pi / 180;
