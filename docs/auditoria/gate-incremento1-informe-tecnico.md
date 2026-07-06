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

## Veredicto

Todos los criterios del gate se cumplen, ejecutados y verificados en PostgreSQL 17 con backup
real (suite 34/34) y frontend compilando (typecheck/lint/build en verde). El cierre de OT y el
informe de recobro permanecen intactos. No se aplicó nada en producción. MIG188 no ejecutada.

**GO — INCREMENTO 1 VALIDADO — LISTO PARA DESPLIEGUE**
