import Anthropic from '@anthropic-ai/sdk'
import { NextResponse } from 'next/server'
import { autenticar, corpusCliente } from '@/lib/copiloto/server'
import type { EventoSso, FuenteSso, AtajoSso } from '@/lib/copiloto-sso/tipos'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'
export const maxDuration = 300

// ============================================================================
// Copiloto Prevención Centinela (26-11-2026, MIG734)
// ----------------------------------------------------------------------------
// Manuel: «quiero hacer un agente IA como mi copiloto, pero versión prevención
// para Centinela». Lo usan supervisores ENEX y prevencionista (teléfono) y la
// oficina (computador).
//   · Conocimiento: base del Campus Centinela (RECSS AMSA v3, EDC Altura y
//     Energía Eléctrica, Lecciones Aprendidas, Directriz de contratos, SOFI)
//     en el corpus (tablas sso_*). El núcleo (01 y 09) va fijo en el prompt
//     con caché; el resto se busca. Los documentos NO están en el repositorio
//     (es público y son del mandante): se leen del corpus en el servidor.
//   · Datos de SICOM en solo lectura: rpc_sso_trabajador con el token del
//     usuario (los permisos de Prevención mandan).
//   · Reglas: citar [Fn], no inventar códigos/controles/porcentajes, avisar
//     cifras de OCR, y ante la duda sobre un control crítico: detener la tarea.
// Cada consulta queda en copiloto_sso_consultas.
// ============================================================================

const MODELO_IA = process.env.COPILOTO_SSO_MODELO ?? process.env.COPILOTO_MODELO ?? 'claude-opus-5-5'
const EFFORT = (process.env.COPILOTO_SSO_EFFORT ?? 'medium') as 'low' | 'medium' | 'high'
const MAX_RONDAS = 6

const PROMPT_BASE = `# ROL
Eres el Copiloto de Prevención de Riesgos de PILLADO EMPRESAS para faena MINERA CENTINELA (Calama, grupo Antofagasta Minerals – AMSA). Eres experto en prevención de riesgos para minería chilena y en lo que Centinela exige a sus empresas contratistas (EECC). Te leen supervisores en terreno (desde el teléfono), la prevencionista (APR) y la oficina. Hablas en español de Chile, técnico y directo.

# LA OPERACIÓN DE PILLADO EN CENTINELA
Contrato con ENEX/ESM: calibración y mantención de estaciones de combustible y lubricantes (surtidores y dispensadores, bombas y estanques, salas de bombas, semimóviles, sistemas de medición e instalaciones eléctricas), con traslados en camioneta dentro de faena y en ruta. Riesgos propios: incendio/explosión, derrames, vapores, ingreso a estanques o fosas, electricidad estática, energía eléctrica, trabajo en altura (techos de salas, estanques, plataformas) y conducción (fatiga y somnolencia).

# FUENTES (en este orden)
1. Base de conocimiento de Centinela: el NÚCLEO va más abajo; para el texto completo usa buscar_normativa (RECSS, EDC Altura, EDC Energía Eléctrica, Lecciones Aprendidas y Boletines, Directriz de Administración de Contratos, Manual SOFI, plataforma y salud). Búscalo SIEMPRE antes de afirmar un requisito, control crítico, plazo o porcentaje.
2. Datos de SICOM del trabajador (consultar_trabajador): cargo, faena, habilitación y vencimientos de exámenes, licencias y cursos. Úsalo cuando pregunten por una persona («¿puede subir X?», «¿qué le falta a Y?») o cuando la ART deba nombrar a la cuadrilla.
3. Legislación chilena (Ley 16.744, DS 76/2007, DS 40/1969, DS 132 RSM, DS 594, DS 160 combustibles, Código del Trabajo y Ley 20.123; SEC, SERNAGEOMIN, SUSESO, ISP). Si necesitas el texto, web_search en fuentes oficiales (bcn.cl, suseso.cl, sernageomin.cl, sec.cl) y cita con enlace markdown.
4. Conocimiento general de prevención: solo si lo anterior no alcanza, y DILO explícitamente («esto no está en los documentos de Centinela que tengo; según la normativa general…»).

# REGLAS OBLIGATORIAS
1. Cita cada dato de la base con su número entre corchetes: [F2], o varios [F1][F4]. No inventes números de fuente. Además nombra el documento y la sección o el N.º de LA cuando sea clave («RECSS cap. 9», «LA 06/2023»).
2. NUNCA inventes códigos de procedimiento, números o nombres de controles críticos, porcentajes, plazos ni categorías. Si no los encuentras: «no lo encontré en los documentos de Centinela que tengo» y di a quién pedirlo (ADC o Gerencia SSO de Centinela, ESM).
3. Las fuentes marcadas (OCR) —RECSS, Directriz y SOFI— se leyeron de documentos escaneados: cuando uses una cifra de ellas, advierte que conviene verificarla en el PDF original o con el ADC.
4. Seguridad primero: ante cualquier duda sobre un control crítico, la respuesta por defecto es **DETENER LA TAREA** y consultar. Nunca sugieras saltarte un control para cumplir un plazo.
5. Categoría del contrato: la calibración y mantención de estaciones NO es traslado; la categoría se calcula con el puntaje del Anexo 2 del RECSS. Si el contrato incluye traslado de combustible o de personal, es categoría A sin puntaje. La categoría formal la define el ADC.
6. EDC que NO están completas en la base (Fatiga y Somnolencia, Vehículos Livianos, Pérdida de Control, sustancias peligrosas/combustibles, incendio, espacios confinados, izaje, ácidos, equipos pesados): dilo y recomienda pedir el documento vigente al ADC; puedes orientar con normativa general marcándolo como tal.
7. Datos de personas: usa solo lo que devuelve consultar_trabajador; no supongas exámenes ni cursos. Lo que SICOM no registra (inducción Persona Nueva del campus, acreditación APRIMIN, e-learning EDC, credencial eléctrica) dilo como «verificar en Campus/acreditación», no como cumplido.
8. No reemplazas al experto SSO acreditado (DS 40) ni al ADC: las decisiones formales son de ellos. La base es lo descargado del Campus Centinela el 26-11-2026; los estándares pueden haberse actualizado.

# FORMATO
- Teléfono primero: respuesta directa en la primera línea, párrafos cortos, listas numeradas para pasos, **negrita** para lo crítico, tablas chicas para chequear.
- Sin relleno, sin repetir la pregunta, sin narrar búsquedas.
- Si el entregable es para jefatura o el cliente, incluye cifras y % y cita las bases.
- Cierra con **Siguiente paso:** y una sola acción concreta cuando aplique.`

