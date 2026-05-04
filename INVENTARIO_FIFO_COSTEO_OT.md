# INVENTARIO FIFO — Costeo de OT y CECO

> **Última actualización:** 2026-05-02 — FASE 5.4-A
> **Audiencia:** administrador, finanzas, contraloría, jefe de mantenimiento, bodeguero, auditor.
> **Estado:** SQL propuesto en `database/schema/56_*.sql` (NO ejecutado). Validaciones Zod en `validations/bodega.ts`. Frontend pendiente.

---

## 1. Decisión técnica: por qué FIFO para repuestos

| Característica | FIFO (elegido para repuestos) | CPP (combustible/insumos fungibles) |
|---|---|---|
| Trazabilidad | ✅ Cada salida apunta a capa exacta | ❌ Solo costo promedio agregado |
| Auditoría finanzas | ✅ OC → recepción → capa → salida → OT | ⚠️ OC → recepción → "promedio" |
| Refleja realidad económica | ✅ Costo real de cada compra | ❌ Diluye precios |
| Vencimientos / lotes | ✅ Sale primero el más antiguo | ❌ No diferencia |
| Complejidad | Media (capas + consumos) | Baja (un costo) |

**Para SICOM-ICEO se elige FIFO en repuestos/materiales/insumos** porque:
1. Permite a Administración y Finanzas reconstruir el costo real de cada OT.
2. Maneja correctamente lotes y vencimientos (filtros, lubricantes con fecha).
3. Distingue compras a precios distintos sin contaminar el costo de OTs antiguas.
4. Cumple estándar de auditoría externa (KPMG, Deloitte, SEC).

> **Nota:** combustible mantiene su modelo actual (un solo costo por estanque, mig 50) porque es producto fungible y mezclado físicamente. Los repuestos físicamente individuales (filtros, baterías, mangueras) sí justifican capas.

---

## 2. Ejemplo concreto — el "filtro $10.000 / $14.000"

### 2.1 Estado inicial

| Compra | OC | Cantidad | Costo unitario | Capa creada |
|---|---|---|---|---|
| 2026-04-15 | OC-2026-001 | 1 filtro | $10.000 | **Capa A**: `cantidad_disponible=1, costo=10000` |
| 2026-04-28 | OC-2026-005 | 1 filtro | $14.000 | **Capa B**: `cantidad_disponible=1, costo=14000` |

**Stock total:** 2 filtros. **Valor total FIFO:** $24.000.

### 2.2 Caso A — sale 1 filtro para OT-2026-100

```sql
-- Internamente la RPC ejecuta:
SELECT fn_consumir_inventario_fifo(
    p_producto_id => 'filtro-uuid',
    p_bodega_id   => 'bodega-uuid',
    p_cantidad    => 1,
    p_ot_id       => 'ot-100-uuid',
    p_ceco_id     => 'ceco-taller-uuid'
);
```

**Resultado:**
- Consume **Capa A** (más antigua): 1 unidad × $10.000.
- Capa A: `cantidad_disponible=0, estado='agotada'`.
- Capa B: intacta (1 unidad disponible a $14.000).
- OT-2026-100: `costo_total_real=$10.000, metodo_costeo='fifo'`.

**JSON devuelto por la RPC:**
```json
{
  "cantidad_consumida": 1,
  "costo_total": 10000,
  "costo_unitario_promedio": 10000,
  "capas_consumidas": [
    {"capa_id": "...", "fecha_recepcion": "2026-04-15", "folio_recepcion": "REC-202604-00012", "cantidad": 1, "costo_unitario": 10000, "costo_total": 10000}
  ],
  "metodo": "fifo"
}
```

### 2.3 Caso B — luego sale 1 filtro más para OT-2026-101

- Capa A está agotada → consume **Capa B**: 1 × $14.000.
- OT-2026-101: `costo_total_real=$14.000`.

### 2.4 Caso C — directamente salen 2 filtros para OT-2026-200

(Estado vuelve al inicial: 2 capas disponibles.)

- Consume **Capa A** completa (1 × $10.000) + **Capa B** completa (1 × $14.000).
- OT-2026-200: `costo_total_real=$24.000`, `costo_unitario_promedio=$12.000`.
- `inventario_consumos_capas` registra **DOS filas** — una por capa consumida.

---

## 3. Modelo de datos (mig 56)

### 3.1 Tabla `inventario_capas`

Cada fila es una capa valorizada creada por una recepción.

