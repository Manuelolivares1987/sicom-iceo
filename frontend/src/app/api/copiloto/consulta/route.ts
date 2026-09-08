import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import Anthropic from '@anthropic-ai/sdk'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'
export const maxDuration = 120

// ============================================================================
// Copiloto Técnico del taller (2026-09-08)
// El mecánico pregunta desde /m/taller/copiloto; acá se arma el contexto real
// del equipo (ficha + historial + NC + OT desde SICOM) más los manuales
// relevantes (proyecto Supabase paralelo "copiloto-corpus") y responde Claude
// con reglas estrictas de no-invención y citas de fuente. Cada consulta queda
// auditada en copiloto_consultas (MIG542).
// ============================================================================

const MODELO_IA = 'claude-opus-5'

const SYSTEM_PROMPT = `Eres el Copiloto Técnico del taller de PILLADO ICEO (flota pesada de arriendo para minería, Chile). Ayudas a mecánicos a diagnosticar y reparar. Hablas en español chileno claro y directo, como un maestro experimentado; el mecánico te lee desde el teléfono, debajo del camión.

REGLAS OBLIGATORIAS:
1. Los valores críticos (torques, presiones, calibraciones, capacidades, códigos de falla, intervalos, amperajes de fusibles) SOLO pueden salir de las FUENTES del contexto. Si no están ahí, di literalmente: "Ese dato no está en los manuales cargados — no te lo puedo inventar" y sugiere dónde buscarlo.
2. Cita siempre la fuente al usar información de los manuales: (Fuente: <título>, pág. <n>).
3. Distingue el tipo de fuente: "Según el manual oficial..." vs "Según procedimiento interno de Pillado...".
4. Usa el HISTORIAL del equipo: si el mismo síntoma ya se reparó antes, dilo primero — es la pista más valiosa.
5. Para trabajos con riesgo (frenos, dirección, suspensión, sistemas presurizados, trabajos bajo el equipo levantado, eléctrico con batería conectada) agrega al final: "⚠️ Valida con el jefe de taller antes de intervenir."
6. Si te faltan datos para diagnosticar, NO adivines: haz máximo 3 preguntas concretas (¿en frío o caliente?, ¿con carga?, ¿hay código en el tablero?, ¿fuga visible?).
7. Diagnóstico como hipótesis ordenadas de más a menos probable, cada una con cómo comprobarla con lo que hay en un taller (multitester, manómetro, inspección visual).
8. Respuestas CORTAS: párrafos de 2-3 líneas, listas, sin relleno. Es una pantalla de teléfono.
9. No mezcles información de otras marcas o modelos distintos al equipo consultado.
10. Si hay foto, describe lo que se ve objetivamente y qué NO se puede confirmar solo con la imagen.`

type Turno = { rol: 'user' | 'assistant'; texto: string }

type Body = {
  pregunta?: string
  activoId?: string
  otId?: string
  historial?: Turno[]
  fotoBase64?: string
  fotoTipo?: string
}

// Serializa filas de BD a texto compacto para el prompt: bota nulls, UUIDs
// internos y trunca textos largos. Aguanta cambios de esquema sin romperse.
function filaATexto(row: Record<string, unknown>): string {
  const partes: string[] = []
  for (const [k, v] of Object.entries(row)) {
    if (v === null || v === undefined || v === '') continue
    if (/(^|_)id$/.test(k) || k === 'usuario_id') continue
    if (/^costo/.test(k)) continue // los costos no van al contexto del mecánico
    const s = String(v)
    if (/^[0-9a-f]{8}-[0-9a-f]{4}/.test(s)) continue
    partes.push(`${k}: ${s.length > 280 ? s.slice(0, 280) + '…' : s}`)
  }
  return partes.join(' · ')
}

// Parte del corpus está en inglés (Mack Body Builder, Fuso, Atlas Copco) y el
// mecánico pregunta en español: la búsqueda FTS no cruza idiomas, así que se
// expande la consulta con los equivalentes de taller. El OR-fallback del RPC
// hace el resto.
const ES_EN: Record<string, string> = {
  fusible: 'fuse', fusibles: 'fuses', rele: 'relay', relé: 'relay', reles: 'relays',
  bomba: 'pump', freno: 'brake', frenos: 'brakes', embrague: 'clutch',
  caja: 'transmission', cambios: 'gearbox', motor: 'engine', correa: 'belt',
  aceite: 'oil', filtro: 'filter', filtros: 'filters', refrigerante: 'coolant',
  direccion: 'steering', dirección: 'steering', suspension: 'suspension',
  eje: 'axle', ejes: 'axles', rueda: 'wheel', neumatico: 'tire', neumático: 'tire',
  bateria: 'battery', batería: 'battery', alternador: 'alternator',
  arranque: 'starter', cableado: 'wiring', diagrama: 'diagram',
  falla: 'fault', fallas: 'faults', codigo: 'code', código: 'code',
  torque: 'torque', apriete: 'torque', presion: 'pressure', presión: 'pressure',
  luces: 'lights', luz: 'lamp', tablero: 'dashboard', sensor: 'sensor',
  compresor: 'compressor', estanque: 'tank', mantencion: 'maintenance',
  mantención: 'maintenance', mantenimiento: 'maintenance', sumergible: 'submersible',
}
function traduccionTaller(q: string): string | null {
  const extras = new Set<string>()
  for (const w of q.toLowerCase().split(/[^a-záéíóúñü]+/)) {
    if (ES_EN[w]) extras.add(ES_EN[w])
  }
  return extras.size ? [...extras].join(' ') : null
}

