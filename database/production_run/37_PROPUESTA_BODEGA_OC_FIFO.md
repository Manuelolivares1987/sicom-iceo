# Propuesta Frente #2 — Bodega OC + FIFO + CECO (mig 37)

**Fecha:** 2026-05-10
**Estado:** Propuesta. NO implementado. Requiere aprobación antes de codear.
**Predecesores:** MIG36 (vistas reconciliación) — APLICADA OK.
**Diagnóstico base:** stock_bodega ↔ inventario_capas **cuadrado al 100%** (40/40, valor $169.692.918). Combustible 3 estanques sin movimientos recientes, varillaje atrasado. 2 mermas auditables en últimos 60d.

---

## 1. RPCs a activar (5 nuevas + 0 reemplazos legacy)

Las RPCs comentadas en `database/schema/55_*.sql` BLOCK K/L/M/N son **versiones antiguas** que mig 56 y 57 REESCRIBEN. La versión definitiva a aplicar es:

| # | RPC | Origen | Reemplaza/extiende | Propósito |
|---|-----|--------|--------------------|-----------|
| 1 | `rpc_registrar_recepcion_bodega(...)` | **mig 56 BLOCK E** | mig 55 BLOCK K (no aplicar) | Recibe contra OC, crea capa FIFO **y** invoca `rpc_registrar_entrada_inventario` legacy en la misma transacción |
| 2 | `rpc_registrar_salida_bodega(...)` | **mig 56 BLOCK F** | mig 55 BLOCK L (no aplicar) | Salida con CECO obligatorio, consume capas FIFO y actualiza stock_bodega legacy |
| 3 | `rpc_registrar_ingreso_combustible_valorizado(...)` | **mig 57 BLOCK G** | mig 55 BLOCK M (no aplicar) | Ingreso combustible con CPP móvil, alimenta `combustible_kardex_valorizado` |
| 4 | `rpc_registrar_salida_combustible_valorizada(...)` | **mig 57 BLOCK H** | mig 55 BLOCK N (no aplicar) | Salida combustible valorizada (venta/equipo propio/despacho) |
| 5 | `rpc_registrar_despacho_combustible_sellos(...)` | **mig 55 BLOCK O** | sin reemplazo | Despacho a cliente con 3 sellos (programado → en_ruta → entregado) |

**Adicional necesario antes:** una RPC simple `rpc_crear_orden_compra(...)` que el comentario mig 55 BLOCK D no tiene escrita. Hay que diseñarla nueva, sencilla:

| # | RPC | Origen | Propósito |
|---|-----|--------|-----------|
| 6 | `rpc_crear_orden_compra(...)` | **nueva** | Crea OC + items, valida proveedor/CECO, deja estado 'abierta'. Sin afectar stock |

**Funciones helper ya activas en prod** (no requieren acción):
- `fn_generar_folio_recepcion_bodega`, `fn_generar_folio_salida_bodega`, `fn_generar_folio_ingreso_combustible`, `fn_generar_folio_salida_combustible`, `fn_generar_folio_despacho_combustible` (mig 55 BLOCK J, aplicadas en `04_apply_mig55_produccion.sql`)
- `fn_consumir_inventario_fifo` (mig 56 BLOCK D, aplicada en `07_apply_mig56_fifo_produccion.sql`)
- `rpc_registrar_stock_inicial_combustible` (mig 57 BLOCK F, aplicada en `10_apply_mig57_combustible_cpp_produccion.sql`)

**Las RPCs legacy se MANTIENEN sin cambios**:
- `rpc_registrar_entrada_inventario`, `rpc_registrar_salida_inventario`, `rpc_registrar_ajuste_inventario`, `rpc_transferir_inventario`, `rpc_aprobar_conteo_inventario` (siguen siendo invocadas por la UI actual y por las RPCs nuevas internamente).

---

## 2. Tablas que se tocarán

### Lectura
- `ordenes_compra`, `ordenes_compra_items` (validar pendientes, precios)
- `proveedores`, `centros_costo` (validar referencias)
- `productos`, `bodegas` (validar existencia)
- `inventario_capas` (FOR UPDATE en consumo FIFO)
- `combustible_estanques` (FOR UPDATE en ingreso/salida combustible)
- `usuarios_perfil` (rol via `fn_user_rol()`)

