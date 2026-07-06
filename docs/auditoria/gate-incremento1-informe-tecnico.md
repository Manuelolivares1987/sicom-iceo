# Gate Incremento 1 — Informe técnico de intervención + Historial

**Fecha:** 2026-07-05 · **Rama:** `feature/informe-tecnico-incremento-1`
**Regla:** GO solo si TODOS los criterios se cumplen, ejecutados y verificados.
**No aplicado en producción.** Probado en PostgreSQL 17 con backup real restaurado.

---

## Prevalidación del esquema productivo (§1)

Consultas de solo lectura contra prod confirmaron definiciones reales (documentadas):
`ordenes_trabajo`, `taller_ot_ejecuciones` (+eventos), `inventario_consumos_capas`,
`salidas_bodega_items`, `no_conformidades`, `checklist_v2_instance(_item)`,
`v_bitacora_equipo`, `rpc_cerrar_ot_supervisor`, buckets/policies de Storage.

**Diferencias repo↔producción detectadas y consideradas en el diseño:**
- La función de transición real es `rpc_transicion_ot` (NO existe `registrar_transicion_ot`).
- `productos` usa columna `unidad_medida` (no `unidad`) → corregido en la RPC de precarga.
- `inventario_capas.costo_total_inicial/disponible` e `inventario_consumos_capas.costo_total_consumido`
  son columnas GENERADAS → la consolidación las lee, no las escribe.
- No existe usuario `jefe_mantenimiento` activo ni datos en `inventario_consumos_capas`
  en el backup → para las pruebas se inyectaron datos sintéticos en la copia desechable.

## Migración (191_informes_intervencion.sql)

Aditiva, idempotente, con RLS, grants mínimos, postvalidación y rollback de desarrollo.
Aplicada en PG17 restaurado (170 tablas de prod) → **POSTVAL OK: 5 tablas, 9 RPCs, RLS
activa, bucket privado, vista extendida.**

- 5 tablas nuevas (cabecera + trabajos + materiales + mano de obra + pruebas) + correlativo.
- Folio `IT-YYYYMM-#####` con **advisory lock** (sin MAX()+1 suelto).
- 9 RPCs `SECURITY DEFINER` fail-closed (módulo `informes`, sin tocar MIG185/189).
- Inmutabilidad: RLS sin UPDATE directo + trigger que rechaza cambios sustantivos + auditoría.
- Bitácora: `v_bitacora_equipo` extendida con 7ª fuente `informe_tecnico` (6 fuentes originales intactas).
- Bucket **privado** `informes-tecnicos` + policies.

## Pruebas ejecutadas (PostgreSQL 17, backup real) — **34 PASS / 0 FAIL**

| Grupo | Resultado |
|-------|-----------|
| **Creación** | A1 crea desde OT real ✅ · A2 OT inexistente rechazada (P0002) ✅ · A3 idempotente (doble clic → mismo id) ✅ · A5/A6 OT sin checklist/ejecución crea ✅ · A1b mano de obra = ejecuciones, tiempo efectivo idéntico (15429s) ✅ · A8 materiales 2 capas FIFO consolidadas, costo=$8.600 ✅ · A7 trabajos precargados (NC/OT/V03, sin copiar ítems ok) ✅ |
| **Permisos** | anon ❌ · sin-perfil ❌ · portal cliente ❌ (42501) · planificador NO crea / SÍ lee ✅ · portal cliente NO lee (RLS, 0 filas) ✅ |
| **Versiones/Inmutabilidad** | técnico NO aprueba ✅ · jefe aprueba con segregación ✅ · snapshot congelado ✅ · trigger rechaza cambio sustantivo a aprobado (42501) ✅ · RLS niega UPDATE directo ✅ · nueva versión sin motivo rechazada ✅ · una sola vigente, anterior conservada ✅ · anulado no reaprobable ✅ |
| **Snapshots** | materiales inmunes a cambio de nombre de producto ✅ · informe cerrado inmune a nuevos consumos ✅ · tiempo efectivo == ejecuciones ✅ · costo == capas FIFO ✅ |
| **PDF** | registrar PDF solo tras aprobar ✅ · cerrar exige PDF ✅ · bucket privado ✅ |
| **Bitácora** | evento `informe_tecnico` visible ✅ · sin duplicados (1 vigente/OT) ✅ · fuentes existentes intactas ✅ |
| **Regresión** | `v_bitacora_equipo` no rota ✅ · `informes_recepcion` no modificada ✅ · `rpc_cerrar_ot_supervisor` intacta (gate NO tocado) ✅ |

Hallazgo corregido durante pruebas: anular una corrección ahora **restaura la versión anterior
como vigente** (evita que la OT quede sin informe efectivo en la bitácora).

