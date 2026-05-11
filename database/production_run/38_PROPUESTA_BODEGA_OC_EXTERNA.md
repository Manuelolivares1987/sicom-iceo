# Propuesta MIG38 — Bodega OC externa + ítems no inventariables

**Fecha:** 2026-05-10
**Estado:** Propuesta. NO implementado. Requiere aprobación antes de codear.
**Predecesores:** MIG36 (vistas reconciliación), MIG37 (OC + recepción FIFO + salida OT) aplicadas. UI listado/crear OC manual operativa.
**Trigger del cambio de enfoque:** OC ejemplo Pillado N°13559 (VOLVO CHILE SPA) — la OC viene de afuera, contiene servicios además de productos, y debe poder cargarse sin generar stock para los ítems que son servicios.

---

## 1. Diagnóstico del modelo actual (lo que SOPORTA hoy)

### `ordenes_compra`
| Campo | Tipo | Notas |
|-------|------|-------|
| `id` | UUID | PK |
| `numero_oc` | VARCHAR(40) UNIQUE | Hoy se autogenera `OC-YYYY-NNNNN`. Permite recibir un número externo via parámetro de `rpc_crear_orden_compra`. |
| `proveedor_id` | UUID FK | OK |
| `fecha_oc` | DATE | Una sola fecha. |
| `estado` | `estado_oc_enum` | abierta/parcial/cerrada/anulada |
| `monto_total_clp` | NUMERIC(14,0) | Solo total — no separa neto/IVA |
| `observacion` | TEXT | OK |

### `ordenes_compra_items`
| Campo | Tipo | Notas |
|-------|------|-------|
| `producto_id` | UUID FK **nullable** | ✅ Acepta items sin producto |
| `descripcion` | VARCHAR(500) NOT NULL | ✅ Texto libre obligatorio |
| `unidad` | VARCHAR(20) | OK |
| `cantidad_comprada/recibida/pendiente` | NUMERIC | `pendiente` es GENERATED |
| `precio_unitario_clp` | NUMERIC(12,2) | OK |
| `estado` | `estado_oc_item_enum` | pendiente/parcial/completo |
| `observacion` | TEXT | OK |

### RPCs
- **`rpc_crear_orden_compra`** acepta items con `producto_id` NULL si pasás `descripcion`. ✅
- **`rpc_registrar_recepcion_bodega`** exige `producto_id` en cada item (línea: `RAISE EXCEPTION 'item.producto_id es obligatorio'`) ❌ y siempre crea capa FIFO + invoca `rpc_registrar_entrada_inventario`. No tiene rama "documental".

### Storage
Bucket `documentos` ya creado en MIG14D (público, mismo que usa QR checklist y Calama-evidencias con prefijos). **Lo reutilizamos con path prefix `bodega-oc/<oc_id>/<filename>`**, igual que el patrón existente. **No hace falta bucket nuevo.**

### Proveedores
`proveedores.rut` existe ✅. `centros_costo` existe con columna `codigo` ✅.

---

## 2. Gaps específicos respecto al nuevo enfoque

### Faltantes en `ordenes_compra`
- `numero_oc_externo` — número que aparece en el PDF (puede diferir del interno). Permite búsqueda contra el documento físico.
- `documento_url` + `documento_storage_path` — referencia al archivo cargado.
- `fecha_emision` + `fecha_entrega` — la OC ejemplo tiene ambas; hoy solo hay `fecha_oc`.
- `proveedor_rut_snapshot` — RUT al momento de cargar la OC (denormalizado por si el proveedor cambia o no existe en `proveedores`).
- `neto_clp` + `iva_clp` — desglose contable.
- `forma_pago` — texto libre (ej. "30 días").
- `origen` — `'externa'` | `'manual'`. Default `'manual'` para no romper OCs existentes.
- `raw_extracted_json` — JSONB con lo que se extraiga del PDF/OCR/captura asistida.
- UNIQUE compuesto: `(proveedor_id, numero_oc_externo)` WHERE `numero_oc_externo IS NOT NULL` → detecta duplicados.

