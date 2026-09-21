import { NextResponse } from 'next/server'
import Anthropic from '@anthropic-ai/sdk'
import {
  autenticar, corpusCliente, slug, fichaEquipo, buscarCodigo, codigosEnTexto, urlPagina,
  BUCKET_ADJUNTOS, TIPOS_ADJUNTO, type FichaEquipo, type CodigoFalla, type AdjuntoRef,
} from '@/lib/copiloto/server'
import type { EventoCopiloto, FuenteCopiloto, CodigoCopiloto } from '@/lib/copiloto/tipos'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'
export const maxDuration = 300

// ============================================================================
// Copiloto Técnico del taller
// 2026-09-08  v1: contexto del equipo (SICOM) + manuales (corpus) → Claude.
// 2026-09-19  v2 «clase mundial» (Manuel: «que sea una verdadera ayuda»):
//   - Claude trabaja como agente: busca en los manuales cuantas veces
//     necesite (en español, inglés y portugués — los manuales OEM vienen en
//     los tres), consulta la tabla de códigos de falla, lista documentos y
//     MIRA la página del diagrama citado (visión) antes de explicarlo.
//   - Ficha técnica del camión (VIN, motor, caja, ECUs, cómo leer códigos en
//     su tablero) desde la Biblioteca Maestra.
//   - Códigos de falla detectados en la pregunta se buscan de inmediato,
//     sin esperar a la IA.
//   - Stream NDJSON: estado de lo que está buscando, texto, fuentes numeradas
//     [F1] con enlace al documento oficial e imagen de la página.
//   - Adjuntos: el mecánico sube fotos y PDFs (storage del corpus, URL
//     firmada); Claude los lee (visión / documento).
//   - Si el repositorio no alcanza, Claude busca en la web (web_search /
//     web_fetch, fuentes oficiales primero) y usa su criterio técnico,
//     SIEMPRE etiquetando el origen (Manuel: «si no encuentra en su
//     repositorio te ocupe a ti para solucionar»).
// Reglas de no-invención intactas: valores críticos solo desde fuentes.
// Cada consulta queda auditada en copiloto_consultas (MIG542).
// ============================================================================

const MODELO_IA = 'claude-opus-5'
// medium: buen balance calidad/latencia para un mecánico esperando en el
// teléfono; se puede subir a 'high' en Netlify sin redeploy de código.
const EFFORT = (process.env.COPILOTO_EFFORT ?? 'medium') as 'low' | 'medium' | 'high' | 'xhigh' | 'max'
const MAX_RONDAS = 6

const SYSTEM_PROMPT = `# ROL
Eres el Copiloto Técnico del taller de PILLADO EMPRESAS: un técnico master en diagnóstico de camiones pesados diésel (24 V, J1939/J1587, postratamiento SCR/DPF/EGR, cajas automatizadas y Allison, frenos neumáticos ABS/EBS, hidráulica de implementos). Acompañas a mecánicos en terreno y en taller, que te leen desde el teléfono. Hablas en español de Chile, claro, directo y respetuoso, como un jefe de taller experimentado que enseña mientras resuelve.

# CONTEXTO DE LA OPERACIÓN
Flota de arriendo para minería en Chile: aljibes de combustible, camiones de riego y agua industrial, camiones pluma, polibrazo y carrocería plana. Marcas: Mercedes-Benz (Actros, Axor, Atego, Accelo), Mack GU813 con Allison, Volvo VM y FMX, Renault C440 y Scania P450B. Faenas en Coquimbo y Calama (2.300 m de altura): polvo, calor, vibración y ralentí prolongado por uso de PTO. La disponibilidad del equipo es crítica, pero la seguridad va primero.

# MÉTODO DE DIAGNÓSTICO (sigue este orden)
1. Verificar la falla: qué, cuándo, en qué condición (frío/caliente, con carga, en altura, con PTO), desde cuándo y si hay código.
2. Revisar lo que ya se sabe: historial del equipo, casos resueltos del taller, OT y no conformidades abiertas.
3. Entender el sistema: cómo funciona el circuito o sistema involucrado en ESE modelo (ficha técnica).
4. Hipótesis ordenadas de más a menos probable, considerando las condiciones de faena.
5. Plan de pruebas de lo simple a lo complejo y de lo barato a lo caro: inspección visual → mediciones con multitester/manómetro → pruebas funcionales → herramienta OEM. Cada prueba con herramienta, punto de medición y criterio de aceptación.
6. Confirmación: cómo verificar que la reparación resolvió la causa raíz (no solo el síntoma).

# FUENTES Y HERRAMIENTAS (en este orden)
1. Repositorio del taller: usa buscar_manuales (varias veces si hace falta, también en inglés y portugués: fuse/relay/wiring diagram/connector; fusível/relé/esquema elétrico/chicote), buscar_codigo_falla, listar_documentos, casos_resueltos y ver_pagina para MIRAR diagramas, tablas de fusibles y pinouts antes de explicarlos (el mecánico ve la misma imagen).
2. Adjuntos del mecánico: fotos y PDFs (informe de escáner, manual, placa, tablero). Léelos con atención; cita un PDF como "(adjunto: <nombre>, pág. N)".
3. Web, si el repositorio no alcanza: web_search / web_fetch priorizando sitios oficiales del fabricante (manuales, body builder, boletines, recalls) y de fabricantes de componentes (Allison, WABCO, Bendix, Bosch, Delco Remy…). Foros solo como último recurso y nunca sitios de manuales pirateados. Cita cada dato web con un enlace markdown [dominio](URL) en la misma línea.
4. Criterio experto: si no hay información en el repositorio ni en la web, NO te quedes en "no está". Resuelve con tu conocimiento de ingeniería de camiones pesados siguiendo el PROTOCOLO SIN DOCUMENTACIÓN.

# PROTOCOLO SIN DOCUMENTACIÓN (cuando resuelves con criterio experto)
Estructura la respuesta así:
- **Cómo funciona**: principio de funcionamiento del sistema en términos concretos para ese tipo de camión.
- **Causas probables**: ordenadas, con el porqué de cada una (síntoma que la delata).
- **Plan de pruebas**: pasos numerados; qué medir, dónde y qué resultado confirma o descarta cada causa. Usa criterios relativos o de estándar universal (p. ej. comparar lado a lado, caída de voltaje en circuito, continuidad, presencia de alimentación y masa, 60 Ω entre CAN-H y CAN-L) y NO valores específicos del fabricante que no tengas citados.
- **Dato que falta**: qué valor exacto se necesita (torque, presión, pin, amperaje) y dónde conseguirlo: portal OEM de la ficha técnica, concesionario, herramienta de diagnóstico (XENTRY, Premium Tech Tool, SDP3/SWS, Techline) o la placa del componente.
- **Riesgos**: qué NO hacer mientras tanto.

# REGLAS OBLIGATORIAS
1. Valores críticos (torques, presiones, calibraciones, capacidades, intervalos, amperajes de fusibles, pines, resistencias y voltajes específicos del fabricante) SOLO desde una fuente citada: [Fn], códigos de la tabla, adjunto o enlace web. Nunca de memoria. Si no aparecen: "Ese dato no lo encontré en los manuales ni en fuentes confiables — no te lo voy a inventar", y di dónde conseguirlo.
2. Cita cada dato del repositorio con su número entre corchetes: [F3], o varios: [F1][F4]. No inventes números de fuente.
3. Jerarquía de confiabilidad: manual oficial > procedimiento interno de Pillado > guía técnica o web oficial del fabricante > web de terceros > experiencia de campo (foros) > criterio experto. Si usas foros o criterio experto, dilo explícitamente.
4. Si la información es de otra variante (Volvo norteamericano para un FMX brasileño, Actros europeo para uno off-road, 12 V para un sistema de 24 V), adviértelo y pide validar en el equipo.
5. La experiencia del taller es la pista más valiosa: si el mismo síntoma ya se resolvió en este equipo o en otro del mismo modelo, dilo primero ("En este mismo equipo / en otro GU813 esto se resolvió con…").
6. Si hay un DIAGNÓSTICO EN CURSO: no pidas repetir comprobaciones hechas; propone LA siguiente comprobación más discriminante (una a la vez, con herramienta y valor esperado) y pide registrarla con "Registrar comprobación". Cuando la evidencia apunte a una causa, dilo y recuerda "Encontré la causa" para que el caso quede guardado.
7. Código de falla: qué significa, qué ECU lo levanta, causas probables en orden, primera comprobación y si el equipo puede seguir operando. Si no está en la tabla, dilo y explica cómo leer el código completo en el tablero de ESE modelo (ficha técnica) o con escáner.
8. Si faltan datos para diagnosticar, no adivines: máximo 3 preguntas concretas, las que más discriminan.
9. Foto: describe lo que se ve objetivamente y qué NO se puede confirmar solo con la imagen.
10. No mezcles información de marcas o modelos distintos al equipo consultado.
11. Seguridad: en frenos, dirección, suspensión, sistemas presurizados (aire, hidráulica, combustible), grúa y polibrazo, trabajo bajo equipo levantado, estanques de combustible (DS 160) y eléctrico con batería conectada, termina con "⚠️ Valida con el jefe de taller antes de intervenir." más el bloqueo/aislación que corresponda (calzar ruedas, liberar presión, desconectar batería, bloqueo LOTO).

# FORMATO DE RESPUESTA (pantalla de teléfono)
- Primera línea: el nivel de respaldo de la respuesta, uno de: "📘 Respaldo: manuales de la flota", "🌐 Respaldo: fuentes web", "🧠 Respaldo: criterio experto (no verificado en manual)" o una combinación.
- Luego la respuesta directa o la primera acción. Sin relleno, sin repetir la pregunta, sin narrar tus búsquedas (la app ya muestra el progreso).
- Párrafos de 1 a 3 líneas, listas numeradas para pasos, **negrita** para valores y componentes clave; tablas markdown solo si son chicas (fusibles, pines).
- Cierra, cuando aplique, con "**Siguiente paso:**" y una sola acción concreta.`

