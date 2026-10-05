import { NextResponse } from 'next/server'
import Anthropic from '@anthropic-ai/sdk'
import { jsonSchemaOutputFormat } from '@anthropic-ai/sdk/helpers/json-schema'
import { autenticar, corpusCliente, urlPagina } from '@/lib/copiloto/server'
import type { ConversacionCopiloto, DiagnosticoCopiloto, FuenteCopiloto, MensajeGuardado, CodigoCopiloto } from '@/lib/copiloto/tipos'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'
export const maxDuration = 120

// ============================================================================
// Copiloto — una conversación guardada (MIG583).
//  GET  ?id=   → hilo + caso + mensajes, con las imágenes de páginas y fotos
//                firmadas de nuevo (las URL firmadas del chat original vencen).
//  POST {accion:'resolver'} → la solución definitiva: cierra el caso por RPC
//                (con el token del mecánico, RLS manda) y le pide a la IA que
//                destile la LECCIÓN del hilo completo: eso es lo que el
//                copiloto cita la próxima vez. La lección nunca bloquea el
//                guardado: si la IA falla, el caso queda igual.
// ============================================================================

const SELECT_CONV = 'id, usuario_id, activo_id, ot_id, diagnostico_id, titulo, estado, mensajes, ultimo_at, created_at, activo:activos(patente, codigo)'
const SELECT_DX = 'id, ot_id, activo_id, usuario_id, sintoma, sistema, estado, comprobaciones, causa_raiz, reparacion, leccion, resuelto_at, validado_at, reaperturas, created_at'

type FuenteGuardada = {
  n: number; titulo: string; pagina: number; tipo: string; url: string | null; citada: boolean
  confiabilidad?: string | null; documento_id?: string | null
}
type AdjuntoGuardado = { nombre: string; tipo: string; path?: string | null }

export async function GET(req: Request) {
  const auth = await autenticar(req)
  if ('error' in auth) return NextResponse.json({ error: auth.error }, { status: auth.status })
  const { sb } = auth
  const id = new URL(req.url).searchParams.get('id')
  if (!id || !/^[0-9a-f-]{36}$/i.test(id)) return NextResponse.json({ error: 'id inválido' }, { status: 400 })

  const { data: conv } = await sb.from('copiloto_conversaciones').select(SELECT_CONV).eq('id', id).maybeSingle()
  if (!conv) return NextResponse.json({ error: 'Conversación no encontrada' }, { status: 404 })
  const conversacion = conv as unknown as ConversacionCopiloto

  const [{ data: dx }, { data: filas }] = await Promise.all([
    conversacion.diagnostico_id
      ? sb.from('copiloto_diagnosticos').select(SELECT_DX).eq('id', conversacion.diagnostico_id).maybeSingle()
      : Promise.resolve({ data: null }),
    sb.from('copiloto_consultas')
      .select('id, pregunta, respuesta, fuentes, codigos, adjuntos, feedback, created_at')
      .eq('conversacion_id', id).order('created_at', { ascending: true }).limit(200),
  ])

  const corpus = corpusCliente()
  const mensajes: MensajeGuardado[] = await Promise.all(((filas ?? []) as {
    id: string; pregunta: string; respuesta: string | null; fuentes: FuenteGuardada[]
    codigos: CodigoCopiloto[]; adjuntos: AdjuntoGuardado[]; feedback: 'util' | 'no_util' | null; created_at: string
  }[]).map(async (f) => {
    const fuentes: FuenteCopiloto[] = await Promise.all((f.fuentes ?? []).map(async (s) => {
      let imagen: string | null = null
      if (corpus && s.documento_id) {
        const { data: pg } = await corpus.from('copiloto_paginas').select('storage_path')
          .eq('documento_id', s.documento_id).eq('pagina', s.pagina).maybeSingle()
        if (pg) imagen = await urlPagina(corpus, (pg as { storage_path: string }).storage_path, 6 * 3600)
      }
      return {
        n: s.n, titulo: s.titulo, pagina: s.pagina, tipo: s.tipo, url: s.url ?? null,
        confiabilidad: s.confiabilidad ?? null, citada: s.citada, imagen, documentoId: s.documento_id ?? null,
      }
    }))
    const adjuntos = await Promise.all((f.adjuntos ?? []).map(async (a) => {
      let preview: string | null = null
      if (corpus && a.path && a.tipo.startsWith('image/')) {
        const { data } = await corpus.storage.from('adjuntos').createSignedUrl(a.path, 3600)
        preview = data?.signedUrl ?? null
      }
      return { nombre: a.nombre, tipo: a.tipo, preview }
    }))
    return {
      consultaId: f.id, pregunta: f.pregunta, respuesta: f.respuesta, fuentes,
      codigos: Array.isArray(f.codigos) ? f.codigos : [], adjuntos, feedback: f.feedback, created_at: f.created_at,
    }
  }))

  return NextResponse.json({
    conversacion,
    diagnostico: (dx as unknown as DiagnosticoCopiloto | null) ?? null,
    mensajes,
  })
}

// ── Solución definitiva ─────────────────────────────────────────────────────
const MODELO_LECCION = process.env.COPILOTO_MODELO_LECCION ?? 'claude-opus-5-5'

const SISTEMAS = ['electrico', 'motor', 'transmision', 'frenos', 'hidraulica', 'direccion',
  'tren_rodaje', 'combustible', 'postratamiento', 'implemento', 'lubricacion', 'otro']

