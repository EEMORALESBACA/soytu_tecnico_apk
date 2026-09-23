// ════════════════════════════════════════════════════════════
// ENCUESTA "¿CÓMO TE ATENDÍ?" — perfil público del técnico
// La página encuesta.html (pública) no puede leer `tecnicos` ni contar
// servicios, así que aquí mantenemos `perfilPublicoTecnico/{uid}` con
// SOLO lo que el cliente debe ver: nombre, foto, años, servicios,
// calificación y certificaciones. Sin teléfono, INE ni ubicación.
// ════════════════════════════════════════════════════════════
const { onDocumentCreated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

const CERTIFICACIONES = {
  linea_blanca: "Línea Blanca",
  refrigeracion_ac: "Refrigeración",
  electronica_tv: "Electrónica",
};

function estrellasDe(e) {
  if (!e) return null;
  if (typeof e.promedioEstrellas === "number") return e.promedioEstrellas;
  const v = [e.calidadServicio, e.tratoTecnico].filter((x) => typeof x === "number");
  return v.length ? v.reduce((a, b) => a + b, 0) / v.length : null;
}

function aniosDe(t) {
  if (typeof t.aniosExperiencia === "number") return t.aniosExperiencia; // si RH lo captura
  const inicio = new Date(t.fechaRegistro || 0).getTime();
  if (!inicio) return null;
  return Math.floor((Date.now() - inicio) / (365.25 * 24 * 3600 * 1000));
}

async function recalcularPerfil(uid) {
  if (!uid) return;
  const db = admin.firestore();
  const tec = await db.doc(`tecnicos/${uid}`).get();
  const ref = db.doc(`perfilPublicoTecnico/${uid}`);
  if (!tec.exists) { await ref.delete().catch(() => {}); return; }
  const t = tec.data();

  const snap = await db.collection("servicios").where("technicianId", "==", uid).get();
  let completados = 0, suma = 0, n = 0;
  snap.forEach((d) => {
    const s = d.data();
    if (s.estadoAsignacion === "cerrado" && s.estadoFinal === "completado") completados++;
    const p = estrellasDe(s.encuesta);
    if (p) { suma += p; n++; }
  });

  const certificaciones = Object.entries(t.examenes || {})
    .filter(([, r]) => r && typeof r.calificacion === "number" && r.calificacion >= 70)
    .map(([id]) => CERTIFICACIONES[id] || id);

  await ref.set({
    nombre: t.nombre || "",
    selfieUrl: t.selfieUrl || null,
    empresaId: t.empresaId || null,
    aniosExperiencia: aniosDe(t),
    servicios: completados,
    calificacion: n ? Math.round((suma / n) * 10) / 10 : null,
    totalEncuestas: n,
    certificaciones,
    actualizado: new Date().toISOString(),
  });
}

// 1) Llega una encuesta → se copia dentro de la orden y se recalcula el perfil.
exports.alResponderEncuesta = onDocumentCreated("encuestas/{id}", async (event) => {
  const e = event.data && event.data.data();
  if (!e || !e.servicioId) return;
  const db = admin.firestore();
  const sref = db.doc(`servicios/${e.servicioId}`);
  const s = await sref.get();
  if (!s.exists) return;
  const sd = s.data();

  const faltantes = {};
  if (!e.technicianId && sd.technicianId) faltantes.technicianId = sd.technicianId;
  if (!e.empresaId && sd.empresaId) faltantes.empresaId = sd.empresaId;
  if (Object.keys(faltantes).length) await event.data.ref.update(faltantes);

  if (!sd.encuesta) {
    const { servicioId, ...resto } = e; // eslint-disable-line no-unused-vars
    await sref.update({ encuesta: resto });
  }
  await recalcularPerfil(sd.technicianId);
});

// 2) Se cierra un servicio → el contador de servicios queda al día
//    antes de que el cliente abra la encuesta.
exports.perfilAlCerrarServicio = onDocumentWritten("servicios/{id}", async (event) => {
  const antes = event.data.before.exists ? event.data.before.data() : null;
  const ahora = event.data.after.exists ? event.data.after.data() : null;
  if (!ahora || !ahora.technicianId) return;
  const recienCerrado = ahora.estadoAsignacion === "cerrado" && (!antes || antes.estadoAsignacion !== "cerrado");
  if (recienCerrado) await recalcularPerfil(ahora.technicianId);
});

// 3) Cambia nombre, foto, exámenes o años del técnico → se actualiza su tarjeta.
//    (Ignora las escrituras de GPS para no gastar lecturas.)
exports.perfilAlEditarTecnico = onDocumentWritten("tecnicos/{uid}", async (event) => {
  const antes = event.data.before.exists ? event.data.before.data() : {};
  const ahora = event.data.after.exists ? event.data.after.data() : null;
  const uid = event.params.uid;
  if (!ahora) { await admin.firestore().doc(`perfilPublicoTecnico/${uid}`).delete().catch(() => {}); return; }
  const huella = (t) => JSON.stringify([t.nombre, t.selfieUrl, t.examenes, t.aniosExperiencia, t.empresaId]);
  if (huella(antes) !== huella(ahora)) await recalcularPerfil(uid);
});

// 4) Respaldo nocturno: recalcula a todos (y llena los perfiles la primera vez).
exports.recalcularPerfilesNoche = onSchedule(
  { schedule: "30 3 * * *", timeZone: "America/Mexico_City" },
  async () => {
    const snap = await admin.firestore().collection("tecnicos").get();
    for (const d of snap.docs) {
      try { await recalcularPerfil(d.id); } catch (e) { console.error("perfil", d.id, e.message); }
    }
  }
);
