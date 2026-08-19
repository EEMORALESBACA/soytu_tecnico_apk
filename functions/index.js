const { onDocumentWritten, onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onCall, HttpsError, onRequest } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");

admin.initializeApp();
setGlobalOptions({ region: "us-central1", maxInstances: 5 });

const LIGA_TRACKING = (id) => `https://soytu.com.mx/soytu/tracking.html?id=${id}`;
const ADMIN_WHATSAPP = "2201600812";
const TEMA_ADMINS = "admins_alertas";

function normalizarTelE164(telefonoDestino) {
  let numero = String(telefonoDestino || "").replace(/\D/g, "");
  if (numero.length === 10) numero = "521" + numero; // MX celular
  return "+" + numero;
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
      to: normalizarTelE164(telefono).replace("+", ""),
      type: "text",
      text: { body: texto },
    }),
  });
  if (!r.ok) console.error("WhatsApp fallo:", r.status, await r.text());
  return r.ok;
}

/**
 * enviarSms — escribe un "pendiente" en Firestore (sms_pendientes).
 * Tu app "SOYTU Gateway SMS", corriendo en tu celular dedicado, lo manda
 * con tu SIM en cuanto aparece. Si tarda más de 5 min, un respaldo por
 * Twilio (si está configurado) lo intenta mandar por su cuenta.
 */
async function enviarSms(telefonoDestino, texto) {
  if (!telefonoDestino) return false;
  const destino = normalizarTelE164(telefonoDestino);
  await admin.firestore().collection("sms_pendientes").add({
    telefono: destino,
    texto,
    estado: "pendiente",
    creado: new Date().toISOString(),
  });
  return true;
}

async function enviarSmsPorTwilio(telefonoE164, texto) {
  const cfgTw = await admin.firestore().doc("config/twilio").get();
  const sid = cfgTw.get("accountSid");
  const authToken = cfgTw.get("authToken");
  const fromNumber = cfgTw.get("fromNumber");
  if (!sid || !authToken || !fromNumber) return false;

  const params = new URLSearchParams({ To: telefonoE164, From: fromNumber, Body: texto });
  const auth64Tw = Buffer.from(`${sid}:${authToken}`).toString("base64");
  const r = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`, {
    method: "POST",
    headers: {
      Authorization: `Basic ${auth64Tw}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: params.toString(),
  });
  if (!r.ok) console.error("Twilio SMS fallo:", r.status, await r.text());
  return r.ok;
}

/**
 * notificarAdmins — manda un push FCM al tema `admins_alertas`. Cualquier
 * celular con la app SOYTU Admin instalada y sesión de admin válida está
 * suscrito a este tema y recibe la misma alerta, sin importar cuántos
 * administradores tengas.
 */
async function notificarAdmins({ titulo, cuerpo, tipo, extra = {} }) {
  try {
    await admin.messaging().send({
      topic: TEMA_ADMINS,
      notification: { title: titulo, body: cuerpo },
      data: { tipo, ...extra },
      android: {
        priority: "high",
        notification: { sound: "default", channelId: tipo === "tecnico_pendiente" ? "tecnicos_pendientes_admin" : "servicios_nuevos_admin" },
      },
    });
  } catch (e) {
    console.error("notificarAdmins fallo:", e.message);
  }
}

