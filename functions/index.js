const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");

admin.initializeApp();
setGlobalOptions({ region: "us-central1", maxInstances: 5 });

const LIGA_TRACKING = (id) => `https://soytu.com.mx/soytu/tracking.html?id=${id}`;
const ADMIN_WHATSAPP = "2201600812";

function normalizarTel(tel) {
  let t = String(tel || "").replace(/\D/g, "");
  if (t.length === 10) return "521" + t;
  if (t.length === 12 && t.startsWith("52")) return "521" + t.slice(2);
  return t;
}

async function enviarWhatsApp(telefono, texto) {
  const cfg = await admin.firestore().doc("config/whatsapp").get();
  const token = cfg.get("token");
  const phoneId = cfg.get("phoneNumberId");
  if (!token || !phoneId || !telefono) return false;
  const r = await fetch(`https://graph.facebook.com/v20.0/${phoneId}/messages`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      messaging_product: "whatsapp",
      to: normalizarTel(telefono),
      type: "text",
      text: { body: texto },
    }),
  });
  if (!r.ok) console.error("WhatsApp fallo:", r.status, await r.text());
  return r.ok;
}

/**
 * Vigila `servicios`: asignación → push al técnico; en camino → WhatsApp
 * al cliente con foto, placas y liga de rastreo; llegada → aviso.
 * (Sin cambios respecto a la versión anterior de esta función.)
 */
exports.vigilarServicios = onDocumentWritten("servicios/{id}", async (event) => {
  const antes = event.data.before.exists ? event.data.before.data() : null;
  const ahora = event.data.after.exists ? event.data.after.data() : null;
  if (!ahora) return;
  const id = event.params.id;

  const nuevaAsignacion =
    ahora.technicianId &&
    ahora.estadoAsignacion === "asignado" &&
    (!antes || antes.technicianId !== ahora.technicianId || antes.estadoAsignacion !== "asignado");

  if (nuevaAsignacion) {
    const tec = await admin.firestore().doc(`tecnicos/${ahora.technicianId}`).get();
    const token = tec.get("fcmToken");
    if (token) {
      try {
        await admin.messaging().send({
          token,
          notification: {
            title: "🔔 Nuevo servicio SOYTU",
            body: `Folio ${ahora.folio || id}: ${ahora.clienteNombre || ""} · ${[
              ahora.equipoTipo, ahora.marca,
            ].filter(Boolean).join(" ")} · ${ahora.tipoServicio === "cargo" ? "CARGO" : "GARANTÍA"}`,
          },
          data: { servicioId: id, tipo: "nuevo_servicio" },
          android: {
            priority: "high",
            notification: { channelId: "servicios_soytu", sound: "default", defaultVibrateTimings: true, visibility: "public" },
          },
        });
      } catch (e) { console.error("FCM fallo:", e.message); }
    }
  }

  const saleEnCamino = ahora.estadoAsignacion === "enCamino" && (!antes || antes.estadoAsignacion !== "enCamino");
  if (saleEnCamino) {
    let tecNombre = "", tecPlacas = "", tecSelfie = null;
    if (ahora.technicianId) {
      const tec = await admin.firestore().doc(`tecnicos/${ahora.technicianId}`).get();
      if (tec.exists) {
        tecNombre = tec.get("nombre") || "";
        tecPlacas = tec.get("placas") || "";
        tecSelfie = tec.get("selfieUrl") || null;
      }
    }
    const texto =
      `Hola ${ahora.clienteNombre || ""} 👋 Tu técnico SOYTU ya va en camino a tu domicilio por el servicio ${ahora.folio || ""}.\n` +
      (tecNombre ? `👷 Te atiende: ${tecNombre}\n` : "") +
      (tecPlacas ? `🚗 Llegará en el vehículo con placas: ${tecPlacas}\n` : "") +
      `📍 Sigue su ubicación en tiempo real (con su fotografía): ${LIGA_TRACKING(id)}\n— SOYTU · Creando Conexiones`;
    const cfg = await admin.firestore().doc("config/whatsapp").get();
    const token = cfg.get("token");
    const phoneId = cfg.get("phoneNumberId");
    if (token && phoneId && ahora.clienteTelefono) {
      const cuerpo = tecSelfie
        ? { messaging_product: "whatsapp", to: normalizarTel(ahora.clienteTelefono), type: "image", image: { link: tecSelfie, caption: texto } }
        : { messaging_product: "whatsapp", to: normalizarTel(ahora.clienteTelefono), type: "text", text: { body: texto } };
      const r = await fetch(`https://graph.facebook.com/v20.0/${phoneId}/messages`, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify(cuerpo),
      });
      if (!r.ok) console.error("WhatsApp enCamino fallo:", r.status, await r.text());
    }
  }

  const llego = ahora.estadoAsignacion === "enSitio" && (!antes || antes.estadoAsignacion !== "enSitio");
  if (llego) {
    await enviarWhatsApp(ahora.clienteTelefono, `✅ Tu técnico SOYTU llegó a tu domicilio para atender el servicio ${ahora.folio || ""}. — SOYTU · Creando Conexiones`);
  }
});