### Escritura (por RPC)
| RPC | Tablas |
|-----|--------|
| `rpc_crear_orden_compra` | `ordenes_compra` (INSERT), `ordenes_compra_items` (INSERT) |
| `rpc_registrar_recepcion_bodega` | `recepciones_bodega` (INSERT), `recepciones_bodega_items` (INSERT), `inventario_capas` (INSERT), `ordenes_compra_items` (UPDATE), `ordenes_compra` (UPDATE estado), + invoca `rpc_registrar_entrada_inventario` (escribe `stock_bodega`, `movimientos_inventario`, `kardex_inventario`) |
| `rpc_registrar_salida_bodega` | `salidas_bodega` (INSERT), `salidas_bodega_items` (INSERT con costo_real FIFO), `inventario_capas` (UPDATE cantidad_disponible / estado), `inventario_consumos_capas` (INSERT), + invoca `rpc_registrar_salida_inventario` (escribe `stock_bodega`, `movimientos_inventario`, `kardex_inventario`) |
| `rpc_registrar_ingreso_combustible_valorizado` | `ingresos_combustible` (INSERT), `combustible_kardex_valorizado` (INSERT), `combustible_estanques` (UPDATE stock + cpp + valor) |
| `rpc_registrar_salida_combustible_valorizada` | `salidas_combustible` (INSERT), `combustible_kardex_valorizado` (INSERT), `combustible_estanques` (UPDATE stock + valor) |
| `rpc_registrar_despacho_combustible_sellos` | `despachos_combustible` (INSERT + transiciones de estado), + invoca `rpc_registrar_salida_combustible_valorizada` |

### NO se tocan (importante)
- `inventario_capas` existentes (40 capas iniciales) → solo se consumen por salidas, NO se re-siembran ni se recalculan.
- `stock_bodega` actuales → solo cambian vía las RPCs legacy invocadas internamente. No hay UPDATE directo desde las RPCs nuevas.
- `combustible_kardex_valorizado` histórico → solo INSERT, nunca UPDATE/DELETE.

---

## 3. Riesgos

### Técnicos

| Riesgo | Probabilidad | Impacto | Mitigación |
|--------|--------------|---------|------------|
| **Doble descuento de stock** | Media | Crítico (corrompe inventario) | Tests de integración con assert: cada salida disminuye `stock_bodega.cantidad` y `inventario_capas.cantidad_disponible` exactamente una vez |
| **RPCs nuevas conviven con UI legacy** | Alta | Medio | Convivencia diseñada (mig 56 invoca legacy internamente). La UI actual sigue usando RPCs legacy directas; las nuevas RPCs son adicionales |
| **FIFO insuficiente al consumir** | Media | Alto | `fn_consumir_inventario_fifo` ya RAISE si no hay stock. Override admin pendiente de diseñar |
| **Costo de OC vs costo real diferentes** | Baja | Bajo | Override admin con justificación ≥ 10 caracteres, queda en observación con prefijo `OVERRIDE ADMIN:` |
| **Combustible: CPP móvil con stock inicial = 0** | Alta (EST-600 hoy) | Medio | Bloquear ingreso si estanque no tiene stock_inicial registrado; usar `rpc_registrar_stock_inicial_combustible` primero |
| **Re-aplicación de la mig** | Media | Alto si no es idempotente | `CREATE OR REPLACE FUNCTION` para todas; verificar idempotencia de cualquier seed |
| **RLS bloquea UI** | Baja | Medio | Las RPCs son SECURITY DEFINER, no dependen de RLS del caller. Vistas ya tienen GRANT SELECT a authenticated |

### Operacionales