### Faltantes en `ordenes_compra_items`
- `tipo_item` — enum/check: `inventariable`, `servicio`, `combustible`, `lubricante`, `repuesto`, `consumible`, `activo`, `otro`. Default `inventariable`.
- `requiere_stock` — BOOLEAN default true. La RPC de recepción usa este flag para decidir si crea capa FIFO.
- `centro_costo_id` (FK opcional) — referencia normalizada a `centros_costo`. Si no se encuentra el código en la OC, se deja NULL y se guarda el código texto en…
- `centro_costo_codigo_externo` — texto literal del PDF (ej. "CC-15-15") por si nuestro maestro no lo tiene.
- `codigo_externo` — código del producto en el PDF (ej. "SERSEGCER006"). Permite remapear más adelante sin perder el origen.
- `unidad_externa` — la unidad tal como aparece en el PDF ("UN"), distinta a `unidad` mapeada.
- `raw_item_json` — JSONB del item original.
- Estado adicional `pendiente_mapeo_producto` (extender CHECK) y `conforme_servicio`/`rechazado` (recepción documental).

### Faltantes en RPCs
- `rpc_crear_orden_compra` debe aceptar nuevos campos por item: `tipo_item`, `requiere_stock`, `centro_costo_id`, `centro_costo_codigo_externo`, `codigo_externo`, `unidad_externa`, `raw_item_json`.
- **Nueva RPC** `rpc_importar_orden_compra_externa` (o flag `p_origen='externa'` en la existente) — atómica con cabecera, items, y storage path.
- `rpc_registrar_recepcion_bodega` necesita rama documental: si `item.requiere_stock = false`, **no exige producto_id**, **no crea capa FIFO**, **no invoca entrada legacy**, solo registra `cantidad_recibida` en el item OC y crea fila en `recepciones_bodega_items` con flag `recepcion_documental=true`.

---

## 3. Respuestas directas a tus preguntas

| # | Pregunta | Respuesta |
|---|----------|-----------|
| 1 | `ordenes_compra` permite documento_url? | ❌ no |
| 2 | `ordenes_compra` tiene `numero_oc` externo? | Parcial: usa `numero_oc` como único campo. Conviene separar. |
| 3.1 | `producto_id` nullable? | ✅ sí |
| 3.2 | descripción libre? | ✅ sí (`descripcion` NOT NULL) |
| 3.3 | tipo_item? | ❌ no |
| 3.4 | centro_costo? | ❌ no |
| 3.5 | unidad/precio/total? | ✅ unidad, ✅ precio, total se calcula `cant*precio` (no almacenado por línea) |
| 4 | `rpc_crear_orden_compra` items sin `producto_id`? | ✅ sí |
| 5 | `rpc_registrar_recepcion_bodega` exige `producto_id`? | ❌ sí lo exige — bloquea servicios |
| 6 | Recepción documental sin stock? | ❌ no soportada |
| 7 | Tabla adjuntos/documentos OC? | ❌ no dedicada — propongo columnas en `ordenes_compra` (MVP) |
| 8 | Storage bucket OC? | Reusar `documentos` (existe) con path `bodega-oc/<oc_id>/...` |
| 9 | Detección OC duplicada por número + proveedor? | ❌ no — solo UNIQUE de `numero_oc` interno |

---

## 4. Migración mínima propuesta — MIG38

`database/production_run/38_bodega_oc_externa_servicios.sql`

### BLOQUE 0 — Prechecks
- MIG37 aplicada (las 3 RPCs nuevas existen).
- `proveedores`, `centros_costo`, `ordenes_compra`, `ordenes_compra_items` existen.
- Bucket `documentos` existe.
- Usuario admin o `service_role`.

### BLOQUE 1 — ALTERs aditivos en `ordenes_compra`
```sql
ALTER TABLE ordenes_compra ADD COLUMN IF NOT EXISTS numero_oc_externo VARCHAR(60);
ALTER TABLE ordenes_compra ADD COLUMN IF NOT EXISTS documento_url TEXT;
ALTER TABLE ordenes_compra ADD COLUMN IF NOT EXISTS documento_storage_path TEXT;
ALTER TABLE ordenes_compra ADD COLUMN IF NOT EXISTS origen VARCHAR(20) NOT NULL DEFAULT 'manual'
    CHECK (origen IN ('manual','externa'));
ALTER TABLE ordenes_compra ADD COLUMN IF NOT EXISTS fecha_emision DATE;
ALTER TABLE ordenes_compra ADD COLUMN IF NOT EXISTS fecha_entrega DATE;
ALTER TABLE ordenes_compra ADD COLUMN IF NOT EXISTS proveedor_rut_snapshot VARCHAR(20);
ALTER TABLE ordenes_compra ADD COLUMN IF NOT EXISTS neto_clp NUMERIC(14,0);
ALTER TABLE ordenes_compra ADD COLUMN IF NOT EXISTS iva_clp NUMERIC(14,0);
ALTER TABLE ordenes_compra ADD COLUMN IF NOT EXISTS forma_pago VARCHAR(80);
ALTER TABLE ordenes_compra ADD COLUMN IF NOT EXISTS raw_extracted_json JSONB;

-- UNIQUE parcial (no rompe filas existentes con NULL)
CREATE UNIQUE INDEX IF NOT EXISTS uq_oc_externa_proveedor
    ON ordenes_compra (proveedor_id, numero_oc_externo)
    WHERE numero_oc_externo IS NOT NULL;
```

