import { spawn } from 'node:child_process'
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
const SP = 'C:/Users/MANUEL~1/AppData/Local/Temp/claude/C--Users-Manuel-Olivares/ae56acb4-8fd2-40de-b168-1fa539324f0d/scratchpad'
const qs = JSON.parse(readFileSync(`${SP}/consultas_reales.json`, 'utf8'))
mkdirSync(`${SP}/eval`, { recursive: true })
const run = (x, i) => new Promise((ok) => {
  const env = { ...process.env, T_PATENTE: x.patente ?? '', T_MARCA: x.marca ?? '', T_MODELO: x.modelo ?? '' }
  const p = spawn('node', ['.copiloto-test/harness.mjs', x.pregunta, x.patente ? 'equipo' : 'general'], { env })
  let out = ''; p.stdout.on('data', (d) => (out += d)); p.stderr.on('data', (d) => (out += d))
  p.on('close', () => { writeFileSync(`${SP}/eval/${String(i + 1).padStart(2, '0')}.txt`, `PREGUNTA: ${x.pregunta}\nEQUIPO: ${x.patente ?? '(sin equipo)'} ${x.marca ?? ''} ${x.modelo ?? ''}\n\n${out}`); console.log('listo', i + 1); ok() })
})
const cola = qs.map((x, i) => () => run(x, i))
await Promise.all(Array.from({ length: 4 }, async () => { while (cola.length) await cola.shift()() }))