| Riesgo | Mitigación |
|--------|------------|
| Equipo opera con dos flujos paralelos | Comunicar y entrenar: nuevas entradas/salidas pasan por OC/CECO; cosas viejas siguen igual hasta cerrarse |
| Bodeguero no sabe cuándo usar nuevo flujo | UI diferenciada: botón "Nueva entrada/salida con OC" vs "Ajuste manual" |
| Productos sin OC histórica no encajan | Permitir recepción sin OC (`p_orden_compra_id NULL`) en RPC; documentar como excepción |

---

## 4. Prechecks obligatorios (antes de aplicar mig 37)

Bloque `DO $$ ... RAISE EXCEPTION 'STOP - ...'` al inicio de la migración, falla rápido si alguno no se cumple:

1. **Mig 55 base aplicada:** `proveedores`, `centros_costo`, `ordenes_compra`, `ordenes_compra_items`, `recepciones_bodega`, `recepciones_bodega_items`, `salidas_bodega`, `salidas_bodega_items`, `ingresos_combustible`, `salidas_combustible`, `despachos_combustible` existen.
2. **Mig 56 base aplicada:** `inventario_capas`, `inventario_consumos_capas`, `fn_consumir_inventario_fifo` existen.
3. **Mig 57 base aplicada:** `combustible_stock_inicial`, `combustible_kardex_valorizado`, columnas `costo_promedio_lt` y `valor_total_stock` en `combustible_estanques`.
4. **Funciones de folio activas:** las 5 `fn_generar_folio_*` existen.
5. **`fn_user_rol()` activa:** retorna texto, no NULL.
6. **Stock legacy ↔ FIFO cuadrado:** `(SELECT COUNT(*) FROM v_bodega_reconciliacion_stock_fifo WHERE estado_reconciliacion <> 'cuadrado') = 0`. Si no, abortar — no se activa transaccional sobre inventario divergente.
7. **No hay capas con cantidad_disponible negativa.**
8. **No hay productos con stock > 0 y costo 0** (Q5 del diag).
9. **Usuario que ejecuta = administrador.**

Si cualquiera falla → `RAISE EXCEPTION 'STOP - ...'` con mensaje específico. No se aplica nada.

---

## 5. Rollback lógico

La migración es **aditiva** (no DROPea nada, no altera datos). Rollback:

```sql
-- ROLLBACK MIG37
DROP FUNCTION IF EXISTS rpc_crear_orden_compra CASCADE;
DROP FUNCTION IF EXISTS rpc_registrar_recepcion_bodega CASCADE;
DROP FUNCTION IF EXISTS rpc_registrar_salida_bodega CASCADE;
DROP FUNCTION IF EXISTS rpc_registrar_ingreso_combustible_valorizado CASCADE;
DROP FUNCTION IF EXISTS rpc_registrar_salida_combustible_valorizada CASCADE;
DROP FUNCTION IF EXISTS rpc_registrar_despacho_combustible_sellos CASCADE;
-- Datos creados durante la operación quedan:
-- recepciones_bodega, salidas_bodega, capas, consumos_capas no se eliminan.
-- Si necesitas borrar transaccional ya generado, hay que script aparte
-- (NO incluido en rollback automático por seguridad).
```

**Rollback DE DATOS** (separado, manual, solo si urgencia):
```sql
-- ATENCION: solo si la mig se aplicó pero se decide retroceder y no hay
-- operación real ejecutada todavía.
DELETE FROM inventario_consumos_capas WHERE created_at >= '<fecha_mig37>';
UPDATE inventario_capas SET cantidad_disponible = cantidad_inicial, estado = 'disponible'
 WHERE updated_at >= '<fecha_mig37>';
DELETE FROM salidas_bodega_items WHERE created_at >= '<fecha_mig37>';
DELETE FROM salidas_bodega WHERE created_at >= '<fecha_mig37>';
DELETE FROM recepciones_bodega_items WHERE created_at >= '<fecha_mig37>';
DELETE FROM recepciones_bodega WHERE created_at >= '<fecha_mig37>';
-- + revertir stock_bodega y movimientos_inventario asociados — requiere
-- query manual con doc por OT/movimiento. No automatizable seguro.
```

---

## 6. Validaciones SQL (post-aplicación)

Al final de la mig 37, bloque `DO $$ ... RAISE NOTICE`:

