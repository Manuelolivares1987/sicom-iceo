# PLAN DE OPERACIÓN — STAGING (Migraciones pendientes 52-57)

> **Última actualización:** 2026-05-02 — FASE 5.6
> **Audiencia:** administrador, DBA, finanzas (validación stock).
> **Estado:** Plan documentado. NO ejecutar sin staging real disponible.

---

## 1. Inventario de migraciones pendientes

| Mig | Propósito | Tipo | Estado | Dependencias | Riesgo | Staging | Producción | Observación |
|---|---|---|---|---|---|---|---|---|
| **52** | RLS hardening, role-check RPCs, ruta pública QR, Storage policies | Recomendaciones por bloque | Comentado, NO ejecutado | mig 31 (`fn_user_rol`), mig 21 (RLS base) | **Alto** si se aplica todo | ⚠️ Solo Block A (vista QR) primero | Solo Block A. Resto post-evaluación | Bloques B/C/D pueden romper accesos legítimos. Probar en staging por bloque |
| **53** | Seed perfiles piloto (11 roles) | Manual + SQL | Comentado | Crear usuarios en Auth Dashboard primero | Bajo | ✅ Tras crear usuarios | ✅ Tras crear usuarios | UUIDs reales requeridos. Ya 2 usuarios creados (Gustavo, Eduardo) |
| **54** | Verificaciones flota + checklists FASE 5.2 | SAFE + opcionales | Solo Block 0 SAFE | mig 22, 30, 37, 44, 45 | Bajo | ✅ Block 0 + A (índice) | ✅ Block 0 + A | Block D (versionado plantillas) post-piloto |
| **55** | Bodega: OC, recepciones, CECO, salidas, combustible base, despachos sellos | Operativo crítico | Comentado | mig 02, 03, 09, 31, 50 | **Medio-Alto** | ✅ Bloques A-O completos | ✅ Después de pruebas | **Base obligatoria** para 56 y 57 |
| **56** | FIFO repuestos/materiales (capas + consumos + función) | Operativo crítico | Comentado | **mig 55 aplicada** | **Alto** (cambia costeo OT) | ✅ Tras 55 + tests 1-6 | ✅ Tras pruebas + capacitación | Reescribe rpc_registrar_recepcion_bodega y rpc_registrar_salida_bodega |
| **57** | Combustible CPP móvil + kardex valorizado | Operativo crítico | Comentado | **mig 55 aplicada** | **Alto** (cambia costeo combustible) | ✅ Tras 55 + tests 1-7 | ✅ Tras pruebas + capacitación | Independiente de 56 (FIFO no aplica a líquidos) |

### 1.1 Otras migraciones pendientes (revisión)

```bash
# Listar migraciones aplicadas vs no aplicadas
ls database/schema/*.sql | sort
```

Las migraciones **01-51** están todas aplicadas (verificación FASE 0). Las **52-57** son las pendientes. No se detectaron otras `.sql` huérfanas.

---

## 2. Pre-requisitos antes de tocar staging

### 2.1 Definir staging
Si **no existe staging**:
1. Crear proyecto Supabase nuevo (puede ser plan free temporal): `sicom-iceo-staging`.
2. En el proyecto staging, ejecutar migraciones **01-51** (las ya aplicadas en prod) en orden numérico.
3. Importar **datos críticos** desde producción:
   - `usuarios_perfil` (al menos 2-3 perfiles de prueba).
   - `faenas`, `contratos`, `marcas`, `modelos` (maestros).
   - 5-10 `activos` representativos.
   - `bodegas`, `productos` (10-20 ítems).
   - `combustible_estanques` (al menos 1).
4. Validar que el frontend conecta a staging (cambiar `.env.local` con URL/anon key staging).

### 2.2 Backup obligatorio antes de aplicar 55-57

```bash
# Desde Supabase Dashboard → Database → Backups → Create snapshot
# O por CLI:
pg_dump --schema=public --data-only -t usuarios_perfil -t activos -t flota_vehicular \
        -t stock_bodega -t combustible_estanques -t movimientos_inventario \
        -t movimientos_combustible -t ordenes_trabajo \
        > backup_pre_55_$(date +%Y%m%d).sql
```