// ── Herramientas ────────────────────────────────────────────────────────────
const SISTEMAS_ENUM = ['electrico', 'motor', 'transmision', 'frenos', 'hidraulica', 'direccion',
  'tren_rodaje', 'combustible', 'postratamiento', 'implemento', 'lubricacion']
// Evaluación con preguntas reales (19-09-2026): desde un Volvo preguntaron
// «¿qué manual tienes de Mercedes?» y las herramientas, filtradas por la
// marca del equipo abierto, respondieron que no había ninguno. La marca por
// la que se pregunta explícitamente manda sobre la del equipo.
const MARCAS_ENUM = ['mercedes-benz', 'mack', 'volvo', 'renault', 'scania', 'imt', 'todas']

const TOOLS: Anthropic.Beta.Messages.BetaToolUnion[] = [
  {
    name: 'buscar_manuales',
    description: 'Busca en el corpus de manuales de la flota (manuales oficiales OEM, body builder, diagramas eléctricos, procedimientos internos de Pillado, guías técnicas investigadas, recalls). Devuelve extractos numerados [Fn] con título, página y si hay imagen de la página. Filtra automáticamente por la marca/modelo del equipo consultado. Búsqueda por palabras (full-text): usa términos técnicos concretos, no frases largas. Repite en inglés o portugués si en español no aparece.',
    input_schema: {
      type: 'object',
      properties: {
        consulta: { type: 'string', description: 'Palabras clave, p.ej. "fusible luces trabajo", "wiring diagram PTO", "esquema elétrico ARLA".' },
        sistema: { type: 'string', enum: SISTEMAS_ENUM, description: 'Opcional: prioriza documentos de ese sistema.' },
        marca: { type: 'string', enum: MARCAS_ENUM, description: 'Solo si la pregunta es explícitamente de OTRA marca que la del equipo abierto (o de todas). Si no, omítelo: se usa la del equipo.' },
      },
      required: ['consulta'],
    },
    eager_input_streaming: true,
  },
  {
    name: 'buscar_codigo_falla',
    description: 'Busca un código de falla en la tabla estructurada (SPN/FMI J1939, MID/PID/SID, códigos Mercedes FR/MR/GS, Allison, WABCO blink, DM1 Scania...). Acepta formatos como "SPN 3251 FMI 0", "3251-0", "P0420", "MID 128 PID 100" o una descripción ("sensor NOx"). Devuelve significado, causas y comprobaciones con su fuente.',
    input_schema: {
      type: 'object',
      properties: { codigo: { type: 'string' } },
      required: ['codigo'],
    },
    eager_input_streaming: true,
  },
  {
    name: 'listar_documentos',
    description: 'Lista los documentos de la biblioteca. Con `texto` busca por título (p.ej. "diagrama", "fusibles", "body builder", "Allison"). Sin `texto` y con `marca` entrega el CATÁLOGO completo de esa marca agrupado por sistema: úsalo cuando pregunten "¿qué tienes de Volvo/Mercedes…?".',
    input_schema: {
      type: 'object',
      properties: {
        texto: { type: 'string', description: 'Palabras del título. Omitir para ver el catálogo de una marca.' },
        marca: { type: 'string', enum: MARCAS_ENUM, description: 'Marca a listar; por defecto la del equipo abierto.' },
      },
    },
    eager_input_streaming: true,
  },
  {
    name: 'ver_pagina',
    description: 'Muestra la IMAGEN de una página (diagramas eléctricos, tablas de fusibles/relés, pinouts, esquemas hidráulicos). Pasa el número de fuente [Fn] que tenga imagen disponible, o documento_id + pagina de listar_documentos. Úsalo para leer un diagrama antes de explicarlo. La misma imagen se le muestra al mecánico.',
    input_schema: {
      type: 'object',
      properties: {
        fuente: { type: 'integer', description: 'Número n de una fuente [Fn].' },
        documento_id: { type: 'string' },
        pagina: { type: 'integer' },
      },
    },
    eager_input_streaming: true,
  },
  {
    name: 'casos_resueltos',
    description: 'Busca casos de diagnóstico ya resueltos en este taller para este equipo o su mismo modelo, con otras palabras que las de la pregunta (p.ej. el sistema o el componente sospechoso).',
    input_schema: {
      type: 'object',
      properties: { texto: { type: 'string' } },
      required: ['texto'],
    },
    eager_input_streaming: true,
  },
  // Respaldo cuando el repositorio no alcanza (herramientas de servidor de
  // Anthropic: corren en su infraestructura, sin código nuestro).
  { type: 'web_search_20260209', name: 'web_search', max_uses: 4 },
  { type: 'web_fetch_20260209', name: 'web_fetch', max_uses: 3 },
]