### BLOQUE 2 — ALTERs aditivos en `ordenes_compra_items`
```sql
ALTER TABLE ordenes_compra_items ADD COLUMN IF NOT EXISTS tipo_item VARCHAR(20) NOT NULL DEFAULT 'inventariable'
    CHECK (tipo_item IN ('inventariable','servicio','combustible','lubricante','repuesto','consumible','activo','otro'));
ALTER TABLE ordenes_compra_items ADD COLUMN IF NOT EXISTS requiere_stock BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE ordenes_compra_items ADD COLUMN IF NOT EXISTS codigo_externo VARCHAR(60);
ALTER TABLE ordenes_compra_items ADD COLUMN IF NOT EXISTS unidad_externa VARCHAR(30);
ALTER TABLE ordenes_compra_items ADD COLUMN IF NOT EXISTS centro_costo_id UUID REFERENCES centros_costo(id);
ALTER TABLE ordenes_compra_items ADD COLUMN IF NOT EXISTS centro_costo_codigo_externo VARCHAR(40);
ALTER TABLE ordenes_compra_items ADD COLUMN IF NOT EXISTS raw_item_json JSONB;

-- Cruzar tipo_item con requiere_stock: si tipo = servicio/activo/otro -> requiere_stock=false
-- (no constraint duro; lo aplican las RPCs para no romper OCs existentes en backfill)
```

### BLOQUE 3 — Backfill conservador
- `origen = 'manual'` para todas las OCs existentes (default).
- `tipo_item = 'inventariable'` y `requiere_stock = true` para items existentes (default).
- `unidad_externa = unidad` para items existentes.
- No tocar `numero_oc_externo` (queda NULL en OCs internas).

### BLOQUE 4 — Nueva RPC `rpc_importar_orden_compra_externa`
Wrap de la lógica de creación con:
- `p_numero_oc_externo` (obligatorio)
- `p_proveedor_rut_snapshot`
- `p_fecha_emision`, `p_fecha_entrega`
- `p_neto_clp`, `p_iva_clp`, `p_forma_pago`
- `p_documento_url`, `p_documento_storage_path`
- `p_raw_extracted_json`
- `p_items` JSONB con campos extendidos: `codigo_externo`, `descripcion`, `unidad_externa`, `cantidad_comprada`, `precio_unitario_clp`, `tipo_item`, `requiere_stock`, `centro_costo_codigo_externo`, `raw_item_json`

Detección de duplicado: si ya existe `(proveedor_id, numero_oc_externo)`, RAISE con mensaje claro.
Autogen `numero_oc` interno (igual que hoy).
`origen = 'externa'` automático.

### BLOQUE 5 — Extender `rpc_registrar_recepcion_bodega` (rama documental)
```
Por cada item recibido:
  SELECT requiere_stock, tipo_item FROM ordenes_compra_items WHERE id = oc_item_id;
  IF requiere_stock = FALSE THEN
    -- Rama documental
    UPDATE ordenes_compra_items SET cantidad_recibida = cantidad_recibida + qty
    INSERT recepciones_bodega_items con producto_id NULL + costo_unitario=0 + observacion='recepcion documental: <conforme|rechazado>'
    Continue (no crea capa, no invoca entrada legacy)
  ELSE
    -- Rama actual: requiere producto_id, crea capa FIFO, invoca entrada legacy
  END IF
```

Para que la rama documental funcione, `recepciones_bodega_items.producto_id` debe permitir NULL. Verificar — si hoy es NOT NULL, agregar `ALTER COLUMN producto_id DROP NOT NULL` (aditivo seguro).

### BLOQUE 6 — Storage policy (si no aplica ya al bucket `documentos`)
Ya existe policy permisiva en `documentos`. Verificar y, si hace falta, agregar policy específica para paths `bodega-oc/*`.

### BLOQUE 7 — Validaciones post
- 14 columnas nuevas presentes.
- UNIQUE index activo.
- RPCs nuevas/actualizadas existen.
- Reconciliación stock vs FIFO sigue cuadrada (sanidad).

