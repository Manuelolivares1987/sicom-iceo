# Importación de Checklists de Flota — SICOM-ICEO

> **Última actualización:** 2026-04-29 — FASE 5.2
> **Audiencia:** administrador del sistema, jefe de taller, prevencionista.
> **Objetivo:** transformar los checklists que la empresa entrega en Excel/Word/PDF a plantillas almacenadas en `checklist_templates` para que sean usadas automáticamente al crear OTs y para verificación de disponibilidad.

---

## 1. Por qué importar checklists a la BD

- Las plantillas viven en la tabla `checklist_templates` con items en formato JSONB.
- Cuando se crea una OT manual sin plan PM, la RPC `rpc_crear_ot` busca la plantilla activa para ese `tipo_ot` y copia los items a `checklist_ot` (mig 22).
- En la verificación de disponibilidad (ready-to-rent), `fn_iniciar_verificacion_disponibilidad` también copia los items del checklist correspondiente (mig 45).
- Esto significa: **mantener el checklist actualizado en BD es la forma correcta de actualizar el flujo operativo**, sin tocar código React.

---

## 2. Formato recomendado para cargar checklists (CSV / Excel)

Cada plantilla es un **archivo** o **hoja**. Cada fila es un ítem.

### 2.1 Columnas mínimas obligatorias

| categoria_equipo | tipo_checklist | orden | item | critico | requiere_foto | tipo_respuesta |
|---|---|---|---|---|---|---|
| `camion_cisterna` | `verificacion_disponibilidad` | 1 | Verificar nivel de aceite motor | TRUE | FALSE | `ok_no_ok_na` |
| `camion_cisterna` | `verificacion_disponibilidad` | 2 | Verificar presión neumáticos delanteros | TRUE | TRUE | `ok_no_ok_na` |
| `camion_cisterna` | `verificacion_disponibilidad` | 3 | Verificar bombas y mangueras (sin fugas) | TRUE | TRUE | `ok_no_ok_na` |
| `camion_cisterna` | `preventivo` | 1 | Cambio de filtro aire | TRUE | FALSE | `ok_no_ok_na` |
| `camion_cisterna` | `preventivo` | 2 | Lectura horómetro | TRUE | TRUE | `numero` |

### 2.2 Diccionario de columnas

| Columna | Tipo | Ejemplos válidos | Notas |
|---|---|---|---|
| `categoria_equipo` | string | `camion_cisterna`, `lubrimovil`, `pistola_captura`, `equipo_bombeo`, `surtidor` | Debe coincidir con valores de `tipo_activo_enum`. Si la plantilla aplica a varios tipos, replicar fila por tipo. |
| `tipo_checklist` | string | `preventivo`, `correctivo`, `inspeccion`, `verificacion_disponibilidad`, `lubricacion`, `abastecimiento` | Debe coincidir con `tipo_ot_enum`. |
| `orden` | entero | 1, 2, 3, ... | Define el orden visual del ítem en el checklist. |
| `item` | string | "Verificar nivel de aceite motor" | Texto que el técnico ve. Máx 200 caracteres. |
| `critico` | bool | TRUE/FALSE | Si es TRUE, no se puede aprobar el checklist con este ítem en estado "no_ok". |
| `requiere_foto` | bool | TRUE/FALSE | Si es TRUE, el técnico no puede marcar "ok" sin adjuntar foto. |
| `tipo_respuesta` | string | `ok_no_ok_na`, `texto`, `numero`, `foto` | Cómo se valida el ítem. Por defecto: `ok_no_ok_na`. |

> **Nota actual:** la tabla `checklist_templates` (mig 22) usa los campos `obligatorio` y `requiere_foto` y un `descripcion`. La columna `critico` se mapea a `obligatorio`. Los campos `categoria_equipo` y `tipo_respuesta` están **propuestos** en `54_*.sql` Block D para versionado avanzado, pero **aún no aplicados**. Para el piloto se mantiene la estructura actual (obligatorio + requiere_foto).

---

## 3. Procedimiento paso a paso para importar

### Caso A — Empresa entrega checklist en Excel/Word

#### Paso 1 — Convertir a tabla con las columnas de §2.1

Abre el archivo entregado, copia los ítems a una hoja nueva con esta estructura:

| categoria_equipo | tipo_checklist | orden | item | critico | requiere_foto |
|---|---|---|---|---|---|
| ... | ... | 1..N | (un ítem por fila) | TRUE/FALSE | TRUE/FALSE |

Guarda como `.csv` con coma como separador, codificación UTF-8.

#### Paso 2 — Convertir a JSON manualmente (copy-paste rápido)

Abre el CSV en cualquier conversor online a JSON, o escribe a mano:

```json
[
  {"orden": 1, "descripcion": "Verificar nivel de aceite motor",          "obligatorio": true,  "requiere_foto": false},
  {"orden": 2, "descripcion": "Verificar presión neumáticos delanteros",  "obligatorio": true,  "requiere_foto": true},
  {"orden": 3, "descripcion": "Verificar bombas y mangueras (sin fugas)", "obligatorio": true,  "requiere_foto": true}
]
```

#### Paso 3 — Insertar en la BD

**Opción A (recomendada para no técnicos):** desde la UI.

1. Login como administrador en `/dashboard/admin/checklist-templates`.
2. Bloque "Crear nueva plantilla" → seleccionar `tipo_ot`, escribir nombre, click **Crear plantilla vacía**.
3. La plantilla aparece abajo con 0 ítems → click **Agregar ítem** por cada fila del Excel.
4. Marcar **Obligatorio** y **Requiere foto** según corresponda.
5. **Guardar cambios**.

**Opción B (rápida para checklists de muchos ítems):** desde SQL.

Editar `database/schema/54_flota_estado_programado_checklists.sql` BLOCK C.1, descomentar y ajustar:

```sql
INSERT INTO checklist_templates (tipo_ot, nombre, descripcion, items, activo)
VALUES (
    'verificacion_disponibilidad'::tipo_ot_enum,
    'Checklist Ready-to-Rent Camión Cisterna v1',
    'Entregado por cliente CMP en mar-2026',
    '[ ... pegar JSON del paso 2 ... ]'::jsonb,
    true
);
```

Ejecutar en Supabase → SQL Editor.

#### Paso 4 — Probar antes de usar

Después de insertar, ejecutar **siempre** estas verificaciones:

```sql
-- Confirmar que la plantilla quedó con los ítems esperados
SELECT id, tipo_ot, nombre, jsonb_array_length(items) AS n_items, activo
  FROM checklist_templates
 WHERE nombre LIKE '%Camión Cisterna%';

-- Si tiene los ítems esperados, hacer una prueba real:
-- 1. Crear una OT manual de tipo verificacion_disponibilidad
-- 2. Confirmar que checklist_ot tiene los mismos N items
-- 3. Si OK, listo
```

---

### Caso B — Empresa entrega checklist en PDF (formato no estructurado)

1. Pasar el PDF por OCR (Adobe Acrobat, ABBYY, Google Drive abrir como Doc).
2. Limpiar texto a una tabla en Excel con las columnas de §2.1.
3. Continuar con Caso A desde Paso 2.

---

## 4. Versionado de checklists

Cuando el cliente actualiza el checklist:

### 4.1 Versionado simple (recomendado para piloto)

1. **Desactivar** la plantilla anterior:
```sql
UPDATE checklist_templates
   SET activo = false, updated_at = NOW()
 WHERE id = 'UUID-PLANTILLA-VIEJA';
```

2. **Crear** la nueva como una nueva fila (Caso A § Paso 3).

→ Las OTs ya creadas con la versión vieja **siguen** con sus ítems originales en `checklist_ot`. Solo las OTs nuevas tomarán los ítems de la plantilla nueva.

### 4.2 Versionado avanzado (post-piloto)

Si se requiere trazabilidad estricta de versiones (auditoría SEC/SEREMI), aplicar `BLOCK D` de `54_flota_estado_programado_checklists.sql` que agrega:
- columna `version` (entero)
- columna `template_padre_id` (FK a versión anterior)
- columna `valido_desde` / `valido_hasta` (fechas)
- columna `categoria_equipo`

→ Discutir con DBA antes de aplicar; afecta consultas existentes.

---

## 5. Quién puede actualizar checklists

> Verificado contra `frontend/src/hooks/use-permissions.ts`.

