# BODEGA — OC, CECO y trazabilidad clase mundial

> **Última actualización:** 2026-04-30 — FASE 5.3
> **Audiencia:** administrador, jefe de mantenimiento, bodeguero, operador de abastecimiento, auditor.
> **Estado:** SQL propuesto en `database/schema/55_*.sql` (NO ejecutado). Schemas Zod listos en `validations/bodega.ts`. Frontend pendiente — implementación incremental.

---

## 1. Resumen del flujo objetivo

```
              PROVEEDOR (ENEX, ESMAX, repuestero, etc.)
                          │
                          ▼
                ╔══════════════════╗
                ║  ORDEN DE COMPRA ║   (numero_oc, items, monto)
                ║  estado: abierta ║
                ╚════════╤═════════╝
                         │
        ┌────────────────┼─────────────────┐
        ▼                ▼                 ▼
  ┌────────────┐   ┌────────────┐    ┌────────────┐
  │ RECEPCIÓN  │   │ RECEPCIÓN  │    │ RECEPCIÓN  │
  │ parcial 1  │   │ parcial 2  │    │ parcial N  │
  │ folio REC  │   │ folio REC  │    │ folio REC  │
  └────┬───────┘   └────┬───────┘    └────┬───────┘
       │                │                  │
       └────────┬───────┴──────────────────┘
                ▼
       Stock bodega aumentado por cada recepción
       OC pasa a "parcial" → "cerrada" cuando se completa
                │
                ▼
          ╔═══════════════════╗
          ║  SALIDA DE BODEGA ║   ← CECO obligatorio
          ║  folio SAL        ║      OT opcional (si tipo=ot)
          ║  motivo + persona ║      Persona obligatoria (si tipo=persona)
          ╚═══════════════════╝
                │
                ▼
       Stock bodega descontado
       Kardex y auditoría actualizados
```

---

## 2. Modelo de datos propuesto (NO ejecutado)

Migración: `database/schema/55_bodega_combustible_oc_ceco_trazabilidad.sql`. Todo comentado, listo para revisión bloque por bloque.

| Tabla | Rol | Bloque SQL |
|---|---|---|
| `proveedores` | Maestro de proveedores (ENEX, ESMAX, etc.) | B |
| `centros_costo` | Maestro de CECO | C |
| `ordenes_compra` | OC con estado abierta/parcial/cerrada/anulada | D |
| `ordenes_compra_items` | Items con cantidad_pendiente generada | D |
| `recepciones_bodega` | Cabecera de recepción parcial | E |
| `recepciones_bodega_items` | Items recibidos por recepción | E |
| `salidas_bodega` | Salida con CECO + OT + persona | F |
| `salidas_bodega_items` | Items salidos | F |

**Tablas reutilizadas (no se duplican):**
- `productos`, `bodegas`, `stock_bodega`, `movimientos_inventario`, `kardex` (mig 03).
- `ordenes_trabajo` (mig 03) — referenciada por `salidas_bodega.ot_id`.
- `usuarios_perfil` — referenciada por `solicitado_por`, `entregado_a_perfil_id`, `autorizado_por`.

---

## 3. Recepción parcial contra OC — cómo funciona

### 3.1 Reglas de negocio

1. Una OC nace en estado `abierta` con N items.
2. Cada `ordenes_compra_items.cantidad_pendiente` es **columna generada** = `cantidad_comprada - cantidad_recibida`.
3. Cada recepción puede cubrir cualquier subconjunto de items con cualquier cantidad ≤ pendiente.
4. **`UNIQUE (proveedor_id, documento_proveedor_tipo, documento_proveedor_numero)`** previene duplicar guías.
5. Al recibir, la RPC `rpc_registrar_recepcion_bodega`:
   - Genera folio interno `REC-YYYYMM-XXXXX`.
   - Inserta cabecera + items.
   - Llama a `rpc_registrar_entrada_inventario` (existente) por cada item → aumenta `stock_bodega` y crea kardex.
   - Suma `cantidad_recibida` en `ordenes_compra_items`.
   - Actualiza `ordenes_compra_items.estado` a `parcial` o `completo`.
   - Actualiza `ordenes_compra.estado` a `parcial` o `cerrada` según los items.
6. Si se intenta recibir más que `cantidad_pendiente`, **se bloquea** salvo que el rol sea `administrador` y pase `p_permite_sobrecantidad=true` (justifica explícitamente).

