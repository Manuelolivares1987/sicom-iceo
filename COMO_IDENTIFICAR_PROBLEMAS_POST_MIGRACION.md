# Cómo identificar problemas post-migración

> **Última actualización:** 2026-05-02 — FASE 5.8
> **Audiencia:** administrador + soporte usuarios.

Cuando un usuario reporta que "algo no funciona" después de aplicar mig 55/56/57, esta guía indica cómo aislar la causa rápidamente.

---

## 1. Problemas de estructura

### Síntomas
- Frontend muestra: `relation "tabla_X" does not exist`.
- RPC falla con `function "rpc_X" does not exist`.
- Error: `column "campo_Y" of relation "tabla_X" does not exist`.

### Cómo detectar

```sql
-- ¿Existe la tabla?
SELECT * FROM information_schema.tables
 WHERE table_schema = 'public' AND table_name = 'NOMBRE_TABLA';

-- ¿Existe la columna?
SELECT column_name, data_type FROM information_schema.columns
 WHERE table_name = 'NOMBRE_TABLA' AND column_name = 'NOMBRE_COLUMNA';

-- ¿Existe la función?
SELECT proname, pg_get_function_arguments(oid) AS args
  FROM pg_proc WHERE proname = 'NOMBRE_FUNCION';

-- ¿Existe el tipo enum?
SELECT typname, enum_range(NULL::NOMBRE_ENUM)
  FROM pg_type WHERE typname = 'NOMBRE_ENUM';
```

### Causa probable
- Mig 55/56/57 no aplicada o aplicada parcialmente.
- Verificar `operacion_migraciones_log` cuál fue el último paso ejecutado.

### Resolución
- Re-ejecutar el `0X_apply_*.sql` correspondiente. Es idempotente.

---

## 2. Problemas de permisos / RLS

### Síntomas
- Usuario ve "Permission denied for table X".
- Dashboard vacío para un rol que debería ver datos.
- Botón "Crear OT" no funciona aunque el menú aparezca.

### Cómo detectar

```sql
-- Politicas RLS activas en una tabla
SELECT schemaname, tablename, policyname, cmd, roles, qual, with_check
  FROM pg_policies WHERE schemaname='public' AND tablename='NOMBRE_TABLA';

-- ¿RLS habilitado?
SELECT relname, relrowsecurity FROM pg_class
 WHERE relname='NOMBRE_TABLA';

-- ¿Qué rol tiene el usuario?
SELECT email, rol, activo FROM usuarios_perfil WHERE email='<email-usuario>';

-- Auth users (verificar UUID)
SELECT id, email FROM auth.users WHERE email='<email-usuario>';
```

### Causa probable
- `usuarios_perfil` no tiene fila para ese auth user (perfil no creado).
- `usuarios_perfil.rol` no coincide con la matriz `usePermissions`.
- RLS bloquea el SELECT/INSERT.

### Resolución
- Crear/actualizar perfil:
  ```sql
  UPDATE usuarios_perfil SET rol='supervisor', activo=true WHERE email='...';
  ```
- Verificar el frontend (consola navegador) qué tabla está consultando.

---

## 3. Problemas de stock

### Síntomas
- "Stock insuficiente" cuando aparentemente hay stock.
- "Salida no se puede registrar".
- Costos OT inexplicablemente altos o bajos.

### Cómo detectar

```sql
-- Stock negativo (no debería existir)
SELECT p.codigo, b.codigo AS bodega, sb.cantidad
  FROM stock_bodega sb
  JOIN productos p ON p.id=sb.producto_id
  JOIN bodegas b ON b.id=sb.bodega_id
 WHERE sb.cantidad < 0;

-- Stock_bodega vs capas FIFO
SELECT p.codigo, b.codigo,
       sb.cantidad   AS stock_bodega,
       SUM(ic.cantidad_disponible) AS capas_total,
       sb.cantidad - COALESCE(SUM(ic.cantidad_disponible), 0) AS diferencia
  FROM stock_bodega sb
  JOIN productos p ON p.id=sb.producto_id
  JOIN bodegas b ON b.id=sb.bodega_id
  LEFT JOIN inventario_capas ic
    ON ic.producto_id=sb.producto_id AND ic.bodega_id=sb.bodega_id AND ic.estado='disponible'
 WHERE sb.cantidad > 0
 GROUP BY p.codigo, b.codigo, sb.cantidad
HAVING ABS(sb.cantidad - COALESCE(SUM(ic.cantidad_disponible), 0)) > 0.001;

-- Productos con stock pero sin capa (post mig 56)
SELECT p.codigo, b.codigo, sb.cantidad, sb.costo_promedio
  FROM stock_bodega sb
  JOIN productos p ON p.id=sb.producto_id
  JOIN bodegas b ON b.id=sb.bodega_id
 WHERE sb.cantidad > 0
   AND NOT EXISTS (
       SELECT 1 FROM inventario_capas ic
        WHERE ic.producto_id=sb.producto_id AND ic.bodega_id=sb.bodega_id AND ic.estado='disponible'
   );

-- Costo_promedio NULL o 0
SELECT p.codigo, sb.cantidad, sb.costo_promedio
  FROM stock_bodega sb JOIN productos p ON p.id=sb.producto_id
 WHERE sb.cantidad > 0 AND (sb.costo_promedio IS NULL OR sb.costo_promedio = 0);
```