const INSTRUCCION_ATAJO: Record<AtajoSso, string> = {
  art: `\n\n# ATAJO: ART DE LA TAREA
Arma un Análisis de Riesgos del Trabajo (ART) para la tarea descrita, alineado con Centinela:
1. **Tarea, lugar y equipo** (si nombran personas, consulta cada una con consultar_trabajador y marca si están habilitadas).
2. **Pasos de la tarea** (secuencia corta).
3. Por paso: **peligros / riesgos** y **medidas de control**.
4. **EDC aplicables y sus controles críticos** (busca en la base: Energía Eléctrica, Altura, etc.) con la pregunta de verificación de cada uno.
5. **Detener la tarea si…** (condiciones concretas).
6. **Lección aprendida relacionada** (busca una LA que aplique y resúmela en 2 líneas).
7. ¿Es **no rutinaria**? Si lo es: libro de obra y autorización del ADC.
Si falta un dato clave de la tarea, pregunta máximo 2 cosas.`,
  charla: `\n\n# ATAJO: CHARLA DE 5 MINUTOS
Prepara una charla de 5 minutos desde una Lección Aprendida de AMSA/Centinela (búscala con buscar_normativa; si no indican cuál, elige la que más aplique a estaciones de combustible: electricidad, altura, fatiga o incendio):
1. **Título** y N.º de LA.
2. **¿Qué pasó?** (3-4 líneas).
3. **¿Qué falló?** (controles que faltaron).
4. **¿Qué aprendimos?**
5. **¿Cómo aplica a nuestra tarea en estaciones de combustible?** (2-3 ejemplos concretos).
6. **3 preguntas para el equipo** y un **compromiso** de cierre.
Lenguaje simple para leer en voz alta.`,
  subir: `\n\n# ATAJO: ¿PUEDE SUBIR ESTE TRABAJADOR?
1. Consulta al trabajador con consultar_trabajador.
2. Veredicto en la primera línea: ✅ Puede subir · ⚠️ Puede subir con observaciones · ⛔ No puede subir (y por qué).
3. Tabla: requisito · estado en SICOM · vence. Destaca lo VENCIDO y lo que vence en menos de 30 días.
4. Según su tarea (eléctrico → EDC Energía; altura → examen de altura física sobre 1,8 m y 8.º par sobre 10 m; conductor → licencias y fatiga), agrega lo que exige Centinela citando la base.
5. Lo que SICOM no registra, como «verificar»: inducción Persona Nueva, acreditación APRIMIN, e-learning EDC, credencial eléctrica.
Si hay varias personas con ese nombre, pregunta cuál.`,
}

