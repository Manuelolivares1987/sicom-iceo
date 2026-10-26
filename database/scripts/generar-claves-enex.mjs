#!/usr/bin/env node
// Claves nuevas para los supervisores de ENEX, en un txt para entregar.
//
//   node database/scripts/generar-claves-enex.mjs
//
// Genera una clave al azar por cuenta, la asigna con cambiar-clave.mjs (que
// repara la cuenta y verifica con un login real) y deja todo en
// Escritorio/Accesos_Supervisores_ENEX.txt. Las claves no se imprimen en la
// consola: solo quedan en ese archivo. Bórralo después de entregarlas.

import { execFileSync } from 'child_process'
import { randomInt } from 'crypto'
import { existsSync, writeFileSync } from 'fs'
import { homedir } from 'os'
import { resolve, dirname, join } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))

const CUENTAS = [
  { correo: 'supervisor.combustible@sicom-iceo.cl', mundo: 'Combustible' },
  { correo: 'supervisor.lubricantes@sicom-iceo.cl', mundo: 'Lubricantes' },
]

// Fácil de dictar y de escribir en el celular: sin letras que se confunden
// (l/1, O/0) y con un formato que se lee de una vez: Palabra-Palabra-1234.
const PALABRAS = ['Cobre', 'Surtidor', 'Faena', 'Calama', 'Diesel', 'Estanque', 'Bomba', 'Valvula',
  'Desierto', 'Turno', 'Sello', 'Manguera', 'Filtro', 'Camion', 'Pampa', 'Andes']
const clave = () =>
  `${PALABRAS[randomInt(PALABRAS.length)]}-${PALABRAS[randomInt(PALABRAS.length)]}-${randomInt(1000, 10000)}`

const escritorio = [join(homedir(), 'OneDrive', 'Escritorio'), join(homedir(), 'OneDrive', 'Desktop'),
  join(homedir(), 'Desktop')].find((d) => existsSync(d)) ?? homedir()
const archivo = join(escritorio, 'Accesos_Supervisores_ENEX.txt')

const resultados = []
for (const c of CUENTAS) {
  const pass = clave()
  try {
    execFileSync(process.execPath, [resolve(__dirname, 'cambiar-clave.mjs'), c.correo, pass], { stdio: 'pipe' })
    resultados.push({ ...c, pass, ok: true })
    console.log(`✓ ${c.correo}: clave nueva asignada y login verificado`)
  } catch (e) {
    resultados.push({ ...c, pass: null, ok: false })
    console.error(`✗ ${c.correo}: ${String(e.stderr ?? e.message).trim().split('\n').pop()}`)
  }
}

const hoy = new Date().toLocaleDateString('es-CL', { timeZone: 'America/Santiago' })
const txt = `ACCESOS SUPERVISORES ENEX — SICOM
Generado: ${hoy}
Entregar a cada supervisor SOLO su acceso. Borrar este archivo después.
======================================================================

${resultados.map((r) => `SUPERVISOR ${r.mundo.toUpperCase()}
  Usuario:  ${r.correo}
  Clave:    ${r.ok ? r.pass : '(NO SE PUDO CAMBIAR — avisar)'}
`).join('\n')}
======================================================================
CÓMO ENTRAR (una sola vez, con señal)
  1. En el celular, abrir:  https://pilladoiceo.netlify.app
  2. Ingresar usuario y clave.
  3. La app entra sola a "Terreno ENEX", en su mundo (Combustible o
     Lubricantes), y descarga todo para trabajar sin señal.
  4. Esperar el aviso verde "Listo para trabajar sin señal".
  5. Una sola vez: menú del navegador → "Agregar a pantalla de inicio".
     (En iPhone es necesario para que no se borre lo guardado.)

DESPUÉS
  - NO cerrar sesión. La sesión dura aunque pasen días sin señal.
  - Abrir la app con señal antes de ir a faena (se actualiza sola).
  - Sin señal se trabaja igual: lo guardado queda en "Por enviar"
    y se envía solo cuando vuelve la señal. No desinstalar ni borrar
    datos del navegador mientras haya algo en "Por enviar".
  - En cada servicio: "Observaciones y repuestos" para anotar hallazgos
    y pedir repuestos. Al guardar, llega un correo a la jefatura.
`
writeFileSync(archivo, txt, 'utf8')
console.log(`\nArchivo: ${archivo}`)
if (resultados.some((r) => !r.ok)) process.exit(1)