---

## 5. UI mínima para importar OC externa

### Ruta
`/dashboard/abastecimiento/oc/importar`

### Cambio en `/dashboard/abastecimiento/oc`
Reemplazar botón único "Nueva OC" por dos botones:
- **"Importar OC externa"** (primario) → `/oc/importar`
- **"Crear OC manual"** (secundario, menor visibilidad) → `/oc/nueva` (existente)

### Flujo `/oc/importar` (wizard de 4 pasos)

**Paso 1 — Documento**
- Input file (PDF/JPG/PNG/XLSX). Subida directa a Supabase Storage `documentos` con path `bodega-oc/<oc_id_temp>/<filename>`.
- Almacena URL en estado local.
- Botón "Siguiente" habilitado tras carga exitosa.

**Paso 2 — Cabecera**
Campos editables:
- N° OC externo (obligatorio)
- Proveedor (selector con buscador; opción "Crear proveedor nuevo" si no existe → modal mini)
- RUT proveedor (auto-completa del seleccionado; editable para snapshot)
- Fecha emisión / Fecha entrega
- Forma de pago (texto libre)
- Neto / IVA / Total (input numérico)
- Observación

**Paso 3 — Items (tabla editable)**
Cada fila:
- Código externo (texto libre del PDF)
- Descripción (NOT NULL)
- Cantidad / Unidad
- Centro de costo (selector + texto libre fallback)
- Precio unitario / Total línea
- **Tipo ítem** (select): `inventariable | servicio | combustible | lubricante | repuesto | consumible | activo | otro` — al cambiar a `servicio/activo/otro`, deshabilita selector de producto y setea `requiere_stock=false` con badge gris.
- **Producto mapeado** (selector buscable, opcional para tipo no inventariable) → si tipo requiere_stock pero no se mapea, marcar fila amarilla "pendiente_mapeo_producto" (se puede guardar; solo no permite recepción de stock hasta resolver).

Botón "Agregar fila" y "Eliminar fila".

**Paso 4 — Validación + Guardar**
Pantalla resumen:
- Total ítems vs `neto_clp` cabecera (tolerancia $1 por redondeo).
- IVA calculado vs IVA cabecera.
- Total = neto + IVA cabecera vs (sum ítems + IVA).
- Cuenta de items por tipo (3 inventariables, 2 servicios, etc.).
- Cuenta de items pendientes de mapeo.
- Botón "Guardar OC" — invoca `rpc_importar_orden_compra_externa` y al éxito redirige a `/oc/[id]`.

### Cambios en `/oc/[id]` (detalle)
- Botón "Ver documento original" (si `documento_url`).
- Badge `origen` (externa/manual).
- Mostrar `numero_oc_externo` arriba del interno.
- Mostrar neto/IVA/total y forma de pago.
- En tabla items: badges por `tipo_item` (inventariable/servicio/etc) + flag "Requiere stock" + alertas "Pendiente mapeo".
- Acciones por item (próxima etapa, no en esta mig):
  - **Mapear producto** (si pendiente).
  - **Recepcionar stock** (si requiere_stock + producto mapeado).
  - **Conformar servicio** (si requiere_stock=false).
  - **Rechazar item**.

### Sidebar
Reemplazar único item por:
- Órdenes de Compra (listado)
- Importar OC externa
- (Crear OC manual ya accesible desde el listado)

---

## 6. Riesgos

### Técnicos
| Riesgo | Mitigación |
|--------|------------|
| Items existentes (pre-MIG38) sin `tipo_item` ni `requiere_stock` | Default `inventariable` + `true` en el ADD COLUMN. Comportamiento idéntico al actual. |
| Recepción documental con producto_id NULL en `recepciones_bodega_items` | Solo agregar `ALTER COLUMN producto_id DROP NOT NULL` si hoy es NOT NULL. Verificar y documentar. |
| OC duplicada por mismo `numero_oc_externo` | UNIQUE parcial bloquea. Mensaje claro. |
| Diferencia entre suma items y total cabecera | Validación cliente con tolerancia $1; warning visible. No bloquea guardar (queda en `raw_extracted_json`). |
| Captura asistida sin OCR → ingreso manual lento | Aceptable para MVP. Reusable con OCR/IA después si se conecta a `raw_extracted_json`. |

