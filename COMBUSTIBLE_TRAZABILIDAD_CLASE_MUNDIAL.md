# Combustible — Trazabilidad clase mundial

> **Última actualización:** 2026-04-30 — FASE 5.3
> **Audiencia:** administrador, jefe de mantenimiento, operador de abastecimiento, conductor.
> **Estado:** SQL propuesto en `database/schema/55_*.sql` (NO ejecutado). Schemas Zod listos en `validations/combustible.ts`.

---

## 1. Tres flujos críticos

```
                 ┌─────────────────────────────────────┐
                 │   1. INGRESO (compra a proveedor)   │
                 │      ENEX, ESMAX, COPEC, otros      │
                 └──────────────┬──────────────────────┘
                                │
                                ▼
                         ESTANQUE PILLADO
                         stock teórico ↑
                                │
        ┌───────────────────────┼─────────────────────┐
        ▼                       ▼                     ▼
  ┌────────────┐      ┌──────────────────┐    ┌──────────────────┐
  │ 2a. VENTA  │      │ 2b. CARGA EQUIPO │    │ 2c. DESPACHO     │
  │  EXTERNA   │      │   PROPIO PILLADO │    │   CLIENTE        │
  │            │      │                  │    │   (con sellos)   │
  │ tercero    │      │ camioneta, etc.  │    │ camión cisterna  │
  │ retira     │      │ kilometraje +    │    │ 3 sellos         │
  │ vale firma │      │ horómetro        │    │ fotos salida     │
  │            │      │                  │    │ fotos entrega    │
  └────────────┘      └──────────────────┘    └──────────────────┘
                                │
                                ▼
                         estanque ↓ litros
                         CECO obligatorio
                         evidencia obligatoria
```

---

## 2. Flujo 1 — Ingreso de combustible (ENEX / ESMAX / otro)

### 2.1 Datos capturados desde la guía física

| Campo del documento | Campo en BD |
|---|---|
| Razón social proveedor | `proveedor_id` (FK) + `proveedor_nombre_snapshot` |
| Número de guía | `numero_guia` (UNIQUE por proveedor) |
| Número de pedido (si existe) | `numero_pedido` |
| Fecha de la guía | `fecha_documento` |
| Fecha real de recepción | `fecha_recepcion` (auto NOW()) |
| Producto | `producto_combustible` (default `diesel`) |
| Volumen carga indicado en guía | `volumen_carga_litros` |
| Lectura inicial medidor | `meter_inicial` |
| Lectura final medidor | `meter_final` |
| Litros realmente entregados | `litros_entregados` |
| Diferencia litros (auto-calculada) | `diferencia_litros` (columna generada) |
| Conductor del camión | `conductor_nombre` |
| Patente del camión | `camion_patente` |
| Cliente / receptor en documento | `cliente_nombre_documento` |
| Receptor real (UUID) | `recibido_por` |
| Foto/PDF de la guía | `evidencia_guia_url` (Storage) |
| Firma conductor (si hay) | `firma_conductor_url` |
| Firma receptor (si hay) | `firma_receptor_url` |

### 2.2 Reglas de negocio (validadas por Zod + RPC)

1. `evidencia_guia_url` es **OBLIGATORIA** (`z.string().url(...)`).
2. `numero_guia` no puede duplicarse para el mismo proveedor (`UNIQUE (proveedor_id, numero_guia)`).
3. Si `meter_inicial` y `meter_final` están presentes → `meter_final >= meter_inicial`.
4. Si `volumen_carga_litros` ≠ `litros_entregados` (diferencia ≥ 0.01 lt) → exige `observacion` con mínimo 5 caracteres.
5. La RPC `rpc_registrar_ingreso_combustible`:
   - Valida proveedor activo.
   - Genera folio `ICB-YYYYMM-XXXXX`.
   - Reusa `fn_registrar_movimiento_combustible` (existente) → aumenta `stock_teorico_lt` del estanque.
   - Inserta en `ingresos_combustible` con todos los datos formales.
   - Auditoría automática.

### 2.3 Folio interno

Formato: **`ICB-YYYYMM-XXXXX`**.

---

## 3. Flujo 2a — Venta externa (tercero retira)

### 3.1 Datos capturados

