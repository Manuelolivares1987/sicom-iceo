// .copiloto-test/next-server.ts
var NextResponse = { json: (b, i) => new Response(JSON.stringify(b), { status: i?.status ?? 200, headers: { "content-type": "application/json" } }) };

// src/app/api/copiloto/consulta/route.ts
import Anthropic from "@anthropic-ai/sdk";

// src/lib/copiloto/server.ts
import { createClient } from "@supabase/supabase-js";
function corpusCliente() {
  const url = process.env.COPILOTO_SUPABASE_URL;
  const key = process.env.COPILOTO_SUPABASE_SERVICE_KEY;
  if (!url || !key) return null;
  return createClient(url, key, { auth: { persistSession: false } });
}
function slug(v) {
  if (!v) return null;
  return v.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim().replace(/\s+/g, "-");
}
function normalizarPatente(p) {
  if (!p) return null;
  const s = p.toUpperCase().replace(/[^A-Z0-9]/g, "");
  const m = s.match(/^([A-Z]{2,4})(\d{2,4})$/);
  return m ? `${m[1]}-${m[2]}` : s || null;
}
async function fichaEquipo(corpus, patente) {
  const p = normalizarPatente(patente);
  if (!corpus || !p) return null;
  const { data } = await corpus.from("copiloto_fichas_equipo").select("*").eq("patente", p).maybeSingle();
  return data ?? null;
}
async function buscarCodigo(corpus, texto2, marca, limit = 8) {
  const { data, error } = await corpus.rpc("buscar_codigo_falla", { p_texto: texto2, p_marca: marca, p_limit: limit });
  if (error) throw error;
  return data ?? [];
}
function codigosEnTexto(q) {
  const out = /* @__PURE__ */ new Set();
  for (const m of Array.from(q.matchAll(/spn\s*[:#]?\s*(\d{2,7})(?:\D{1,8}fmi\s*[:#]?\s*(\d{1,2}))?/gi))) {
    out.add(m[2] ? `SPN ${m[1]} FMI ${m[2]}` : `SPN ${m[1]}`);
  }
  for (const m of Array.from(q.matchAll(/\b([PBCU][0-9A-F]{4})\b/gi))) out.add(m[1].toUpperCase());
  for (const m of Array.from(q.matchAll(/\bmid\s*(\d{2,3})\s*(pid|sid|psid)\s*(\d{1,4})(?:\D{1,6}fmi\s*(\d{1,2}))?/gi))) {
    out.add(`MID ${m[1]} ${m[2].toUpperCase()} ${m[3]}${m[4] ? ` FMI ${m[4]}` : ""}`);
  }
  if (!out.size && /c[oó]digo|falla|dtc|error/i.test(q)) {
    const m = q.match(/\b(\d{3,6})\s*[-/ ]\s*(\d{1,2})\b/);
    if (m) out.add(`${m[1]} ${m[2]}`);
  }
  return Array.from(out).slice(0, 3);
}
var BUCKET_PAGINAS = "paginas";
async function urlPagina(corpus, storagePath, segundos = 3600) {
  const { data } = await corpus.storage.from(BUCKET_PAGINAS).createSignedUrl(storagePath, segundos);
  return data?.signedUrl ?? null;
}
var BUCKET_ADJUNTOS = "adjuntos";
var TIPOS_ADJUNTO = ["image/jpeg", "image/png", "image/webp", "application/pdf"];
var MAX_BYTES_ADJUNTO = 20 * 1024 * 1024;

// .copiloto-test/server-fake.ts
var ACTIVO = {
  codigo: process.env.T_PATENTE ?? "KCBY-30",
  nombre: "Equipo",
  patente: process.env.T_PATENTE ?? "KCBY-30",
  tipo: "camion",
  estado: "operativo",
  horas_uso_actual: 12e3,
  kilometraje_actual: 21e4,
  anio_fabricacion: 2017,
  modelo: { nombre: process.env.T_MODELO ?? "Actros 3336 K", marca: { nombre: process.env.T_MARCA ?? "Mercedes-Benz" } }
};
function chain(result) {
  const p = Promise.resolve(result);
  const self = new Proxy(p, { get: (t, k) => k in t ? typeof t[k] === "function" ? t[k].bind(t) : t[k] : () => self });
  return self;
}
var sb = {
  from: (t) => ({
    select: () => chain(t === "activos" ? { data: ACTIVO, error: null } : { data: [], error: null }),
    insert: () => chain({ data: { id: "prueba-local" }, error: null }),
    update: () => chain({ data: null, error: null })
  }),
  rpc: () => chain({ data: [], error: null })
};
async function autenticar() {
  return { sb, uid: "uid-prueba" };
}

// src/app/api/copiloto/consulta/route.ts
var MODELO_IA = "claude-opus-5";
var EFFORT = process.env.COPILOTO_EFFORT ?? "medium";
var MAX_RONDAS = 6;
var SYSTEM_PROMPT = `# ROL
Eres el Copiloto T\xE9cnico del taller de PILLADO EMPRESAS: un t\xE9cnico master en diagn\xF3stico de camiones pesados di\xE9sel (24 V, J1939/J1587, postratamiento SCR/DPF/EGR, cajas automatizadas y Allison, frenos neum\xE1ticos ABS/EBS, hidr\xE1ulica de implementos). Acompa\xF1as a mec\xE1nicos en terreno y en taller, que te leen desde el tel\xE9fono. Hablas en espa\xF1ol de Chile, claro, directo y respetuoso, como un jefe de taller experimentado que ense\xF1a mientras resuelve.

# CONTEXTO DE LA OPERACI\xD3N
Flota de arriendo para miner\xEDa en Chile: aljibes de combustible, camiones de riego y agua industrial, camiones pluma, polibrazo y carrocer\xEDa plana. Marcas: Mercedes-Benz (Actros, Axor, Atego, Accelo), Mack GU813 con Allison, Volvo VM y FMX, Renault C440 y Scania P450B. Faenas en Coquimbo y Calama (2.300 m de altura): polvo, calor, vibraci\xF3n y ralent\xED prolongado por uso de PTO. La disponibilidad del equipo es cr\xEDtica, pero la seguridad va primero.

# M\xC9TODO DE DIAGN\xD3STICO (sigue este orden)
1. Verificar la falla: qu\xE9, cu\xE1ndo, en qu\xE9 condici\xF3n (fr\xEDo/caliente, con carga, en altura, con PTO), desde cu\xE1ndo y si hay c\xF3digo.
2. Revisar lo que ya se sabe: historial del equipo, casos resueltos del taller, OT y no conformidades abiertas.
3. Entender el sistema: c\xF3mo funciona el circuito o sistema involucrado en ESE modelo (ficha t\xE9cnica).
4. Hip\xF3tesis ordenadas de m\xE1s a menos probable, considerando las condiciones de faena.
5. Plan de pruebas de lo simple a lo complejo y de lo barato a lo caro: inspecci\xF3n visual \u2192 mediciones con multitester/man\xF3metro \u2192 pruebas funcionales \u2192 herramienta OEM. Cada prueba con herramienta, punto de medici\xF3n y criterio de aceptaci\xF3n.
6. Confirmaci\xF3n: c\xF3mo verificar que la reparaci\xF3n resolvi\xF3 la causa ra\xEDz (no solo el s\xEDntoma).

# FUENTES Y HERRAMIENTAS (en este orden)
1. Repositorio del taller: usa buscar_manuales (varias veces si hace falta, tambi\xE9n en ingl\xE9s y portugu\xE9s: fuse/relay/wiring diagram/connector; fus\xEDvel/rel\xE9/esquema el\xE9trico/chicote), buscar_codigo_falla, listar_documentos, casos_resueltos y ver_pagina para MIRAR diagramas, tablas de fusibles y pinouts antes de explicarlos (el mec\xE1nico ve la misma imagen).
2. Adjuntos del mec\xE1nico: fotos y PDFs (informe de esc\xE1ner, manual, placa, tablero). L\xE9elos con atenci\xF3n; cita un PDF como "(adjunto: <nombre>, p\xE1g. N)".
3. Web, si el repositorio no alcanza: web_search / web_fetch priorizando sitios oficiales del fabricante (manuales, body builder, boletines, recalls) y de fabricantes de componentes (Allison, WABCO, Bendix, Bosch, Delco Remy\u2026). Foros solo como \xFAltimo recurso y nunca sitios de manuales pirateados. Cita cada dato web con un enlace markdown [dominio](URL) en la misma l\xEDnea.
4. Criterio experto: si no hay informaci\xF3n en el repositorio ni en la web, NO te quedes en "no est\xE1". Resuelve con tu conocimiento de ingenier\xEDa de camiones pesados siguiendo el PROTOCOLO SIN DOCUMENTACI\xD3N.

# PROTOCOLO SIN DOCUMENTACI\xD3N (cuando resuelves con criterio experto)
Estructura la respuesta as\xED:
- **C\xF3mo funciona**: principio de funcionamiento del sistema en t\xE9rminos concretos para ese tipo de cami\xF3n.
- **Causas probables**: ordenadas, con el porqu\xE9 de cada una (s\xEDntoma que la delata).
- **Plan de pruebas**: pasos numerados; qu\xE9 medir, d\xF3nde y qu\xE9 resultado confirma o descarta cada causa. Usa criterios relativos o de est\xE1ndar universal (p. ej. comparar lado a lado, ca\xEDda de voltaje en circuito, continuidad, presencia de alimentaci\xF3n y masa, 60 \u03A9 entre CAN-H y CAN-L) y NO valores espec\xEDficos del fabricante que no tengas citados.
- **Dato que falta**: qu\xE9 valor exacto se necesita (torque, presi\xF3n, pin, amperaje) y d\xF3nde conseguirlo: portal OEM de la ficha t\xE9cnica, concesionario, herramienta de diagn\xF3stico (XENTRY, Premium Tech Tool, SDP3/SWS, Techline) o la placa del componente.
- **Riesgos**: qu\xE9 NO hacer mientras tanto.

# REGLAS OBLIGATORIAS
1. Valores cr\xEDticos (torques, presiones, calibraciones, capacidades, intervalos, amperajes de fusibles, pines, resistencias y voltajes espec\xEDficos del fabricante) SOLO desde una fuente citada: [Fn], c\xF3digos de la tabla, adjunto o enlace web. Nunca de memoria. Si no aparecen: "Ese dato no lo encontr\xE9 en los manuales ni en fuentes confiables \u2014 no te lo voy a inventar", y di d\xF3nde conseguirlo.
2. Cita cada dato del repositorio con su n\xFAmero entre corchetes: [F3], o varios: [F1][F4]. No inventes n\xFAmeros de fuente.
3. Jerarqu\xEDa de confiabilidad: manual oficial > procedimiento interno de Pillado > gu\xEDa t\xE9cnica o web oficial del fabricante > web de terceros > experiencia de campo (foros) > criterio experto. Si usas foros o criterio experto, dilo expl\xEDcitamente.
4. Si la informaci\xF3n es de otra variante (Volvo norteamericano para un FMX brasile\xF1o, Actros europeo para uno off-road, 12 V para un sistema de 24 V), advi\xE9rtelo y pide validar en el equipo.
5. La experiencia del taller es la pista m\xE1s valiosa: si el mismo s\xEDntoma ya se resolvi\xF3 en este equipo o en otro del mismo modelo, dilo primero ("En este mismo equipo / en otro GU813 esto se resolvi\xF3 con\u2026").
6. Si hay un DIAGN\xD3STICO EN CURSO: no pidas repetir comprobaciones hechas; propone LA siguiente comprobaci\xF3n m\xE1s discriminante (una a la vez, con herramienta y valor esperado) y pide registrarla con "Registrar comprobaci\xF3n". Cuando la evidencia apunte a una causa, dilo y recuerda "Encontr\xE9 la causa" para que el caso quede guardado.
7. C\xF3digo de falla: qu\xE9 significa, qu\xE9 ECU lo levanta, causas probables en orden, primera comprobaci\xF3n y si el equipo puede seguir operando. Si no est\xE1 en la tabla, dilo y explica c\xF3mo leer el c\xF3digo completo en el tablero de ESE modelo (ficha t\xE9cnica) o con esc\xE1ner.
8. Si faltan datos para diagnosticar, no adivines: m\xE1ximo 3 preguntas concretas, las que m\xE1s discriminan.
9. Foto: describe lo que se ve objetivamente y qu\xE9 NO se puede confirmar solo con la imagen.
10. No mezcles informaci\xF3n de marcas o modelos distintos al equipo consultado.
11. Seguridad: en frenos, direcci\xF3n, suspensi\xF3n, sistemas presurizados (aire, hidr\xE1ulica, combustible), gr\xFAa y polibrazo, trabajo bajo equipo levantado, estanques de combustible (DS 160) y el\xE9ctrico con bater\xEDa conectada, termina con "\u26A0\uFE0F Valida con el jefe de taller antes de intervenir." m\xE1s el bloqueo/aislaci\xF3n que corresponda (calzar ruedas, liberar presi\xF3n, desconectar bater\xEDa, bloqueo LOTO).

# FORMATO DE RESPUESTA (pantalla de tel\xE9fono)
- Primera l\xEDnea: el nivel de respaldo de la respuesta, uno de: "\u{1F4D8} Respaldo: manuales de la flota", "\u{1F310} Respaldo: fuentes web", "\u{1F9E0} Respaldo: criterio experto (no verificado en manual)" o una combinaci\xF3n.
- Luego la respuesta directa o la primera acci\xF3n. Sin relleno, sin repetir la pregunta, sin narrar tus b\xFAsquedas (la app ya muestra el progreso).
- P\xE1rrafos de 1 a 3 l\xEDneas, listas numeradas para pasos, **negrita** para valores y componentes clave; tablas markdown solo si son chicas (fusibles, pines).
- Cierra, cuando aplique, con "**Siguiente paso:**" y una sola acci\xF3n concreta.`;
var SISTEMAS_ENUM = [
  "electrico",
  "motor",
  "transmision",
  "frenos",
  "hidraulica",
  "direccion",
  "tren_rodaje",
  "combustible",
  "postratamiento",
  "implemento",
  "lubricacion"
];
var TOOLS = [
  {
    name: "buscar_manuales",
    description: "Busca en el corpus de manuales de la flota (manuales oficiales OEM, body builder, diagramas el\xE9ctricos, procedimientos internos de Pillado, gu\xEDas t\xE9cnicas investigadas, recalls). Devuelve extractos numerados [Fn] con t\xEDtulo, p\xE1gina y si hay imagen de la p\xE1gina. Filtra autom\xE1ticamente por la marca/modelo del equipo consultado. B\xFAsqueda por palabras (full-text): usa t\xE9rminos t\xE9cnicos concretos, no frases largas. Repite en ingl\xE9s o portugu\xE9s si en espa\xF1ol no aparece.",
    input_schema: {
      type: "object",
      properties: {
        consulta: { type: "string", description: 'Palabras clave, p.ej. "fusible luces trabajo", "wiring diagram PTO", "esquema el\xE9trico ARLA".' },
        sistema: { type: "string", enum: SISTEMAS_ENUM, description: "Opcional: prioriza documentos de ese sistema." }
      },
      required: ["consulta"]
    },
    eager_input_streaming: true
  },
  {
    name: "buscar_codigo_falla",
    description: 'Busca un c\xF3digo de falla en la tabla estructurada (SPN/FMI J1939, MID/PID/SID, c\xF3digos Mercedes FR/MR/GS, Allison, WABCO blink, DM1 Scania...). Acepta formatos como "SPN 3251 FMI 0", "3251-0", "P0420", "MID 128 PID 100" o una descripci\xF3n ("sensor NOx"). Devuelve significado, causas y comprobaciones con su fuente.',
    input_schema: {
      type: "object",
      properties: { codigo: { type: "string" } },
      required: ["codigo"]
    },
    eager_input_streaming: true
  },
  {
    name: "listar_documentos",
    description: 'Lista los documentos disponibles cuyo t\xEDtulo calce (p.ej. "diagrama", "fusibles", "body builder", "Allison"). \xDAsalo cuando pregunten qu\xE9 manuales/diagramas hay, o para encontrar el documento correcto antes de buscar dentro.',
    input_schema: {
      type: "object",
      properties: { texto: { type: "string" } },
      required: ["texto"]
    },
    eager_input_streaming: true
  },
  {
    name: "ver_pagina",
    description: "Muestra la IMAGEN de una p\xE1gina (diagramas el\xE9ctricos, tablas de fusibles/rel\xE9s, pinouts, esquemas hidr\xE1ulicos). Pasa el n\xFAmero de fuente [Fn] que tenga imagen disponible, o documento_id + pagina de listar_documentos. \xDAsalo para leer un diagrama antes de explicarlo. La misma imagen se le muestra al mec\xE1nico.",
    input_schema: {
      type: "object",
      properties: {
        fuente: { type: "integer", description: "N\xFAmero n de una fuente [Fn]." },
        documento_id: { type: "string" },
        pagina: { type: "integer" }
      }
    },
    eager_input_streaming: true
  },
  {
    name: "casos_resueltos",
    description: "Busca casos de diagn\xF3stico ya resueltos en este taller para este equipo o su mismo modelo, con otras palabras que las de la pregunta (p.ej. el sistema o el componente sospechoso).",
    input_schema: {
      type: "object",
      properties: { texto: { type: "string" } },
      required: ["texto"]
    },
    eager_input_streaming: true
  },
  // Respaldo cuando el repositorio no alcanza (herramientas de servidor de
  // Anthropic: corren en su infraestructura, sin código nuestro).
  { type: "web_search_20260209", name: "web_search", max_uses: 4 },
  { type: "web_fetch_20260209", name: "web_fetch", max_uses: 3 }
];
function filaATexto(row) {
  const partes = [];
  for (const [k, v] of Object.entries(row)) {
    if (v === null || v === void 0 || v === "") continue;
    if (/(^|_)id$/.test(k) || k === "usuario_id") continue;
    if (/^costo/.test(k)) continue;
    const s = typeof v === "object" ? JSON.stringify(v) : String(v);
    if (/^[0-9a-f]{8}-[0-9a-f]{4}/.test(s)) continue;
    partes.push(`${k}: ${s.length > 280 ? s.slice(0, 280) + "\u2026" : s}`);
  }
  return partes.join(" \xB7 ");
}
var ES_EN = {
  fusible: "fuse",
  fusibles: "fuses",
  rele: "relay",
  rel\u00E9: "relay",
  reles: "relays",
  bomba: "pump",
  freno: "brake",
  frenos: "brakes",
  embrague: "clutch",
  caja: "transmission",
  cambios: "gearbox",
  motor: "engine",
  correa: "belt",
  aceite: "oil",
  filtro: "filter",
  filtros: "filters",
  refrigerante: "coolant",
  direccion: "steering",
  direcci\u00F3n: "steering",
  suspension: "suspension",
  eje: "axle",
  ejes: "axles",
  rueda: "wheel",
  neumatico: "tire",
  neum\u00E1tico: "tire",
  bateria: "battery",
  bater\u00EDa: "battery",
  alternador: "alternator",
  arranque: "starter",
  cableado: "wiring",
  diagrama: "diagram",
  esquema: "schematic",
  plano: "wiring",
  falla: "fault",
  fallas: "faults",
  codigo: "code",
  c\u00F3digo: "code",
  conector: "connector",
  torque: "torque",
  apriete: "torque",
  presion: "pressure",
  presi\u00F3n: "pressure",
  luces: "lights",
  luz: "lamp",
  tablero: "instrument",
  sensor: "sensor",
  compresor: "compressor",
  estanque: "tank",
  mantencion: "maintenance",
  mantenci\u00F3n: "maintenance",
  mantenimiento: "maintenance",
  sumergible: "submersible",
  adblue: "DEF",
  urea: "DEF",
  inyector: "injector",
  turbo: "turbocharger",
  masa: "ground"
};
function traduccionTaller(q) {
  const extras = /* @__PURE__ */ new Set();
  for (const w of q.toLowerCase().split(/[^a-záéíóúñü]+/)) {
    if (ES_EN[w]) extras.add(ES_EN[w]);
  }
  return extras.size ? Array.from(extras).join(" ") : null;
}
function codigoParaCliente(c) {
  return {
    codigo: c.codigo,
    formato: c.formato,
    descripcion: c.descripcion,
    aplica: c.aplica,
    marca: c.marca,
    causas: Array.isArray(c.causas) ? c.causas : [],
    comprobaciones: Array.isArray(c.comprobaciones) ? c.comprobaciones : [],
    confiabilidad: c.confiabilidad,
    fuente: c.fuente,
    coincidencia: c.coincidencia
  };
}
function codigosATexto(cs) {
  return cs.map(
    (c) => `- ${c.codigo} (${c.formato}${c.ecu ? `, ECU ${c.ecu}` : ""}${c.aplica ? `, aplica: ${c.aplica}` : ""}; coincidencia ${c.coincidencia}; confiabilidad ${c.confiabilidad}${c.fuente ? `; fuente: ${c.fuente}` : ""})
  Significado: ${c.descripcion}
` + (c.causas?.length ? `  Causas: ${c.causas.join(" | ")}
` : "") + (c.comprobaciones?.length ? `  Comprobaciones: ${c.comprobaciones.join(" | ")}
` : "")
  ).join("");
}
function fichaATexto(f) {
  const l = [
    `FICHA T\xC9CNICA (Biblioteca Maestra): ${f.patente} \xB7 ${f.marca ?? ""} ${f.modelo ?? ""} ${f.anio ?? ""}`,
    f.vin && `VIN ${f.vin}`,
    f.numero_motor && `N\xB0 motor ${f.numero_motor}`,
    f.motor && `Motor: ${f.motor}`,
    f.transmision && `Transmisi\xF3n: ${f.transmision}`,
    f.emisiones && `Emisiones: ${f.emisiones}`,
    f.ecus && `Electr\xF3nica/ECUs: ${f.ecus}`,
    f.equipamiento && `Equipamiento: ${f.equipamiento}`,
    f.implemento && `Implemento (componentes): ${f.implemento}`,
    f.zona && `Zona: ${f.zona}`,
    f.lectura_codigos && `C\xF3mo leer c\xF3digos en el tablero: ${f.lectura_codigos}`,
    f.fuente_oem && `Portal OEM (manual de taller por VIN): ${f.fuente_oem}`,
    f.notas && `Notas: ${f.notas}`
  ].filter(Boolean);
  return l.join("\n") + "\n";
}
async function POST(req) {
  const auth = await autenticar(req);
  if ("error" in auth) return NextResponse.json({ error: auth.error }, { status: auth.status });
  const { sb: sb2, uid } = auth;
  if (!process.env.ANTHROPIC_API_KEY) {
    return NextResponse.json({ error: "Copiloto sin configurar (falta ANTHROPIC_API_KEY en el servidor)." }, { status: 503 });
  }
  let body;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "JSON inv\xE1lido." }, { status: 400 });
  }
  const pregunta2 = (body.pregunta ?? "").trim();
  const adjuntos = (body.adjuntos ?? []).filter((a) => a && typeof a.path === "string" && a.path.startsWith(`${uid}/`) && !a.path.includes("..") && TIPOS_ADJUNTO.includes(a.tipo)).slice(0, 6);
  if (pregunta2.length < 3 && !body.fotoBase64 && !adjuntos.length) {
    return NextResponse.json({ error: "Escribe la pregunta o el s\xEDntoma." }, { status: 400 });
  }
  if (body.fotoBase64 && body.fotoBase64.length > 55e5) {
    return NextResponse.json({ error: "La foto es muy pesada. Intenta de nuevo." }, { status: 400 });
  }
  const ndjson = body.formato === "ndjson";
  const corpus = corpusCliente();
  let contextoEquipo = "";
  let marcaSlug = null;
  let modeloSlug = null;
  let ficha = null;
  if (body.activoId) {
    const [act, hist, ncs, ot, casos, dx] = await Promise.all([
      sb2.from("activos").select("codigo, nombre, patente, tipo, estado, horas_uso_actual, kilometraje_actual, anio_fabricacion, vin_chasis, numero_motor, tipo_equipamiento, capacidad, modelo:modelos(nombre, marca:marcas(nombre))").eq("id", body.activoId).maybeSingle(),
      sb2.from("v_historial_mantenimiento_equipo").select("*").eq("activo_id", body.activoId).order("fecha", { ascending: false }).limit(12),
      sb2.from("no_conformidades").select("*").eq("activo_id", body.activoId).eq("resuelto", false).order("created_at", { ascending: false }).limit(10),
      body.otId ? sb2.from("ordenes_trabajo").select("folio, tipo, estado, prioridad, observaciones").eq("id", body.otId).maybeSingle() : Promise.resolve({ data: null, error: null }),
      // Experiencia interna: casos resueltos del mismo equipo o modelo (MIG543)
      sb2.rpc("rpc_copiloto_casos_similares", {
        p_activo_id: body.activoId,
        p_texto: pregunta2 || "falla",
        p_limit: 3
      }),
      body.diagnosticoId ? sb2.from("copiloto_diagnosticos").select("sintoma, sistema, estado, comprobaciones").eq("id", body.diagnosticoId).maybeSingle() : Promise.resolve({ data: null, error: null })
    ]);
    const a = act.data;
    if (a) {
      const modelo = a.modelo;
      marcaSlug = slug(modelo?.marca?.nombre);
      modeloSlug = slug(modelo?.nombre);
      contextoEquipo += `EQUIPO: ${a.codigo ?? ""} ${a.nombre ?? ""} \xB7 patente ${a.patente ?? "\u2014"} \xB7 ${modelo?.marca?.nombre ?? ""} ${modelo?.nombre ?? ""}${a.anio_fabricacion ? ` \xB7 a\xF1o ${a.anio_fabricacion}` : ""} \xB7 estado ${a.estado ?? "\u2014"} \xB7 hor\xF3metro ${a.horas_uso_actual ?? "\u2014"} h \xB7 km ${a.kilometraje_actual ?? "\u2014"}${a.vin_chasis ? ` \xB7 VIN ${a.vin_chasis}` : ""}${a.numero_motor ? ` \xB7 motor N\xB0 ${a.numero_motor}` : ""}${a.tipo_equipamiento ? ` \xB7 ${a.tipo_equipamiento}` : ""}${a.capacidad ? ` ${a.capacidad}` : ""}
`;
      try {
        ficha = await fichaEquipo(corpus, a.patente);
      } catch {
      }
      if (ficha) contextoEquipo += "\n" + fichaATexto(ficha);
    }
    if (ot.data) contextoEquipo += `
OT ACTUAL: ${filaATexto(ot.data)}
`;
    if (hist.data?.length) {
      contextoEquipo += `
HISTORIAL DE MANTENIMIENTO (\xFAltimos ${hist.data.length}):
` + hist.data.map((r) => `- ${filaATexto(r)}`).join("\n") + "\n";
    }
    if (ncs.data?.length) {
      contextoEquipo += `
NO CONFORMIDADES ABIERTAS (${ncs.data.length}):
` + ncs.data.map((r) => `- ${filaATexto(r)}`).join("\n") + "\n";
    }
    const casosData = casos.data ?? [];
    if (casosData.length) contextoEquipo += `
CASOS RESUELTOS ANTERIORES (experiencia interna del taller):
${casosATexto(casosData)}`;
    const dxData = dx.data;
    if (dxData && dxData.estado === "abierto") {
      const compr = (dxData.comprobaciones ?? []).map((x, i) => `${i + 1}. ${x.descripcion}${x.valor ? ` = ${x.valor}` : ""} \u2192 ${x.resultado}`).join("\n");
      contextoEquipo += `
DIAGN\xD3STICO EN CURSO:
S\xEDntoma declarado: ${dxData.sintoma}${dxData.sistema ? ` \xB7 Sistema: ${dxData.sistema}` : ""}
` + (compr ? `Comprobaciones ya registradas:
${compr}
` : "A\xFAn sin comprobaciones registradas.\n");
    }
  }
  const fuentes = /* @__PURE__ */ new Map();
  const porNumero = /* @__PURE__ */ new Map();
  const paginasVistas = /* @__PURE__ */ new Set();
  function registrar(rows) {
    return rows.map((r) => {
      const ya = fuentes.get(r.chunk_id);
      if (ya) return ya;
      const f = { ...r, n: fuentes.size + 1 };
      fuentes.set(r.chunk_id, f);
      porNumero.set(f.n, f);
      return f;
    });
  }
  function fuentesATexto(fs) {
    return fs.map(
      (f) => `[F${f.n}] ${f.titulo} \u2014 p\xE1g. ${f.pagina} (${f.tipo_documento === "manual_oficial" ? "manual oficial" : f.tipo_documento.replace(/_/g, " ")}${f.confiabilidad ? `, ${f.confiabilidad.replace(/_/g, " ")}` : ""}${f.con_imagen ? ", IMAGEN DISPONIBLE \u2192 ver_pagina" : ""})
` + f.contenido.slice(0, 2200)
    ).join("\n\n");
  }
  let corpusDisponible = false;
  async function buscarManuales(consulta, sistema, limit = 8) {
    if (!corpus) return [];
    const { data, error } = await corpus.rpc("buscar_chunks", {
      p_query: consulta,
      p_marca: marcaSlug,
      p_modelo: modeloSlug,
      p_limit: limit,
      p_sistema: sistema ?? null
    });
    if (error) throw error;
    corpusDisponible = true;
    return registrar(data ?? []);
  }
  const codigosDetectados = codigosEnTexto(pregunta2);
  const codigosEncontrados = [];
  let bloqueFuentes = "";
  if (corpus && pregunta2) {
    try {
      const traduccion = traduccionTaller(pregunta2);
      const [es, en, ...cods] = await Promise.all([
        buscarManuales(pregunta2, void 0, 8),
        traduccion ? buscarManuales(traduccion, void 0, 4) : Promise.resolve([]),
        ...codigosDetectados.map((c) => buscarCodigo(corpus, c, marcaSlug, 5).catch(() => []))
      ]);
      const iniciales = [...es, ...en].slice(0, 10);
      for (const lista of cods) codigosEncontrados.push(...lista);
      bloqueFuentes = iniciales.length ? `FUENTES (b\xFAsqueda autom\xE1tica inicial; usa buscar_manuales para m\xE1s):
${fuentesATexto(iniciales)}` : "FUENTES: la b\xFAsqueda autom\xE1tica no encontr\xF3 secciones relevantes; usa buscar_manuales con otros t\xE9rminos (o en ingl\xE9s/portugu\xE9s).";
    } catch {
      bloqueFuentes = "FUENTES: el corpus de manuales no respondi\xF3. Responde con el contexto del equipo y criterio general, dejando claro qu\xE9 valores habr\xEDa que confirmar en el manual.";
    }
  } else if (!corpus) {
    bloqueFuentes = "FUENTES: el corpus de manuales a\xFAn no est\xE1 disponible. Responde solo con el contexto del equipo y criterio general de taller, dejando claro qu\xE9 valores habr\xEDa que confirmar en el manual.";
  }
  const bloqueCodigos = codigosEncontrados.length ? `
C\xD3DIGOS DE FALLA (tabla estructurada, detectados en la pregunta):
${codigosATexto(codigosEncontrados)}` : codigosDetectados.length ? `
C\xD3DIGOS DE FALLA: se detect\xF3 ${codigosDetectados.join(", ")} en la pregunta pero no est\xE1 en la tabla cargada.
` : "";
  const { data: ins } = await sb2.from("copiloto_consultas").insert({
    usuario_id: uid,
    activo_id: body.activoId ?? null,
    ot_id: body.otId ?? null,
    diagnostico_id: body.diagnosticoId ?? null,
    pregunta: pregunta2 || (adjuntos.length ? `(adjuntos: ${adjuntos.map((a) => a.nombre).join(", ")})` : "(solo foto)"),
    con_foto: !!body.fotoBase64 || adjuntos.some((a) => a.tipo.startsWith("image/")),
    modelo: MODELO_IA,
    fuentes: []
  }).select("id").single();
  const consultaId = ins?.id ?? null;
  const contenidoUsuario = [];
  const adjuntosFallidos = [];
  if (adjuntos.length && corpus) {
    const bajados = await Promise.all(adjuntos.map(async (a) => {
      const { data, error } = await corpus.storage.from(BUCKET_ADJUNTOS).download(a.path);
      if (error || !data) return null;
      return { a, b64: Buffer.from(await data.arrayBuffer()).toString("base64") };
    }));
    bajados.forEach((x, i) => {
      if (!x) {
        adjuntosFallidos.push(adjuntos[i].nombre);
        return;
      }
      if (x.a.tipo === "application/pdf") {
        contenidoUsuario.push({
          type: "document",
          title: x.a.nombre.slice(0, 200),
          source: { type: "base64", media_type: "application/pdf", data: x.b64 }
        });
      } else {
        contenidoUsuario.push({
          type: "image",
          source: { type: "base64", media_type: x.a.tipo, data: x.b64 }
        });
      }
    });
    await corpus.from("copiloto_adjuntos").update({ consulta_id: consultaId, estado: "usado" }).in("storage_path", adjuntos.map((a) => a.path));
  }
  if (body.fotoBase64) {
    contenidoUsuario.push({
      type: "image",
      source: { type: "base64", media_type: body.fotoTipo === "image/png" ? "image/png" : "image/jpeg", data: body.fotoBase64 }
    });
  }
  contenidoUsuario.push({
    type: "text",
    text: `${contextoEquipo ? contextoEquipo + "\n" : "EQUIPO: consulta general, sin equipo seleccionado (no filtres por marca).\n\n"}${bloqueFuentes}
${bloqueCodigos}` + (adjuntos.length ? `
ADJUNTOS DEL MEC\xC1NICO: ${adjuntos.map((a) => a.nombre).join(", ")}${adjuntosFallidos.length ? ` (no se pudieron leer: ${adjuntosFallidos.join(", ")})` : ""}
` : "") + `
PREGUNTA DEL MEC\xC1NICO:
${pregunta2 || "Revisa lo que adjunt\xE9 y dime qu\xE9 observas y qu\xE9 hago."}`
  });
  const mensajes = [
    ...(body.historial ?? []).slice(-6).map((t) => ({
      role: t.rol === "assistant" ? "assistant" : "user",
      content: t.texto.slice(0, 4e3)
    })),
    { role: "user", content: contenidoUsuario }
  ];
  async function ejecutar(tool, emitir) {
    const input = tool.input ?? {};
    const str = (k) => typeof input[k] === "string" ? input[k].trim() : "";
    const err = (m) => ({ type: "tool_result", tool_use_id: tool.id, is_error: true, content: m });
    const ok = (content) => ({ type: "tool_result", tool_use_id: tool.id, content });
    try {
      switch (tool.name) {
        case "buscar_manuales": {
          const q = str("consulta");
          if (q.length < 2) return err("consulta vac\xEDa");
          emitir({ t: "estado", d: `Buscando en manuales: \xAB${q}\xBB` });
          if (!corpus) return ok("El corpus de manuales no est\xE1 disponible.");
          const sistema = SISTEMAS_ENUM.includes(str("sistema")) ? str("sistema") : void 0;
          const r = await buscarManuales(q, sistema, 6);
          return ok(r.length ? fuentesATexto(r) : "Sin resultados. Prueba otros t\xE9rminos, sin\xF3nimos o el idioma del manual (ingl\xE9s/portugu\xE9s).");
        }
        case "buscar_codigo_falla": {
          const q = str("codigo");
          if (!q) return err("c\xF3digo vac\xEDo");
          emitir({ t: "estado", d: `Buscando c\xF3digo de falla ${q}` });
          if (!corpus) return ok("La tabla de c\xF3digos no est\xE1 disponible.");
          const r = await buscarCodigo(corpus, q, marcaSlug, 8);
          for (const c of r) if (!codigosEncontrados.some((x) => x.id === c.id)) codigosEncontrados.push(c);
          return ok(r.length ? codigosATexto(r) : `El c\xF3digo \xAB${q}\xBB no est\xE1 en la tabla cargada.`);
        }
        case "listar_documentos": {
          const q = str("texto");
          emitir({ t: "estado", d: `Revisando documentos disponibles: \xAB${q}\xBB` });
          if (!corpus) return ok("El corpus no est\xE1 disponible.");
          const { data, error } = await corpus.rpc("buscar_documentos", { p_texto: q, p_marca: marcaSlug, p_limit: 15 });
          if (error) throw error;
          const docs = data ?? [];
          return ok(docs.length ? docs.map((d) => `- ${d.titulo} (documento_id ${d.documento_id}; ${d.paginas ?? "?"} p\xE1gs; ${d.tipo_documento}${d.marca ? `; ${d.marca}` : ""}${d.con_imagenes ? "; p\xE1ginas con imagen" : ""})`).join("\n") : "No hay documentos con ese t\xEDtulo. Prueba buscar_manuales por contenido.");
        }
        case "ver_pagina": {
          if (!corpus) return ok("El corpus no est\xE1 disponible.");
          let docId = null, pagina = null, titulo = "";
          let fuenteN = null;
          if (typeof input.fuente === "number") {
            const f = porNumero.get(input.fuente);
            if (!f) return err(`No existe la fuente F${input.fuente}`);
            docId = f.documento_id;
            pagina = f.pagina;
            titulo = f.titulo;
            fuenteN = f.n;
          } else if (str("documento_id") && typeof input.pagina === "number") {
            docId = str("documento_id");
            pagina = input.pagina;
          } else return err("Indica fuente, o documento_id y pagina");
          emitir({ t: "estado", d: `Mirando la p\xE1gina ${pagina}${titulo ? ` de \xAB${titulo}\xBB` : ""}` });
          const { data: pg } = await corpus.from("copiloto_paginas").select("storage_path").eq("documento_id", docId).eq("pagina", pagina).maybeSingle();
          if (!pg) return ok("Esa p\xE1gina no tiene imagen disponible (solo texto). Trabaja con el extracto de texto.");
          const url = await urlPagina(corpus, pg.storage_path);
          if (!url) return err("No se pudo generar la imagen de la p\xE1gina");
          if (fuenteN == null) {
            const { data: d } = await corpus.from("copiloto_documentos").select("titulo, archivo, tipo_documento, sistema, url_fuente, confiabilidad").eq("id", docId).maybeSingle();
            const doc = d;
            const [f] = registrar([{
              chunk_id: -(Date.now() % 1e9) - pagina,
              documento_id: docId,
              titulo: doc?.titulo ?? "Documento",
              archivo: doc?.archivo ?? "",
              tipo_documento: doc?.tipo_documento ?? "manual_oficial",
              pagina,
              contenido: "",
              sistema: doc?.sistema ?? null,
              url_fuente: doc?.url_fuente ?? null,
              confiabilidad: doc?.confiabilidad ?? null,
              con_imagen: true
            }]);
            fuenteN = f.n;
            titulo = f.titulo;
          }
          const img = await fetch(url);
          if (!img.ok) return err("No se pudo descargar la imagen de la p\xE1gina");
          const b64 = Buffer.from(await img.arrayBuffer()).toString("base64");
          paginasVistas.add(fuenteN);
          return ok([
            { type: "image", source: { type: "base64", media_type: "image/jpeg", data: b64 } },
            { type: "text", text: `Imagen de [F${fuenteN}] ${titulo} \u2014 p\xE1g. ${pagina}. C\xEDtala como [F${fuenteN}].` }
          ]);
        }
        case "casos_resueltos": {
          const q = str("texto");
          if (!body.activoId) return ok("Sin equipo seleccionado: no hay casos por modelo.");
          emitir({ t: "estado", d: "Revisando casos resueltos del taller" });
          const { data, error } = await sb2.rpc("rpc_copiloto_casos_similares", { p_activo_id: body.activoId, p_texto: q || "falla", p_limit: 5 });
          if (error) throw error;
          const cs = data ?? [];
          return ok(cs.length ? casosATexto(cs) : "No hay casos resueltos parecidos para este equipo o modelo.");
        }
        default:
          return err(`Herramienta desconocida: ${tool.name}`);
      }
    } catch (e) {
      return err(`Fall\xF3 la herramienta: ${e instanceof Error ? e.message : "error"}`);
    }
  }
  async function fuentesCliente(respuesta) {
    const citadas = new Set(Array.from(respuesta.matchAll(/\[F(\d+)\]/g)).map((m) => Number(m[1])));
    const lista = Array.from(porNumero.values()).filter((f) => citadas.has(f.n) || paginasVistas.has(f.n));
    const conImg = lista.filter((f) => f.con_imagen);
    const imgs = /* @__PURE__ */ new Map();
    if (corpus && conImg.length) {
      await Promise.all(conImg.map(async (f) => {
        const { data } = await corpus.from("copiloto_paginas").select("storage_path").eq("documento_id", f.documento_id).eq("pagina", f.pagina).maybeSingle();
        const u = data ? await urlPagina(corpus, data.storage_path, 6 * 3600) : null;
        if (u) imgs.set(f.n, u);
      }));
    }
    const repo = lista.sort((a, b) => a.n - b.n).map((f) => {
      const esPdf = f.url_fuente && /\.pdf($|\?)/i.test(f.url_fuente);
      return {
        n: f.n,
        titulo: f.titulo,
        pagina: f.pagina,
        tipo: f.tipo_documento,
        confiabilidad: f.confiabilidad ?? null,
        url: f.url_fuente ? esPdf ? `${f.url_fuente}#page=${f.pagina}` : f.url_fuente : null,
        imagen: imgs.get(f.n) ?? null,
        citada: citadas.has(f.n)
      };
    });
    const web = /* @__PURE__ */ new Map();
    for (const m of Array.from(respuesta.matchAll(/\[([^\]]{1,120})\]\((https?:\/\/[^\s)]+)\)/g))) {
      if (!web.has(m[2])) web.set(m[2], m[1]);
    }
    let n = porNumero.size;
    const webFuentes = Array.from(web.entries()).slice(0, 12).map(([url, titulo]) => ({
      n: ++n,
      titulo,
      pagina: 0,
      tipo: "web",
      confiabilidad: null,
      url,
      imagen: null,
      citada: true
    }));
    return [...repo, ...webFuentes];
  }
  const anthropic = new Anthropic();
  const t02 = Date.now();
  const encoder = new TextEncoder();
  const stream = new ReadableStream({
    async start(controller) {
      const emitir = (e) => {
        if (ndjson) controller.enqueue(encoder.encode(JSON.stringify(e) + "\n"));
        else if (e.t === "texto") controller.enqueue(encoder.encode(e.d));
      };
      let respuesta = "";
      let inTok = 0, outTok = 0;
      try {
        if (codigosEncontrados.length) emitir({ t: "codigos", d: codigosEncontrados.map(codigoParaCliente) });
        emitir({ t: "estado", d: "Analizando con manuales, casos e historial\u2026" });
        let reintentosJson = 0;
        for (let ronda = 0; ronda < MAX_RONDAS; ronda++) {
          const ultima = ronda === MAX_RONDAS - 1;
          const s = anthropic.beta.messages.stream({
            model: MODELO_IA,
            max_tokens: 16e3,
            betas: ["server-side-fallback-2026-07-01"],
            fallbacks: "default",
            thinking: { type: "adaptive" },
            output_config: { effort: EFFORT },
            system: [{ type: "text", text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" } }],
            // Caché del prefijo que crece ronda a ronda (PDFs adjuntos, resultados)
            cache_control: { type: "ephemeral" },
            // En la última ronda se quitan las herramientas: tiene que responder
            tools: ultima ? void 0 : TOOLS,
            messages: mensajes
          });
          s.on("text", (delta) => {
            respuesta += delta;
            emitir({ t: "texto", d: delta });
          });
          s.on("streamEvent", (ev) => {
            if (ev.type === "content_block_start" && ev.content_block.type === "server_tool_use") {
              emitir({ t: "estado", d: ev.content_block.name === "web_fetch" ? "Leyendo una p\xE1gina web\u2026" : "No est\xE1 en el repositorio: buscando en la web\u2026" });
            }
          });
          let msg;
          try {
            msg = await s.finalMessage();
            reintentosJson = 0;
          } catch (e) {
            if (e instanceof Anthropic.APIError || reintentosJson++ >= 1) throw e;
            continue;
          }
          inTok += Math.round((msg.usage.input_tokens ?? 0) + (msg.usage.cache_read_input_tokens ?? 0) * 0.1 + (msg.usage.cache_creation_input_tokens ?? 0) * 1.25);
          outTok += msg.usage.output_tokens ?? 0;
          if (msg.stop_reason === "refusal") {
            const aviso = "\n\n[El copiloto no puede responder esta consulta. Reform\xFAlala o consulta al jefe de taller.]";
            respuesta += aviso;
            emitir({ t: "texto", d: aviso });
            break;
          }
          if (msg.stop_reason === "pause_turn") {
            mensajes.push({ role: "assistant", content: msg.content });
            emitir({ t: "estado", d: "Buscando en la web\u2026" });
            continue;
          }
          const usos = msg.content.filter((b) => b.type === "tool_use");
          if (msg.stop_reason !== "tool_use" || usos.length === 0) break;
          mensajes.push({ role: "assistant", content: msg.content });
          const resultados = await Promise.all(usos.map((u) => ejecutar(u, emitir)));
          mensajes.push({ role: "user", content: resultados });
          if (respuesta.trim()) {
            respuesta += "\n\n";
            emitir({ t: "texto", d: "\n\n" });
          }
        }
        const fs = await fuentesCliente(respuesta);
        emitir({ t: "fuentes", d: fs });
        if (codigosEncontrados.length) emitir({ t: "codigos", d: codigosEncontrados.map(codigoParaCliente) });
        if (consultaId) {
          await sb2.from("copiloto_consultas").update({
            respuesta,
            fuentes: fs.map((f) => ({ n: f.n, titulo: f.titulo, pagina: f.pagina, tipo: f.tipo, url: f.url, citada: f.citada })),
            input_tokens: inTok,
            output_tokens: outTok,
            duracion_ms: Date.now() - t02
          }).eq("id", consultaId);
        }
        emitir({ t: "fin", consultaId });
      } catch (err) {
        console.error("[copiloto] consulta fall\xF3", consultaId, err instanceof Error ? err.message : err);
        const msg = err instanceof Anthropic.APIError ? `

[El copiloto tuvo un problema (${err.status}). Intenta de nuevo.]` : "\n\n[El copiloto tuvo un problema. Intenta de nuevo.]";
        emitir({ t: "texto", d: msg });
        emitir({ t: "error", d: msg.trim() });
        if (consultaId) {
          await sb2.from("copiloto_consultas").update({
            respuesta: respuesta + msg,
            input_tokens: inTok,
            output_tokens: outTok,
            duracion_ms: Date.now() - t02
          }).eq("id", consultaId);
        }
      } finally {
        controller.close();
      }
    }
  });
  return new Response(stream, {
    headers: {
      "Content-Type": ndjson ? "application/x-ndjson; charset=utf-8" : "text/plain; charset=utf-8",
      "Cache-Control": "no-cache",
      "X-Accel-Buffering": "no",
      ...consultaId ? { "X-Copiloto-Id": consultaId } : {}
    }
  });
}
function casosATexto(cs) {
  return cs.map((c) => {
    const compr = (c.comprobaciones ?? []).map((x) => `${x.descripcion}${x.valor ? ` = ${x.valor}` : ""} (${x.resultado})`).join("; ");
    return `- [${c.mismo_equipo ? "ESTE MISMO EQUIPO" : `mismo modelo, ${c.equipo}`} \xB7 ${(c.resuelto_at ?? "").slice(0, 10)}] S\xEDntoma: ${c.sintoma}. Causa ra\xEDz: ${c.causa_raiz}.${c.reparacion ? ` Reparaci\xF3n: ${c.reparacion}.` : ""}${compr ? ` Comprobaciones: ${compr}.` : ""}`;
  }).join("\n") + "\n";
}

// .copiloto-test/harness.ts
var pregunta = process.argv[2] ?? "hola";
var conEquipo = process.argv[3] !== "general";
var t0 = Date.now();
var res = await POST(new Request("http://x/api", { method: "POST", body: JSON.stringify({ pregunta, activoId: conEquipo ? "a1" : void 0, formato: "ndjson" }) }));
if (!(res.headers.get("content-type") ?? "").includes("ndjson")) {
  console.log("HTTP", res.status, await res.text());
  process.exit(1);
}
var reader = res.body.getReader();
var dec = new TextDecoder();
var buf = "";
var texto = "";
for (; ; ) {
  const { done, value } = await reader.read();
  if (done) break;
  buf += dec.decode(value, { stream: true });
  const ls = buf.split("\n");
  buf = ls.pop() ?? "";
  for (const l of ls) {
    if (!l) continue;
    const e = JSON.parse(l);
    if (e.t === "estado") console.log("  [estado]", e.d);
    else if (e.t === "texto") texto += e.d;
    else if (e.t === "fuentes") console.log("  [fuentes]", e.d.map((f) => `F${f.n}${f.imagen ? "\u{1F5BC}" : ""}${f.citada ? "" : "(no citada)"} ${f.titulo.slice(0, 55)} p${f.pagina}${f.url ? " \u{1F517}" : ""}`).join("\n            "));
    else if (e.t === "codigos") console.log("  [codigos]", e.d.map((c) => c.codigo).join(", "));
    else if (e.t === "error") console.log("  [ERROR]", e.d);
  }
}
console.log("\n----- RESPUESTA (" + Math.round((Date.now() - t0) / 1e3) + " s) -----\n" + texto);
