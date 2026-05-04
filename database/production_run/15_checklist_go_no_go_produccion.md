# 15 — Checklist GO / NO GO (Producción)

> **Cuándo usar:** después de ejecutar 02-13 en orden.

---

## Bloque A — Backup y prechecks

- [ ] Backup confirmado (paso 01) — archivo `.sql.gz` existe localmente
- [ ] Prechecks (paso 02): `DIAGNOSTICO = "PRECHECKS OK"` ó "WARNING" con mitigación documentada
- [ ] Bitácora (paso 03): tabla `operacion_migraciones_log` creada y registro `PROD_INICIO` insertado

## Bloque B — Mig 55

- [ ] `04_apply_mig55_produccion.sql` ejecutado — log `PROD_MIG55_END` resultado `ok`
- [ ] `05_validate_mig55_produccion.sql` resultado: `OK MIG55`
- [ ] 11 tablas nuevas creadas
- [ ] 5 funciones de folio funcionan

## Bloque C — Datos maestros

- [ ] `06_seed_datos_maestros_produccion.sql` ejecutado
- [ ] Proveedores combustible activos ≥ 3 (ENEX, ESMAX, COPEC)
- [ ] CECO activos ≥ 8

## Bloque D — Mig 56 FIFO

- [ ] `07_apply_mig56_fifo_produccion.sql` ejecutado — log `PROD_MIG56_END` ok
- [ ] `08_validate_mig56_fifo_produccion.sql` resultado: `OK MIG56` (o "PENDIENTE SEMBRAR CAPAS" — aceptable previo a 09)
- [ ] `inventario_capas` y `inventario_consumos_capas` existen
- [ ] `fn_consumir_inventario_fifo` existe
- [ ] `v_stock_valorizado_fifo` existe

## Bloque E — Capas iniciales (Finanzas)

- [ ] `09_seed_capas_iniciales_fifo_produccion.sql`:
  - [ ] Productos sin costo identificados y resueltos (Finanzas)
  - [ ] INSERT ejecutado (descomentado)
  - [ ] Reconciliación: `productos_desincronizados = 0` (excluyendo los sin costo)
  - [ ] Log `PROD_FIFO_SEED_CAPAS` ok

## Bloque F — Mig 57 Combustible CPP

- [ ] `10_apply_mig57_combustible_cpp_produccion.sql` ejecutado — log `PROD_MIG57_END` ok
- [ ] `11_validate_mig57_combustible_cpp_produccion.sql` resultado: `OK MIG57` (o "PENDIENTE STOCK INICIAL")
- [ ] `combustible_stock_inicial` y `combustible_kardex_valorizado` existen
- [ ] `combustible_estanques` extendida con `costo_promedio_lt`, `valor_total_stock`
- [ ] RPC `rpc_registrar_stock_inicial_combustible` existe
- [ ] Vista `v_combustible_stock_valorizado_actual` existe

## Bloque G — Stock inicial combustible (Finanzas)

- [ ] `12_seed_stock_inicial_combustible_produccion.sql`:
  - [ ] Estanques pendientes identificados
  - [ ] Para cada estanque con stock > 0, `rpc_registrar_stock_inicial_combustible` ejecutado
  - [ ] Vista `v_combustible_stock_valorizado_actual`: cada estanque con costo > 0 y valor coherente
  - [ ] Log `PROD_CPP_STOCK_INICIAL` ok

## Bloque H — Roles y dashboards

- [ ] `13_validate_roles_dashboards_produccion.sql` resultado: `OK ROLES`
- [ ] Usuarios críticos activos: admin, bodegacoq, planificador

## Bloque I — Mig 52 Block A (opcional)

- [ ] **NO ejecutado** (default — recomendado)
- [ ] **O** ejecutado y frontend ya ajustado (`rpc_ficha_activo_publica`)

## Bloque J — Frontend

- [ ] `npm run typecheck` ✅
- [ ] `npm run build` ✅
- [ ] Dashboard funciona en producción (admin loguea correctamente)
- [ ] Sin errores en consola del navegador

---

## Errores detectados

| Paso | Error | Resolución | Estado |
|---|---|---|---|
| | | | |
| | | | |

---

## Decisión final

**GO ☐  /  NO GO ☐**

**Firma responsable:** ________________________
**Fecha y hora:** ________________________
**Observaciones:** ________________________

---

## Bitácora completa de la ventana

| Fecha/hora | Paso | Resultado | Observación |
|---|---|---|---|
| | 01 backup | OK / FALLA | |
| | 02 prechecks | OK / FALLA | |
| | 03 bitácora | OK / FALLA | |
| | 04 mig55 | OK / FALLA | |
| | 05 validate mig55 | OK / FALLA | |
| | 06 seed maestros | OK / FALLA | |
| | 07 mig56 | OK / FALLA | |
| | 08 validate mig56 | OK / FALLA | |
| | 09 seed capas FIFO | OK / FALLA | |
| | 10 mig57 | OK / FALLA | |
| | 11 validate mig57 | OK / FALLA | |
| | 12 stock inicial comb | OK / FALLA | |
| | 13 roles | OK / FALLA | |
| | 14 mig52 Block A | NO EJECUTADO / OK | |
| | npm typecheck | OK / FALLA | |
| | npm build | OK / FALLA | |

→ Guardar también la bitácora SQL: `SELECT * FROM operacion_migraciones_log ORDER BY fecha_inicio DESC;`