| Campo | Notas |
|---|---|
| `producto_id`, `bodega_id` | A qué producto y bodega pertenece |
| `recepcion_bodega_id`, `recepcion_bodega_item_id`, `orden_compra_id`, `orden_compra_item_id`, `proveedor_id` | Trazabilidad completa hacia origen |
| `fecha_recepcion`, `folio_recepcion`, `numero_oc` | Datos del documento (denormalizado para reportes rápidos) |
| `cantidad_inicial` (CHECK > 0) | No cambia jamás (es el original) |
| `cantidad_disponible` (CHECK >= 0, <= cantidad_inicial) | Decrementa con cada consumo |
| `costo_unitario` (CHECK >= 0) | Inmutable: el costo de esta compra específica |
| `costo_total_inicial`, `costo_total_disponible` | Columnas **GENERATED** automáticas |
| `lote`, `vencimiento`, `numero_serie` | Trazabilidad física |
| `estado` | `disponible` / `agotada` / `bloqueada` / `ajustada` |

**Índice clave:** `(producto_id, bodega_id, fecha_recepcion ASC, created_at ASC, id ASC) WHERE estado='disponible'` — habilita el orden FIFO determinista.

### 3.2 Tabla `inventario_consumos_capas`

Detalle de cada consumo. Una salida puede generar 1 a N filas según cuántas capas consuma.

| Campo | Notas |
|---|---|
| `salida_bodega_id`, `salida_bodega_item_id`, `movimiento_inventario_id` | Origen del consumo |
| `ot_id`, `ceco_id` | Destino del costo (para reportes finanzas) |
| `producto_id`, `bodega_id` | Denormalizado |
| `capa_id` | FK a la capa consumida |
| `cantidad_consumida` (> 0), `costo_unitario_capa` | Datos del consumo |
| `costo_total_consumido` | Columna **GENERATED** |
| `fecha_consumo`, `consumido_por` | Auditoría |

### 3.3 Extensión a `ot_materiales_planeados` (mig 48 + FASE 5.4-A)

Se agregan 5 columnas:

```sql
ALTER TABLE ot_materiales_planeados
    ADD COLUMN costo_unitario_real    NUMERIC(14,4),
    ADD COLUMN costo_total_real       NUMERIC(16,2),
    ADD COLUMN metodo_costeo          VARCHAR(20) DEFAULT 'fifo',
    ADD COLUMN salida_bodega_id       UUID REFERENCES salidas_bodega(id),
    ADD COLUMN ceco_id                UUID REFERENCES centros_costo(id);
```

→ Cada material despachado a una OT queda con su costo real cargado, **listo para sumarse al costo total de la OT**.

---

## 4. Función core — `fn_consumir_inventario_fifo`

### 4.1 Garantías

1. **Transaccional**: si falla, rollback completo. No quedan capas decrementadas sin consumo registrado.
2. **Concurrencia segura**: usa `SELECT ... FOR UPDATE` en el orden FIFO determinista. Dos transacciones simultáneas no pueden pisar la misma capa.
3. **Stock no negativo**: pre-check antes del lock + defensa post-loop con `RAISE EXCEPTION`.
4. **Mensaje claro**: `Stock insuficiente para producto X en bodega Y. Disponible: N, solicitado: M.`
5. **Auditable**: toda invocación crea filas en `inventario_consumos_capas` con `consumido_por = auth.uid()`.

### 4.2 Flujo

```
fn_consumir_inventario_fifo(p_producto_id, p_bodega_id, p_cantidad, ...)
  │
  ▼
1. Validar p_cantidad > 0
  │
  ▼
2. Pre-check: SUM(cantidad_disponible) >= p_cantidad
   Si no → RAISE 'Stock insuficiente'
  │
  ▼
3. SELECT capas WHERE estado='disponible'
   ORDER BY fecha_recepcion, created_at, id
   FOR UPDATE
  │
  ▼
4. LOOP cada capa:
     v_consumir = LEAST(pendiente, capa.cantidad_disponible)
     INSERT inventario_consumos_capas (capa_id, cantidad, costo_unitario)
     UPDATE inventario_capas SET cantidad_disponible -= v_consumir
                                  estado = CASE WHEN restante=0 THEN 'agotada' ELSE 'disponible' END
     pendiente -= v_consumir
   Hasta pendiente = 0
  │
  ▼
5. RETURN JSONB:
   { cantidad_consumida, costo_total, costo_unitario_promedio, capas_consumidas[], metodo:'fifo' }
```

