# 12 — GO / NO GO CHECKLIST (Staging)

> **Cuándo usar:** después de ejecutar los scripts 01-11 en orden.
> **Quién decide:** Administrador (Manuel), con Finanzas para costos.

---

## Checklist completo

### Bloque A — Pre-aplicación

- [ ] `01_prechecks_safe.sql` ejecutado
  - [ ] Conectado a STAGING (no producción)
  - [ ] 25 tablas legacy presentes
  - [ ] 0 tablas nuevas pre-existentes
  - [ ] 7 funciones base presentes (`fn_user_rol`, etc.)

- [ ] `02_seed_datos_maestros.sql` ejecutado (si tablas ya existen, en orden 03→02)
  - [ ] ≥4 proveedores combustible (ENEX, ESMAX, COPEC, PETROBRAS)
  - [ ] ≥1 proveedor repuestos
  - [ ] ≥8 CECOs activos

### Bloque B — Mig 55 (Bodega + Combustible base)

- [ ] `03_apply_mig55_bodega_combustible_base.sql` ejecutado
  - [ ] 11 tablas nuevas creadas
  - [ ] 5 funciones de folio funcionando
  - [ ] Sin errores de FK

- [ ] `04_validate_mig55.sql` ejecutado
  - [ ] DO block "TEST OK" + "TEST COMPLETADO"
  - [ ] UNIQUE proveedor+doc en recepciones presente
  - [ ] CHECKs de despacho con sellos presentes

### Bloque C — Mig 56 (FIFO repuestos)

- [ ] `05_apply_mig56_fifo.sql` ejecutado
  - [ ] `inventario_capas` creada
  - [ ] `inventario_consumos_capas` creada
  - [ ] `ot_materiales_planeados` extendida con 5 columnas
  - [ ] `fn_consumir_inventario_fifo` funcional
  - [ ] Vista `v_stock_valorizado_fifo` creada

- [ ] `06_seed_capas_iniciales_fifo.sql`
  - [ ] Pre-checks revisados (productos sin costo, cantidades negativas)
  - [ ] Costos validados con Finanzas
  - [ ] INSERT ejecutado
  - [ ] Reconciliación: 0 productos desincronizados

- [ ] `07_validate_fifo.sql` ejecutado
  - [ ] TEST 1 OK ($10.000)
  - [ ] TEST 2 OK ($14.000)
  - [ ] TEST 3 OK (multi-capa $24.000)
  - [ ] TEST 4 OK (stock insuficiente)
  - [ ] Reconciliación post-test: 0

### Bloque D — Mig 57 (Combustible CPP móvil)

- [ ] `08_apply_mig57_combustible_cpp.sql` ejecutado
  - [ ] `combustible_stock_inicial` creada
  - [ ] `combustible_kardex_valorizado` creada
  - [ ] `combustible_estanques` extendida con `costo_promedio_lt`, `valor_total_stock`
  - [ ] `ingresos_combustible` y `salidas_combustible` extendidas con campos CPP
  - [ ] RPC `rpc_registrar_stock_inicial_combustible` funcional

- [ ] `09_seed_stock_inicial_combustible.sql`
  - [ ] Lista de estanques validada con Finanzas
  - [ ] Para cada estanque con stock > 0: `rpc_registrar_stock_inicial_combustible` ejecutada
  - [ ] Vista `v_combustible_stock_valorizado_actual` muestra valores correctos

- [ ] `10_validate_combustible_cpp.sql` ejecutado
  - [ ] TEST 1 OK (stock 1.000 lt @ $900)
  - [ ] TEST 2 OK (CPP $966,67 después de ingreso)
  - [ ] TEST 3 OK (salida 500 lt @ CPP)
  - [ ] Reconciliación estanque vs último kardex: pares coinciden

### Bloque E — Roles y dashboards

- [ ] `11_validate_roles_dashboards.sql` ejecutado
  - [ ] administrador, bodeguero, planificador activos
  - [ ] Faenas asignadas correctamente
  - [ ] Sin roles fuera del enum

- [ ] Frontend conectado a staging:
  - [ ] `.env.local` apunta a staging
  - [ ] `npm run dev` levanta sin errores
  - [ ] Login con cada rol redirige al dashboard correspondiente
  - [ ] AdminDashboard muestra KPIs sistema
  - [ ] BodegueroDashboard muestra stock + alertas
  - [ ] MantenimientoDashboard muestra OTs

---

## Criterios GO

✅ **Aprobar paso a producción si:**

- Todo el checklist anterior ✅
- Sin errores en logs de Supabase
- Reconciliaciones FIFO + combustible: 0 desincronizaciones
- Tests 1-20 (de los documentos maestros) pasaron
- Build frontend limpio
- Aprobación de Finanzas sobre costos sembrados

→ **Proceder con `PLAN_PASO_PRODUCCION_CONTROLADO.md`**.

---

## Criterios NO GO

🛑 **Detener y NO ir a producción si:**

- Cualquier checkbox del checklist queda sin marcar.
- Reconciliación FIFO devuelve > 0 filas.
- Reconciliación combustible (estanque vs kardex) no coincide.
- Algún test falla con "TEST X FALLO".
- Build frontend rompe.
- Finanzas no validó costos.
- Hay productos con cantidad > 0 y `costo_promedio` NULL/0 sin justificación.
- Estanques con stock > 0 sin `combustible_stock_inicial` activo.
- Errores de FK / constraint que requieren corrección.

→ **Documentar bloqueo, corregir en staging, reintentar checklist completo.**

---

## Bitácora de ejecución

| Fecha | Script | Resultado | Observaciones | Responsable |
|---|---|---|---|---|
| 2026-05-XX | `01_prechecks_safe.sql` | OK / FALLA | (anotar) | Manuel |
| 2026-05-XX | `02_seed_datos_maestros.sql` | OK / FALLA | (anotar) | Manuel |
| 2026-05-XX | `03_apply_mig55...` | OK / FALLA | (anotar) | Manuel |
| 2026-05-XX | `04_validate_mig55.sql` | OK / FALLA | (anotar) | Manuel |
| 2026-05-XX | `05_apply_mig56_fifo.sql` | OK / FALLA | (anotar) | Manuel |
| 2026-05-XX | `06_seed_capas_iniciales_fifo.sql` | OK / FALLA | (anotar) | Manuel + Finanzas |
| 2026-05-XX | `07_validate_fifo.sql` | OK / FALLA | (anotar) | Manuel |
| 2026-05-XX | `08_apply_mig57_combustible_cpp.sql` | OK / FALLA | (anotar) | Manuel |
| 2026-05-XX | `09_seed_stock_inicial_combustible.sql` | OK / FALLA | (anotar) | Manuel + Finanzas |
| 2026-05-XX | `10_validate_combustible_cpp.sql` | OK / FALLA | (anotar) | Manuel |
| 2026-05-XX | `11_validate_roles_dashboards.sql` | OK / FALLA | (anotar) | Manuel |

---

## Decisión final

**GO ☐  /  NO GO ☐**

**Firma responsable:** ______________________
**Fecha:** ______________________
**Observaciones:** ______________________