```sql
-- 6.1 RPCs presentes
SELECT 'rpc_crear_orden_compra', COUNT(*) FROM pg_proc WHERE proname='rpc_crear_orden_compra';
SELECT 'rpc_registrar_recepcion_bodega', COUNT(*) FROM pg_proc WHERE proname='rpc_registrar_recepcion_bodega';
-- ...etc (6 RPCs total)

-- 6.2 Reconciliación sigue cuadrada después
SELECT
    estado_reconciliacion,
    COUNT(*)
FROM v_bodega_reconciliacion_stock_fifo
GROUP BY estado_reconciliacion;
-- Esperado: cuadrado=40, resto=0

-- 6.3 No hay capas negativas
SELECT COUNT(*) FROM inventario_capas
 WHERE cantidad_disponible < 0;
-- Esperado: 0

-- 6.4 RPCs legacy intactas (no se hayan dropeado por error)
SELECT 'rpc_registrar_entrada_inventario', COUNT(*) FROM pg_proc WHERE proname='rpc_registrar_entrada_inventario';
SELECT 'rpc_registrar_salida_inventario',  COUNT(*) FROM pg_proc WHERE proname='rpc_registrar_salida_inventario';
-- Esperado: 1 cada una
```

**Validación operativa con datos reales** (post-deploy, smoke test manual):

1. Crear OC piloto con 1 item, cantidad 1, precio conocido.
2. Recepcionar OC piloto completa.
3. Verificar: nueva capa creada, OC item completo, stock_bodega +1, kardex +1 movimiento entrada, reconciliación sigue cuadrada.
4. Hacer salida del producto a un CECO, cantidad 1.
5. Verificar: capa creada en paso 2 ahora con cantidad_disponible = 0 y estado 'agotada', stock_bodega -1, consumo_capa registrado con costo igual a precio OC, reconciliación sigue cuadrada.
6. Rollback piloto (DELETE manual) o dejar para auditoría.

---

## 7. Plan de implementación por etapas

### Etapa 2A — Diseño y revisión (ESTE DOCUMENTO)
- ✅ Inventario de 6 RPCs a activar
- ✅ Mapeo de tablas afectadas
- ✅ Riesgos y mitigaciones
- ⏳ **Aprobación del usuario** para pasar a 2B

### Etapa 2B — Codificación de mig 37 (`database/production_run/37_bodega_oc_recepcion_fifo_seguro.sql`)
- 1 archivo idempotente
- Sección 0: prechecks (los 9 listados arriba)
- Sección 1-6: las 6 RPCs con `CREATE OR REPLACE FUNCTION`
- Sección 7: GRANTs apropiados a authenticated
- Sección 8: validaciones post (las 4 queries del punto 6)
- Sección 9: log a `operacion_migraciones_log`
- Sección comentada al final: rollback manual

### Etapa 2C — Aplicar en staging primero
- Ejecutar mig 37 contra **staging** (si existe), correr smoke test del punto 6 con datos reales.
- Si OK → aplicar en producción.
- Si falla → corregir y volver a 2B.

### Etapa 2D — UI mínima viable
Una vez RPCs en prod, agregar:
1. `frontend/src/app/dashboard/abastecimiento/oc/page.tsx` — listado de OC con filtros y estado.
2. `frontend/src/app/dashboard/abastecimiento/oc/nueva/page.tsx` — crear OC.
3. `frontend/src/app/dashboard/abastecimiento/oc/[id]/page.tsx` — detalle OC + botón "Recepcionar" cuando estado abierta/parcial.
4. Extender `dashboard/inventario/salida/page.tsx` para opcionalmente usar el flujo nuevo con CECO obligatorio.
5. Servicios: `frontend/src/lib/services/bodega-oc.ts`, hooks `use-bodega-oc.ts`.
6. Validaciones Zod ya existen en `frontend/src/validations/bodega.ts` — sólo cablear.

### Etapa 2E — Despacho combustible con sellos (UI)
1. `frontend/src/app/dashboard/abastecimiento/despachos/nuevo/page.tsx` — programar despacho.
2. Pantalla operador para marcar "en ruta" → "entregado" con foto del sello.