// ── Tipos internos ──────────────────────────────────────────────────────────
type Turno = { rol: 'user' | 'assistant'; texto: string }
type Body = {
  pregunta?: string
  activoId?: string
  otId?: string
  diagnosticoId?: string
  historial?: Turno[]
  fotoBase64?: string
  fotoTipo?: string
  adjuntos?: AdjuntoRef[]
  formato?: 'ndjson' | 'texto'
}
type ChunkRow = {
  chunk_id: number; documento_id: string; titulo: string; archivo: string; tipo_documento: string
  pagina: number; contenido: string; sistema: string | null
  url_fuente?: string | null; confiabilidad?: string | null; con_imagen?: boolean
}
type FuenteInterna = ChunkRow & { n: number }
type Caso = {
  equipo: string; mismo_equipo: boolean; sintoma: string; causa_raiz: string
  reparacion: string | null; sistema: string | null; resuelto_at: string
  comprobaciones: { descripcion?: string; resultado?: string; valor?: string }[]
}

// Serializa filas de BD a texto compacto para el prompt: bota nulls, UUIDs
// internos y trunca textos largos. Aguanta cambios de esquema sin romperse.
function filaATexto(row: Record<string, unknown>): string {
  const partes: string[] = []
  for (const [k, v] of Object.entries(row)) {
    if (v === null || v === undefined || v === '') continue
    if (/(^|_)id$/.test(k) || k === 'usuario_id') continue
    if (/^costo/.test(k)) continue // los costos no van al contexto del mecánico
    const s = typeof v === 'object' ? JSON.stringify(v) : String(v)
    if (/^[0-9a-f]{8}-[0-9a-f]{4}/.test(s)) continue
    partes.push(`${k}: ${s.length > 280 ? s.slice(0, 280) + '…' : s}`)
  }
  return partes.join(' · ')
}

// Parte del corpus está en inglés/portugués y el mecánico pregunta en
// español: la FTS no cruza idiomas, así que la primera búsqueda automática
// se expande con los equivalentes de taller (Claude hace el resto con la
// herramienta).
const ES_EN: Record<string, string> = {
  fusible: 'fuse', fusibles: 'fuses', rele: 'relay', relé: 'relay', reles: 'relays',
  bomba: 'pump', freno: 'brake', frenos: 'brakes', embrague: 'clutch',
  caja: 'transmission', cambios: 'gearbox', motor: 'engine', correa: 'belt',
  aceite: 'oil', filtro: 'filter', filtros: 'filters', refrigerante: 'coolant',
  direccion: 'steering', dirección: 'steering', suspension: 'suspension',
  eje: 'axle', ejes: 'axles', rueda: 'wheel', neumatico: 'tire', neumático: 'tire',
  bateria: 'battery', batería: 'battery', alternador: 'alternator',
  arranque: 'starter', cableado: 'wiring', diagrama: 'diagram', esquema: 'schematic', plano: 'wiring',
  falla: 'fault', fallas: 'faults', codigo: 'code', código: 'code', conector: 'connector',
  torque: 'torque', apriete: 'torque', presion: 'pressure', presión: 'pressure',
  luces: 'lights', luz: 'lamp', tablero: 'instrument', sensor: 'sensor',
  compresor: 'compressor', estanque: 'tank', mantencion: 'maintenance',
  mantención: 'maintenance', mantenimiento: 'maintenance', sumergible: 'submersible',
  adblue: 'DEF', urea: 'DEF', inyector: 'injector', turbo: 'turbocharger', masa: 'ground',
}
function traduccionTaller(q: string): string | null {
  const extras = new Set<string>()
  for (const w of q.toLowerCase().split(/[^a-záéíóúñü]+/)) {
    if (ES_EN[w]) extras.add(ES_EN[w])
  }
  return extras.size ? Array.from(extras).join(' ') : null
}

function codigoParaCliente(c: CodigoFalla): CodigoCopiloto {
  return {
    codigo: c.codigo, formato: c.formato, descripcion: c.descripcion, aplica: c.aplica, marca: c.marca,
    causas: Array.isArray(c.causas) ? c.causas : [], comprobaciones: Array.isArray(c.comprobaciones) ? c.comprobaciones : [],
    confiabilidad: c.confiabilidad, fuente: c.fuente, coincidencia: c.coincidencia,
  }
}

function codigosATexto(cs: CodigoFalla[]): string {
  return cs.map((c) =>
    `- ${c.codigo} (${c.formato}${c.ecu ? `, ECU ${c.ecu}` : ''}${c.aplica ? `, aplica: ${c.aplica}` : ''}; `
    + `coincidencia ${c.coincidencia}; confiabilidad ${c.confiabilidad}${c.fuente ? `; fuente: ${c.fuente}` : ''})\n`
    + `  Significado: ${c.descripcion}\n`
    + (c.causas?.length ? `  Causas: ${c.causas.join(' | ')}\n` : '')
    + (c.comprobaciones?.length ? `  Comprobaciones: ${c.comprobaciones.join(' | ')}\n` : ''),
  ).join('')
}

