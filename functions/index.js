const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onCall, HttpsError, onRequest } = require("firebase-functions/v2/https");
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

async function generarYEnviarAlerta(momento) {
  const db = admin.firestore();
  const snap = await db.collection("servicios").get();
  const hoy = Date.now();
  const pendientes = [];
  const vencidos = [];
  const sinVisitar = [];
  snap.forEach((d) => {
    const s = d.data();
    if (s.estadoAsignacion === "cerrado" && s.estadoFinal === "pendiente") {
      pendientes.push(s.folio || d.id);
    } else if (s.estadoAsignacion !== "cerrado" && s.fechaCreacion) {
      const dias = (hoy - new Date(s.fechaCreacion).getTime()) / 86400000;
      if (dias > 30) vencidos.push(`${s.folio || d.id} (${Math.round(dias)}d)`);
      else if (["asignado", "aceptado"].includes(s.estadoAsignacion) && dias > 3) {
        sinVisitar.push(`${s.folio || d.id} (${Math.round(dias)}d)`);
      }
    }
  });

  const almSnap = await db.collection("almacen_refacciones").get();
  const bajos = [];
  almSnap.forEach((d) => {
    const r = d.data();
    if ((r.stock || 0) <= (r.stockMinimo || 0)) bajos.push(r.nombre || d.id);
  });

  if (!pendientes.length && !vencidos.length && !bajos.length && !sinVisitar.length) return;

  let texto = `📋 SOYTU · Reporte de seguimiento (${momento})\n\n`;
  if (sinVisitar.length) texto += `🚗 Sin visitar +3 días (${sinVisitar.length}): ${sinVisitar.slice(0, 15).join(", ")}\n\n`;
  if (pendientes.length) texto += `🔧 Faltante de refacción (${pendientes.length}): ${pendientes.slice(0, 15).join(", ")}\n\n`;
  if (vencidos.length) texto += `⏰ Más de 30 días abiertos (${vencidos.length}): ${vencidos.slice(0, 15).join(", ")}\n\n`;
  if (bajos.length) texto += `📦 Refacciones con stock bajo (${bajos.length}): ${bajos.slice(0, 15).join(", ")}\n\n`;
  texto += `Revisa el detalle en tu panel: https://soytu.com.mx/soytu/admin-soytu.html`;

  await enviarWhatsApp(ADMIN_WHATSAPP, texto);
}

exports.alertaDiariaManana = onSchedule({ schedule: "0 9 * * *", timeZone: "America/Mexico_City" }, async () => generarYEnviarAlerta("inicio del día"));
exports.alertaDiariaTarde = onSchedule({ schedule: "0 19 * * *", timeZone: "America/Mexico_City" }, async () => generarYEnviarAlerta("fin del día"));

async function verificarAdmin(auth) {
  if (!auth) throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  const doc = await admin.firestore().doc(`admins/${auth.uid}`).get();
  if (!doc.exists) throw new HttpsError("permission-denied", "Solo el administrador puede generar ligas de pago.");
}

exports.crearLigaPago = onCall(async (request) => {
  await verificarAdmin(request.auth);
  const { servicioId, monto, descripcion, clienteNombre, clienteTelefono, clienteCorreo } = request.data || {};

  if (!servicioId) throw new HttpsError("invalid-argument", "Falta servicioId.");
  const montoNum = Number(monto);
  if (!montoNum || montoNum <= 0) throw new HttpsError("invalid-argument", "El monto debe ser mayor a cero.");

  const cfg = await admin.firestore().doc("config/conekta").get();
  const privateKey = cfg.get("privateKey");
  if (!privateKey) {
    throw new HttpsError("failed-precondition", "Falta configurar la llave privada de Conekta en config/conekta.");
  }

  const svcRef = admin.firestore().doc(`servicios/${servicioId}`);
  const svcSnap = await svcRef.get();
  if (!svcSnap.exists) throw new HttpsError("not-found", "El servicio no existe.");
  const svc = svcSnap.data();

  const body = {
    name: `SOYTU · Folio ${svc.folio || servicioId}`,
    type: "PaymentLink",
    recurrent: false,
    expires_at: Math.floor(Date.now() / 1000) + 7 * 24 * 60 * 60,
    allowed_payment_methods: ["card", "cash", "bank_transfer"],
    needs_shipping_contact: false,
    order_template: {
      currency: "MXN",
      line_items: [
        {
          name: descripcion || `Servicio ${svc.folio || servicioId}`,
          unit_price: Math.round(montoNum * 100),
          quantity: 1,
        },
      ],
      metadata: { servicioId, folio: svc.folio || "" },
      customer_info: {
        name: clienteNombre || svc.clienteNombre || "Cliente SOYTU",
        email: clienteCorreo || svc.clienteCorreo || undefined,
        phone: clienteTelefono || svc.clienteTelefono || undefined,
      },
    },
  };

  const auth64 = Buffer.from(`${privateKey}:`).toString("base64");
  const r = await fetch("https://api.conekta.io/checkouts", {
    method: "POST",
    headers: {
      Authorization: `Basic ${auth64}`,
      Accept: "application/vnd.conekta-v2.2.0+json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  const data = await r.json();
  if (!r.ok) {
    console.error("Conekta error:", data);
    throw new HttpsError("internal", data?.details?.[0]?.message || data?.message || "Conekta rechazó la solicitud.");
  }

  const pagoConekta = {
    checkoutId: data.id,
    url: data.url,
    monto: montoNum,
    estado: "pendiente",
    creado: new Date().toISOString(),
    expira: body.expires_at,
  };
  await svcRef.set({ pagoConekta, montoCobrado: montoNum }, { merge: true });

  return { url: data.url, checkoutId: data.id };
});

exports.webhookConekta = onRequest(async (req, res) => {
  try {
    const evento = req.body || {};
    const tipo = evento.type || "";
    if (!tipo.includes("paid")) { res.status(200).send("ignorado"); return; }

    const obj = evento.data && evento.data.object ? evento.data.object : {};
    const posiblesIds = [
      obj.checkout_id, obj.checkout && obj.checkout.id,
      obj.order_id, obj.id,
      obj.metadata && obj.metadata.servicioId,
    ].filter(Boolean);

    const db = admin.firestore();
    const servicioIdDirecto = obj.metadata && obj.metadata.servicioId;
    let servicioDoc = null;
    if (servicioIdDirecto) {
      const d = await db.doc(`servicios/${servicioIdDirecto}`).get();
      if (d.exists) servicioDoc = d;
    }
    if (!servicioDoc) {
      for (const posibleId of posiblesIds) {
        const snap = await db.collection("servicios").where("pagoConekta.checkoutId", "==", posibleId).limit(1).get();
        if (!snap.empty) { servicioDoc = snap.docs[0]; break; }
      }
    }

    if (!servicioDoc) {
      console.warn("webhookConekta: no se encontró servicio para el evento", JSON.stringify(evento).slice(0, 500));
      res.status(200).send("sin coincidencia");
      return;
    }

    const svc = servicioDoc.data();
    await servicioDoc.ref.set({
      pagoConekta: { ...(svc.pagoConekta || {}), estado: "pagado", pagadoEn: new Date().toISOString() },
      metodoPago: "tarjeta",
    }, { merge: true });

    await enviarWhatsApp(ADMIN_WHATSAPP, `💰 SOYTU: se cobró el servicio ${svc.folio || servicioDoc.id} por $${(svc.pagoConekta?.monto || 0).toLocaleString("es-MX")} MXN.`);

    res.status(200).send("ok");
  } catch (e) {
    console.error("webhookConekta error:", e);
    res.status(500).send("error");
  }
});
