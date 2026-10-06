// Harness del Copiloto: llama a la ruta REAL (/api/copiloto/consulta) con un
// SICOM falso (server-fake.ts) y el corpus real. Imprime el stream legible;
// con EVAL_JSON=1 agrega al final una línea JSON para el evaluador (eval.mjs).
import { POST } from '../src/app/api/copiloto/consulta/route'
const pregunta = process.argv[2] ?? 'hola'
const conEquipo = process.argv[3] !== 'general'
const t0 = Date.now()
const res = await POST(new Request('http://x/api', { method: 'POST', body: JSON.stringify({ pregunta, activoId: conEquipo ? 'a1' : undefined, formato: 'ndjson' }) }))
if (!(res.headers.get('content-type') ?? '').includes('ndjson')) { console.log('HTTP', res.status, await res.text()); process.exit(1) }
const reader = res.body!.getReader(); const dec = new TextDecoder(); let buf = '', texto = ''
const estados: string[] = []; let fuentes: unknown[] = []; let codigos: string[] = []; let fin: Record<string, unknown> = {}; let error: string | null = null
for (;;) { const { done, value } = await reader.read(); if (done) break; buf += dec.decode(value, { stream: true })
  const ls = buf.split('\n'); buf = ls.pop() ?? ''
  for (const l of ls) { if (!l) continue; const e = JSON.parse(l)
    if (e.t === 'estado') { estados.push(e.d); console.log('  [estado]', e.d) }
    else if (e.t === 'texto') texto += e.d
    else if (e.t === 'fuentes') { fuentes = e.d; console.log('  [fuentes]', e.d.map((f: any) => `F${f.n}${f.imagen ? '🖼' : ''}${f.citada ? '' : '(no citada)'} ${f.titulo.slice(0, 55)} p${f.pagina}${f.url ? ' 🔗' : ''}`).join('\n            ')) }
    else if (e.t === 'codigos') { codigos = e.d.map((c: any) => c.codigo); console.log('  [codigos]', codigos.join(', ')) }
    else if (e.t === 'fin') fin = e
    else if (e.t === 'error') { error = e.d; console.log('  [ERROR]', e.d) } } }
console.log('\n----- RESPUESTA (' + Math.round((Date.now() - t0) / 1000) + ' s) -----\n' + texto)
if (process.env.EVAL_JSON) console.log('\n__EVAL__' + JSON.stringify({ texto, estados, fuentes, codigos, error, ms: Date.now() - t0, ...fin }))