function fichaATexto(f: FichaEquipo): string {
  const l = [
    `FICHA TÉCNICA (Biblioteca Maestra): ${f.patente} · ${f.marca ?? ''} ${f.modelo ?? ''} ${f.anio ?? ''}`,
    f.vin && `VIN ${f.vin}`, f.numero_motor && `N° motor ${f.numero_motor}`,
    f.motor && `Motor: ${f.motor}`, f.transmision && `Transmisión: ${f.transmision}`,
    f.emisiones && `Emisiones: ${f.emisiones}`, f.ecus && `Electrónica/ECUs: ${f.ecus}`,
    f.equipamiento && `Equipamiento: ${f.equipamiento}`, f.implemento && `Implemento (componentes): ${f.implemento}`,
    f.zona && `Zona: ${f.zona}`, f.lectura_codigos && `Cómo leer códigos en el tablero: ${f.lectura_codigos}`,
    f.fuente_oem && `Portal OEM (manual de taller por VIN): ${f.fuente_oem}`, f.notas && `Notas: ${f.notas}`,
  ].filter(Boolean)
  return l.join('\n') + '\n'
}

// ── Handler ─────────────────────────────────────────────────────────────────
export async function POST(req: Request) {
  const auth = await autenticar(req)
  if ('error' in auth) return NextResponse.json({ error: auth.error }, { status: auth.status })
  const { sb, uid } = auth

  if (!process.env.ANTHROPIC_API_KEY) {
    return NextResponse.json({ error: 'Copiloto sin configurar (falta ANTHROPIC_API_KEY en el servidor).' }, { status: 503 })
  }

  let body: Body
  try { body = await req.json() } catch { return NextResponse.json({ error: 'JSON inválido.' }, { status: 400 }) }
  const pregunta = (body.pregunta ?? '').trim()
  // Adjuntos: solo rutas del propio usuario (<uid>/...) y tipos permitidos
  const adjuntos = (body.adjuntos ?? [])
    .filter((a) => a && typeof a.path === 'string' && a.path.startsWith(`${uid}/`) && !a.path.includes('..')
      && TIPOS_ADJUNTO.includes(a.tipo))
    .slice(0, 6)
  if (pregunta.length < 3 && !body.fotoBase64 && !adjuntos.length) {
    return NextResponse.json({ error: 'Escribe la pregunta o el síntoma.' }, { status: 400 })
  }
  if (body.fotoBase64 && body.fotoBase64.length > 5_500_000) {
    return NextResponse.json({ error: 'La foto es muy pesada. Intenta de nuevo.' }, { status: 400 })
  }
  const ndjson = body.formato === 'ndjson'
  const corpus = corpusCliente()

  // Sin equipo abierto pero la pregunta nombra una patente ("¿qué neumático
  // ocupa el hhwb-42?"): se carga ese equipo (RLS de SICOM decide si lo ve).
  if (!body.activoId) {
    const m = pregunta.match(/\b([A-Za-z]{4})[-\s]?(\d{2})\b/)
    if (m) {
      const { data } = await sb.from('activos').select('id')
        .ilike('patente', `${m[1].toUpperCase()}-${m[2]}`).limit(1).maybeSingle()
      const id = (data as { id?: string } | null)?.id
      if (id) body.activoId = id
    }
  }

  // ── Contexto del equipo desde SICOM (con el token del usuario: RLS manda) ──
  let contextoEquipo = ''
  let marcaSlug: string | null = null
  let modeloSlug: string | null = null
  let ficha: FichaEquipo | null = null

  if (body.activoId) {
    const [act, hist, ncs, ot, casos, dx] = await Promise.all([
      sb.from('activos')
        .select('codigo, nombre, patente, tipo, estado, horas_uso_actual, kilometraje_actual, anio_fabricacion, vin_chasis, numero_motor, tipo_equipamiento, capacidad, modelo:modelos(nombre, marca:marcas(nombre))')
        .eq('id', body.activoId).maybeSingle(),
      sb.from('v_historial_mantenimiento_equipo').select('*')
        .eq('activo_id', body.activoId).order('fecha', { ascending: false }).limit(12),
      sb.from('no_conformidades').select('*')
        .eq('activo_id', body.activoId).eq('resuelto', false)
        .order('created_at', { ascending: false }).limit(10),
      body.otId
        ? sb.from('ordenes_trabajo').select('folio, tipo, estado, prioridad, observaciones').eq('id', body.otId).maybeSingle()
        : Promise.resolve({ data: null, error: null }),
      // Experiencia interna: casos resueltos del mismo equipo o modelo (MIG543)
      sb.rpc('rpc_copiloto_casos_similares', {
        p_activo_id: body.activoId, p_texto: pregunta || 'falla', p_limit: 3,
      }),
      body.diagnosticoId
        ? sb.from('copiloto_diagnosticos').select('sintoma, sistema, estado, comprobaciones').eq('id', body.diagnosticoId).maybeSingle()
        : Promise.resolve({ data: null, error: null }),
    ])

    const a = act.data as Record<string, unknown> | null
    if (a) {
      const modelo = a.modelo as { nombre?: string; marca?: { nombre?: string } } | null
      marcaSlug = slug(modelo?.marca?.nombre)
      modeloSlug = slug(modelo?.nombre)
      contextoEquipo += `EQUIPO: ${a.codigo ?? ''} ${a.nombre ?? ''} · patente ${a.patente ?? '—'} · ${modelo?.marca?.nombre ?? ''} ${modelo?.nombre ?? ''}`
        + `${a.anio_fabricacion ? ` · año ${a.anio_fabricacion}` : ''} · estado ${a.estado ?? '—'} · horómetro ${a.horas_uso_actual ?? '—'} h · km ${a.kilometraje_actual ?? '—'}`
        + `${a.vin_chasis ? ` · VIN ${a.vin_chasis}` : ''}${a.numero_motor ? ` · motor N° ${a.numero_motor}` : ''}`
        + `${a.tipo_equipamiento ? ` · ${a.tipo_equipamiento}` : ''}${a.capacidad ? ` ${a.capacidad}` : ''}\n`
      try { ficha = await fichaEquipo(corpus, a.patente as string | null) } catch { /* ficha opcional */ }
      if (ficha) contextoEquipo += '\n' + fichaATexto(ficha)
    }
    if (ot.data) contextoEquipo += `\nOT ACTUAL: ${filaATexto(ot.data as Record<string, unknown>)}\n`
    if (hist.data?.length) {
      contextoEquipo += `\nHISTORIAL DE MANTENIMIENTO (últimos ${hist.data.length}):\n`
        + hist.data.map((r) => `- ${filaATexto(r as Record<string, unknown>)}`).join('\n') + '\n'
    }
    if (ncs.data?.length) {
      contextoEquipo += `\nNO CONFORMIDADES ABIERTAS (${ncs.data.length}):\n`
        + ncs.data.map((r) => `- ${filaATexto(r as Record<string, unknown>)}`).join('\n') + '\n'
    }
    const casosData = (casos.data ?? []) as Caso[]
    if (casosData.length) contextoEquipo += `\nCASOS RESUELTOS ANTERIORES (experiencia interna del taller):\n${casosATexto(casosData)}`

    const dxData = dx.data as {
      sintoma: string; sistema: string | null; estado: string
      comprobaciones: { descripcion?: string; resultado?: string; valor?: string }[]
    } | null
    if (dxData && dxData.estado === 'abierto') {
      const compr = (dxData.comprobaciones ?? [])
        .map((x, i) => `${i + 1}. ${x.descripcion}${x.valor ? ` = ${x.valor}` : ''} → ${x.resultado}`)
        .join('\n')
      contextoEquipo += `\nDIAGNÓSTICO EN CURSO:\nSíntoma declarado: ${dxData.sintoma}`
        + `${dxData.sistema ? ` · Sistema: ${dxData.sistema}` : ''}\n`
        + (compr ? `Comprobaciones ya registradas:\n${compr}\n` : 'Aún sin comprobaciones registradas.\n')
    }
  }

  // ── Registro de fuentes: numeración estable [Fn] durante toda la consulta ──
  const fuentes = new Map<number, FuenteInterna>()       // chunk_id → fuente
  const porNumero = new Map<number, FuenteInterna>()
  const paginasVistas = new Set<number>()                  // n de fuentes con ver_pagina
  function registrar(rows: ChunkRow[]): FuenteInterna[] {
    return rows.map((r) => {
      const ya = fuentes.get(r.chunk_id)
      if (ya) return ya
      const f: FuenteInterna = { ...r, n: fuentes.size + 1 }
      fuentes.set(r.chunk_id, f); porNumero.set(f.n, f)
      return f
    })
  }
  function fuentesATexto(fs: FuenteInterna[]): string {
    return fs.map((f) =>
      `[F${f.n}] ${f.titulo} — pág. ${f.pagina} (${f.tipo_documento === 'manual_oficial' ? 'manual oficial' : f.tipo_documento.replace(/_/g, ' ')}`
      + `${f.confiabilidad ? `, ${f.confiabilidad.replace(/_/g, ' ')}` : ''}${f.con_imagen ? ', IMAGEN DISPONIBLE → ver_pagina' : ''})\n`
      + f.contenido.slice(0, 2200),
    ).join('\n\n')
  }

  let corpusDisponible = false
  async function buscarManuales(consulta: string, sistema?: string, limit = 8, marca?: string): Promise<FuenteInterna[]> {
    if (!corpus) return []
    // Marca explícita distinta a la del equipo: sin filtro de modelo
    const otraMarca = marca && marca !== marcaSlug
    const { data, error } = await corpus.rpc('buscar_chunks', {
      p_query: consulta,
      p_marca: marca === 'todas' ? null : (marca ?? marcaSlug),
      p_modelo: otraMarca ? null : modeloSlug,
      p_limit: limit, p_sistema: sistema ?? null,
    })
    if (error) throw error
    corpusDisponible = true
    return registrar((data ?? []) as ChunkRow[])
  }

  // ── Búsquedas iniciales en paralelo (sin esperar a la IA) ─────────────────
  const codigosDetectados = codigosEnTexto(pregunta)
  const codigosEncontrados: CodigoFalla[] = []
  let bloqueFuentes = ''
  if (corpus && pregunta) {
    try {
      const traduccion = traduccionTaller(pregunta)
      const [es, en, ...cods] = await Promise.all([
        buscarManuales(pregunta, undefined, 8),
        traduccion ? buscarManuales(traduccion, undefined, 4) : Promise.resolve([] as FuenteInterna[]),
        ...codigosDetectados.map((c) => buscarCodigo(corpus, c, marcaSlug, 5).catch(() => [] as CodigoFalla[])),
      ])
      const iniciales = [...es, ...en].slice(0, 10)
      for (const lista of cods) codigosEncontrados.push(...lista)
      bloqueFuentes = iniciales.length
        ? `FUENTES (búsqueda automática inicial; usa buscar_manuales para más):\n${fuentesATexto(iniciales)}`
        : 'FUENTES: la búsqueda automática no encontró secciones relevantes; usa buscar_manuales con otros términos (o en inglés/portugués).'
    } catch {
      bloqueFuentes = 'FUENTES: el corpus de manuales no respondió. Responde con el contexto del equipo y criterio general, dejando claro qué valores habría que confirmar en el manual.'
    }
  } else if (!corpus) {
    bloqueFuentes = 'FUENTES: el corpus de manuales aún no está disponible. Responde solo con el contexto del equipo y criterio general de taller, dejando claro qué valores habría que confirmar en el manual.'
  }
  const bloqueCodigos = codigosEncontrados.length
    ? `\nCÓDIGOS DE FALLA (tabla estructurada, detectados en la pregunta):\n${codigosATexto(codigosEncontrados)}`
    : codigosDetectados.length ? `\nCÓDIGOS DE FALLA: se detectó ${codigosDetectados.join(', ')} en la pregunta pero no está en la tabla cargada.\n` : ''

  // ── Registrar la consulta ANTES de llamar a la IA (auditoría MIG542) ──────
  const { data: ins } = await sb.from('copiloto_consultas').insert({
    usuario_id: uid,
    activo_id: body.activoId ?? null,
    ot_id: body.otId ?? null,
    diagnostico_id: body.diagnosticoId ?? null,
    pregunta: pregunta || (adjuntos.length ? `(adjuntos: ${adjuntos.map((a) => a.nombre).join(', ')})` : '(solo foto)'),
    con_foto: !!body.fotoBase64 || adjuntos.some((a) => a.tipo.startsWith('image/')),
    modelo: MODELO_IA,
    fuentes: [],
  }).select('id').single()
  const consultaId: string | null = ins?.id ?? null

  // ── Mensajes para Claude ───────────────────────────────────────────────────
  const contenidoUsuario: Anthropic.Beta.Messages.BetaContentBlockParam[] = []
  const adjuntosFallidos: string[] = []
  if (adjuntos.length && corpus) {
    const bajados = await Promise.all(adjuntos.map(async (a) => {
      const { data, error } = await corpus.storage.from(BUCKET_ADJUNTOS).download(a.path)
      if (error || !data) return null
      return { a, b64: Buffer.from(await data.arrayBuffer()).toString('base64') }
    }))
    bajados.forEach((x, i) => {
      if (!x) { adjuntosFallidos.push(adjuntos[i].nombre); return }
      if (x.a.tipo === 'application/pdf') {
        contenidoUsuario.push({
          type: 'document', title: x.a.nombre.slice(0, 200),
          source: { type: 'base64', media_type: 'application/pdf', data: x.b64 },
        })
      } else {
        contenidoUsuario.push({
          type: 'image',
          source: { type: 'base64', media_type: x.a.tipo as 'image/jpeg' | 'image/png' | 'image/webp', data: x.b64 },
        })
      }
    })
    await corpus.from('copiloto_adjuntos').update({ consulta_id: consultaId, estado: 'usado' })
      .in('storage_path', adjuntos.map((a) => a.path))
  }
  if (body.fotoBase64) {
    contenidoUsuario.push({
      type: 'image',
      source: { type: 'base64', media_type: body.fotoTipo === 'image/png' ? 'image/png' : 'image/jpeg', data: body.fotoBase64 },
    })
  }
  contenidoUsuario.push({
    type: 'text',
    text: `${contextoEquipo ? contextoEquipo + '\n' : 'EQUIPO: consulta general, sin equipo seleccionado (no filtres por marca).\n\n'}`
      + `${bloqueFuentes}\n${bloqueCodigos}`
      + (adjuntos.length ? `\nADJUNTOS DEL MECÁNICO: ${adjuntos.map((a) => a.nombre).join(', ')}${adjuntosFallidos.length ? ` (no se pudieron leer: ${adjuntosFallidos.join(', ')})` : ''}\n` : '')
      + `\nPREGUNTA DEL MECÁNICO:\n${pregunta || 'Revisa lo que adjunté y dime qué observas y qué hago.'}`,
  })

  const mensajes: Anthropic.Beta.Messages.BetaMessageParam[] = [
    ...(body.historial ?? []).slice(-6).map((t): Anthropic.Beta.Messages.BetaMessageParam => ({
      role: t.rol === 'assistant' ? 'assistant' : 'user',
      content: t.texto.slice(0, 4000),
    })),
    { role: 'user', content: contenidoUsuario },
  ]

  // ── Ejecución de herramientas ─────────────────────────────────────────────
  async function ejecutar(
    tool: Anthropic.Beta.Messages.BetaToolUseBlock,
    emitir: (e: EventoCopiloto) => void,
  ): Promise<Anthropic.Beta.Messages.BetaToolResultBlockParam> {
    const input = (tool.input ?? {}) as Record<string, unknown>
    const str = (k: string) => (typeof input[k] === 'string' ? (input[k] as string).trim() : '')
    const err = (m: string): Anthropic.Beta.Messages.BetaToolResultBlockParam =>
      ({ type: 'tool_result', tool_use_id: tool.id, is_error: true, content: m })
    const ok = (content: string | Anthropic.Beta.Messages.BetaToolResultBlockParam['content']) =>
      ({ type: 'tool_result' as const, tool_use_id: tool.id, content })

    try {
      switch (tool.name) {
        case 'buscar_manuales': {
          const q = str('consulta')
          if (q.length < 2) return err('consulta vacía')
          emitir({ t: 'estado', d: `Buscando en manuales: «${q}»` })
          if (!corpus) return ok('El corpus de manuales no está disponible.')
          const sistema = SISTEMAS_ENUM.includes(str('sistema')) ? str('sistema') : undefined
          const marca = MARCAS_ENUM.includes(str('marca')) ? str('marca') : undefined
          const r = await buscarManuales(q, sistema, 6, marca)
          return ok(r.length ? fuentesATexto(r) : 'Sin resultados. Prueba otros términos, sinónimos o el idioma del manual (inglés/portugués).')
        }
        case 'buscar_codigo_falla': {
          const q = str('codigo')
          if (!q) return err('código vacío')
          emitir({ t: 'estado', d: `Buscando código de falla ${q}` })
          if (!corpus) return ok('La tabla de códigos no está disponible.')
          const r = await buscarCodigo(corpus, q, marcaSlug, 8)
          for (const c of r) if (!codigosEncontrados.some((x) => x.id === c.id)) codigosEncontrados.push(c)
          return ok(r.length ? codigosATexto(r) : `El código «${q}» no está en la tabla cargada.`)
        }
        case 'listar_documentos': {
          const q = str('texto')
          const marcaPedida = MARCAS_ENUM.includes(str('marca')) ? str('marca') : null
          const marca = marcaPedida === 'todas' ? null : (marcaPedida ?? marcaSlug)
          emitir({ t: 'estado', d: q ? `Revisando documentos disponibles: «${q}»` : `Revisando la biblioteca de ${marca ?? 'toda la flota'}` })
          if (!corpus) return ok('El corpus no está disponible.')
          if (!q) {
            // Catálogo de la marca agrupado por sistema (conteo real, no una muestra)
            let cat = corpus.from('copiloto_documentos')
              .select('titulo, modelo, sistema, tipo_documento, paginas').order('sistema').order('titulo').limit(400)
            if (marca) cat = cat.eq('marca', marca)
            const { data: docs, error: e2 } = await cat
            if (e2) throw e2
            const lista = (docs ?? []) as { titulo: string; modelo: string | null; sistema: string | null; tipo_documento: string; paginas: number | null }[]
            if (!lista.length) return ok(`No hay documentos de ${marca ?? 'ninguna marca'} en la biblioteca.`)
            const grupos = new Map<string, typeof lista>()
            for (const d of lista) {
              const k = d.sistema ?? 'general / varios'
              if (!grupos.has(k)) grupos.set(k, [])
              grupos.get(k)!.push(d)
            }
            return ok(`Catálogo ${marca ?? 'toda la flota'}: ${lista.length} documentos.\n`
              + Array.from(grupos.entries()).map(([k, ds]) => `## ${k} (${ds.length})\n`
                + ds.slice(0, 25).map((d) => `- ${d.titulo}${d.modelo ? ` [${d.modelo}]` : ''} (${d.tipo_documento.replace(/_/g, ' ')}, ${d.paginas ?? '?'} págs)`).join('\n')
                + (ds.length > 25 ? `\n- … y ${ds.length - 25} más` : '')).join('\n'))
          }
          const { data, error } = await corpus.rpc('buscar_documentos', { p_texto: q, p_marca: marca, p_limit: 20 })
          if (error) throw error
          const docs = (data ?? []) as { documento_id: string; titulo: string; marca: string | null; sistema: string | null; tipo_documento: string; paginas: number | null; con_imagenes: boolean }[]
          return ok(docs.length
            ? docs.map((d) => `- ${d.titulo} (documento_id ${d.documento_id}; ${d.paginas ?? '?'} págs; ${d.tipo_documento}${d.marca ? `; ${d.marca}` : ''}${d.con_imagenes ? '; páginas con imagen' : ''})`).join('\n')
            : 'No hay documentos con ese título. Prueba buscar_manuales por contenido.')
        }
        case 'ver_pagina': {
          if (!corpus) return ok('El corpus no está disponible.')
          let docId: string | null = null, pagina: number | null = null, titulo = ''
          let fuenteN: number | null = null
          if (typeof input.fuente === 'number') {
            const f = porNumero.get(input.fuente)
            if (!f) return err(`No existe la fuente F${input.fuente}`)
            docId = f.documento_id; pagina = f.pagina; titulo = f.titulo; fuenteN = f.n
          } else if (str('documento_id') && typeof input.pagina === 'number') {
            docId = str('documento_id'); pagina = input.pagina
          } else return err('Indica fuente, o documento_id y pagina')
          emitir({ t: 'estado', d: `Mirando la página ${pagina}${titulo ? ` de «${titulo}»` : ''}` })
          const { data: pg } = await corpus.from('copiloto_paginas').select('storage_path')
            .eq('documento_id', docId).eq('pagina', pagina).maybeSingle()
          if (!pg) return ok('Esa página no tiene imagen disponible (solo texto). Trabaja con el extracto de texto.')
          const url = await urlPagina(corpus, (pg as { storage_path: string }).storage_path)
          if (!url) return err('No se pudo generar la imagen de la página')
          if (fuenteN == null) {
            // Página pedida por documento: se registra como fuente para que el
            // mecánico la vea y la respuesta la pueda citar.
            const { data: d } = await corpus.from('copiloto_documentos')
              .select('titulo, archivo, tipo_documento, sistema, url_fuente, confiabilidad').eq('id', docId).maybeSingle()
            const doc = d as { titulo: string; archivo: string; tipo_documento: string; sistema: string | null; url_fuente: string | null; confiabilidad: string | null } | null
            const [f] = registrar([{
              chunk_id: -(Date.now() % 1e9) - pagina!, documento_id: docId!, titulo: doc?.titulo ?? 'Documento',
              archivo: doc?.archivo ?? '', tipo_documento: doc?.tipo_documento ?? 'manual_oficial', pagina: pagina!,
              contenido: '', sistema: doc?.sistema ?? null, url_fuente: doc?.url_fuente ?? null,
              confiabilidad: doc?.confiabilidad ?? null, con_imagen: true,
            }])
            fuenteN = f.n; titulo = f.titulo
          }
          // Se baja acá y va en base64: si Anthropic no logra descargar una
          // URL, la petición ENTERA falla con 400 (probado 19-09-2026).
          const img = await fetch(url)
          if (!img.ok) return err('No se pudo descargar la imagen de la página')
          const b64 = Buffer.from(await img.arrayBuffer()).toString('base64')
          paginasVistas.add(fuenteN)
          return ok([
            { type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: b64 } },
            { type: 'text', text: `Imagen de [F${fuenteN}] ${titulo} — pág. ${pagina}. Cítala como [F${fuenteN}].` },
          ])
        }
        case 'casos_resueltos': {
          const q = str('texto')
          if (!body.activoId) return ok('Sin equipo seleccionado: no hay casos por modelo.')
          emitir({ t: 'estado', d: 'Revisando casos resueltos del taller' })
          const { data, error } = await sb.rpc('rpc_copiloto_casos_similares', { p_activo_id: body.activoId, p_texto: q || 'falla', p_limit: 5 })
          if (error) throw error
          const cs = (data ?? []) as Caso[]
          return ok(cs.length ? casosATexto(cs) : 'No hay casos resueltos parecidos para este equipo o modelo.')
        }
        default:
          return err(`Herramienta desconocida: ${tool.name}`)
      }
    } catch (e) {
      return err(`Falló la herramienta: ${e instanceof Error ? e.message : 'error'}`)
    }
  }

  // ── Fuentes para el cliente: numeradas, con enlace e imagen ───────────────
  async function fuentesCliente(respuesta: string): Promise<FuenteCopiloto[]> {
    const citadas = new Set(Array.from(respuesta.matchAll(/\[F(\d+)\]/g)).map((m) => Number(m[1])))
    const lista = Array.from(porNumero.values()).filter((f) => citadas.has(f.n) || paginasVistas.has(f.n))
    // Imágenes firmadas de las páginas citadas que tengan render
    const conImg = lista.filter((f) => f.con_imagen)
    const imgs = new Map<number, string>()
    if (corpus && conImg.length) {
      await Promise.all(conImg.map(async (f) => {
        const { data } = await corpus.from('copiloto_paginas').select('storage_path')
          .eq('documento_id', f.documento_id).eq('pagina', f.pagina).maybeSingle()
        const u = data ? await urlPagina(corpus, (data as { storage_path: string }).storage_path, 6 * 3600) : null
        if (u) imgs.set(f.n, u)
      }))
    }
    const repo = lista.sort((a, b) => a.n - b.n).map((f): FuenteCopiloto => {
      const esPdf = f.url_fuente && /\.pdf($|\?)/i.test(f.url_fuente)
      return {
        n: f.n, titulo: f.titulo, pagina: f.pagina, tipo: f.tipo_documento,
        confiabilidad: f.confiabilidad ?? null,
        url: f.url_fuente ? (esPdf ? `${f.url_fuente}#page=${f.pagina}` : f.url_fuente) : null,
        imagen: imgs.get(f.n) ?? null,
        citada: citadas.has(f.n),
      }
    })
    // Fuentes web: los enlaces markdown que Claude escribió en la respuesta
    const web = new Map<string, string>()
    for (const m of Array.from(respuesta.matchAll(/\[([^\]]{1,120})\]\((https?:\/\/[^\s)]+)\)/g))) {
      if (!web.has(m[2])) web.set(m[2], m[1])
    }
    let n = porNumero.size
    const webFuentes: FuenteCopiloto[] = Array.from(web.entries()).slice(0, 12).map(([url, titulo]) => ({
      n: ++n, titulo, pagina: 0, tipo: 'web', confiabilidad: null, url, imagen: null, citada: true,
    }))
    return [...repo, ...webFuentes]
  }

  // ── Stream ────────────────────────────────────────────────────────────────
  const anthropic = new Anthropic()
  const t0 = Date.now()
  const encoder = new TextEncoder()

  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      const emitir = (e: EventoCopiloto) => {
        if (ndjson) controller.enqueue(encoder.encode(JSON.stringify(e) + '\n'))
        else if (e.t === 'texto') controller.enqueue(encoder.encode(e.d))
      }
      let respuesta = ''
      let inTok = 0, outTok = 0
      try {
        if (codigosEncontrados.length) emitir({ t: 'codigos', d: codigosEncontrados.map(codigoParaCliente) })
        emitir({ t: 'estado', d: 'Analizando con manuales, casos e historial…' })

        let reintentosJson = 0
        for (let ronda = 0; ronda < MAX_RONDAS; ronda++) {
          const ultima = ronda === MAX_RONDAS - 1
          const s = anthropic.beta.messages.stream({
            model: MODELO_IA,
            max_tokens: 16000,
            betas: ['server-side-fallback-2026-07-01'],
            fallbacks: 'default',
            thinking: { type: 'adaptive' },
            output_config: { effort: EFFORT },
            system: [{ type: 'text', text: SYSTEM_PROMPT, cache_control: { type: 'ephemeral' } }],
            // Caché del prefijo que crece ronda a ronda (PDFs adjuntos, resultados)
            cache_control: { type: 'ephemeral' },
            // En la última ronda se quitan las herramientas: tiene que responder
            tools: ultima ? undefined : TOOLS,
            messages: mensajes,
          })
          s.on('text', (delta) => { respuesta += delta; emitir({ t: 'texto', d: delta }) })
          s.on('streamEvent', (ev) => {
            if (ev.type === 'content_block_start' && ev.content_block.type === 'server_tool_use') {
              emitir({ t: 'estado', d: ev.content_block.name === 'web_fetch' ? 'Leyendo una página web…' : 'No está en el repositorio: buscando en la web…' })
            }
          })

          let msg: Anthropic.Beta.Messages.BetaMessage
          try {
            msg = await s.finalMessage()
            reintentosJson = 0
          } catch (e) {
            // Solo se reintenta un input de herramienta ilegible; errores de API se propagan
            if (e instanceof Anthropic.APIError || reintentosJson++ >= 1) throw e
            continue
          }
          // Tokens de entrada "equivalentes facturados": el panel de jefatura
          // multiplica por la tarifa base, y con varias rondas la caché pesa.
          inTok += Math.round((msg.usage.input_tokens ?? 0)
            + (msg.usage.cache_read_input_tokens ?? 0) * 0.1
            + (msg.usage.cache_creation_input_tokens ?? 0) * 1.25)
          outTok += msg.usage.output_tokens ?? 0

          if (msg.stop_reason === 'refusal') {
            const aviso = '\n\n[El copiloto no puede responder esta consulta. Reformúlala o consulta al jefe de taller.]'
            respuesta += aviso; emitir({ t: 'texto', d: aviso })
            break
          }
          // Búsqueda web larga: el servidor pausa el turno; se reenvía para seguir
          if (msg.stop_reason === 'pause_turn') {
            mensajes.push({ role: 'assistant', content: msg.content })
            emitir({ t: 'estado', d: 'Buscando en la web…' })
            continue
          }
          const usos = msg.content.filter((b): b is Anthropic.Beta.Messages.BetaToolUseBlock => b.type === 'tool_use')
          if (msg.stop_reason !== 'tool_use' || usos.length === 0) break

          mensajes.push({ role: 'assistant', content: msg.content })
          const resultados = await Promise.all(usos.map((u) => ejecutar(u, emitir)))
          mensajes.push({ role: 'user', content: resultados })
          // El texto previo a las herramientas ("voy a revisar…") no es la respuesta
          if (respuesta.trim()) { respuesta += '\n\n'; emitir({ t: 'texto', d: '\n\n' }) }
        }

        const fs = await fuentesCliente(respuesta)
        emitir({ t: 'fuentes', d: fs })
        if (codigosEncontrados.length) emitir({ t: 'codigos', d: codigosEncontrados.map(codigoParaCliente) })

        if (consultaId) {
          await sb.from('copiloto_consultas').update({
            respuesta,
            fuentes: fs.map((f) => ({ n: f.n, titulo: f.titulo, pagina: f.pagina, tipo: f.tipo, url: f.url, citada: f.citada })),
            input_tokens: inTok,
            output_tokens: outTok,
            duracion_ms: Date.now() - t0,
          }).eq('id', consultaId)
        }
        emitir({ t: 'fin', consultaId })
      } catch (err) {
        console.error('[copiloto] consulta falló', consultaId, err instanceof Error ? err.message : err)
        const detalle = err instanceof Error ? err.message : ''
        const msg = /credit balance|billing/i.test(detalle)
          ? '\n\n[El copiloto está sin saldo de IA. Avisa a jefatura para recargar la cuenta de Anthropic.]'
          : err instanceof Anthropic.RateLimitError || /overloaded/i.test(detalle)
            ? '\n\n[El copiloto está con mucha demanda en este momento. Intenta de nuevo en un minuto.]'
            : err instanceof Anthropic.APIError
              ? `\n\n[El copiloto tuvo un problema (${err.status ?? 'conexión'}). Intenta de nuevo.]`
              : '\n\n[El copiloto tuvo un problema. Intenta de nuevo.]'
        emitir({ t: 'texto', d: msg })
        emitir({ t: 'error', d: msg.trim() })
        if (consultaId) {
          await sb.from('copiloto_consultas').update({
            respuesta: respuesta + msg, input_tokens: inTok, output_tokens: outTok, duracion_ms: Date.now() - t0,
          }).eq('id', consultaId)
        }
      } finally {
        controller.close()
      }
    },
  })

  return new Response(stream, {
    headers: {
      'Content-Type': ndjson ? 'application/x-ndjson; charset=utf-8' : 'text/plain; charset=utf-8',
      'Cache-Control': 'no-cache',
      'X-Accel-Buffering': 'no',
      ...(consultaId ? { 'X-Copiloto-Id': consultaId } : {}),
    },
  })
}

function casosATexto(cs: Caso[]): string {
  return cs.map((c) => {
    const compr = (c.comprobaciones ?? [])
      .map((x) => `${x.descripcion}${x.valor ? ` = ${x.valor}` : ''} (${x.resultado})`).join('; ')
    return `- [${c.mismo_equipo ? 'ESTE MISMO EQUIPO' : `mismo modelo, ${c.equipo}`} · ${(c.resuelto_at ?? '').slice(0, 10)}] `
      + `Síntoma: ${c.sintoma}. Causa raíz: ${c.causa_raiz}.`
      + `${c.reparacion ? ` Reparación: ${c.reparacion}.` : ''}`
      + `${compr ? ` Comprobaciones: ${compr}.` : ''}`
  }).join('\n') + '\n'
}