function slug(v?: string | null): string | null {
  if (!v) return null
  return v.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim().replace(/\s+/g, '-')
}

export async function POST(req: Request) {
  const token = req.headers.get('authorization')?.replace(/^Bearer\s+/i, '')
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  if (!token || !url || !anon) {
    return NextResponse.json({ error: 'No autorizado.' }, { status: 401 })
  }
  const sb = createClient(url, anon, { global: { headers: { Authorization: `Bearer ${token}` } } })
  const { data: userData, error: authErr } = await sb.auth.getUser(token)
  if (authErr || !userData?.user) {
    return NextResponse.json({ error: 'Sesión inválida.' }, { status: 401 })
  }
  const uid = userData.user.id

  if (!process.env.ANTHROPIC_API_KEY) {
    return NextResponse.json({ error: 'Copiloto sin configurar (falta ANTHROPIC_API_KEY en el servidor).' }, { status: 503 })
  }

  let body: Body
  try { body = await req.json() } catch { return NextResponse.json({ error: 'JSON inválido.' }, { status: 400 }) }
  const pregunta = (body.pregunta ?? '').trim()
  if (pregunta.length < 3 && !body.fotoBase64) {
    return NextResponse.json({ error: 'Escribe la pregunta o el síntoma.' }, { status: 400 })
  }
  if (body.fotoBase64 && body.fotoBase64.length > 5_500_000) {
    return NextResponse.json({ error: 'La foto es muy pesada. Intenta de nuevo.' }, { status: 400 })
  }

  // ── Contexto del equipo desde SICOM (con el token del usuario: RLS manda) ──
  let contextoEquipo = ''
  let marcaSlug: string | null = null
  let modeloSlug: string | null = null

  if (body.activoId) {
    const [act, hist, ncs, ot] = await Promise.all([
      sb.from('activos')
        .select('codigo, nombre, patente, tipo, estado, horas_uso_actual, kilometraje_actual, modelo:modelos(nombre, marca:marcas(nombre))')
        .eq('id', body.activoId).maybeSingle(),
      sb.from('v_historial_mantenimiento_equipo').select('*')
        .eq('activo_id', body.activoId).order('fecha', { ascending: false }).limit(12),
      sb.from('no_conformidades').select('*')
        .eq('activo_id', body.activoId).eq('resuelto', false)
        .order('created_at', { ascending: false }).limit(10),
      body.otId
        ? sb.from('ordenes_trabajo').select('folio, tipo, estado, prioridad, observaciones').eq('id', body.otId).maybeSingle()
        : Promise.resolve({ data: null, error: null }),
    ])

    const a = act.data as Record<string, unknown> | null
    if (a) {
      const modelo = a.modelo as { nombre?: string; marca?: { nombre?: string } } | null
      marcaSlug = slug(modelo?.marca?.nombre)
      modeloSlug = slug(modelo?.nombre)
      contextoEquipo += `EQUIPO: ${a.codigo ?? ''} ${a.nombre ?? ''} · patente ${a.patente ?? '—'} · ${modelo?.marca?.nombre ?? ''} ${modelo?.nombre ?? ''} · estado ${a.estado ?? '—'} · horómetro ${a.horas_uso_actual ?? '—'} h · km ${a.kilometraje_actual ?? '—'}\n`
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
  }

  // ── Manuales relevantes desde el corpus paralelo ───────────────────────────
  type ChunkRow = {
    titulo: string; archivo: string; tipo_documento: string
    pagina: number; contenido: string; sistema: string | null
  }
  let fuentes: ChunkRow[] = []
  let corpusDisponible = false
  const corpusUrl = process.env.COPILOTO_SUPABASE_URL
  const corpusKey = process.env.COPILOTO_SUPABASE_SERVICE_KEY
  if (corpusUrl && corpusKey) {
    try {
      const corpus = createClient(corpusUrl, corpusKey, { auth: { persistSession: false } })
      // Búsqueda en español + búsqueda con los términos de taller traducidos
      // (parte del corpus está en inglés); se mezclan sin duplicar.
      const traduccion = traduccionTaller(pregunta)
      const [es, en] = await Promise.all([
        corpus.rpc('buscar_chunks', { p_query: pregunta, p_marca: marcaSlug, p_modelo: modeloSlug, p_limit: 8 }),
        traduccion
          ? corpus.rpc('buscar_chunks', { p_query: traduccion, p_marca: marcaSlug, p_modelo: modeloSlug, p_limit: 4 })
          : Promise.resolve({ data: null, error: null }),
      ])
      if (!es.error) {
        corpusDisponible = true
        const vistos = new Set<number>()
        fuentes = [...((es.data ?? []) as (ChunkRow & { chunk_id: number })[]),
                   ...(((en.data ?? []) as (ChunkRow & { chunk_id: number })[]))]
          .filter((f) => (vistos.has(f.chunk_id) ? false : (vistos.add(f.chunk_id), true)))
          .slice(0, 10)
      }
    } catch { /* corpus caído no bota la consulta: se responde sin manuales */ }
  }

  let bloqueFuentes = ''
  if (fuentes.length > 0) {
    bloqueFuentes = 'FUENTES (extractos de los manuales cargados):\n' + fuentes.map((f, i) =>
      `[FUENTE ${i + 1}] ${f.titulo} — pág. ${f.pagina} (${f.tipo_documento === 'manual_oficial' ? 'manual oficial' : f.tipo_documento.replace(/_/g, ' ')})\n${f.contenido.slice(0, 2200)}`
    ).join('\n\n')
  } else {
    bloqueFuentes = corpusDisponible
      ? 'FUENTES: la búsqueda no encontró secciones relevantes en los manuales cargados para esta pregunta.'
      : 'FUENTES: el corpus de manuales aún no está disponible. Responde solo con el contexto del equipo y criterio general de taller, dejando claro qué valores habría que confirmar en el manual.'
  }

  // ── Registrar la consulta ANTES de llamar a la IA (auditoría MIG542) ──────
  const { data: ins } = await sb.from('copiloto_consultas').insert({
    usuario_id: uid,
    activo_id: body.activoId ?? null,
    ot_id: body.otId ?? null,
    pregunta: pregunta || '(solo foto)',
    con_foto: !!body.fotoBase64,
    modelo: MODELO_IA,
    fuentes: fuentes.map((f) => ({ titulo: f.titulo, pagina: f.pagina, tipo: f.tipo_documento })),
  }).select('id').single()
  const consultaId: string | null = ins?.id ?? null

  // ── Mensajes para Claude ───────────────────────────────────────────────────
  const contenidoUsuario: Anthropic.ContentBlockParam[] = []
  if (body.fotoBase64) {
    contenidoUsuario.push({
      type: 'image',
      source: {
        type: 'base64',
        media_type: (body.fotoTipo === 'image/png' ? 'image/png' : 'image/jpeg'),
        data: body.fotoBase64,
      },
    })
  }
  contenidoUsuario.push({
    type: 'text',
    text: `${contextoEquipo ? contextoEquipo + '\n' : ''}${bloqueFuentes}\n\nPREGUNTA DEL MECÁNICO:\n${pregunta || 'Revisa la foto y dime qué se observa.'}`,
  })

  const mensajes: Anthropic.MessageParam[] = [
    ...(body.historial ?? []).slice(-6).map((t): Anthropic.MessageParam => ({
      role: t.rol === 'assistant' ? 'assistant' : 'user',
      content: t.texto.slice(0, 4000),
    })),
    { role: 'user', content: contenidoUsuario },
  ]

  const anthropic = new Anthropic()
  const t0 = Date.now()

  const encoder = new TextEncoder()
  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      let respuesta = ''
      try {
        const msgStream = anthropic.messages.stream({
          model: MODELO_IA,
          max_tokens: 2000,
          system: [{ type: 'text', text: SYSTEM_PROMPT, cache_control: { type: 'ephemeral' } }],
          messages: mensajes,
        })
        for await (const event of msgStream) {
          if (event.type === 'content_block_delta' && event.delta.type === 'text_delta') {
            respuesta += event.delta.text
            controller.enqueue(encoder.encode(event.delta.text))
          }
        }
        const final = await msgStream.finalMessage()
        if (consultaId) {
          await sb.from('copiloto_consultas').update({
            respuesta,
            input_tokens: final.usage.input_tokens,
            output_tokens: final.usage.output_tokens,
            duracion_ms: Date.now() - t0,
          }).eq('id', consultaId)
        }
      } catch (err) {
        const msg = err instanceof Anthropic.APIError
          ? `\n\n[El copiloto tuvo un problema (${err.status}). Intenta de nuevo.]`
          : '\n\n[El copiloto tuvo un problema. Intenta de nuevo.]'
        controller.enqueue(encoder.encode(msg))
        if (consultaId) {
          await sb.from('copiloto_consultas').update({
            respuesta: respuesta + msg, duracion_ms: Date.now() - t0,
          }).eq('id', consultaId)
        }
      } finally {
        controller.close()
      }
    },
  })

  return new Response(stream, {
    headers: {
      'Content-Type': 'text/plain; charset=utf-8',
      'Cache-Control': 'no-cache',
      'X-Accel-Buffering': 'no',
      ...(consultaId ? { 'X-Copiloto-Id': consultaId } : {}),
    },
  })
}
