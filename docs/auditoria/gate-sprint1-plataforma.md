# Gate Sprint 1 — Plataforma operable, recuperable y desplegable

**Fecha:** 2026-07-05 · **Alcance:** 7 frentes en 3 entregas (A→B→C). **No** re-audita Fase 0. **MIG188 desautorizada.**

## Veredicto: **NO-GO**

Se completó y **probó** el núcleo de la **Entrega A** (registro de migraciones con hash + CI + primeras pruebas + lógica de retención de backups). Las Entregas **B** (QR, idempotencia, observabilidad) y **C** (RLS núcleo) **no** están construidas/probadas. Por la regla "no declarar GO sin ejecución", el sprint es **NO-GO** hasta cerrar los 11 criterios.

---

## 1. Veredicto por frente

| # | Frente | Estado | Ejecutado/probado |
|---|---|---|---|
| 4 | **Registro de migraciones + ejecutor** | ✅ **HECHO** | `190_schema_migrations.sql` + `db-migrate.mjs`; 7/7 pruebas de control (`test-db-migrate.mjs`) en PG17 local |
| 5 | **CI obligatorio** | ✅ **HECHO** (workflow + suite inicial) | `.github/workflows/ci.yml`; 8/8 vitest + typecheck 0 + build 99/99 + destructivas + ejecutor. Falta activar branch protection como *required check*. |
| 1 | **Backups automáticos + restauración** | ⚠️ **PARCIAL** | Tabla `backup_ejecuciones` creada; `backup-pg-dump.ps1` con **retención robusta "más reciente por período"** (probada: 72→21 con 12 meses). **Falta:** cifrado+logging en el script, cron programado, **almacenamiento externo**, validador de restauración ejecutado, alerta por fallo. |
| 3 | **Protección QR** | ⛔ **PENDIENTE** (Entrega B) | tokens/hash/expiración/rate-limit/límites de payload/idempotency no implementados |
| 8 | **Idempotencia** | ⛔ **PENDIENTE** (Entrega B) | idempotency key en salidas/traspaso/OT/cierre/GPS/QR no implementada |
| 7 | **Observabilidad y alertas** | ⛔ **PENDIENTE** (Entrega B) | modelo de eventos + 11 alertas + severidades no implementados |
| 6 | **RLS tablas núcleo** | ⛔ **PENDIENTE** (Entrega C) | `no_conformidades`, `estado_diario_flota`, etc. sin RLS |

## 2. Cambios realizados (esta iteración)

| Archivo | Propósito |
|---|---|
| `database/production_run/190_schema_migrations.sql` | tablas `schema_migrations` + `backup_ejecuciones` |
| `database/scripts/db-migrate.mjs` | ejecutor: registro, bloqueo de re-ejecución y drift de hash, dry-run, status, detección de dobles/saltos, integración destructivo |
| `database/scripts/test-db-migrate.mjs` | 7 pruebas de control del ejecutor (para CI) |
| `.github/workflows/ci.yml` | pipeline: install/lint/typecheck/test/build/secretos/destructivo/ejecutor |
| `frontend/src/lib/reporte-contrato.ts` + tests | contrato RPC↔frontend testeable |
| `frontend/src/lib/__tests__/permisos.test.ts` | pruebas del helper de permisos (defaults, fail-closed) |
| `frontend/vitest.config.mts`, script `test` | infraestructura de pruebas |
| `database/scripts/backup-pg-dump.ps1` | retención "más reciente por período" (7/5/12) |
| `docs/operacion/cierre-fase0.md`, `mig187-observacion.md` | cierre operativo Fase 0 + observación MIG187 |

## 3. Migraciones

| Versión | Estado | Notas |
|---|---|---|
| 190 | **probada en preprod** (PG17 local), **no aplicada a prod** | crea el registro; aplicar con `db-migrate.mjs --apply` |
| 188 | **desautorizada** | `v_autorizado=false`; fuera de este sprint |

## 4. Pruebas ejecutadas