### Resolución
- **Stock negativo:** investigar último movimiento. Probablemente trigger o RPC con bug. **NO ajustar manualmente.**
- **Producto con stock sin capa:** sembrar capa con `09_seed_capas_iniciales_fifo_produccion.sql` (con costo Finanzas).
- **Desincronización persistente:** `auditoria_eventos` para encontrar quién modificó.

---

## 4. Problemas de combustible

### Síntomas
- "Stock insuficiente en estanque".
- Estanque con `valor_total_stock = 0` pero `stock_teorico_lt > 0`.
- "No autenticado" o "Rol no autorizado" al registrar movimiento.

### Cómo detectar

```sql
-- Estanques con stock pero sin CPP
SELECT codigo, stock_teorico_lt, costo_promedio_lt, valor_total_stock
  FROM combustible_estanques
 WHERE activo=true AND stock_teorico_lt > 0
   AND (costo_promedio_lt IS NULL OR costo_promedio_lt = 0);

-- Estanque vs último kardex (deben coincidir)
SELECT e.codigo,
       e.stock_teorico_lt AS estanque_stock,
       (SELECT stock_lt_despues FROM combustible_kardex_valorizado
         WHERE estanque_id=e.id ORDER BY fecha_movimiento DESC LIMIT 1) AS kardex_stock,
       e.valor_total_stock AS estanque_valor,
       (SELECT valor_stock_despues FROM combustible_kardex_valorizado
         WHERE estanque_id=e.id ORDER BY fecha_movimiento DESC LIMIT 1) AS kardex_valor
  FROM combustible_estanques e WHERE e.activo=true;

-- Salida sin CECO (no debería existir)
SELECT folio_salida, ceco_id FROM salidas_combustible WHERE ceco_id IS NULL;

-- Estanques con stock_inicial activo
SELECT e.codigo, si.fecha, si.litros_iniciales, si.costo_unitario_inicial
  FROM combustible_estanques e
  LEFT JOIN combustible_stock_inicial si
       ON si.estanque_id=e.id AND si.anulado=false
 WHERE e.activo=true AND e.stock_teorico_lt > 0;
```

### Resolución
- **Estanque sin CPP:** registrar `rpc_registrar_stock_inicial_combustible` con costo Finanzas.
- **Desincronización estanque/kardex:** **NO modificar** manualmente. Investigar último movimiento.

---

## 5. Problemas de duplicidad

### Síntomas
- "duplicate key value violates unique constraint".
- Folios repetidos en reportes.

### Cómo detectar

```sql
-- Folios recepciones duplicados
SELECT folio_recepcion, COUNT(*) FROM recepciones_bodega GROUP BY folio_recepcion HAVING COUNT(*) > 1;

-- Guías combustible duplicadas
SELECT proveedor_id, numero_guia, COUNT(*) FROM ingresos_combustible
GROUP BY proveedor_id, numero_guia HAVING COUNT(*) > 1;

-- OC duplicadas
SELECT numero_oc, COUNT(*) FROM ordenes_compra GROUP BY numero_oc HAVING COUNT(*) > 1;

-- Stock inicial combustible duplicado activo
SELECT estanque_id, COUNT(*) FROM combustible_stock_inicial
WHERE anulado=false GROUP BY estanque_id HAVING COUNT(*) > 1;
```

### Resolución
- Folios duplicados son indicador de bug en el generador. Verificar `seq_folio_*` y la función `fn_generar_folio_*`.
- Guías duplicadas: el UNIQUE las bloquea. Si aparecen, el constraint no se aplicó.
- OC duplicadas: `numero_oc UNIQUE` está activo. Verificar.

---

## 6. Problemas de frontend

### Síntomas
- Pantalla en blanco.
- Error al guardar (toast rojo sin detalle).
- Dashboard vacío que antes mostraba datos.
- Botón desaparecido.

### Cómo detectar

1. **Consola del navegador** (F12 → Console):
   - Buscar errores rojos.
   - Buscar mensajes `[supabase]`.
   - Buscar `403 Forbidden`, `404 Not Found`, `500 Internal Server Error`.

