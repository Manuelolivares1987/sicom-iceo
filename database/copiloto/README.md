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

## v2 «clase mundial» (2026-09-19)

Pedido de Manuel: información técnica de toda la flota (diagramas eléctricos,
códigos, fusibles) y la app a estándar mundial. Qué cambió:

- **Agente con herramientas** (`/api/copiloto/consulta`): Claude busca en los
  manuales las veces que necesite (es/en/pt), consulta la tabla de códigos,
  lista documentos, revisa casos resueltos y **mira la página del diagrama**
  (visión) antes de explicarlo. Stream NDJSON con progreso, texto y fuentes
  numeradas `[Fn]` (enlace al documento oficial + imagen de la página).
- **Fix**: el filtro por modelo exigía igualdad (`actros-3336-k` ≠ `actros`):
  desde el camión nunca salían los manuales de Actros/Atego/Axor/Accelo/FMX.
  Ahora calza por prefijo (`corpus_schema_v2.sql`).
- **Códigos de falla** estructurados (`copiloto_codigos_falla`) con búsqueda
  directa sin IA (`/api/copiloto/codigo`) — botón `#` en el chat.
- **Ficha técnica por camión** (`copiloto_fichas_equipo`, desde la Biblioteca
  Maestra → `conocimiento/flota_pesada.json`): VIN, motor, caja, ECUs y cómo
  leer códigos en SU tablero (`/api/copiloto/ficha`).
- **Páginas de diagramas como imagen** (`copiloto_paginas` + bucket `paginas`,
  ~230 MB): visor con zoom en el teléfono.
- **Conocimiento investigado en la web** (`conocimiento/*.md`, una ficha por
  hecho con su URL y confiabilidad: oficial / técnica / experiencia de campo).
- UI: markdown con tablas, citas tocables, dictado por voz, selector de equipo
  sin OT, tarjetas de códigos.
- **Adjuntos del mecánico** (hasta 6 fotos/PDF, 20 MB c/u): el teléfono sube
  directo al bucket `adjuntos` del corpus con URL firmada
  (`/api/copiloto/adjunto`) y Claude los lee (visión / PDF).
- **Aportes a la biblioteca desde el celular**: cualquier foto o PDF adjunto
  se puede «Aportar a biblioteca» con una descripción (etiqueta de fusibles
  de la tapa, placa de motor/bomba/grúa/PTO, diagrama pegado en el equipo,
  manual del implemento). Flujo de jefatura:
  ```
  node copiloto-conocimiento.mjs --aportes      # baja a Manuales/_Aportes taller/
  # revisar y borrar lo que no sirva
  python copiloto-aportes-pdf.py                # foto + descripción → PDF buscable
  node copiloto-ingesta.mjs --dir "<...>/Manuales/_Aportes taller"
  python copiloto-paginas.py --doc "aporte taller"
  ```
- **Si el repositorio no alcanza, Claude resuelve**: búsqueda y lectura web
  (herramientas de servidor `web_search` / `web_fetch`, fuentes oficiales
  primero, cada dato con su enlace) y, si tampoco hay, criterio técnico
  general marcado «🧠 no verificado en manual». Los valores críticos siguen
  exigiendo fuente citada. Costo extra: ~US$0,01 por búsqueda web.

### Puesta en marcha v2 (en orden)

```
cd database/scripts
node copiloto-conocimiento.mjs --schema-v2         # tablas, bucket y búsqueda v2
node copiloto-ingesta.mjs --dir "<...>/Manuales/_Investigacion web 2026-09-19"   # PDFs nuevos
node copiloto-conocimiento.mjs --todo              # fichas, conocimiento, códigos, URLs
python copiloto-paginas.py --dry-run               # cuánto pesa
python copiloto-paginas.py                         # render + subida de diagramas
```

Para regenerar `flota_pesada.json` desde el Excel (ExcelJS no lo lee):
`python copiloto-flota-json.py [ruta.xlsx]` y luego `node copiloto-conocimiento.mjs --fichas`.

Opcional en Netlify: `COPILOTO_EFFORT` (`low|medium|high`, default `medium`).

**Ojo plan free:** el proyecto `copiloto-corpus` se pausa tras 7 días sin
uso. Si queda INACTIVE, el copiloto responde sin manuales (no se cae).
Reactivarlo en supabase.com → proyecto → *Restore*.

## Kaufmann Asesor Virtual (2026-09-21)

`asesor.kaufmann.cl` (cuenta Pillado) publica por modelo: información técnica
(manuales de taller, planos eléctricos, diagnóstico), pautas de mantenimiento
y garantías. Axor, Atego, Accelo, Fuso Canter, Freightliner M2-106, aljibes y
Actros Euro IV-V (la carpeta `Mercedes ACTROS` ya había salido de acá: el
número inicial del archivo es el id de Kaufmann).

- 371 archivos nuevos (+102 PDF dentro de las pautas ZIP/RAR) en
  `Mantenimiento/Manuales/_Kaufmann Asesor 2026-09/<Modelo>/<pestaña>/`,
  nombrados `<id>_<Modelo>_<archivo>` para que la ingesta asigne marca/modelo.
- **No se suben los PDF al storage** (el plan free es 1 GB): los archivos de
  `/uploads/` de Kaufmann son públicos, así que `copiloto_documentos.url_fuente`
  apunta al original y la cita abre `…pdf#page=N`. 458 documentos enlazados.
  Si Kaufmann los pone tras login, el texto sigue en el corpus y la copia
  local queda en el Desktop.
- Inventario: la página se recorre desde el navegador con sesión (las fichas
  por modelo están en `/vehicles/<id>`; los checkbox de cada fila traen el id).

## Fase 3 (pendiente)

- OCR de los PDF escaneados (con las imágenes de página, Claude ya puede leerlos por visión).
- Embeddings pgvector si la búsqueda full-text se queda corta.