### 3.2 Datos del documento físico capturados

| Campo | Origen del dato |
|---|---|
| `documento_proveedor_tipo` | guía / factura / vale / boleta / otro |
| `documento_proveedor_numero` | Número del documento físico (clave única por proveedor) |
| `evidencia_url` | Foto/PDF de la guía (subida a Storage) |
| `recibido_por` | UUID del bodeguero |
| `fecha_recepcion` | Timestamp del registro |
| Por item: `lote`, `fecha_vencimiento`, `costo_unitario_clp` | Captura para CPP y FIFO |

### 3.3 Folio interno

Formato: **`REC-YYYYMM-XXXXX`** (por mes, secuencial).
Generado por `fn_generar_folio_recepcion_bodega()` con sequence `seq_folio_recepcion_bodega`.

---

## 4. Salida con CECO + Persona + OT — cómo funciona

### 4.1 Tipos de salida

| `tipo_salida` | Caso de uso | Requeridos |
|---|---|---|
| `ot` | Material despachado para una OT específica | `ot_id` + `ceco_id` |
| `persona` | Material entregado a una persona (no asociado a OT) | `entregado_a` o `entregado_a_perfil_id` + `ceco_id` |
| `ceco` | Cargo directo a CECO (consumibles, EPP, etc.) | `ceco_id` |
| `venta` | Venta a tercero | `ceco_id` + identificación cliente en `motivo`/`observacion` |
| `ajuste_autorizado` | Ajuste con autorización formal | `ceco_id` + `autorizado_por` (administrador) |

### 4.2 Reglas

1. **CECO es OBLIGATORIO** para toda salida. No hay excepciones.
2. La RPC `rpc_registrar_salida_bodega`:
   - Genera folio interno `SAL-YYYYMM-XXXXX`.
   - Valida tipo + campos requeridos.
   - Inserta cabecera + items.
   - Llama a `rpc_registrar_salida_inventario` (existente) por cada item → descuenta stock.
   - **Bloquea stock negativo** automáticamente (la RPC existente lo valida).
3. Auditoría automática vía `audit_trigger`.

### 4.3 Folio interno

Formato: **`SAL-YYYYMM-XXXXX`**.

---

## 5. Validaciones Zod listas

Archivo: `frontend/src/validations/bodega.ts`.

| Schema | Cubre |
|---|---|
| `proveedorSchema` | Alta de proveedor (codigo, nombre, RUT, tipo, contacto) |
| `centroCostoSchema` | Alta de CECO (código, nombre, área, contrato/faena) |
| `ocSchema` + `ocItemSchema` | Crear OC con items (al menos 1) |
| `recepcionBodegaSchema` + `recepcionItemSchema` | Recepción parcial con evidencia obligatoria |
| `salidaBodegaSchema` + `salidaItemSchema` | Salida con CECO obligatorio + reglas según tipo |

### 5.1 Reglas críticas validadas en Zod

- **CECO obligatorio** en toda salida (`ceco_id: z.string().uuid('CECO es obligatorio...')`).
- **Salida tipo OT** exige `ot_id` (refine).
- **Salida tipo persona** exige `entregado_a` o `entregado_a_perfil_id` (refine).
- **Cantidad** siempre `positive()` (no permite 0 ni negativos).
- **Motivo** mínimo 5 caracteres en salidas.
- **Evidencia** URL válida en recepciones (`z.string().url(...)`).
- **OC** debe tener al menos 1 item.

---

## 6. Roles responsables

> Verificado contra `frontend/src/hooks/use-permissions.ts` + RPCs propuestas con role-check.

| Acción | Roles autorizados | Defensa |
|---|---|---|
| Crear OC | administrador, bodeguero, jefe_mantenimiento, subgerente_operaciones | RPC propuesta (BLOCK K) |
| Recibir contra OC | administrador, bodeguero, jefe_mantenimiento, supervisor, subgerente_operaciones | RPC propuesta |
| Recibir sobrecantidad | **solo** administrador | RPC propuesta con flag explícito |
| Registrar salida | administrador, bodeguero, jefe_mantenimiento, supervisor, planificador, subgerente_operaciones | RPC propuesta (BLOCK L) |
| Crear/editar proveedor | administrador, subgerente_operaciones | UI futura + RLS |
| Crear/editar CECO | administrador, subgerente_operaciones | UI futura + RLS |
| Anular recepción/salida | administrador | UI futura |