| Campo | Notas |
|---|---|
| `tipo_salida` | `'venta_externa'` |
| `cliente_id` o `cliente_nombre_manual` | Identificación del comprador (al menos uno obligatorio) |
| `litros` | > 0 |
| `ceco_id` | **OBLIGATORIO** (CECO de venta externa) |
| `retira_nombre` | Persona que físicamente retira |
| `motivo` | Min 5 caracteres |
| `evidencia_vale_url` | **OBLIGATORIA** — foto del vale |
| `autorizado_por` | UUID del autorizador |

### 3.2 Reglas

- `cliente_id` o `cliente_nombre_manual` obligatorio (refine en Zod).
- `evidencia_vale_url` obligatoria.
- Stock se descuenta automáticamente vía `fn_registrar_movimiento_combustible`.

---

## 4. Flujo 2b — Carga a equipo propio Pillado

### 4.1 Datos capturados

| Campo | Notas |
|---|---|
| `tipo_salida` | `'carga_equipo_propio'` |
| `equipo_activo_id` o `unidad_equipo_descripcion` | Al menos uno obligatorio |
| `kilometraje` | Snapshot al cargar |
| `horometro` | Snapshot al cargar |
| `conductor_id` o `conductor_nombre_manual` | Quién recibe el combustible |
| `ceco_id` | **OBLIGATORIO** |
| `evidencia_vale_url` | **OBLIGATORIA** |

### 4.2 Reglas

- `equipo_activo_id` o `unidad_equipo_descripcion` obligatorio (refine en Zod).
- Si se selecciona equipo de la flota, queda registro de carga histórica para análisis de consumo (`fn_registrar_movimiento_combustible` con `destino_tipo='vehiculo_flota'`).

---

## 5. Flujo 2c — Despacho a cliente con 3 sellos

**Este es el flujo más crítico de auditoría.** Cuando un camión Pillado sale a entregar combustible a una faena, lleva 3 sellos numerados que el receptor debe verificar al llegar.

### 5.1 Etapa A — Preparación del despacho (al salir del taller)

Datos capturados al **salir**:

| Campo | Obligatorio |
|---|---|
| `salida_combustible_id` | ✅ FK a la salida origen (tipo=despacho_cliente) |
| `camion_activo_id` | ✅ Camión cisterna asignado |
| `conductor_id` | ✅ Conductor responsable |
| `destino_cliente` o `destino_faena_id` | ✅ Al menos uno |
| `sello_1_numero`, `sello_2_numero`, `sello_3_numero` | ✅ Los 3 |
| `foto_sello_1_salida_url`, `foto_sello_2_salida_url`, `foto_sello_3_salida_url` | ✅ Las 3 fotos |
| `litros_cargados` | ✅ Total cargado al estanque del camión |
| `fecha_salida` | auto NOW() al ejecutar la RPC |

> **CHECK constraint en BD** garantiza que ninguno de los 6 campos de sellos pueda estar vacío al pasar de `programado` a `en_ruta`.

Estado: `programado` → `en_ruta` (al ejecutar `rpc_registrar_despacho_combustible_sellos`).

### 5.2 Etapa B — Confirmación de entrega (al llegar al cliente)

Datos capturados al **entregar**:

| Campo | Obligatorio |
|---|---|
| `foto_sello_1_entrega_url`, `foto_sello_2_entrega_url`, `foto_sello_3_entrega_url` | ✅ Las 3 fotos al llegar |
| `sellos_intactos` | ✅ Boolean — confirma que sellos no fueron forzados |
| `litros_entregados` | ✅ Volumen real entregado al cliente |
| `receptor_nombre` | ✅ Nombre de quien recibe |
| `receptor_rut` | Recomendado |
| `firma_receptor_url` | ✅ Firma digital del receptor |
| `observacion_entrega` | Opcional |

> **CHECK constraint en BD** garantiza que las 3 fotos de entrega existan al pasar a `entregado` u `observado`.

### 5.3 Lógica de cierre

La RPC `rpc_confirmar_entrega_combustible`:

1. Valida que las 3 fotos de entrega estén presentes.
2. Calcula `diferencia_litros = litros_entregados - litros_cargados`.
3. **Si `sellos_intactos = false` OR diferencia > 0.5%** → marca `estado='observado'` y crea registro en `no_conformidades` con `severidad='alta'` y `tipo='diferencia_litros'`.
4. **Si todo OK** → `estado='entregado'`.
5. Auditoría automática.

### 5.4 Folio

Formato: **`DCB-YYYYMM-XXXXX`** (despacho combustible).

---

## 6. Reglas de stock automáticas

| Operación | Stock estanque |
|---|---|
| Ingreso (compra proveedor) | ↑ `litros_entregados` |
| Salida — venta externa | ↓ `litros` |
| Salida — carga equipo propio | ↓ `litros` |
| Salida — despacho cliente | ↓ `litros_cargados` (al despachar; ajuste posterior si entrega real difiere) |
| Varillaje con `generar_ajuste=true` | ↑↓ según diferencia física vs teórica (mig 50) |
| Constraint BD | `stock_teorico_lt >= 0` y `stock_teorico_lt <= capacidad_lt` |

Todo movimiento pasa por la RPC `fn_registrar_movimiento_combustible` (existente, mig 50) que actualiza el estanque dentro de la misma transacción.

---

## 7. Auditoría completa

Cada movimiento de combustible queda con:

1. **Folio interno único** (`ICB-...`, `SCB-...`, `DCB-...`).
2. **Trigger `audit_trigger`** captura INSERT/UPDATE/DELETE en todas las tablas.
3. **Foto obligatoria** en cada paso (guía, vale, sellos × 6 — 3 salida + 3 entrega).
4. **Firma digital opcional** (conductor, receptor, autorizador).
5. **`created_by`, `recibido_por`, `conductor_id`, `receptor_nombre`** — captura de actores.
6. **`no_conformidades`** automáticas para diferencias relevantes.
7. **Constraint UNIQUE** en `proveedor_id + numero_guia` — imposible duplicar guía.

---

## 8. Validaciones Zod listas

Archivo: `frontend/src/validations/combustible.ts` (extendido en FASE 5.3).

| Schema | Cubre |
|---|---|
| `ingresoCombustibleFormalSchema` | Ingreso ENEX/ESMAX con guía + meter readings + diferencia con observación |
| `salidaCombustibleFormalSchema` | Venta / carga propio / despacho con CECO + reglas según tipo |
| `despachoSalidaSellosSchema` | 3 sellos numerados + 3 fotos salida + camión + conductor |
| `despachoEntregaSchema` | 3 fotos entrega + sellos_intactos + litros + receptor + firma |

### 8.1 Reglas críticas validadas

- 🔴 **Foto guía obligatoria** en ingreso (`evidencia_guia_url: z.string().url(...)`).
- 🔴 **Foto vale obligatoria** en salida (`evidencia_vale_url: z.string().url(...)`).
- 🔴 **3 sellos + 3 fotos salida obligatorios** en despacho.
- 🔴 **3 fotos entrega obligatorias** al confirmar.
- 🔴 **Firma receptor obligatoria** al confirmar entrega.
- 🔴 **CECO obligatorio** en toda salida.
- 🔴 **`meter_final >= meter_inicial`** (refine).
- 🔴 **Diferencia litros exige observación** (refine).
- 🔴 **`carga_equipo_propio` exige equipo o descripción** (refine).
- 🔴 **`venta_externa` exige cliente** (refine).

---

## 9. Roles responsables

| Acción | Roles autorizados |
|---|---|
| Ingreso combustible | administrador, bodeguero, operador_abastecimiento, supervisor, jefe_mantenimiento, subgerente_operaciones |
| Salida venta externa | administrador, operador_abastecimiento, subgerente_operaciones (con autorización) |
| Salida carga propio | administrador, operador_abastecimiento, supervisor, planificador |
| Despacho con sellos (preparar) | administrador, operador_abastecimiento, jefe_mantenimiento |
| Confirmar entrega | conductor (`conductor_id` del despacho) o administrador |
| Anular despacho | administrador |

---

## 10. Pruebas manuales sugeridas (cuando se aplique SQL)