const TOOLS: Anthropic.Beta.Messages.BetaToolUnion[] = [
  {
    name: 'buscar_normativa',
    description: 'Busca en la base de conocimiento de Centinela (RECSS AMSA v3, EDC Trabajos en Altura, EDC Interacción con Energía Eléctrica, Lecciones Aprendidas y Boletines, Directriz de Administración de Contratos, Manual SOFI, plataforma y salud). Devuelve extractos numerados [Fn] con documento y sección. Búsqueda por palabras: términos concretos (2 a 6 palabras), no frases largas. Repite con otras palabras si no aparece.',
    input_schema: {
      type: 'object',
      properties: { consulta: { type: 'string', description: 'Ej: "aislar bloquear energía cero", "baranda rodapié vano", "categoría contrato puntaje", "LA 06/2023 fatiga".' } },
      required: ['consulta'],
    },
  },
  {
    name: 'consultar_trabajador',
    description: 'Busca un trabajador en SICOM (Prevención) por nombre o RUT y devuelve cargo, faena, si está habilitado según los requisitos de su faena y el estado y vencimiento de cada examen, licencia y curso registrado. Solo lectura.',
    input_schema: {
      type: 'object',
      properties: { nombre_o_rut: { type: 'string', description: 'Nombre, apellido o RUT. Ej: "Fabián Castillo", "12.345.678-9".' } },
      required: ['nombre_o_rut'],
    },
  },
  { type: 'web_search_20260209', name: 'web_search', max_uses: 3 },
]

type Turno = { rol: 'user' | 'assistant'; texto: string }
type Body = { pregunta?: string; historial?: Turno[]; atajo?: AtajoSso | null }
type Chunk = { chunk_id: number; codigo: string; titulo: string; escaneado: boolean; seccion: string | null; contenido: string }

// El núcleo (01 y 09) se arma una vez por instancia desde el corpus.
let nucleoCache: { texto: string; at: number } | null = null
async function nucleo(corpus: NonNullable<ReturnType<typeof corpusCliente>>): Promise<string> {
  if (nucleoCache && Date.now() - nucleoCache.at < 6 * 3600_000) return nucleoCache.texto
  const { data: docs } = await corpus.from('sso_documentos').select('id, codigo, titulo').in('codigo', ['01', '09'])
  let texto = ''
  for (const d of (docs ?? []).sort((a, b) => a.codigo.localeCompare(b.codigo))) {
    const { data: ch } = await corpus.from('sso_chunks').select('seccion, contenido').eq('documento_id', d.id).order('orden')
    texto += `\n\n## ${d.titulo}\n` + (ch ?? []).map((c) => `### ${c.seccion ?? ''}\n${c.contenido}`).join('\n')
  }
  nucleoCache = { texto, at: Date.now() }
  return texto
}