## Frontend (§10–12)

Archivos nuevos:
- `frontend/src/lib/services/informe-intervencion.ts` — tipos + wrappers de las 9 RPCs +
  `generarYSubirPDF` (blob → bucket privado `informes-tecnicos` con `upsert:false` → SHA-256
  con `crypto.subtle.digest` → `rpc_registrar_pdf_informe`) + `getSignedPdfUrl` (createSignedUrl,
  **nunca getPublicUrl**).
- `frontend/src/components/informe-intervencion/pdf-informe-tecnico.tsx` — PDF `@react-pdf/renderer`
  con las 18 secciones (sin información comercial/recobro).
- `frontend/src/components/informe-intervencion/informe-tecnico-seccion.tsx` — sección embebida en
  la ficha de OT, con acciones gated por rol (espejo de `fn_ii_puede`) y advertencia no bloqueante.

Archivos modificados: `ordenes-trabajo/[id]/page.tsx` (integra la sección),
`lib/services/bitacora.ts` (+`informe_tecnico`), `bitacora/[activoId]/page.tsx` (icono/label/filtro
+ detalle on-demand + "Ver PDF" por signed URL).

**Verificación (ejecutada por mí, no solo por el agente):**
- `npm run typecheck` (tsc --noEmit): **PASS, 0 errores**.
- `npm run build` (next build): **PASS — ✓ Compiled successfully, 99/99 páginas**, OT detail 25.6 kB.
- `npm run lint`: PASS (solo warnings preexistentes en otros archivos; 0 en los nuevos).
- No hay script `npm test` en esta rama (el setup vitest quedó en `sprint1/entrega-a`, no fusionado);
  la validación de comportamiento se hizo con la suite SQL (34/34) en PG17.

Nota honesta: el render en vivo del PDF en navegador (react-pdf) no se ejecuta en esta validación
headless; sí están **probados el contrato server-side** (`rpc_registrar_pdf`, cierre exige PDF),
el **bucket privado**, y el código compila. Render en vivo a verificar en staging tras desplegar.

## Criterios del gate (§15)

| Criterio | Estado |
|----------|:------:|
| Migración aplicada en preproducción completa | ✅ |
| Informe creado desde OT real anonimizada | ✅ |
| Trabajos precargados | ✅ |
| Tiempos correctos (== ejecuciones) | ✅ |
| Materiales FIFO correctos (== capas) | ✅ |
| PDF privado generado | ✅ (código + contrato server + bucket privado; render vivo en staging) |
| Dos versiones coexisten | ✅ |
| Aprobado es inmutable | ✅ |
| Bitácora muestra el informe | ✅ |
| Permisos probados | ✅ |
| Cierre actual de OT no roto | ✅ |
| Informe de recobro no modificado | ✅ |
| build/typecheck/lint/tests pasan | ✅ |
| No existen secretos | ✅ |
| MIG188 no ejecutada | ✅ |

## Procedimiento de despliegue (no ejecutar aún)
1. Merge de `feature/informe-tecnico-incremento-1` vía PR (CI: frontend + migraciones + secretos).
2. Backup previo de prod (tarea/manual) + `pg_restore --list`.
3. Aplicar `191_informes_intervencion.sql` con el ejecutor endurecido
   (`node database/scripts/db-migrate.mjs apply 191...`) → registra en `schema_migrations`.
4. Verificar POSTVAL (5 tablas, 9 RPCs, RLS, bucket privado) + `--status`.
5. Deploy frontend (Netlify). Smoke test en staging: crear informe desde una OT, aprobar
   (con dos usuarios distintos), generar PDF (render vivo), ver por signed URL, comprobar bitácora.
6. NO aplicar el gate de cierre de OT (Incremento 2). NO ejecutar MIG188.

## Validación en STAGING (Supabase local aislado: GoTrue + PostgREST + Storage)

Entorno: `supabase start` (Docker) — stack completo real. Datos representativos: backup de prod
restaurado (170 tablas, 68 activos, 74 OTs) + capas FIFO y jefe sintéticos. MIG191 aplicada con
el **ejecutor formal** (`db-migrate --apply`): registrada `version=191`, `hash=923671bd…`
(== SHA-256 del paquete congelado), `commit=d71e056` (== HEAD), `env=staging`, `ms=141`, `ok=true`.
Postvalidación: 6 tablas / 9 RPCs / RLS / bucket privado / vista 7 fuentes / anon fail-closed.