---

## 3. Orden de aplicación en staging

### Paso 1 — Verificaciones SAFE (lectura)

```sql
-- 1. mig 52 BLOCK 0 — políticas y SECURITY DEFINER actuales
-- (descomentar y ejecutar las queries SELECT de mig 52 BLOCK 0)

-- 2. mig 54 BLOCK 0 — salud flota
-- (descomentar y ejecutar las queries de mig 54 BLOCK 0)

-- 3. mig 55 BLOCK 0 — confirmar tablas base existen
-- 4. mig 56 BLOCK 0 — confirmar mig 55 prerequisito
-- 5. mig 57 BLOCK 0 — confirmar mig 55 prerequisito
```

✅ **No hay cambios en BD** en este paso. Solo lectura.

### Paso 2 — Datos maestros mínimos (mig 55 dependencias)

Ejecutar **antes** de mig 55:

```sql
-- 2a. Seed proveedores (mig 55 BLOCK B sugerencia, ejecutar como ADMIN)
-- DESCOMENTAR el INSERT de mig 55 BLOCK B con valores reales:
INSERT INTO proveedores (codigo, nombre, tipo, activo) VALUES
    ('ENEX',  'ENEX S.A.',                'combustible', true),
    ('ESMAX', 'Esmax Distribucion S.A.',  'combustible', true),
    ('COPEC', 'Empresas Copec S.A.',      'combustible', true)
    -- agregar repuesteros reales
ON CONFLICT (codigo) DO NOTHING;

-- 2b. Seed CECO mínimos
INSERT INTO centros_costo (codigo, nombre, area, activo) VALUES
    ('CECO-TALLER-CQB',   'Taller Coquimbo',          'mantenimiento', true),
    ('CECO-TALLER-CAL',   'Taller Calama',            'mantenimiento', true),
    ('CECO-OPERACIONES',  'Operaciones',              'operacional',   true),
    ('CECO-COMERCIAL',    'Comercial',                'comercial',     true),
    ('CECO-VENTA-EXT',    'Venta combustible externa','comercial',     true),
    ('CECO-ADMIN',        'Administración',           'admin',         true)
ON CONFLICT (codigo) DO NOTHING;
```

### Paso 3 — Aplicar mig 55 (bloque por bloque)

```sql
-- 3a. mig 55 Block A: enums                  → idempotente
-- 3b. mig 55 Block B: proveedores            → ya seedeado en Paso 2
-- 3c. mig 55 Block C: centros_costo          → ya seedeado en Paso 2
-- 3d. mig 55 Block D: ordenes_compra+items
-- 3e. mig 55 Block E: recepciones_bodega+items
-- 3f. mig 55 Block F: salidas_bodega+items
-- 3g. mig 55 Block G: ingresos_combustible
-- 3h. mig 55 Block H: salidas_combustible
-- 3i. mig 55 Block I: despachos_combustible
-- 3j. mig 55 Block J: folios
-- 3k. mig 55 Block K: rpc_registrar_recepcion_bodega (versión BASE — no FIFO aún)
-- 3l. mig 55 Block L: rpc_registrar_salida_bodega (versión BASE — no FIFO aún)
-- 3m. mig 55 Block M: rpc_registrar_ingreso_combustible (versión BASE)
-- 3n. mig 55 Block N-O: salida combustible + despacho con sellos
```

→ **Probar:** crear 1 OC ficticia, hacer recepción parcial, hacer salida con CECO, ver eventos en `auditoria_eventos`.

### Paso 4 — Aplicar mig 56 (FIFO repuestos)

```sql
-- 4a. mig 56 Block A: inventario_capas
-- 4b. mig 56 Block B: inventario_consumos_capas
-- 4c. mig 56 Block C: extender ot_materiales_planeados
-- 4d. mig 56 Block D: fn_consumir_inventario_fifo
-- 4e. mig 56 Block E: rpc_registrar_recepcion_bodega VERSIÓN FIFO (sobreescribe Paso 3k)
-- 4f. mig 56 Block F: rpc_registrar_salida_bodega VERSIÓN FIFO (sobreescribe Paso 3l)
-- 4g. mig 56 Block G: 4 vistas finanzas
```