- **Ejecutor de migraciones (7/7):** aplica+registra; omite re-ejecución (mismo hash); **bloquea drift de hash**; bloquea DELETE sin WHERE; bloquea GRANT a anon; permite destructivo anotado; dry-run no aplica.
- **Frontend (8/8 vitest):** contrato del reporte (4) + helper de permisos (4, incl. fail-closed de flota/approve).
- **Typecheck:** exit 0. **Build:** 99/99 páginas. **Destructivo:** 228 migraciones sin operaciones desprotegidas.
- **Retención de backups:** 72 dumps → 21 conservados, 12 meses representados (probado con archivos ficticios).

## 5. Métricas antes/después

| Métrica | Antes | Después |
|---|---|---|
| Control de re-ejecución de migraciones | ninguno (ejecutor aplica cualquier archivo) | **registro + bloqueo de re-ejecución y drift** |
| Pruebas automatizadas | 0 | **15** (8 frontend + 7 ejecutor) |
| CI | inexistente | **workflow con 3 jobs bloqueantes** |
| Retención de backups | anclada a lunes/día-1 (frágil) | **más reciente por período (robusta)** |

## 6. Backup y restauración

Retención corregida y probada. **Pendiente para GO:** ejecutar un backup automático real, copia externa confirmada, restauración probada end-to-end, alerta simulada por fallo. (El backup manual pre-Fase 0 fue cifrado AES-256 y verificado — ver `gate-final-fase-0.md`.)

## 7. Estado de RLS (reconciliado con prod 2026-07-05, solo lectura)

- **`estado_diario_flota`: CERRADA** ✅ — MIG185 la dejó con `relrowsecurity=true`, policy `pol_edf_select_authenticated` (SELECT authenticated), **anon sin ningún privilegio**; las escrituras de authenticated quedan bloqueadas por RLS (sin policy de escritura → default-deny; solo escriben las funciones SECURITY DEFINER). (El informe previo la listaba por error como pendiente.) Cleanup menor futuro: revocar los grants de INSERT/UPDATE/DELETE de authenticated (ya inertes por RLS).
- **Pendientes reales (Entrega C)** — verificado `rls=false, 0 policies, anon puede INSERT+SELECT` en: `no_conformidades`, `verificaciones_disponibilidad`, `registro_jornada_conductor`, `normativa_documentos`, `respel_empresas_receptoras`, `respel_movimientos`, `respel_tipos`, `suspel_bodegas`, `suspel_productos`, y tablas de inventario/costos expuestas al portal.

## 8. Estado de QR

`rpc_guardar_checklist_publico` y `rpc_checklist_cliente_guardar` siguen en **allowlist pública sin límites** (Fase 0 cerró el anon del resto). Protección (token/hash/expiración/rate-limit/límites/idempotency) **pendiente** (Entrega B).

## 9. Estado de idempotencia

**No** implementada. Reintentos aún pueden duplicar combustible/OTs/checklists/cierres (Entrega B).

## 10. Estado de observabilidad

**No** implementada. Sin modelo de eventos ni alertas (Entrega B).

## 11. Bloqueadores

Ninguno técnico irresoluble. El NO-GO se debe a **alcance no ejecutado** (Entregas B y C, y completar backup automation de A). No hay dependencias externas faltantes: PG17 instalado, preprod operativa, CI local validado.

## 12. Instrucciones de despliegue (de lo listo — Entrega A núcleo)

Estos artefactos son **aditivos y seguros** (no tocan 185/186/187/189):

1. **Backup previo** (procedimiento `gate-final-fase-0.md §10`).
2. Aplicar el registro con el propio ejecutor:
   `node database/scripts/db-migrate.mjs --apply database/production_run/190_schema_migrations.sql`
   (crea `schema_migrations` + `backup_ejecuciones`; se auto-registra).
3. Postvalidación: `node database/scripts/db-migrate.mjs --status` → registro presente, 190 aplicada.
4. **CI:** activar el workflow y marcar los 3 jobs como *required checks* en la protección de rama `main`.
5. Frontend: sin cambios de runtime (solo pruebas/infra); no requiere redeploy.

**No** desplegar Entregas B/C hasta construirlas y probarlas en preprod (mismo rigor que Fase 0: preprod PG17 + backup + postvalidación).

---

**Criterios GO restantes (cerrar antes de declarar GO):** backup automático ejecutado + copia externa + restauración probada + alerta; QR con límites y rate-limit; operaciones críticas idempotentes; RLS en tablas núcleo; observabilidad con alertas. MIG188 sigue desautorizada; sin secretos en el repo (verificado).