const FORMATO_LECCION = jsonSchemaOutputFormat({
  type: 'object',
  properties: {
    leccion: {
      type: 'string',
      description: 'Lección para el próximo mecánico, en español de Chile, 2 a 5 frases: cuándo sospechar esta causa (síntoma + condición), qué comprobación la confirma más rápido (con el valor medido si lo hay), qué NO funcionó si hubo intentos fallidos, y la reparación definitiva. Solo hechos presentes en la conversación.',
    },
    palabras_clave: {
      type: 'array', items: { type: 'string' },
      description: 'De 5 a 12 términos de búsqueda: componentes, síntomas, códigos de falla y sinónimos de taller (español e inglés). Sin inventar.',
    },
    sistema: { type: 'string', enum: SISTEMAS },
    sintoma_normalizado: { type: 'string', description: 'El síntoma en una frase técnica corta.' },
  },
  required: ['leccion', 'palabras_clave', 'sistema', 'sintoma_normalizado'],
  additionalProperties: false,
} as const)

export async function POST(req: Request) {
  const auth = await autenticar(req)
  if ('error' in auth) return NextResponse.json({ error: auth.error }, { status: auth.status })
  const { sb } = auth
  let body: { accion?: string; conversacionId?: string; causa?: string; reparacion?: string; sistema?: string | null; sintoma?: string | null }
  try { body = await req.json() } catch { return NextResponse.json({ error: 'JSON inválido.' }, { status: 400 }) }
  if (body.accion !== 'resolver') return NextResponse.json({ error: 'Acción desconocida.' }, { status: 400 })
  const convId = body.conversacionId ?? ''
  if (!/^[0-9a-f-]{36}$/i.test(convId)) return NextResponse.json({ error: 'conversación inválida' }, { status: 400 })

  const { data: dxId, error } = await sb.rpc('rpc_copiloto_solucion', {
    p_conversacion_id: convId,
    p_causa_raiz: body.causa ?? '',
    p_reparacion: body.reparacion ?? '',
    p_sistema: body.sistema ?? null,
    p_sintoma: body.sintoma ?? null,
  })
  if (error) return NextResponse.json({ error: error.message }, { status: 400 })

  // Lección destilada del hilo completo (síntoma, bitácora, lo conversado)
  let leccion: string | null = null
  try {
    if (process.env.ANTHROPIC_API_KEY) {
      const [{ data: dx }, { data: filas }, { data: conv }] = await Promise.all([
        sb.from('copiloto_diagnosticos').select(SELECT_DX).eq('id', dxId).maybeSingle(),
        sb.from('copiloto_consultas').select('pregunta, respuesta, created_at').eq('conversacion_id', convId)
          .order('created_at', { ascending: true }).limit(40),
        sb.from('copiloto_conversaciones').select('activo:activos(patente, modelo:modelos(nombre, marca:marcas(nombre)))').eq('id', convId).maybeSingle(),
      ])
      const d = dx as unknown as DiagnosticoCopiloto | null
      const equipo = (conv as unknown as { activo?: { patente?: string; modelo?: { nombre?: string; marca?: { nombre?: string } } } } | null)?.activo
      const transcript = ((filas ?? []) as { pregunta: string; respuesta: string | null }[])
        .map((f) => `MECÁNICO: ${f.pregunta.slice(0, 1200)}\nCOPILOTO: ${(f.respuesta ?? '').slice(0, 1500)}`).join('\n\n')
      const bitacora = (d?.comprobaciones ?? [])
        .map((c) => `- ${c.tipo === 'reparacion_fallida' ? '[REPARACIÓN FALLIDA] ' : ''}${c.descripcion}${c.valor ? ` = ${c.valor}` : ''} → ${c.resultado}`).join('\n')

      const anthropic = new Anthropic()
      const res = await anthropic.messages.parse({
        model: MODELO_LECCION,
        max_tokens: 2000,
        output_config: { effort: 'low', format: FORMATO_LECCION },
        system: 'Eres el jefe de taller que documenta casos técnicos de camiones pesados para que el próximo mecánico llegue más rápido a la causa. Escribes en español de Chile, concreto, sin relleno. Nunca inventas valores ni pasos que no estén en el material.',
        messages: [{
          role: 'user',
          content: `EQUIPO: ${equipo?.patente ?? 'sin equipo'} · ${equipo?.modelo?.marca?.nombre ?? ''} ${equipo?.modelo?.nombre ?? ''}\n`
            + `SÍNTOMA: ${d?.sintoma ?? ''}\nSISTEMA: ${d?.sistema ?? 'no indicado'}\n`
            + `CAUSA RAÍZ (confirmada por el mecánico): ${d?.causa_raiz ?? ''}\nSOLUCIÓN DEFINITIVA (confirmada): ${d?.reparacion ?? ''}\n`
            + `REAPERTURAS: ${d?.reaperturas ?? 0}\n\nBITÁCORA DE COMPROBACIONES:\n${bitacora || '(sin comprobaciones registradas)'}\n\n`
            + `CONVERSACIÓN:\n${transcript || '(sin mensajes)'}\n\nDestila la lección.`,
        }],
      })
      const out = res.parsed_output
      if (out?.leccion) {
        leccion = `${out.leccion.trim()}\nPalabras clave: ${out.palabras_clave.join(', ')}`
        await sb.rpc('rpc_copiloto_caso_leccion', { p_diagnostico_id: dxId, p_leccion: leccion, p_sistema: out.sistema === 'otro' ? null : out.sistema })
      }
    }
  } catch (e) {
    console.error('[copiloto] lección falló', convId, e instanceof Error ? e.message : e)
  }

  const { data: dxFinal } = await sb.from('copiloto_diagnosticos').select(SELECT_DX).eq('id', dxId).maybeSingle()
  return NextResponse.json({ ok: true, diagnosticoId: dxId, leccion, diagnostico: dxFinal ?? null })
}