→ **Probar Tests 1-6** de `INVENTARIO_FIFO_COSTEO_OT.md §11`.

### Paso 5 — Sembrar capas iniciales para repuestos legacy

Para productos con stock existente **antes** de FIFO, registrar capa inicial con costo histórico:

```sql
-- Para CADA producto en stock_bodega con cantidad > 0, crear capa inicial.
-- Costo histórico = stock_bodega.costo_promedio (CPP existente).
INSERT INTO inventario_capas (
    producto_id, bodega_id, fecha_recepcion, folio_recepcion,
    cantidad_inicial, cantidad_disponible, unidad, costo_unitario,
    estado
)
SELECT
    sb.producto_id, sb.bodega_id, CURRENT_DATE, 'CAPA-INICIAL-LEGACY',
    sb.cantidad, sb.cantidad, COALESCE(p.unidad_medida, 'unidad'),
    COALESCE(sb.costo_promedio, 0),
    'disponible'
FROM stock_bodega sb
JOIN productos p ON p.id = sb.producto_id
WHERE sb.cantidad > 0;
```

→ **Verificar reconciliación:** Mig 56 BLOCK H.5 debe devolver 0 filas.

### Paso 6 — Aplicar mig 57 (combustible CPP móvil)

```sql
-- 6a. mig 57 Block A: extender combustible_estanques
-- 6b. mig 57 Block B: combustible_stock_inicial
-- 6c. mig 57 Block C: combustible_kardex_valorizado
-- 6d. mig 57 Block D-E: extender ingresos/salidas
-- 6e. mig 57 Block F: rpc_registrar_stock_inicial_combustible
-- 6f. mig 57 Block G: rpc_registrar_ingreso_combustible_valorizado
-- 6g. mig 57 Block H: rpc_registrar_salida_combustible_valorizada
-- 6h. mig 57 Block I: extender despachos
-- 6i. mig 57 Block J: 3 vistas finanzas
```

### Paso 7 — Registrar stock inicial combustible

Para cada estanque con stock > 0, **administrador** ejecuta:

```sql
SELECT rpc_registrar_stock_inicial_combustible(
    'estanque-uuid-aqui',
    CURRENT_DATE,
    1000.0,           -- litros actuales medidos físicamente (varillaje)
    900.0000,         -- costo histórico estimado validado por Finanzas
    NULL,             -- documento respaldo opcional
    'Apertura piloto: stock fisico verificado por varillaje 2026-05-02. Costo historico estimado por Finanzas segun ultima compra ENEX.'
);
```

→ Verificar `v_combustible_stock_valorizado_actual`.

### Paso 8 — Tests funcionales completos

| # | Test | Documento |
|---|---|---|
| 1 | Recepción parcial OC | `BODEGA_OC_CECO_TRAZABILIDAD.md §8` |
| 2 | Bloqueo sobrecantidad | `BODEGA_OC_CECO_TRAZABILIDAD.md §8` |
| 3 | Salida tipo OT | `BODEGA_OC_CECO_TRAZABILIDAD.md §8` |
| 4 | Salida tipo persona | idem |
| 5 | Documento duplicado | idem |
| 6 | FIFO básico | `INVENTARIO_FIFO_COSTEO_OT.md §11` |
| 7 | FIFO multi-capa | idem |
| 8 | Stock insuficiente | idem |
| 9 | Recepción precio distinto | idem |
| 10 | Concurrencia 2 salidas | idem |
| 11 | Stock inicial combustible | `COMBUSTIBLE_COSTEO_PROMEDIO_TRAZABILIDAD.md §9` |
| 12 | Ingreso recalcula CPP | idem |
| 13 | Salida usa CPP vigente | idem |
| 14 | Costo manual prohibido | idem |
| 15 | Stock combustible insuficiente | idem |
| 16 | Diferencia meter exige obs | idem |
| 17 | Reconciliación estanque vs kardex | idem |
| 18 | Despacho con sellos completo | `COMBUSTIBLE_TRAZABILIDAD_CLASE_MUNDIAL.md §10` |
| 19 | Confirmar entrega con diferencia | idem |
| 20 | Sellos rotos | idem |