---

## 5. Recepción contra OC crea capa

### 5.1 RPC `rpc_registrar_recepcion_bodega` (versión FIFO de mig 56 BLOCK E)

Por cada item recibido:
1. **Valida cantidad** ≤ pendiente de OC item; sobrecantidad bloqueada salvo `permite_sobrecantidad=true` + administrador + `justificacion_override` ≥10 caracteres.
2. **Valida costo** = `precio_unitario_clp` de OC item; diferencia bloqueada salvo `permite_precio_distinto=true` + administrador + justificación.
3. **Crea capa** en `inventario_capas` con `cantidad_inicial = cantidad_recibida`, `cantidad_disponible = cantidad_recibida`, `costo_unitario = costo_real`.
4. **Aumenta `stock_bodega`** vía `rpc_registrar_entrada_inventario` (existente, mantiene CPP/kardex en paralelo).
5. **Actualiza OC**: suma `cantidad_recibida`, ajusta estado item (`pendiente`/`parcial`/`completo`), ajusta estado OC global.

### 5.2 Reglas de negocio

| Regla | Defensa |
|---|---|
| Recepción debe estar contra una OC | Frontend + Zod (warning si `orden_compra_id IS NULL`) |
| Sobrecantidad bloqueada | RPC `RAISE EXCEPTION` salvo override admin |
| Precio distinto bloqueado | RPC `RAISE EXCEPTION` salvo override admin |
| Override exige justificación ≥10 caracteres | Validación en RPC + Zod `recepcionFifoSchema` |
| Recepción parcial OK | OC item pasa a `parcial`, OC global a `parcial` |
| Una OC puede tener N capas (recepciones distintas) | Por diseño: cada recepción genera capa propia |

---

## 6. Salida consume capas FIFO

### 6.1 RPC `rpc_registrar_salida_bodega` (versión FIFO de mig 56 BLOCK F)

Por cada item de salida:
1. **Valida CECO obligatorio** y **OT obligatoria** si `tipo_salida='ot'`.
2. **Inserta `salidas_bodega_items`** con cantidad (sin costo aún).
3. **Llama `fn_consumir_inventario_fifo`** → consume capas en orden y devuelve costo real.
4. **Actualiza el item** con `costo_unitario_clp = costo_unitario_promedio` (FIFO).
5. **Crea movimiento_inventario** vía `rpc_registrar_salida_inventario` (existente, mantiene kardex y descuenta `stock_bodega`).
6. **Si tipo=ot**: inserta/actualiza fila en `ot_materiales_planeados` con `costo_unitario_real`, `costo_total_real`, `metodo_costeo='fifo'`, `salida_bodega_id`, `ceco_id`.

### 6.2 Garantías

- **Stock negativo imposible**: doble defensa (FIFO pre-check + RPC existente con `CHECK stock >= 0`).
- **Costo manual prohibido** salvo `metodo_costeo='manual_autorizado'` con autorización admin + justificación (Zod `salidaFifoSchema`).
- **Detalle conservado**: aunque se consuman 5 capas, las 5 quedan registradas en `inventario_consumos_capas`.

---

## 7. Cómo se costea una OT

```
OT-2026-100 (cambio de filtro motor + filtro aire)
   │
   ├─ ot_materiales_planeados:
   │    Filtro motor:  cantidad=1, costo_unitario_real=$10.000, costo_total_real=$10.000  (Capa A)
   │    Filtro aire:   cantidad=1, costo_unitario_real=$14.000, costo_total_real=$14.000  (Capa B)
   │    metodo_costeo='fifo' en ambos
   │
   └─ ordenes_trabajo:
        costo_materiales = SUM(ot_materiales_planeados.costo_total_real) = $24.000
        costo_mano_obra  = (registro separado, mig 03)
        costo_total      = costo_mano_obra + costo_materiales (columna generada en mig 03)
```

→ Finanzas puede consultar **`v_costo_ot_materiales_fifo`** y obtener detalle por OT con todas las capas consumidas, OC origen, proveedor, fecha de recepción.

---

## 8. Cómo se valoriza el stock restante

Vista **`v_stock_valorizado_fifo`**:

```sql
SELECT * FROM v_stock_valorizado_fifo;

-- producto_codigo | bodega | cantidad_total_disponible | valor_total_fifo | costo_promedio_informativo | capas_activas
-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- FILTRO-AIRE-XYZ | CQB    | 5                         | $58.000          | $11.600                    | 3
-- BATERIA-12V-100A | CQB   | 2                         | $260.000         | $130.000                   | 2
```