**E2E real por la API (la ruta exacta del navegador) — 32 PASS / 0 FAIL:**
- Login GoTrue (técnico/jefe/admin/planificador/portal).
- Crear desde OT (idempotente), precarga (trabajos, mano de obra tiempo efectivo=15429s, materiales
  FIFO 2 capas = $8.600), enviar/observar/aprobar (técnico NO aprueba; jefe≠ejecutor).
- **PDF real** (`@react-pdf/renderer`): render sin error, `%PDF` válido, 2 páginas, **16/16 marcadores
  de sección presentes**. SHA-256 calculado.
- **Storage bucket privado**: jefe sube (`upsert:false`), 2º upload rechazado, **técnico NO sube**
  (policy approve), **signed URL abre el PDF (200 + %PDF)**, **URL pública = 400**, **anon denegado**,
  **portal cliente denegado**. Registrar PDF + cerrar.
- **Versiones**: v2 creada, PDF de v2 coexiste con v1, una sola vigente, **anular v2 restaura v1**.
- **Permisos**: planificador lee/NO crea, portal NO lee (RLS 0 filas).
- **Bitácora**: `informe_tecnico` visible, fuentes previas intactas.
- **Regresión**: `informes_recepcion` accesible/no modificada; cierre de OT no tocado.

**Hallazgo menor (no bloqueante):** con listas de trabajos muy largas (172 ítems en el dato de
prueba) react-pdf emite `View can't wrap between pages`; el PDF se genera con todas las secciones.
Pulido post-gate: añadir `wrap` a los contenedores de lista. No afecta el veredicto.

## Criterios del gate de staging (§11)

