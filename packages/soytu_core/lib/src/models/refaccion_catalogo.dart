/// Catálogos de refacciones por tipo de equipo. Se usan en el checklist de
/// "refacciones utilizadas / faltantes" al cerrar un servicio: la app elige
/// automáticamente el catálogo correcto según `equipoTipo` del servicio.
library refaccion_catalogo;

const List<String> catalogoRefaccionesTv = [
  'Fuente de poder',
  'Tarjeta Main',
  'Tarjeta T-CON',
  'Panel / LED',
  'Backlight / tiras LED',
  'Tarjeta de audio',
  'Sensor IR',
  'Botonera',
  'Control remoto',
  'Cable flex / LVDS',
  'Altavoces',
  'Fusibles',
  'Capacitores electrolíticos',
  'Sintonizador / Tuner',
  'Módulo WiFi',
];

const List<String> catalogoRefaccionesLavadora = [
  'Motor / motoventilador',
  'Bomba de desagüe',
  'Banda',
  'Válvula de entrada de agua',
  'Tarjeta de control',
  'Sensor de nivel (presostato)',
  'Amortiguadores / resortes',
  'Rodamientos / baleros de tina',
  'Sello / retén de tina',
  'Manguera de desagüe',
  'Perilla / selector',
  'Bisagra de puerta',
  'Empaque de puerta',
  'Escobillas de motor',
];

const List<String> catalogoRefaccionesRefrigerador = [
  'Compresor',
  'Termostato',
  'Filtro secador',
  'Ventilador evaporador',
  'Ventilador condensador',
  'Tarjeta de control',
  'Sensor de temperatura',
  'Resistencia de descongelamiento (defrost)',
  'Fusible térmico',
  'Empaque de puerta',
  'Válvula de agua (dispensador/hielo)',
  'Motor de hielera',
  'Relevador / protector de compresor',
  'Gas refrigerante (recarga)',
];

const List<String> catalogoRefaccionesAireAcondicionado = [
  'Compresor',
  'Motoventilador (evaporadora)',
  'Motoventilador (condensadora)',
  'Tarjeta de control (evaporadora)',
  'Tarjeta de potencia (condensadora)',
  'Capacitor de arranque',
  'Válvula de expansión',
  'Sensor de temperatura',
  'Filtro de aire',
  'Control remoto',
  'Gas refrigerante (recarga)',
  'Tubería / conexiones',
  'Aislante térmico',
];

const List<String> catalogoRefaccionesLavavajillas = [
  'Bomba de lavado',
  'Bomba de desagüe',
  'Resistencia de calentamiento',
  'Tarjeta de control',
  'Válvula de entrada de agua',
  'Sensor de temperatura',
  'Brazo aspersor',
  'Sello / empaque de puerta',
  'Filtro',
  'Dispensador de jabón/abrillantador',
  'Manguera de desagüe',
];

const List<String> catalogoRefaccionesEstufa = [
  'Quemador',
  'Válvula de gas',
  'Ignición / bujía de encendido',
  'Termopar',
  'Perilla de control',
  'Reloj / temporizador',
  'Resistencia de horno',
  'Sensor de temperatura de horno',
  'Bisagra de puerta',
  'Empaque de puerta de horno',
  'Panel de control',
];

const List<String> catalogoRefaccionesMicroondas = [
  'Magnetrón',
  'Transformador de alto voltaje',
  'Capacitor de alto voltaje',
  'Diodo de alto voltaje',
  'Fusible',
  'Plato giratorio / motor',
  'Panel de control',
  'Sensor de puerta (switch)',
  'Rejilla / guía de onda',
  'Bombilla interior',
];

/// Otros equipos sin catálogo específico: lista genérica corta + campo libre.
const List<String> catalogoRefaccionesGenerico = [
  'Tarjeta de control',
  'Motor',
  'Sensor',
  'Fusible',
  'Cableado / conector',
  'Empaque / sello',
];

/// Elige el catálogo correcto según el texto libre de `equipoTipo` que captura
/// el administrador al asignar el servicio (por eso se compara sin acentos,
/// en minúsculas, y por coincidencia parcial).
List<String> catalogoParaEquipo(String equipoTipo) {
  final t = equipoTipo
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u');

  if (t.contains('tv') || t.contains('pantalla') || t.contains('television')) {
    return catalogoRefaccionesTv;
  }
  if (t.contains('lavavaj') || t.contains('dishwasher')) {
    return catalogoRefaccionesLavavajillas;
  }
  if (t.contains('lava') || t.contains('secadora')) {
    return catalogoRefaccionesLavadora;
  }
  if (t.contains('refrigera') || t.contains('nevera') || t.contains('congelador')) {
    return catalogoRefaccionesRefrigerador;
  }
  if (t.contains('aire') || t.contains('minisplit') || t.contains('clima')) {
    return catalogoRefaccionesAireAcondicionado;
  }
  if (t.contains('estufa') || (t.contains('horno') && !t.contains('microond'))) {
    return catalogoRefaccionesEstufa;
  }
  if (t.contains('microond')) {
    return catalogoRefaccionesMicroondas;
  }
  return catalogoRefaccionesGenerico;
}