// ════════════════════════════════════════════════════════════
// SERVICIOS: alertas de WhatsApp al cliente + push FCM al técnico
// ════════════════════════════════════════════════════════════
exports.vigilarServicios = onDocumentWritten("servicios/{id}", async (event) => {
  const antes = event.data.before.exists ? event.data.before.data() : null;
  const ahora = event.data.after.exists ? event.data.after.data() : null;
  if (!ahora) return;
  const id = event.params.id;

  // ── Aviso al ADMIN: servicio nuevo (documento recién creado) ──
  if (!antes) {
    await notificarAdmins({
      titulo: "🧾 Nuevo servicio SOYTU",
      cuerpo: `${ahora.clienteNombre || "Cliente"} · ${[ahora.equipoTipo, ahora.marca].filter(Boolean).join(" ")} · Folio ${ahora.folio || id}`,
      tipo: "nuevo_servicio_admin",
      extra: { servicioId: id },
    });
  }

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

  // Aviso de "en camino": SMS automático por el Gateway (celular dedicado).
  // Aviso de "en camino" al cliente — con la liga para rastrear a su
  // técnico en tiempo real. Intenta primero por WhatsApp (mensaje rico,
  // con foto y placas del técnico); si WhatsApp no está configurado
  // todavía, cae automáticamente a SMS (gateway del celular / Twilio).
  const saleEnCamino = ahora.estadoAsignacion === "enCamino" && (!antes || antes.estadoAsignacion !== "enCamino");
  if (saleEnCamino && ahora.clienteTelefono) {
    let tecNombre = "", tecPlacas = "", tecSelfie = null;
    if (ahora.technicianId) {
      const tec = await admin.firestore().doc(`tecnicos/${ahora.technicianId}`).get();
      if (tec.exists) {
        tecNombre = tec.get("nombre") || "";
        tecPlacas = tec.get("placas") || "";
        tecSelfie = tec.get("selfieUrl") || null;
      }
    }
    const textoBase =
      `Hola ${ahora.clienteNombre || ""} 👋 Tu técnico SOYTU ya va en camino a tu domicilio por el servicio ${ahora.folio || ""}.\n` +
      (tecNombre ? `👷 Te atiende: ${tecNombre}\n` : "") +
      (tecPlacas ? `🚗 Llegará en el vehículo con placas: ${tecPlacas}\n` : "") +
      `📍 Sigue su ubicación en tiempo real (con su fotografía): ${LIGA_TRACKING(id)}\n— SOYTU · Creando Conexiones`;

    const cfgWa = await admin.firestore().doc("config/whatsapp").get();
    const waToken = cfgWa.get("token");
    const waPhoneId = cfgWa.get("phoneNumberId");

    if (waToken && waPhoneId) {
      const cuerpo = tecSelfie
        ? { messaging_product: "whatsapp", to: normalizarTelE164(ahora.clienteTelefono).replace("+", ""), type: "image", image: { link: tecSelfie, caption: textoBase } }
        : { messaging_product: "whatsapp", to: normalizarTelE164(ahora.clienteTelefono).replace("+", ""), type: "text", text: { body: textoBase } };
      const r = await fetch(`https://graph.facebook.com/v20.0/${waPhoneId}/messages`, {
        method: "POST",
        headers: { Authorization: `Bearer ${waToken}`, "Content-Type": "application/json" },
        body: JSON.stringify(cuerpo),
      });
      if (!r.ok) {
        console.error("WhatsApp enCamino falló, cae a SMS:", r.status, await r.text());
        await enviarSms(ahora.clienteTelefono, textoBase);
      }
    } else {
      // WhatsApp no configurado todavía: SMS directo, sin bloquear el aviso.
      const textoSms =
        `Hola ${ahora.clienteNombre || ""}, ${tecNombre ? `su técnico SOYTU (${tecNombre})` : "su técnico SOYTU"} ` +
        `ya va en camino por el servicio ${ahora.folio || ""}. Sígalo en tiempo real: ${LIGA_TRACKING(id)} — SOYTU`;
      await enviarSms(ahora.clienteTelefono, textoSms);
    }
  }
});

// ════════════════════════════════════════════════════════════
// SOLICITUDES WEB (colección `orders`, cliente.html): avisa al admin
// ════════════════════════════════════════════════════════════
exports.vigilarOrdenesWeb = onDocumentCreated("orders/{id}", async (event) => {
  const o = event.data.data();
  await notificarAdmins({
    titulo: "🌐 Nueva solicitud desde la web",
    cuerpo: `${o.clientName || "Cliente"} · ${o.appliance || "Servicio"} — fuera de marcas`,
    tipo: "nuevo_servicio_admin",
    extra: { ordenId: event.params.id },
  });
});

// ════════════════════════════════════════════════════════════
// RH: avisa al admin cuando el personal pide vacaciones/permiso
// ════════════════════════════════════════════════════════════
exports.vigilarVacaciones = onDocumentCreated("vacaciones_solicitudes/{id}", async (event) => {
  const v = event.data.data();
  await notificarAdmins({
    titulo: "🏖️ Solicitud de vacaciones",
    cuerpo: `${v.empleadoNombre || "Un empleado"} pidió ${v.dias || ""} día(s): ${v.fechaInicio || ""} a ${v.fechaFin || ""}`,
    tipo: "tecnico_pendiente",
    extra: { solicitudId: event.params.id },
  });
});