export async function POST(req: Request) {
  const auth = await autenticar(req)
  if ('error' in auth) return NextResponse.json({ error: auth.error }, { status: auth.status })
  const { sb, uid } = auth
  const body = (await req.json().catch(() => ({}))) as Body
  const pregunta = (body.pregunta ?? '').trim().slice(0, 4000)
  if (!pregunta) return NextResponse.json({ error: 'Falta la pregunta.' }, { status: 400 })
  const atajo = body.atajo && body.atajo in INSTRUCCION_ATAJO ? body.atajo : null

  // Mismo permiso que ver el personal de Prevención (supervisores, APR, jefaturas).
  const { data: puede } = await sb.rpc('fn_prevencion_personal_puede_ver')
  if (!puede) return NextResponse.json({ error: 'Su cuenta no tiene acceso al Copiloto de Prevención.' }, { status: 403 })

  const corpus = corpusCliente()
  if (!corpus) return NextResponse.json({ error: 'El corpus del copiloto no está configurado.' }, { status: 503 })
  const textoNucleo = await nucleo(corpus).catch(() => '')

  const { data: consulta } = await sb.from('copiloto_sso_consultas')
    .insert({ usuario_id: uid, atajo, pregunta, modelo: MODELO_IA }).select('id').single()
  const consultaId: string | undefined = consulta?.id

  const historial = (body.historial ?? []).slice(-6)
  const mensajes: Anthropic.Beta.Messages.BetaMessageParam[] = [
    ...historial.map((t) => ({ role: t.rol, content: t.texto.slice(0, 6000) }) as Anthropic.Beta.Messages.BetaMessageParam),
    { role: 'user', content: pregunta },
  ]
  // Alternancia obligatoria user/assistant: si el historial terminó en user, se une.
  for (let i = mensajes.length - 2; i >= 0; i--) {
    if (mensajes[i].role === mensajes[i + 1].role) {
      mensajes[i] = { role: mensajes[i].role, content: `${mensajes[i].content}\n\n${mensajes[i + 1].content}` }
      mensajes.splice(i + 1, 1)
    }
  }
  if (mensajes[0]?.role === 'assistant') mensajes.shift()

  const fuentes: (FuenteSso & { contenido: string })[] = []
  const herramientas: { nombre: string; entrada: unknown }[] = []

  const ejecutar = async (u: Anthropic.Beta.Messages.BetaToolUseBlock, emitir: (e: EventoSso) => void)
    : Promise<Anthropic.Beta.Messages.BetaToolResultBlockParam> => {
    const inp = (u.input ?? {}) as Record<string, string>
    herramientas.push({ nombre: u.name, entrada: inp })
    try {
      if (u.name === 'buscar_normativa') {
        emitir({ t: 'estado', d: `Buscando en la base de Centinela: «${inp.consulta}»…` })
        const { data, error } = await corpus.rpc('buscar_sso', { p_query: inp.consulta ?? '', p_limite: 6 })
        if (error) throw new Error(error.message)
        const rows = (data ?? []) as Chunk[]
        if (!rows.length) return { type: 'tool_result', tool_use_id: u.id, content: 'Sin resultados. Prueba con otras palabras.' }
        const partes = rows.map((r) => {
          let f = fuentes.find((x) => x.chunkId === r.chunk_id)
          if (!f) {
            f = { n: fuentes.length + 1, chunkId: r.chunk_id, documento: r.titulo, codigo: r.codigo, seccion: r.seccion,
                  escaneado: r.escaneado, citada: false, contenido: r.contenido }
            fuentes.push(f)
          }
          return `[F${f.n}] ${r.titulo}${r.escaneado ? ' (OCR)' : ''} — ${r.seccion ?? ''}\n${r.contenido}`
        })
        return { type: 'tool_result', tool_use_id: u.id, content: partes.join('\n\n---\n\n') }
      }
      if (u.name === 'consultar_trabajador') {
        emitir({ t: 'estado', d: `Revisando en SICOM a ${inp.nombre_o_rut}…` })
        const { data, error } = await sb.rpc('rpc_sso_trabajador', { p_texto: inp.nombre_o_rut ?? '' })
        if (error) throw new Error(error.message)
        return { type: 'tool_result', tool_use_id: u.id, content: JSON.stringify(data) }
      }
      return { type: 'tool_result', tool_use_id: u.id, is_error: true, content: 'Herramienta desconocida.' }
    } catch (e) {
      return { type: 'tool_result', tool_use_id: u.id, is_error: true, content: `Error: ${e instanceof Error ? e.message : e}` }
    }
  }

  const anthropic = new Anthropic()
  const t0 = Date.now()
  const encoder = new TextEncoder()
  const system: Anthropic.Beta.Messages.BetaTextBlockParam[] = [
    { type: 'text', text: PROMPT_BASE + (textoNucleo ? `\n\n# NÚCLEO DE CONOCIMIENTO (base de Centinela, cítalo como «Núcleo» o búscalo para citar [Fn])${textoNucleo}` : ''),
      cache_control: { type: 'ephemeral' } },
    ...(atajo ? [{ type: 'text' as const, text: INSTRUCCION_ATAJO[atajo] }] : []),
  ]

  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      const emitir = (e: EventoSso) => controller.enqueue(encoder.encode(JSON.stringify(e) + '\n'))
      let respuesta = ''
      let inTok = 0, outTok = 0
      let error: string | null = null
      try {
        emitir({ t: 'estado', d: 'Revisando la base de Centinela…' })
        const CIERRE = 'Ya no quedan búsquedas. Escribe AHORA la respuesta con lo que tienes: cita solo las fuentes encontradas y di qué no pudiste verificar.'
        for (let ronda = 0; ronda < MAX_RONDAS; ronda++) {
          const ultima = ronda === MAX_RONDAS - 1
          if (ultima) mensajes.push({ role: 'user', content: CIERRE })
          const s = anthropic.beta.messages.stream({
            model: MODELO_IA,
            max_tokens: 12000,
            betas: ['server-side-fallback-2026-07-01'],
            fallbacks: 'default',
            thinking: { type: 'adaptive' },
            output_config: { effort: EFFORT },
            system,
            cache_control: { type: 'ephemeral' },
            tools: TOOLS,
            ...(ultima ? { tool_choice: { type: 'none' as const } } : {}),
            messages: mensajes,
          })
          s.on('text', (d) => { respuesta += d; emitir({ t: 'texto', d }) })
          s.on('streamEvent', (ev) => {
            if (ev.type === 'content_block_start' && ev.content_block.type === 'server_tool_use') emitir({ t: 'estado', d: 'Buscando la normativa en fuentes oficiales…' })
          })
          const msg = await s.finalMessage()
          inTok += Math.round((msg.usage.input_tokens ?? 0) + (msg.usage.cache_read_input_tokens ?? 0) * 0.1
            + (msg.usage.cache_creation_input_tokens ?? 0) * 1.25)
          outTok += msg.usage.output_tokens ?? 0
          if (msg.stop_reason === 'refusal') { const a = '\n\n[No puedo responder esta consulta. Reformúlala o consulta a la prevencionista.]'; respuesta += a; emitir({ t: 'texto', d: a }); break }
          if (msg.stop_reason === 'pause_turn') { mensajes.push({ role: 'assistant', content: msg.content }); continue }
          const usos = msg.content.filter((b): b is Anthropic.Beta.Messages.BetaToolUseBlock => b.type === 'tool_use')
          if (msg.stop_reason !== 'tool_use' || !usos.length) break
          mensajes.push({ role: 'assistant', content: msg.content })
          mensajes.push({ role: 'user', content: await Promise.all(usos.map((u) => ejecutar(u, emitir))) })
          if (respuesta.trim()) { respuesta += '\n\n'; emitir({ t: 'texto', d: '\n\n' }) }
        }
        if (!respuesta.trim()) { const a = '[El copiloto terminó sin respuesta. Repite la pregunta.]'; respuesta = a; emitir({ t: 'texto', d: a }) }
        const citadas = new Set(Array.from(respuesta.matchAll(/\[F(\d+)\]/g), (m) => Number(m[1])))
        const salida: FuenteSso[] = fuentes.map(({ contenido, ...f }) => ({ ...f, citada: citadas.has(f.n), extracto: contenido.slice(0, 600) }))
        emitir({ t: 'fuentes', d: salida.filter((f) => f.citada) })
        emitir({ t: 'fin', consultaId, duracion_ms: Date.now() - t0 })
      } catch (err) {
        const det = err instanceof Error ? err.message : String(err)
        error = det
        const msg = /credit balance|billing/i.test(det) ? '[El copiloto está sin saldo de IA. Avisa a administración.]'
          : err instanceof Anthropic.RateLimitError || /overloaded/i.test(det) ? '[Mucha demanda en este momento. Intenta en un minuto.]'
          : '[El copiloto tuvo un problema. Intenta de nuevo.]'
        emitir({ t: 'texto', d: `\n\n${msg}` }); emitir({ t: 'error', d: msg })
      } finally {
        if (consultaId) {
          await sb.from('copiloto_sso_consultas').update({
            respuesta, error, tokens_in: inTok, tokens_out: outTok, duracion_ms: Date.now() - t0, herramientas,
            fuentes: fuentes.filter((f) => respuesta.includes(`[F${f.n}]`)).map((f) => ({ n: f.n, documento: f.documento, seccion: f.seccion })),
          }).eq('id', consultaId)
        }
        controller.close()
      }
    },
  })
  return new Response(stream, {
    headers: { 'Content-Type': 'application/x-ndjson; charset=utf-8', 'Cache-Control': 'no-cache', 'X-Accel-Buffering': 'no',
               ...(consultaId ? { 'X-Copiloto-Id': consultaId } : {}) },
  })
}