→ El **valor real** de inventario es la suma de cada capa × su costo. El "costo promedio informativo" es solo referencial (no se usa para costear OTs).

---

## 9. Reportes y vistas para Finanzas

| Vista | Uso |
|---|---|
| `v_trazabilidad_producto_fifo` | Auditoría: capa → recepción → OC → consumos. Para una pregunta "¿de dónde salió este filtro?" |
| `v_costo_ot_materiales_fifo` | Costeo por OT con detalle de capas y proveedores |
| `v_stock_valorizado_fifo` | Cierre contable mensual: cuánto vale el inventario hoy |
| `v_kardex_valorizado_materiales` | Kardex completo (entradas y salidas con valor) por producto/bodega |

### 9.1 Reconciliación obligatoria

Después de aplicar la migración, ejecutar mensualmente:

```sql
-- Diferencia entre stock_bodega.cantidad y SUM(inventario_capas.cantidad_disponible)
-- Si esta query devuelve filas, hay desincronizacion (investigar):
SELECT p.codigo, b.codigo,
       sb.cantidad   AS stock_bodega_cantidad,
       SUM(ic.cantidad_disponible) AS capas_total,
       sb.cantidad - SUM(ic.cantidad_disponible) AS diferencia
  FROM stock_bodega sb
  JOIN productos p ON p.id = sb.producto_id
  JOIN bodegas   b ON b.id = sb.bodega_id
  LEFT JOIN inventario_capas ic
    ON ic.producto_id = sb.producto_id AND ic.bodega_id = sb.bodega_id AND ic.estado = 'disponible'
 GROUP BY p.codigo, b.codigo, sb.cantidad
HAVING ABS(sb.cantidad - COALESCE(SUM(ic.cantidad_disponible), 0)) > 0.001;
```

---

## 10. Validaciones Zod listas

Archivo: `frontend/src/validations/bodega.ts` (extendido en FASE 5.4-A).

| Schema | Cubre |
|---|---|
| `recepcionFifoSchema` | Recepción con `permite_sobrecantidad`, `permite_precio_distinto`, `justificacion_override` ≥10 |
| `salidaFifoSchema` | Salida con `metodo_costeo`. Bloquea costo manual salvo `manual_autorizado` con autorización + justificación |
| `capaInventarioReadSchema` | Tipo de lectura para mostrar capas en UI |

### 10.1 Reglas Zod

- 🔴 Override (sobrecantidad o precio) **exige justificación ≥10 caracteres**.
- 🔴 `metodo_costeo='manual_autorizado'` exige `costo_unitario_manual` + `autorizado_por` + justificación.
- 🔴 Si `metodo_costeo='fifo'`, **NO se acepta costo manual** (lo asigna el sistema).
- 🔴 Salida con CECO obligatorio (heredado de schema base).
- 🔴 Salida tipo OT exige OT (heredado).

---

## 11. Pruebas manuales (cuando se aplique SQL)

### Test 1 — FIFO básico
1. Crear OC con 1 item: filtro × 2 a $10.000.
2. Recibir 1 unidad → Capa A (costo $10.000).
3. Crear nueva OC: filtro × 1 a $14.000.
4. Recibir 1 unidad → Capa B (costo $14.000).
5. Salida 1 unidad para OT-test → debe consumir Capa A.
6. Verificar: `v_costo_ot_materiales_fifo` muestra OT-test con costo $10.000.
7. Salida 1 unidad más → debe consumir Capa B.
8. Verificar: nuevo costo $14.000.

### Test 2 — Salida que excede una capa
1. Estado: Capa A=1 a $10.000, Capa B=2 a $14.000.
2. Salida 2 unidades para OT-test.
3. Debe consumir Capa A completa + 1 unidad de Capa B.
4. `inventario_consumos_capas` debe tener **2 filas** para esta salida.
5. Costo total = $10.000 + $14.000 = $24.000. Promedio = $12.000.

### Test 3 — Stock insuficiente
1. Estado: 1 unidad disponible.
2. Intentar salir 5 unidades.
3. Debe fallar con `RAISE EXCEPTION 'Stock insuficiente para producto X en bodega Y. Disponible: 1, solicitado: 5.'`
4. Ninguna capa debe quedar modificada (rollback completo).