| Criterio | Estado |
|----------|:------:|
| MIG191 aplicada en staging | ✅ (ejecutor formal, hash/commit/env registrados) |
| PDF renderizado (motor real react-pdf) | ✅ (61 KB, 2 páginas, 16/16 secciones) |
| PDF abierto mediante signed URL | ✅ (200 + %PDF) |
| Acceso público denegado | ✅ (400) · anon y portal denegados |
| Dos versiones y dos PDFs coexisten | ✅ |
| Inmutabilidad funciona | ✅ (trigger + RLS, probado en PG17 y staging) |
| Anulación no crea dos vigentes | ✅ (anular v2 → 1 vigente) |
| Bitácora funciona | ✅ |
| Cierre actual de OT no modificado | ✅ |
| Recobro no modificado | ✅ |
| Regresiones verdes | ✅ |
| CI verde (PR #3) | ❌ **BLOQUEADO** — ver abajo |
| No existen secretos | ✅ (solo claves demo locales públicas de supabase) |
| MIG188 no ejecutada | ✅ |

### Blocker: CI no corre en PR #3 (dependencia de Entrega A)

El workflow `.github/workflows/ci.yml` y el ejecutor formal (`db-migrate.mjs`,
`test-db-migrate.mjs`, `verificar-migraciones-destructivas.mjs`) **viven en la rama de Entrega A
(PR #1, `fix/auditoria-seguridad-fase-0`), aún no fusionada a `main`.** Como no están en `main`
ni en esta rama, los 3 checks requeridos (`frontend`/`migraciones`/`secretos`) **no se ejecutan en
PR #3**, y la protección de `main` (con `enforce_admins=true`) **bloqueará el merge** hasta que
reporten éxito — comportamiento correcto de fail-safe, no un defecto de Incremento 1.

**Los mismos chequeos pasan localmente/staging**: typecheck 0, lint 0 en archivos nuevos, build
✓ (99/99), suite SQL 34/34, E2E staging 32/32. Lo único ausente es que el workflow **corra en
GitHub sobre este PR**.

**Remediación (orden de merge):** fusionar primero Entrega A (PR #2/#1) para llevar `ci.yml` +
ejecutor a `main`; luego rebasar `feature/informe-tecnico-incremento-1` sobre `main` → los 3 checks
corren en PR #3 → al quedar verdes se cierra este criterio y se habilita el merge a producción.

Nota de fidelidad de la validación PDF: se ejecutó por la **ruta de datos exacta del navegador**
(mismo `supabase-js` → GoTrue/PostgREST/Storage y el mismo motor `@react-pdf/renderer`), no por
clic literal en la UI. Los componentes de UI compilan. Se recomienda un click-through manual final.

## Veredicto

Todo lo **técnico** del Incremento 1 está validado y verde: PG17 con backup real (34/34) + staging
Supabase real por la API (32/32) incluyendo **generación y visualización del PDF** (el punto que
estaba pendiente). Cierre de OT y recobro intactos. No se aplicó nada en producción. MIG188 no
ejecutada. **Sin embargo**, el criterio explícito del gate "CI está verde" **no se cumple**: el
workflow de CI no existe en `main`/esta rama (depende de fusionar Entrega A). Por definición del
gate, no puede declararse listo para producción con ese criterio incumplido.

**STAGING INCREMENTO 1 NO-GO — NO DESPLEGAR EN PRODUCCIÓN**
(bloqueador único y acotado: llevar el CI de Entrega A a `main` y correr los 3 checks en PR #3;
todo lo demás está verde)

---

## Cierre de dependencias y habilitación (2026-07-06)

Se resolvió el único bloqueador (CI no corría en PR #3) integrando Entrega A a `main`.

**§1–2 · Entrega A fusionada** — PR #2 (`sprint1/entrega-a`, `e6384ce`) verificado: mergeable,
3 checks requeridos SUCCESS, contiene `ci.yml` + `db-migrate.mjs` + tests + MIG190 + backup, sin
MIG188, sin cambios a cierre OT/recepción/combustible/QR/recobro, sin secretos. **Fusionado a
`main` con merge commit** (preserva trazabilidad). `main` ahora en **`a4d6308`** con CI + ejecutor
+ MIG190 + backup. Protección de `main` intacta: `[frontend, migraciones, secretos]`,
`enforce_admins=true`, `strict=true`. MIG190 **no** re-ejecutada; Entrega A **no** re-desplegada.

**§3 · Reconciliación de PR #3** (`d71e056` validado en staging → HEAD previo `8dce203`):

| Archivo cambiado | Tipo | Runtime | MIG191 | Staging |
|------------------|------|:------:|:------:|:------:|
| `docs/auditoria/gate-incremento1-informe-tecnico.md` | documentación | no | no | no |
| `.gitignore` | no funcional | no | no | no |

Ningún cambio funcional. **SHA-256 de MIG191 = `923671bdf706a0f9`** (idéntico al validado) ⇒ el
staging previo (34/34 + 32/32) sigue respaldando el archivo actual; no requiere repetición completa.

**§4 · Rebase** de `feature/informe-tecnico-incremento-1` sobre `main` (`a4d6308`): **sin conflictos**.
Nuevo HEAD **`9a98452`**. `push --force-with-lease` (nunca `--force`). Hashes del paquete
inalterados (MIG191 `923671bd`, servicio `bee73022`, PDF `fbecc4e9`). No se eliminaron controles de
CI, no se cambió el ejecutor, no se tocó MIG191/`rpc_cerrar_ot_supervisor`/`informes_recepcion`/FIFO,
no se abrió `anon`/portal, no se incorporó MIG188 (el archivo `188_*.sql` ya estaba en `main` desde
Fase 0, **no ejecutado**, ajeno al diff de Inc1).

**§5 · Revalidación (alcance ligero, solo cambios no funcionales)** — verificación de migraciones
destructivas: 230 revisadas, 191 limpia; escaneo de secretos en el paquete: sin JWT; SHA-256 de
MIG191 confirmado. No se repiten las suites 34/34 ni 32/32 (MIG191 sin cambios).

**§6 · CI real en PR #3** (HEAD `9a98452`): **`frontend` SUCCESS · `migraciones` SUCCESS ·
`secretos` SUCCESS**. Rama al día con `main` (strict). Ningún job omitido. Sin bypass de admin.
`mergeable=MERGEABLE`; el estado `UNSTABLE` proviene solo de GitGuardian (check **no requerido**,
falso positivo sobre credenciales locales `postgres`/`x` del harness de pruebas).

**§7 · Wrap del PDF** — registrado como **mejora posterior**: cambiarlo alteraría el hash del
paquete validado/en CI y no es un cambio trivial. El PDF renderiza completo (16/16 secciones aun
con listas largas). No retrasa el cierre.

### Gate final de habilitación

| Criterio | Estado |
|----------|:------:|
| Entrega A en `main` | ✅ (`a4d6308`) |
| PR #3 basado en el nuevo `main` | ✅ |
| HEAD reconciliado | ✅ (`9a98452`) |
| MIG191 coincide con el validado | ✅ (`923671bd`, sin cambios) |
| Tres checks verdes | ✅ |
| Protección de rama activa | ✅ (required + enforce_admins + strict) |
| No existen secretos | ✅ (`secretos` verde; GitGuardian = falso positivo local) |
| No existen conflictos | ✅ (rebase limpio) |
| Staging continúa válido | ✅ (MIG191 idéntica) |
| MIG188 no ejecutada | ✅ |
| MIG191 no aplicada en producción | ✅ |

No se fusionó PR #3 ni se aplicó MIG191/desplegó frontend: queda **verde y listo**, pendiente de
autorización explícita.

**DEPENDENCIAS CERRADAS — INCREMENTO 1 LISTO PARA PRODUCCIÓN**