/**
 * ALERTA DIARIA DE SEGUIMIENTO — corre dos veces al día (9:00 y 19:00,
 * hora de CDMX) y manda al WhatsApp del administrador un resumen de:
 *  - Servicios cerrados como "faltante de refacción" (pendientes de refrendo)
 *  - Servicios sin cerrar con más de 30 días abiertos
 * También revisa el almacén y avisa si hay refacciones con stock bajo.
 */
async function generarYEnviarAlerta(momento) {
  const db = admin.firestore();
  const snap = await db.collection("servicios").get();
  const hoy = Date.now();
  const pendientes = [];
  const vencidos = [];
  snap.forEach((d) => {
    const s = d.data();
    if (s.estadoAsignacion === "cerrado" && s.estadoFinal === "pendiente") {
      pendientes.push(s.folio || d.id);
    } else if (s.estadoAsignacion !== "cerrado" && s.fechaCreacion) {
      const dias = (hoy - new Date(s.fechaCreacion).getTime()) / 86400000;
      if (dias > 30) vencidos.push(`${s.folio || d.id} (${Math.round(dias)}d)`);
    }
  });

  const almSnap = await db.collection("almacen_refacciones").get();
  const bajos = [];
  almSnap.forEach((d) => {
    const r = d.data();
    if ((r.stock || 0) <= (r.stockMinimo || 0)) bajos.push(r.nombre || d.id);
  });

  if (!pendientes.length && !vencidos.length && !bajos.length) return;

  let texto = `📋 SOYTU · Reporte de seguimiento (${momento})\n\n`;
  if (pendientes.length) texto += `🔧 Faltante de refacción (${pendientes.length}): ${pendientes.slice(0, 15).join(", ")}\n\n`;
  if (vencidos.length) texto += `⏰ Más de 30 días abiertos (${vencidos.length}): ${vencidos.slice(0, 15).join(", ")}\n\n`;
  if (bajos.length) texto += `📦 Refacciones con stock bajo (${bajos.length}): ${bajos.slice(0, 15).join(", ")}\n\n`;
  texto += `Revisa el detalle en tu panel: https://soytu.com.mx/soytu/admin-soytu.html`;

  await enviarWhatsApp(ADMIN_WHATSAPP, texto);
}

exports.alertaDiariaManana = onSchedule(
  { schedule: "0 9 * * *", timeZone: "America/Mexico_City" },
  async () => generarYEnviarAlerta("inicio del día")
);

exports.alertaDiariaTarde = onSchedule(
  { schedule: "0 19 * * *", timeZone: "America/Mexico_City" },
  async () => generarYEnviarAlerta("fin del día")
);