### Etapa 2F — Cierre y deprecación
Cuando el flujo OC esté siendo usado por >50% del movimiento real:
1. Marcar los puntos de entrada legacy (entrada manual sin OC) como "modo emergencia" con confirmación adicional.
2. Auditar cada 2 semanas: % de movimientos por nuevo flujo.
3. Eventualmente: forzar OC para todas las entradas (eliminar fallback "recepción libre").

---

## 8. Qué queda FUERA de mig 37

Explícitamente **no se hará** en esta migración:

- **Rol "bodeguero" al enum `rol_usuario_enum`.** Manuel marcó en memoria "no tocar el enum global". Las RPCs validan rol con el conjunto actual (`administrador`, `bodeguero`, `jefe_mantenimiento`, `supervisor`, `subgerente_operaciones`). Si `bodeguero` no existe en el enum, hay que ajustar la validación a roles existentes (`operador_abastecimiento`?). **Pregunta abierta para resolver antes de 2B.**
- **Sembrado de capas iniciales:** ya están sembradas. No tocar las 40 existentes.
- **Migración del histórico legacy a OC:** no se inventan OCs retroactivas. El histórico queda como está.
- **Reescritura de la UI completa de inventario:** la UI legacy sigue funcionando. Solo se agrega lo nuevo.
- **Conexión de `panel-materiales.tsx` (mig 48) al nuevo flujo:** despacho a OT sigue por `fn_despachar_material_ot`. Una etapa posterior decide si se unifica.
- **Reportes/dashboards finanzas:** las 4 vistas de mig 56 BLOCK G y las 3 de mig 57 BLOCK J pueden activarse aparte. **No entran en mig 37 base.** Sugerencia: mig 38 separada.
- **Auditoría de overrides admin:** la observación con prefijo `OVERRIDE ADMIN:` ya queda registrada por las RPCs. Un dashboard de auditoría se hace después.
- **Anulaciones (`rpc_anular_recepcion_oc`, `rpc_anular_salida_bodega`):** no están propuestas en mig 55/56. Si las quieres, son trabajo separado — diseño complejo (revertir capas consumidas requiere lógica especial).

---

## 9. Decisiones abiertas para resolver antes de codear

1. **Rol bodeguero:** ¿qué rol del enum actual hace ese trabajo hoy? (Probable: `operador_abastecimiento`. Confirmar.)
2. **Override admin combustible:** ¿permitir sobrecantidad/precio distinto también en combustible o solo en repuestos? (Sugerencia: igual que repuestos, con justificación.)
3. **Smoke test en staging:** ¿existe staging accesible o se aplica directo en prod con backup previo?
4. **Despachos combustible con sellos:** ¿alcance del piloto inicial — solo a clientes externos o también equipos propios?
5. **Vistas de finanzas (mig 56 BLOCK G y mig 57 BLOCK J):** ¿se incluyen en mig 37 o se difieren a mig 38?

---

## Resumen ejecutivo (1 párrafo)

Mig 37 activa 6 RPCs transaccionales que faltaban del módulo Bodega (OC, recepción FIFO-aware, salida con CECO + consumo FIFO, ingreso/salida combustible con CPP móvil, despacho con sellos). La convivencia con el sistema legacy está diseñada: las RPCs nuevas invocan internamente `rpc_registrar_entrada_inventario` / `rpc_registrar_salida_inventario` para mantener `stock_bodega` sincronizado con las capas FIFO — sin doble descuento. Riesgo controlado por 9 prechecks que abortan si el inventario no está cuadrado o si falta alguna dependencia. Rollback aditivo (DROP FUNCTION). No se toca el stock actual, no se rehacen capas, no se reescribe la UI existente. UI nueva (OC + recepción + salida CECO) viene en etapa 2D después de validar RPCs en staging.

---

**Próximo paso pendiente de tu aprobación:** Etapa 2B — codificar `database/production_run/37_bodega_oc_recepcion_fifo_seguro.sql`. No avanzar hasta que resuelvas las 5 decisiones abiertas del punto 9.