### Test 1 — Ingreso ENEX con guía
1. Crear proveedor ENEX si no existe.
2. Registrar ingreso: numero_guia=12345, fecha=hoy, estanque=EST-15K, volumen_carga=2000 lt, meter_inicial=100000, meter_final=102000, litros_entregados=2000, foto guía adjunta.
3. Verificar:
   - `ingresos_combustible` con folio `ICB-...`.
   - `combustible_estanques.stock_teorico_lt += 2000`.
   - `combustible_movimientos` tipo `ingreso` creado.
   - `auditoria_eventos` registrado.

### Test 2 — Duplicar guía
1. Intentar registrar otro ingreso con `proveedor=ENEX, numero_guia=12345`.
2. Debe fallar por `UNIQUE (proveedor_id, numero_guia)`.

### Test 3 — Diferencia con observación
1. Ingreso con `volumen_carga=2000` pero `litros_entregados=1995`.
2. Sin observación → Zod rechaza.
3. Con observación "Diferencia 5 lt por temperatura" → pasa.

### Test 4 — Despacho con sellos
1. Crear salida tipo `despacho_cliente` por 3000 lt al estanque del camión.
2. RPC `rpc_registrar_despacho_combustible_sellos` con sellos `S001, S002, S003` + 3 fotos + camión + conductor.
3. Estado pasa a `en_ruta`.
4. **Intentar pasar a en_ruta SIN una foto** → debe fallar por CHECK constraint.

### Test 5 — Confirmar entrega con diferencia
1. Despacho con `litros_cargados=3000`.
2. Conductor confirma entrega: 3 fotos entrega + receptor + firma + `litros_entregados=2950` + `sellos_intactos=true`.
3. Diferencia 50 lt = 1.67% → > 0.5%.
4. Estado pasa a `observado`, no a `entregado`.
5. Se crea registro en `no_conformidades` con severidad alta.

### Test 6 — Sellos rotos
1. Confirmar entrega con `sellos_intactos=false`.
2. Estado pasa a `observado` automáticamente (independiente de la diferencia).
3. `no_conformidades` registrado.

---

## 11. Pendientes / próximos pasos

| ID | Acción | Prioridad |
|---|---|---|
| C01 | Aplicar BLOCK A–C SQL `55_*.sql` (proveedores, CECO, OC) | Alta |
| C02 | Aplicar BLOCK G (ingresos_combustible) + RPC BLOCK M | Alta |
| C03 | Aplicar BLOCK H (salidas_combustible) + RPC BLOCK N | Alta |
| C04 | Aplicar BLOCK I (despachos) + RPCs BLOCK O | Alta — uso real con clientes |
| C05 | Seed proveedores: ENEX, ESMAX, COPEC | Alta |
| C06 | Seed CECO mínimos: TALLER, OPERACIONES, COMERCIAL, VENTA, ADMIN | Alta |
| C07 | UI ingreso combustible formal: pantalla con OC + guía + foto | Alta |
| C08 | UI salida combustible: pantalla con tipo + CECO + evidencia | Alta |
| C09 | UI despacho con sellos: 2 pantallas (preparar + confirmar) | Crítica para uso real |
| C10 | Capacitar a operador de abastecimiento en flujo de sellos | Crítica |
| C11 | App móvil/PWA para conductor: confirmar entrega con cámara y firma digital | Crítica |

---

## 12. Verificación

- `npm run typecheck` → ✅ 0 errores.
- `npm run build` → ✅ 37 rutas generadas, build limpio.
- SQL `55_*.sql` → creado, **NO ejecutado** (revisar bloque por bloque antes de aplicar).
- Validaciones Zod → 4 schemas nuevos en `combustible.ts`.

---

## 13. Sobre cumplimiento "clase mundial"

Este diseño cubre los 5 principios de trazabilidad de combustibles industriales:

1. **Identificación única**: folios secuenciales + UNIQUE en guías.
2. **Cadena de custodia**: 3 sellos numerados con fotos al salir y al llegar.
3. **Doble registro físico-documental**: meter inicial/final vs volumen documentado.
4. **Evidencia obligatoria**: fotos en todas las etapas + firmas digitales.
5. **Reconciliación**: varillaje diario (mig 50) cruza stock teórico vs físico.

Cualquier auditor (interno, SEC, cliente) puede reconstruir el camino completo desde la compra al proveedor hasta el receptor final con evidencia digital.