2. **Network tab** (F12 → Network):
   - Filtrar por `Fetch/XHR`.
   - Buscar requests fallidas (status 4xx, 5xx).
   - Click en cada → tab "Preview" muestra error de Supabase.

3. **Supabase logs:**
   - Dashboard → Logs → API logs.
   - Filtrar por `error_severity = ERROR`.

4. **Build:**
   ```bash
   cd frontend
   npm run typecheck
   npm run build
   ```

5. **Payload RPC:** revisar el cuerpo del request en Network tab. Confirmar que los UUIDs son válidos.

### Causa común tras mig 55/56/57
- Frontend llama a una RPC con firma vieja (parámetros distintos a los que la RPC espera ahora).
- **Verificar:** la RPC reescrita en mig 56 (`rpc_registrar_recepcion_bodega`, `rpc_registrar_salida_bodega`) no se incluyó en `04_apply_mig55_produccion.sql` (versiones FIFO completas no se aplican aún — el frontend actual usa la versión base).
- Si frontend tiene código nuevo que asume FIFO pero solo se aplicó la base de mig 55: **conflicto de firmas**.

### Resolución
- Mantener frontend en su rama actual hasta que mig 56 esté completa con sus RPCs FIFO.
- O implementar feature flag `metodo_costeo='fifo'` en el frontend.

---

## 7. Problemas críticos que obligan STOP

🚨 **STOP inmediato y rollback si:**

| Síntoma | Acción |
|---|---|
| Login falla para todos los usuarios | Restaurar backup |
| Dashboard del admin no carga | Restaurar backup |
| Stock negativo aparece masivamente | Restaurar backup |
| RPC `rpc_registrar_salida_inventario` falla con error de tipo | Re-aplicar mig 56 (firmas) |
| OTs no cargan en `/dashboard/ordenes-trabajo` | Verificar mig 03 + revertir mig 56 si necesario |
| Inventario no carga en `/dashboard/inventario` | Verificar reconciliación |
| Combustible no carga | Verificar `combustible_estanques` no fue alterado destructivamente |
| Errores masivos RLS en logs | Revertir cualquier cambio de policies |
| Pérdida de datos detectada | **Restaurar backup INMEDIATAMENTE** |

### Procedimiento de rollback completo

```bash
# 1. STOP — informar a usuarios.
# 2. Restaurar dump:
gunzip backup_pre_mig55_*.sql.gz
psql "$DB_URL_PROD" < backup_pre_mig55_<fecha>.sql

# 3. Verificar:
psql "$DB_URL_PROD" -c "SELECT COUNT(*) FROM stock_bodega;"
psql "$DB_URL_PROD" -c "SELECT COUNT(*) FROM ordenes_trabajo;"

# 4. Confirmar usuarios pueden loguear.
# 5. Comunicar retoma.
```

---

## 8. Atajos para diagnóstico rápido

```sql
-- ¿Cuántas tablas nuevas existen?
SELECT COUNT(*) FROM information_schema.tables
 WHERE table_schema='public' AND table_name IN (
    'proveedores','centros_costo','ordenes_compra','ordenes_compra_items',
    'recepciones_bodega','recepciones_bodega_items',
    'salidas_bodega','salidas_bodega_items',
    'ingresos_combustible','salidas_combustible','despachos_combustible',
    'inventario_capas','inventario_consumos_capas',
    'combustible_stock_inicial','combustible_kardex_valorizado'
 );
-- Esperado: 15

-- ¿Bitácora completa?
SELECT codigo_paso, resultado, fecha_inicio
  FROM operacion_migraciones_log ORDER BY fecha_inicio DESC LIMIT 30;

-- ¿Errores en bitácora?
SELECT * FROM operacion_migraciones_log
 WHERE resultado IN ('error','revertido','warning')
 ORDER BY fecha_inicio DESC;

-- ¿Salud general?
SELECT
    (SELECT COUNT(*) FROM stock_bodega WHERE cantidad < 0) AS stock_negativo,
    (SELECT COUNT(*) FROM stock_bodega sb
       WHERE sb.cantidad > 0 AND NOT EXISTS (
         SELECT 1 FROM inventario_capas ic
          WHERE ic.producto_id=sb.producto_id AND ic.bodega_id=sb.bodega_id AND ic.estado='disponible'
       )) AS productos_sin_capa,
    (SELECT COUNT(*) FROM combustible_estanques
      WHERE activo=true AND stock_teorico_lt > 0
        AND (costo_promedio_lt IS NULL OR costo_promedio_lt = 0)) AS estanques_sin_cpp,
    (SELECT COUNT(*) FROM operacion_migraciones_log
      WHERE resultado IN ('error','revertido')) AS errores_log;
-- Todos deben ser 0 si todo está bien.
```