// ════════════════════════════════════════════════════════════
// TÉCNICOS: avisa al admin cuando alguien necesita revisión
// (alta nueva, o recertificación semestral que lo regresó a pendiente)
// ════════════════════════════════════════════════════════════
exports.vigilarTecnicos = onDocumentWritten("tecnicos/{uid}", async (event) => {
  const antes = event.data.before.exists ? event.data.before.data() : null;
  const ahora = event.data.after.exists ? event.data.after.data() : null;
  if (!ahora) return;

  const eraPendiente = antes ? antes.estadoAprobacion === "pendiente" : false;
  const esPendiente = ahora.estadoAprobacion === "pendiente";
  const seVolvioPendiente = esPendiente && !eraPendiente;

  if (seVolvioPendiente) {
    const esAltaNueva = !antes;
    await notificarAdmins({
      titulo: esAltaNueva ? "👷 Nueva alta de técnico" : "⏳ Técnico requiere revisión",
      cuerpo: `${ahora.nombre || "Técnico"} · ${esAltaNueva ? "Registro nuevo" : "Recertificación / re-evaluación"}`,
      tipo: "tecnico_pendiente",
      extra: { technicianId: event.params.uid },
    });
  }
});

// ════════════════════════════════════════════════════════════
// ALERTAS DIARIAS (WhatsApp al admin): pendientes, vencidos, sin visitar
// ════════════════════════════════════════════════════════════
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

// ════════════════════════════════════════════════════════════
// RECERTIFICACIÓN SEMESTRAL DE EXÁMENES
// ════════════════════════════════════════════════════════════
exports.revisarRecertificacionExamenes = onSchedule({ schedule: "0 6 * * *", timeZone: "America/Mexico_City" }, async () => {
  const db = admin.firestore();
  const limiteMs = 180 * 24 * 60 * 60 * 1000; // 180 días
  const ahora = Date.now();
  const snap = await db.collection("tecnicos").get();

  for (const doc of snap.docs) {
    const t = doc.data();
    const examenes = t.examenes || {};
    let vencioAlguno = false;
    const examenesActualizados = { ...examenes };

    for (const [lineaId, resultado] of Object.entries(examenes)) {
      const fechaExamen = new Date(resultado.fecha).getTime();
      if (!fechaExamen) continue;
      if (ahora - fechaExamen > limiteMs) {
        delete examenesActualizados[lineaId];
        vencioAlguno = true;
      }
    }

    if (!vencioAlguno) continue;

    const update = { examenes: examenesActualizados };
    if (t.estadoAprobacion === "aprobado") {
      update.estadoAprobacion = "pendiente";
      update.motivoRechazo = "Recertificación semestral requerida: vuelve a presentar tu(s) examen(es) para seguir activo.";
    }
    await doc.ref.update(update);

    if (t.telefono) {
      await enviarSms(t.telefono,
        `Hola ${t.nombre || ""}, tu certificación SOYTU venció (6 meses). Abre tu app para volver a presentar tu examen y seguir recibiendo servicios. — SOYTU`);
    }
  }
});

// ════════════════════════════════════════════════════════════
// RESPALDO DE SMS POR TWILIO (si el gateway del celular no responde)
// ════════════════════════════════════════════════════════════
exports.respaldoSmsPorTwilio = onSchedule({ schedule: "every 5 minutes", timeZone: "America/Mexico_City" }, async () => {
  const db = admin.firestore();
  const cfgTw = await db.doc("config/twilio").get();
  if (!cfgTw.get("accountSid")) return;

  const limite = new Date(Date.now() - 5 * 60 * 1000).toISOString();
  const snap = await db.collection("sms_pendientes")
    .where("estado", "==", "pendiente")
    .where("creado", "<=", limite)
    .get();

  for (const doc of snap.docs) {
    const { telefono, texto } = doc.data();
    const ok = await enviarSmsPorTwilio(telefono, texto);
    await doc.ref.update({
      estado: ok ? "enviado_twilio" : "error",
      enviadoEn: new Date().toISOString(),
    });
  }
});

// ════════════════════════════════════════════════════════════
// CONEKTA: liga de pago con monto exacto + webhook de confirmación
// ════════════════════════════════════════════════════════════
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

// ════════════════════════════════════════════════════════════
// WHATSAPP: verificación de webhook de Meta (requisito de configuración)
// ════════════════════════════════════════════════════════════
exports.webhookWhatsApp = onRequest(async (req, res) => {
  const TOKEN_VERIFICACION = "3GbxYV7jw5sBZiHh18u0IK5G4Mg20-9v";

  if (req.method === "GET") {
    const modo = req.query["hub.mode"];
    const token = req.query["hub.verify_token"];
    const challenge = req.query["hub.challenge"];
    if (modo === "subscribe" && token === TOKEN_VERIFICACION) {
      res.status(200).send(challenge);
    } else {
      res.status(403).send("Token de verificación incorrecto");
    }
    return;
  }

  console.log("Evento de WhatsApp recibido:", JSON.stringify(req.body).slice(0, 500));
  res.status(200).send("EVENT_RECEIVED");
});
