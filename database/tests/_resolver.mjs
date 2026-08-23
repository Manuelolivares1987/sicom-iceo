// ============================================================================
// Resuelve los alias del frontend cuando sus módulos se importan desde Node.
// ----------------------------------------------------------------------------
// Existe para que las pruebas puedan importar EL MISMO archivo que corre en el
// navegador, en vez de una copia parecida que se desincroniza en dos semanas.
// Traduce el alias '@/' y las dependencias que Next resuelve solo.
// ============================================================================
import { pathToFileURL } from 'node:url'
import { resolve as resolverRuta, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const aqui = dirname(fileURLToPath(import.meta.url))
const SRC = resolverRuta(aqui, '../../frontend/src')
const NM = resolverRuta(aqui, '../../frontend/node_modules')

export async function resolve(especificador, contexto, siguiente) {
  if (especificador.startsWith('@/')) {
    // '@/lib/supabase' no se usa fuera del navegador: la prueba inyecta su
    // propio cliente. Se apunta a un módulo vacío para no arrastrar el SDK.
    if (especificador === '@/lib/supabase') {
      return { url: pathToFileURL(resolverRuta(aqui, '_sin-supabase.mjs')).href, shortCircuit: true }
    }
    return { url: pathToFileURL(resolverRuta(SRC, especificador.slice(2))).href, shortCircuit: true }
  }
  if (especificador === 'exceljs') {
    return { url: pathToFileURL(resolverRuta(NM, 'exceljs/excel.js')).href, shortCircuit: true }
  }
  return siguiente(especificador, contexto)
}