### Test 4 — Recepción con precio distinto
1. OC tiene filtro a $10.000.
2. Bodeguero intenta recibir a $11.000.
3. Sin override → debe fallar.
4. Como administrador con `permite_precio_distinto=true` y justificación "Aumento por flete urgente solicitado por jefe taller" → pasa.
5. Capa creada con `costo_unitario=$11.000` (no $10.000).
6. `recepciones_bodega.observacion` debe contener `OVERRIDE ADMIN: ...`.

### Test 5 — Concurrencia
1. Estado: 1 unidad disponible.
2. Lanzar 2 transacciones simultáneas que intentan consumir esa unidad.
3. Una debe pasar; la otra debe fallar con stock insuficiente (no debe consumirse 2 veces).

### Test 6 — Reconciliación
1. Hacer varias recepciones y salidas mezcladas.
2. Ejecutar query de reconciliación de §9.1.
3. Debe devolver 0 filas.

---

## 12. Archivos creados/modificados

```
A  database/schema/56_inventario_fifo_repuestos_materiales.sql  (NO destructivo, comentado)
M  frontend/src/validations/bodega.ts                           (refactor + 3 schemas FIFO)
A  INVENTARIO_FIFO_COSTEO_OT.md                                 (este documento)
M  AUDITORIA_TECNICA.md                                         (sección 19)
M  BODEGA_OC_CECO_TRAZABILIDAD.md                               (referencia a FIFO)
```

---

## 13. Riesgos y plan de implementación

| ID | Sev | Riesgo | Mitigación |
|---|---|---|---|
| F01 | 🔴 | mig 55 (OC, recepciones, salidas) NO está aplicada todavía → mig 56 no se puede aplicar sola | **Aplicar primero mig 55 BLOCKS A-F**. Sin esas tablas, mig 56 falla por FK |
| F02 | 🟠 | Capas y `stock_bodega` pueden desincronizarse si una RPC se aplica y otra no | La query de reconciliación de §9.1 debe correr semanalmente. Alerta si diferencia > 0 |
| F03 | 🟠 | Concurrencia: dos salidas simultáneas del mismo producto | Mitigado por `FOR UPDATE` ordenado en `fn_consumir_inventario_fifo` |
| F04 | 🟡 | Productos sin capas (legacy, antes de FIFO) no pueden salir por la nueva RPC | Plan de migración: primero recepciones nuevas crean capas; las antiguas requieren una **carga manual** o conviven con el flujo actual hasta agotar |
| F05 | 🟡 | Override de precio/cantidad puede usarse abusivamente | Auditoría de `recepciones_bodega.observacion LIKE '%OVERRIDE ADMIN%'` semanal |
| F06 | 🟡 | El costo unitario del filtro puede tener centavos (4 decimales). Reportes legibles | UI debe redondear a CLP sin decimales para presentación; BD mantiene 4 decimales |
| F07 | 🟡 | Frontend de recepción/salida no muestra todavía capas ni costo | Implementar incrementalmente (post-piloto) |

### 13.1 Plan de implementación recomendado

**Sprint 1 (1-2 días, staging):**
1. Aplicar mig 55 BLOCKS A-F + J-L en staging.
2. Aplicar mig 56 BLOCKS A-D (tablas + función `fn_consumir_inventario_fifo`).
3. Probar tests 1-6 con datos sintéticos.
4. Si todo OK, aplicar a producción.

**Sprint 2 (1 semana):**
5. Aplicar mig 56 BLOCK E (recepción crea capa) + BLOCK F (salida consume FIFO).
6. Aplicar mig 56 BLOCK G (vistas para finanzas).
7. Capacitar a administrador y bodeguero.
8. Reconciliación inicial: sembrar capas para productos con stock existente (script ad-hoc).

**Sprint 3 (frontend):**
9. UI recepción: mostrar precio OC + cantidad pendiente + "Esta recepción creará una capa valorizada FIFO".
10. UI salida: mostrar "Método: FIFO" + costo estimado pre-submit + costo real post-submit.
11. Ficha producto: lista de capas activas.
12. Ficha OT: costo total real de materiales con drill-down a capas.
13. Reportes: integrar las 4 vistas como tabs en `/dashboard/reportes`.

---

## 14. Verificación

- `npm run typecheck` → ✅ 0 errores.
- `npm run build` → ✅ 37 rutas generadas, build limpio.
- SQL `56_*.sql` → creado, **NO ejecutado** (todo comentado).
- Validaciones Zod → 3 schemas nuevos.
- Frontend → no tocado.
