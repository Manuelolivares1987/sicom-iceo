# Copiloto Técnico del Taller

Retoma el proyecto `copiloto-taller` (mayo 2026) integrado a SICOM (2026-09-08).
El mecánico pregunta desde `/m/taller/copiloto` (o con el botón **Copiloto**
dentro de su OT) y Claude responde con:

- el **contexto real del equipo** (ficha, historial de mantenimiento, NC
  abiertas, OT actual) desde la base de SICOM, y
- los **manuales de la flota** (275 PDFs del Desktop) desde un proyecto
  Supabase **paralelo** (`copiloto-corpus`), con citas de documento y página,

bajo reglas estrictas de no-invención: los torques, presiones, fusibles y
códigos de falla solo pueden salir de las fuentes citadas.

## Por qué un Supabase paralelo

Decisión 2026-09-08: la DB de SICOM producción va en 255/500 MB (plan free)
y el storage al 67%. El corpus (50–150 MB de chunks + eventualmente los PDFs)
vive aparte para **no arriesgar la operación**. La app le pega solo desde el
servidor con la service key; no hay una "segunda app".

```
/m/taller (misma app, mismo login)
    └── /api/copiloto/consulta (servidor)
          ├── SICOM DB ............ contexto del equipo + auditoría (MIG542)
          ├── copiloto-corpus ..... buscar_chunks() sobre los manuales
          └── Claude API .......... claude-opus-5, streaming, citas
```

## Puesta en marcha (una sola vez)

1. **Crear el proyecto Supabase** `copiloto-corpus` (supabase.com → New
   project, misma región que SICOM). Anotar:
   - la connection string directa de la DB (Settings → Database),
   - la URL del proyecto y la **service_role** key (Settings → API).

2. **Credenciales locales** — crear `database/.env.copiloto.local`:
   ```
   COPILOTO_DB_URL=postgresql://postgres:...@db.<ref>.supabase.co:5432/postgres
   ```

3. **Aplicar el esquema del corpus**:
   ```
   cd database/scripts
   node copiloto-ingesta.mjs --schema
   ```

4. **Ingestar los manuales** (lee el Desktop, Mercedes primero):
   ```
   node copiloto-ingesta.mjs                      # todo
   node copiloto-ingesta.mjs --carpeta "ACTROS"   # solo Mercedes
   node copiloto-ingesta.mjs --dry-run --max 10   # prueba sin escribir
   ```
   Es idempotente (hash sha256 por archivo): correrlo de nuevo solo agrega lo
   nuevo. Los PDF escaneados sin capa de texto quedan registrados y
   encontrables por título (el OCR es fase 2).

5. **Variables en Netlify** (Site settings → Environment variables):
   - `ANTHROPIC_API_KEY` — key nueva dedicada al copiloto
   - `COPILOTO_SUPABASE_URL` — URL del proyecto corpus
   - `COPILOTO_SUPABASE_SERVICE_KEY` — service_role del proyecto corpus

   Para probar en local, las mismas tres en `frontend/.env.local`.

Sin estas variables la app **no se cae**: el copiloto responde solo con el
contexto del equipo y avisa que los manuales aún no están disponibles.

## Auditoría y costo

Cada consulta queda en `copiloto_consultas` (SICOM, MIG542): usuario, equipo,
pregunta, respuesta, fuentes usadas, tokens y feedback 👍/👎 del mecánico.
Jefatura (administrador/gerencia/jefe_mantenimiento/planificador) ve todo;
cada mecánico ve lo suyo. Con eso se mide: qué se pregunta, qué vacíos tiene
el corpus (búsquedas sin fuentes) y el costo real (tokens × tarifa).

## Fase 2 (pendiente)

- OCR de los PDF escaneados (varios manuales de fusibles/eléctricos lo son).
- Subir los PDFs al storage del corpus (1 GB libre) para "ver la página".
- Embeddings pgvector si la búsqueda full-text se queda corta.
- Panel de jefatura sobre `copiloto_consultas`.
- Casos técnicos: convertir un diagnóstico exitoso en conocimiento citable.