### Operacionales
| Riesgo | Mitigación |
|--------|------------|
| Operador clasifica mal `tipo_item` | Defaults inteligentes: si producto mapeado tiene `categoria='combustible'` → tipo `combustible` y `requiere_stock=true`; si descripción contiene "servicio"/"certificación" → sugerir `servicio` con `requiere_stock=false`. |
| Centro de costo del PDF no existe en `centros_costo` | Guardar texto literal en `centro_costo_codigo_externo`; resolver `centro_costo_id` después. |
| Proveedor de la OC no existe | Modal "Crear proveedor" inline; o guardar `proveedor_rut_snapshot` y obligar a crear/mapear antes de recepcionar. |

### Conformidad
- Toda OC externa debe tener documento adjunto. Validación obligatoria.
- Trazabilidad: `documento_storage_path` queda inmutable.

---

## 7. Qué queda FUERA de esta mig 38

- OCR/IA real (queda preparada arquitectura: `raw_extracted_json` + helper `parseOCText` en frontend).
- Multi-archivo por OC (factura, guía, etc.). Por ahora 1 documento. Si se necesita más, tabla `ordenes_compra_documentos` aparte en mig 39.
- Recepción real con CECO por item (la salida ya tiene CECO; la recepción heredará `centro_costo_id` del item).
- UI de recepción diferenciada (stock vs documental) — etapa 2D-3+ tras aprobar esta mig.
- UI mapeo masivo de productos pendientes (futuro).
- Aprobación/firma del comprador (workflow externo).
- Notificaciones (cuando llega OC nueva, cuando se recepciona, etc.).

---

## 8. Plan de implementación por etapas

| Etapa | Entregable | Aprobación previa |
|-------|------------|-------------------|
| **38-A** | MIG38 SQL: ALTERs aditivos + UNIQUE index + nueva RPC `rpc_importar_orden_compra_externa` + extensión `rpc_registrar_recepcion_bodega` (rama documental) + validaciones | Tu autorización tras leer esta propuesta |
| **38-B** | Service+hook `bodega-oc-importar.ts`/`use-bodega-oc-importar.ts` + Wizard `/oc/importar` (4 pasos) + cambios en `/oc` y `/oc/[id]` | Tras 38-A en prod OK |
| **38-C** | Captura asistida manual con campos editables (sin OCR) + validación de totales + manejo de proveedor nuevo + CC desconocido | Junto a 38-B o separado |
| **38-D** | UI recepción diferenciada: stock vs conformidad servicio | Tras 38-C |
| **38-E** | (Opcional, futuro) OCR/IA conectado a `parseOCText` que llena el wizard | Mucho después |

### Smoke test 38-A
1. Aplicar mig.
2. Ejecutar `rpc_importar_orden_compra_externa` con el JSON de la OC ejemplo 13559:
   ```json
   {
     "numero_oc_externo": "13559",
     "proveedor": "VOLVO CHILE SPA",
     "rut": "76.284.920-8",
     "items": [{ "codigo_externo":"SERSEGCER006","descripcion":"SERVICIO CERTIFICACION OPERATIVIDAD","cantidad":1,"unidad":"UN","precio":290700,"centro_costo":"CC-15-15","tipo_item":"servicio","requiere_stock":false }],
     "neto":290700,"iva":55233,"total":345933,"forma_pago":"30 días"
   }
   ```
3. Verificar: OC creada, item sin capa FIFO, sin tocar stock_bodega.
4. Re-ejecutar mismo input → debe RAISE por duplicado (UNIQUE).
5. Reconciliación: 0 desviados.

---

## 9. Resumen ejecutivo

El modelo actual permite OCs simples con producto y descripción libre, pero **no separa OC externa de OC manual, no clasifica items por tipo (inventariable vs servicio), no soporta recepción documental, y no guarda el documento original**. MIG38 agrega 14 columnas aditivas (11 a `ordenes_compra`, 7 a `items`), una RPC nueva (`rpc_importar_orden_compra_externa`), y extiende la RPC de recepción para distinguir rama documental de rama FIFO. Sin OCR — captura asistida manual con campos editables y validación de totales. **No toca stock**, no rompe la UI actual de "Crear OC manual", y mantiene reconciliación stock vs FIFO intacta. Riesgo controlado por prechecks + defaults conservadores en el backfill.

---

**Próximo paso pendiente de tu autorización:** etapa 38-A (mig SQL). Si aprobás, codifico `database/production_run/38_bodega_oc_externa_servicios.sql` con los 7 bloques descritos. No avanzo a UI (38-B+) hasta que la mig esté aplicada y verificada.