---

## 7. Auditoría

Toda operación queda auditada por:

1. **`auditoria_eventos`** — trigger automático de mig 09 captura `INSERT/UPDATE/DELETE` con usuario, tabla, valores antes/después.
2. **`folio_recepcion`, `folio_salida`** — folios secuenciales únicos imposibles de duplicar.
3. **`created_by`, `recibido_por`, `solicitado_por`, `entregado_a_perfil_id`, `autorizado_por`** — captura de actores en cada paso.
4. **`evidencia_url`** — foto/PDF persistente en Storage Supabase.
5. **Kardex** — generado automáticamente por `rpc_registrar_entrada_inventario` y `rpc_registrar_salida_inventario`.

---

## 8. Pruebas manuales sugeridas (cuando se aplique SQL)

### Test 1 — Recepción parcial
1. Crear OC con 2 items: producto A (10 un), producto B (5 un).
2. Recepción 1: producto A 7 un, producto B 5 un. Adjuntar foto guía.
3. Verificar:
   - `ordenes_compra_items` para producto A: `cantidad_recibida=7`, `pendiente=3`, `estado=parcial`.
   - `ordenes_compra_items` para producto B: `estado=completo`.
   - `ordenes_compra.estado=parcial`.
   - `stock_bodega` aumentó +7 y +5.
4. Recepción 2: producto A 3 un. Otra guía.
5. Verificar OC pasa a `cerrada`.

### Test 2 — Bloqueo de sobrecantidad
1. Sobre la misma OC, intentar recibir producto A con 5 un más (ya completo).
2. Como `bodeguero` → debe fallar con `RAISE EXCEPTION`.
3. Como `administrador` con `p_permite_sobrecantidad=true` → debe pasar pero registrarse en observación.

### Test 3 — Salida tipo OT
1. Crear OT manual.
2. Salida: tipo=OT, ot_id=la OT, ceco_id=CECO_TALLER, motivo="Material para reparación".
3. Verificar:
   - `salidas_bodega.folio_salida` con formato `SAL-...`.
   - Stock descontado.
   - Si stock < cantidad → `RAISE EXCEPTION 'Stock insuficiente...'` (validación RPC existente).

### Test 4 — Salida tipo persona
1. Tipo=persona, ceco_id=CECO_OPS, entregado_a="Eduardo Apellido", motivo="Herramientas para terreno".
2. Si falta `entregado_a` → Zod debe rechazar antes de submit.

### Test 5 — Documento duplicado
1. Recepción 1 con `proveedor=ENEX, tipo=guia, numero=12345`.
2. Recepción 2 con los mismos datos → debe fallar por `UNIQUE (proveedor_id, tipo, numero)`.

---

## 9. Pendientes / próximos pasos

| ID | Acción | Prioridad |
|---|---|---|
| B01 | Aplicar BLOCK A–E del SQL `55_*.sql` (proveedores, CECO, OC, recepciones) | Alta — antes de operación real con OC |
| B02 | Aplicar BLOCK F del SQL (salidas con CECO) | Alta — clave para trazabilidad operativa |
| B03 | Aplicar BLOCK J (folios) y BLOCK K-L (RPCs) | Alta |
| B04 | Seed inicial de proveedores (ENEX, ESMAX, COPEC, etc.) | Alta |
| B05 | Seed inicial de CECO (al menos: TALLER-CQB, TALLER-CAL, OPERACIONES, COMERCIAL, ADMIN) | Alta |
| B06 | UI de OC: pantalla `/dashboard/inventario/oc` con creación + listado | Media |
| B07 | UI de recepción: `/dashboard/inventario/recepcion` con selección de OC + items pendientes + foto | Media |
| B08 | UI de salida con CECO: refactor de `/dashboard/inventario/salida` para usar `salidaBodegaSchema` | Alta |
| B09 | Migrar formularios Inventario a RHF + zodResolver | Media (sigue plan FASE 6) |
| B10 | Capacitar a Gustavo (bodega) en flujo OC + recepción parcial + salida con CECO | Alta — antes de producción real |

---

## 10. Verificación

- `npm run typecheck` → ✅ 0 errores.
- `npm run build` → ✅ 37 rutas generadas, build limpio.
- SQL `55_*.sql` → creado, **NO ejecutado**.
- Validaciones Zod → 6 schemas en `bodega.ts` + 4 schemas en `combustible.ts` (extensión).
