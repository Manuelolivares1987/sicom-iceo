# PLAN DE PASO A PRODUCCIÓN — Migraciones 55-57 (Controlado)

> **Última actualización:** 2026-05-02 — FASE 5.6
> **Pre-requisito:** Staging OK con todos los tests del `PLAN_OPERACION_STAGING_MIGRACIONES.md` §8.
> **Estado:** NO ejecutar sin aprobación explícita y backup confirmado.

---

## 1. Pre-requisitos NO negociables

- [ ] Staging probado completo (20 tests OK).
- [ ] Backup completo de producción reciente (snapshot Supabase + dump SQL local).
- [ ] Ventana acordada con usuarios (sin uso del sistema durante aplicación).
- [ ] Plan de comunicación a usuarios listo.
- [ ] Responsable disponible y dedicado durante toda la ventana.
- [ ] Acceso al panel Supabase + canal de comunicación.
- [ ] Última verificación: build limpio, typecheck limpio.

---

## 2. Ventana horaria recomendada

| Día | Hora | Razón |
|---|---|---|
| **Sábado 16:00 – 22:00** | 6 horas | Ningún usuario operativo el fin de semana |
| **Domingo 09:00 – 13:00** | 4 horas adicionales si rebalse | Margen de buffer |
| **Lunes 06:00** | Validación final y comunicación de retoma | Antes que ingrese Gustavo / Eduardo |

> **Evitar:** lunes a viernes en horario laboral. Evitar día anterior a fin de mes (cierre).

---

## 3. Orden de ejecución (idéntico a staging)

### Bloque A — Pre-vuelo (15 min)

1. Verificar que ningún usuario está logueado (panel Supabase → Auth → Active sessions).
2. Backup snapshot Supabase + dump SQL local.
3. Verificar que `staging` y `producción` tienen los mismos datos maestros base (proveedores, CECO).
4. Confirmar build local actual:
   ```bash
   cd frontend && npm run typecheck && npm run build
   ```

### Bloque B — Datos maestros (15 min)

```sql
-- Seed proveedores (ya validado en staging)
INSERT INTO proveedores (codigo, nombre, tipo, activo) VALUES
    ('ENEX', 'ENEX S.A.', 'combustible', true),
    ('ESMAX', 'Esmax Distribucion S.A.', 'combustible', true),
    ('COPEC', 'Empresas Copec S.A.', 'combustible', true)
    -- + repuesteros reales
ON CONFLICT (codigo) DO NOTHING;

-- Seed CECO (ya validado en staging)
INSERT INTO centros_costo (codigo, nombre, area, activo) VALUES
    ('CECO-TALLER-CQB',   'Taller Coquimbo',           'mantenimiento', true),
    ('CECO-TALLER-CAL',   'Taller Calama',             'mantenimiento', true),
    ('CECO-OPERACIONES',  'Operaciones',               'operacional',   true),
    ('CECO-COMERCIAL',    'Comercial',                 'comercial',     true),
    ('CECO-VENTA-EXT',    'Venta combustible externa', 'comercial',     true),
    ('CECO-ADMIN',        'Administración',            'admin',         true)
ON CONFLICT (codigo) DO NOTHING;
```

### Bloque C — Mig 55 (30 min)

Ejecutar bloques A → O en orden, **cada bloque en una transacción separada**:

```sql
BEGIN;
-- (pegar mig 55 BLOCK A descomentado)
COMMIT;

BEGIN;
-- (pegar mig 55 BLOCK D descomentado)
COMMIT;

-- ... etc.
```

**Después de cada bloque**, verificar:
```sql
SELECT * FROM information_schema.tables WHERE table_schema='public' ORDER BY table_name;
```

### Bloque D — Mig 56 FIFO (30 min)

```sql
-- Bloques A-G en orden
-- DESPUÉS aplicar capas iniciales legacy (Paso 5 staging)
INSERT INTO inventario_capas (
    producto_id, bodega_id, fecha_recepcion, folio_recepcion,
    cantidad_inicial, cantidad_disponible, unidad, costo_unitario, estado
)
SELECT
    sb.producto_id, sb.bodega_id, CURRENT_DATE, 'CAPA-INICIAL-LEGACY',
    sb.cantidad, sb.cantidad, COALESCE(p.unidad_medida, 'unidad'),
    COALESCE(sb.costo_promedio, 0), 'disponible'
FROM stock_bodega sb
JOIN productos p ON p.id = sb.producto_id
WHERE sb.cantidad > 0;
```

### Bloque E — Mig 57 Combustible (30 min)

```sql
-- Bloques A-J en orden
-- DESPUÉS, registrar stock inicial por cada estanque con stock > 0
SELECT rpc_registrar_stock_inicial_combustible(
    e.id, CURRENT_DATE, e.stock_teorico_lt,
    <costo_historico_validado_por_finanzas>,
    NULL,
    'Apertura piloto produccion 2026-05-XX. Stock varillaje fisico. Costo historico Finanzas.'
)
FROM combustible_estanques e
WHERE e.activo = true AND e.stock_teorico_lt > 0;
-- Adaptar manualmente — cada estanque puede tener costo distinto.
```

### Bloque F — Validación post-deploy (1 hora)

Ejecutar la batería completa:

```sql
-- 1. Capas FIFO sembradas
SELECT COUNT(*) AS capas_creadas FROM inventario_capas;
-- Debe ser >= número de productos con stock

-- 2. Stock inicial combustible
SELECT * FROM combustible_stock_inicial WHERE anulado = false;

-- 3. Reconciliación FIFO (mig 56 H.5)
-- Debe devolver 0 filas

-- 4. Reconciliación combustible (mig 57 K.4)
-- Estanque y kardex deben coincidir

-- 5. RPCs disponibles
SELECT proname FROM pg_proc
 WHERE proname IN (
    'rpc_registrar_recepcion_bodega',
    'rpc_registrar_salida_bodega',
    'rpc_registrar_ingreso_combustible_valorizado',
    'rpc_registrar_salida_combustible_valorizada',
    'rpc_registrar_stock_inicial_combustible',
    'fn_consumir_inventario_fifo'
);

-- 6. Vistas creadas
SELECT viewname FROM pg_views
 WHERE viewname IN (
    'v_trazabilidad_producto_fifo',
    'v_costo_ot_materiales_fifo',
    'v_stock_valorizado_fifo',
    'v_kardex_valorizado_materiales',
    'v_combustible_kardex_valorizado',
    'v_combustible_trazabilidad_salida',
    'v_combustible_stock_valorizado_actual'
);
```

### Bloque G — Pruebas funcionales en producción (1 hora)

**Solo administrador**, con datos de prueba mínimos:
1. Crear 1 OC con 1 item.
2. Recibir parcial.
3. Salida tipo OT (con OT real existente).
4. Confirmar costos en `v_costo_ot_materiales_fifo`.
5. **NO** crear datos masivos. Solo validar pipeline end-to-end.

### Bloque H — Comunicación de retoma (15 min)

Mensaje a usuarios:
> *"Sistema disponible. Hoy se aplicaron mejoras de bodega y combustible. Capacitación esta semana sobre nuevas pantallas. Cualquier problema, avisar inmediatamente al administrador."*

---

## 4. Criterios para detener (rollback)

⛔ **Detener inmediatamente y aplicar rollback si:**

- Cualquier query de validación (Bloque F) falla.
- Cualquier reconciliación devuelve filas inesperadas.
- Cualquier login deja de funcionar.
- Cualquier RPC existente deja de responder.
- Cualquier dato legacy aparece corrupto.

### 4.1 Procedimiento de rollback

```bash
# Restaurar desde snapshot Supabase
# Panel → Database → Backups → Restore (seleccionar pre-deploy)

# O restore manual desde dump SQL (más lento):
psql $DB_URL < backup_pre_55_$(date +%Y%m%d).sql
```

→ Verificar que el frontend siga apuntando a la URL de producción.
→ Comunicar a usuarios el rollback.
→ Investigar causa offline antes de reintentar.

---

## 5. Criterios para aprobar el deploy

✅ **Aprobar y continuar si:**

- Bloque A-E ejecutados sin error.
- Bloque F: 100% de queries devuelven resultados esperados.
- Bloque G: 1 ciclo completo OC→recepción→salida→OT con costo correcto.
- Sidebar de cada rol visible correctamente en login.
- Stock total pre/post deploy idéntico.
- Sin errores en `auditoria_eventos` últimas 24h.

---

## 6. Comunicación a usuarios

### Antes (24h previas)

> *"Estimado equipo, el sábado XX entre 16:00 y 22:00 aplicaremos mejoras importantes en bodega y combustible: orden de compra formal, recepción parcial, costo FIFO de repuestos, costo promedio de combustible. Durante esa ventana el sistema estará en mantención. Lunes les compartiré las nuevas pantallas. Cualquier consulta, conmigo."*

### Durante (cuando empieza)

> *"Iniciando mantención. Sistema no disponible 16:00 – 22:00. Aviso al terminar."*

### Después (sistema disponible)

> *"Sistema disponible. Capacitación nuevas pantallas el lunes a las 10:00 (Gustavo bodega, Eduardo planificación). Cualquier problema operativo, contactar inmediatamente."*

### Si falla y se hace rollback

> *"Mantención reagendada por validación pendiente. Sistema funcionando con flujo actual. Avisaré nueva fecha. Disculpas."*

---

## 7. Pruebas post-deploy con usuarios reales

**Lunes (día 1 producción):**
- Gustavo recibe 1 OC real → registrar recepción parcial real.
- Eduardo crea 1 OT real con materiales → confirmar costo FIFO cargado.
- Operador abastecimiento (cuando exista) ingresa 1 carga ENEX real.

**Día 2-7:**
- Reconciliación diaria FIFO + combustible.
- Revisar `v_costo_ot_materiales_fifo` con Finanzas.
- Capturar feedback de los 3 usuarios.

**Día 8 — Retroalimentación:**
- Reunión con Finanzas + Gustavo + Eduardo.
- Decidir si aplicar mig 52 Block A (vista QR pública).
- Planear sprint UI completo (recepción, salida con CECO, stock inicial combustible, kardex valorizado).

---

## 8. Responsabilidades

| Rol | Antes | Durante | Después |
|---|---|---|---|
| Administrador (Manuel) | Backup, comunicación, validación staging | Ejecutar SQL, validar, comunicar | Soporte usuarios, reconciliación diaria |
| Finanzas | Validar costos históricos stock inicial | — | Validar costos OT FIFO + combustible |
| DBA externo (si hay) | Revisión queries staging | Validación performance | Tuning índices si necesario |
| Bodeguero / Planificador / Op Abastecimiento | — | — | Pruebas reales día 1, feedback |

---

## 9. Lista de verificación final antes de "GO"

- [ ] Staging 20 tests pasaron.
- [ ] Backup snapshot Supabase confirmado.
- [ ] Dump SQL local guardado.
- [ ] Build frontend limpio.
- [ ] Datos maestros (proveedores + CECO) validados.
- [ ] Costos históricos para stock inicial combustible validados por Finanzas.
- [ ] Costos promedio actuales para capas FIFO legacy validados.
- [ ] Comunicación pre-deploy enviada.
- [ ] Ventana confirmada con stakeholders.
- [ ] Rollback plan claro y probado en staging.

→ Si TODOS marcados, **GO**. Si alguno no, **detener y resolver**.