### Paso 9 — Aplicar mig 52 Block A (vista pública QR)

**Solo si `/equipo/[id]` se va a usar en terreno con QR:**

```sql
-- mig 52 Block A.1 + A.2 + A.3 + A.4
-- (descomentar y aplicar)
```

→ Cambiar frontend `src/lib/services/activos.ts:137` para llamar `rpc_ficha_activo_publica`.

### Paso 10 — Diferir mig 52 Blocks B, C, D

**No aplicar** sin auditoría adicional. Aplicarlos puede:
- Romper login si role-check de RPCs es muy estricto.
- Bloquear lecturas legítimas si se cambian políticas USING(true).
- Romper Storage si se modifican policies de buckets activos.

→ Tarea para sprint dedicado de seguridad post-MVP.

---

## 4. Criterios para aprobar staging y pasar a producción

| Criterio | Esperado |
|---|---|
| Tests 1-20 pasan | ✅ |
| Reconciliación FIFO mig 56 H.5 | 0 filas |
| Reconciliación combustible mig 57 K.4 | Pares coincidentes |
| Build frontend | ✅ Limpio |
| Login con 5 roles distintos | ✅ Cada uno ve su sidebar correcto |
| Auditoría registra cada operación | ✅ Eventos visibles en `/dashboard/auditoria` |
| Storage subida fotos | ✅ |
| Sin pérdida de datos legacy | ✅ Stock pre-migración intacto |

---

## 5. Comandos rápidos de validación

```sql
-- A. Estado de OCs
SELECT estado, COUNT(*) FROM ordenes_compra GROUP BY estado;

-- B. Capas activas FIFO
SELECT * FROM v_stock_valorizado_fifo LIMIT 20;

-- C. Estado combustible
SELECT * FROM v_combustible_stock_valorizado_actual;

-- D. Eventos auditoría últimas 24h
SELECT tabla, accion, COUNT(*) FROM auditoria_eventos
 WHERE created_at >= NOW() - INTERVAL '24 hours'
 GROUP BY tabla, accion ORDER BY COUNT(*) DESC;

-- E. Reconciliación FIFO
-- (ver mig 56 BLOCK H.5)

-- F. Reconciliación combustible
-- (ver mig 57 BLOCK K.4)
```

---

## 6. Plan de rollback (si algo falla en staging)

1. Si una migración deja la BD inconsistente: `psql staging < backup_pre_XX.sql`.
2. Si una RPC nueva tiene bug: dejar la versión vieja en sombra (no se borra por defecto). Recrear con la versión anterior.
3. Si el frontend rompe: revertir env vars a producción anterior (mientras staging se arregla).

---

## 7. Responsables

| Rol | Tarea |
|---|---|
| Administrador (Manuel) | Coordinación, aplicación SQL, decisión go/no-go |
| DBA externo (si hay) | Revisión de queries, índices, performance |
| Finanzas | Validar costos históricos para stock inicial |
| Bodeguero (Gustavo) | Probar flujos OC + recepción + salida en staging |
| Operador abastecimiento (futuro) | Probar ingreso/salida combustible en staging |

---

## 8. Estimación de tiempo

| Etapa | Estimación |
|---|---|
| Crear staging + import datos | 4-6 horas |
| Pasos 1-3 (verificaciones + maestros + mig 55) | 2 horas |
| Pasos 4-5 (mig 56 + capas iniciales) | 2 horas |
| Paso 6-7 (mig 57 + stock inicial) | 1-2 horas |
| Paso 8 (Tests 1-20) | 4-6 horas |
| Paso 9-10 (mig 52 evaluación) | 2 horas |
| **TOTAL staging** | **~15-20 horas** distribuidas en 2-3 días |

→ Razonable para una ventana de feriado.