| Rol | Crear plantilla | Editar plantilla | Desactivar | Cargar masivo SQL |
|---|---|---|---|---|
| `administrador` | ✅ | ✅ | ✅ | ✅ |
| `gerencia` | ❌ | ❌ | ❌ | ❌ (solo lectura) |
| `subgerente_operaciones` | ⚠️ vía RLS | ⚠️ vía RLS | ❌ | ❌ |
| `jefe_mantenimiento` | ⚠️ vía RLS | ⚠️ vía RLS | ❌ | ❌ |
| `prevencionista` | ⚠️ vía RLS | ⚠️ vía RLS | ❌ | ❌ |
| Otros | ❌ | ❌ | ❌ | ❌ |

⚠️ **Nota crítica:** la página `/dashboard/admin/checklist-templates` está dentro del módulo `admin`, que requiere permiso `view`. Hoy el sidebar la oculta para roles sin permiso, pero **la URL es accesible** si alguien la conoce. La defensa real depende de RLS Supabase sobre `checklist_templates`. Auditar políticas en FASE 5 (`SUPABASE_AUDIT.md`) antes de habilitar el rol no-admin para edición.

---

## 6. Cómo probar un checklist nuevo antes de usarlo en operación

1. **Crear plantilla** (paso anterior).
2. **Crear una OT de prueba** desde la UI:
   - `/dashboard/ordenes-trabajo` → **Crear OT**.
   - Tipo: el mismo `tipo_checklist` que usaste.
   - Activo: cualquiera de prueba.
   - Asignar a ti mismo.
3. **Abrir la OT** → confirmar que aparecen los N ítems del checklist en orden.
4. **Marcar todos los ítems** y subir fotos donde corresponda.
5. **Confirmar que la OT pasa a `ejecutada_ok`** sin errores.
6. Si todo OK, **cancelar** la OT (no `ejecutada` real) si fue solo prueba: `/dashboard/ordenes-trabajo/[id]` → cambiar a estado `cancelada` con motivo "Prueba checklist nuevo".
7. **Listo** — la plantilla está validada y se puede usar en operación real.

---

## 7. Errores frecuentes y cómo resolverlos

| Síntoma | Causa probable | Solución |
|---|---|---|
| Crear OT no copia los ítems del checklist | No hay plantilla activa para ese `tipo_ot` | Confirmar `SELECT * FROM checklist_templates WHERE tipo_ot = '...' AND activo = true;` |
| Aparecen ítems duplicados | Hay múltiples plantillas activas para el mismo `tipo_ot` | Desactivar las que no apliquen: `UPDATE ... SET activo = false WHERE id != 'UUID-CORRECTO';` |
| Items en orden incorrecto | El campo `orden` no es secuencial | Editar la plantilla desde UI (los items se renumeran al guardar) |
| No se puede marcar "ok" | Es ítem `requiere_foto = true` y no hay foto | Subir foto antes de marcar |
| No se puede aprobar verificación | Hay ítem `obligatorio = true` con resultado `no_ok` | Corregir el problema físicamente o marcar `na` si no aplica |

---

## 8. Buenas prácticas operativas

- **Una plantilla activa por `tipo_ot`** en piloto. Múltiples plantillas activas confunden la lógica de copia automática.
- **Nombrar con versión y fecha** en el campo `nombre`: ej. `"Checklist Disponibilidad Camión v3 — 2026-04"`.
- **Probar siempre** con una OT real (en estado cancelada) antes de habilitar en operación.
- **No editar ítems mientras hay OTs en ejecución** con esa plantilla — los cambios afectan futuras OTs, no las en curso.
- **Documentar el origen** del checklist en `descripcion`: "Entregado por cliente XYZ, firmado SEC, ref. doc. ABC".

---

## 9. Roadmap sugerido (post-piloto)

- [ ] Aplicar BLOCK D de `54_*.sql` para versionado formal.
- [ ] Agregar UI de import CSV en `/dashboard/admin/checklist-templates` (carga 50+ ítems en un click).
- [ ] Endurecer RLS en `checklist_templates` para que solo `administrador` pueda mutar (FASE 5 SUPABASE_AUDIT.md).
- [ ] Vista pública `v_checklist_templates_activas` para consulta rápida sin tocar la tabla.
