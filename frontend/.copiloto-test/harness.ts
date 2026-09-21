import { POST } from '../src/app/api/copiloto/consulta/route'
const pregunta = process.argv[2] ?? 'hola'
const conEquipo = process.argv[3] !== 'general'
const t0 = Date.now()
const res = await POST(new Request('http://x/api', { method: 'POST', body: JSON.stringify({ pregunta, activoId: conEquipo ? 'a1' : undefined, formato: 'ndjson' }) }))
if (!(res.headers.get('content-type') ?? '').includes('ndjson')) { console.log('HTTP', res.status, await res.text()); process.exit(1) }
const reader = res.body!.getReader(); const dec = new TextDecoder(); let buf = '', texto = ''
for (;;) { const { done, value } = await reader.read(); if (done) break; buf += dec.decode(value, { stream: true })
  const ls = buf.split('\n'); buf = ls.pop() ?? ''
  for (const l of ls) { if (!l) continue; const e = JSON.parse(l)
    if (e.t === 'estado') console.log('  [estado]', e.d)
    else if (e.t === 'texto') texto += e.d
    else if (e.t === 'fuentes') console.log('  [fuentes]', e.d.map((f: any) => `F${f.n}${f.imagen ? '🖼' : ''}${f.citada ? '' : '(no citada)'} ${f.titulo.slice(0, 55)} p${f.pagina}${f.url ? ' 🔗' : ''}`).join('\n            '))
    else if (e.t === 'codigos') console.log('  [codigos]', e.d.map((c: any) => c.codigo).join(', '))
    else if (e.t === 'error') console.log('  [ERROR]', e.d) } }
console.log('\n----- RESPUESTA (' + Math.round((Date.now() - t0) / 1000) + ' s) -----\n' + texto)
