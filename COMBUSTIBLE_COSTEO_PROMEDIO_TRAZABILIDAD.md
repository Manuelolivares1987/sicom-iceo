# COMBUSTIBLE — Costeo por Promedio Ponderado Móvil + Trazabilidad

> **Última actualización:** 2026-05-02 — FASE 5.4-B
> **Audiencia:** administrador, finanzas, contraloría, operador de abastecimiento, auditor.
> **Estado:** SQL propuesto en `database/schema/57_*.sql` (NO ejecutado). Validaciones Zod listas en `validations/combustible.ts`. Frontend pendiente.

---

## 1. Decisión técnica: por qué CPP móvil para combustible

| Característica | CPP móvil (combustible) | FIFO por capas (repuestos, mig 56) |
|---|---|---|
| Realidad física | ✅ Líquido se mezcla en el estanque | ❌ No aplicable a líquidos |
| Costo unitario | Único promedio ponderado vigente | Distinto por capa de origen |
| Trazabilidad fina | ❌ No hay vínculo físico salida↔compra | ✅ Salida → capa específica |
| Auditoría documental | ✅ OC + guía + vale + foto + sellos + kardex | ✅ Igual + capa |
| Reconciliación física | ✅ Por varillaje físico vs teórico | ✅ Por inventario físico vs capas |

**Decisión:** combustible se costea por **promedio ponderado móvil** porque físicamente está mezclado. La afirmación correcta es:

> *"La salida se valoriza al costo promedio ponderado del estanque vigente al momento de la salida, construido a partir del stock inicial e ingresos previos."*

NO es correcto decir *"este litro vino de la compra X"* — eso solo aplica a productos individuales (filtros, baterías).

---

## 2. Fórmulas

### 2.1 Ingreso (recalcula CPP)

```
valor_actual         = stock_actual_lt × costo_promedio_actual
valor_ingreso        = litros_ingreso × costo_unitario_ingreso
stock_nuevo          = stock_actual_lt + litros_ingreso
costo_promedio_nuevo = (valor_actual + valor_ingreso) / stock_nuevo
valor_stock_nuevo    = valor_actual + valor_ingreso
```

Si `stock_actual = 0`, entonces `costo_promedio_nuevo = costo_unitario_ingreso`.

### 2.2 Salida (NO modifica CPP)

```
costo_unitario_aplicado = costo_promedio_actual   (vigente al momento de la salida)
valor_total_salida      = litros_salida × costo_unitario_aplicado
stock_nuevo             = stock_actual_lt - litros_salida
valor_stock_nuevo       = valor_stock_actual - valor_total_salida
costo_promedio_nuevo    = costo_promedio_actual   (no cambia)
```

> **Importante:** las salidas **NO** modifican el costo promedio. Solo los ingresos lo hacen.

### 2.3 Stock inicial

```
costo_promedio_lt = costo_unitario_inicial
stock_teorico_lt  = litros_iniciales
valor_total_stock = litros_iniciales × costo_unitario_inicial
```

---

## 3. Ejemplo numérico obligatorio

### 3.1 Estado inicial — partida controlada por administrador

| Acción | Detalle |
|---|---|
| RPC | `rpc_registrar_stock_inicial_combustible` |
| Estanque | EST-15K |
| Litros iniciales | **1.000 lt** |
| Costo unitario inicial | **$900/lt** |
| Valor total inicial | **$900.000** |

**Estado del estanque después:**
| `stock_teorico_lt` | `costo_promedio_lt` | `valor_total_stock` |
|---|---|---|
| 1.000 | $900,0000 | $900.000 |

### 3.2 Compra a proveedor ENEX (recibe ingreso valorizado)

| Acción | Detalle |
|---|---|
| RPC | `rpc_registrar_ingreso_combustible_valorizado` |
| Estanque | EST-15K |
| Litros ingreso | **2.000 lt** |
| Costo unitario | **$1.000/lt** |
| Valor ingreso | **$2.000.000** |
| Proveedor | ENEX |
| Guía | `12345-ENEX` |
| Foto guía | obligatoria |

**Cálculo CPP móvil:**
```
valor_actual         = 1.000 × $900     = $900.000
valor_ingreso        = 2.000 × $1.000   = $2.000.000
stock_nuevo          = 1.000 + 2.000    = 3.000 lt
costo_promedio_nuevo = ($900.000 + $2.000.000) / 3.000 = $966,67/lt
valor_stock_nuevo    = $900.000 + $2.000.000 = $2.900.000
```

**Estado del estanque después:**
| `stock_teorico_lt` | `costo_promedio_lt` | `valor_total_stock` |
|---|---|---|
| 3.000 | **$966,6667** | **$2.900.000** |

### 3.3 Salida a Cliente Z (venta externa)

| Acción | Detalle |
|---|---|
| RPC | `rpc_registrar_salida_combustible_valorizada` |
| Estanque | EST-15K |
| Litros salida | **500 lt** |
| Tipo | `venta_externa` |
| Cliente | Cliente Z |
| CECO | CECO-VENTA-EXT |
| Vale | foto obligatoria |

**Cálculo:**
```
costo_unitario_aplicado = $966,67          (CPP vigente)
valor_total_salida      = 500 × $966,67 = $483.333
stock_nuevo             = 3.000 - 500   = 2.500 lt
valor_stock_nuevo       = $2.900.000 - $483.333 = $2.416.667
costo_promedio_nuevo    = $966,67           (NO cambia)
```

**Estado del estanque después:**
| `stock_teorico_lt` | `costo_promedio_lt` | `valor_total_stock` |
|---|---|---|
| 2.500 | $966,6667 | $2.416.667 |

### 3.4 Lo que queda registrado en `combustible_kardex_valorizado`

| fecha | tipo | folio | proveedor/cliente | litros_in | litros_out | costo_unit_mov | stock_después | cpp_después | valor_stock_después |
|---|---|---|---|---|---|---|---|---|---|
| 2026-05-01 | stock_inicial | INI-... | — | 1.000 | 0 | $900 | 1.000 | $900 | $900.000 |
| 2026-05-02 | ingreso_compra | ICB-202605-... | ENEX | 2.000 | 0 | $1.000 | 3.000 | $966,67 | $2.900.000 |
| 2026-05-03 | salida_venta | SCB-202605-... | Cliente Z | 0 | 500 | $966,67 | 2.500 | $966,67 | $2.416.667 |

→ **Trazabilidad completa:** Administración puede reconstruir el estado del estanque en cualquier momento, identificar todas las compras que formaron el CPP, todas las salidas con su cliente/equipo/CECO, y conciliar contra varillaje físico.

---

## 4. Stock inicial → compra → ingreso → salida → saldo (flujo end-to-end)

```
┌────────────────────────────────────────────────────────────────────┐
│  STOCK INICIAL (admin/subgerente, una vez por estanque)            │
│  rpc_registrar_stock_inicial_combustible                           │
│  └──→ combustible_stock_inicial                                    │
│       combustible_estanques.stock/cpp/valor                        │
│       combustible_kardex_valorizado (tipo=stock_inicial)           │
└────────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌────────────────────────────────────────────────────────────────────┐
│  COMPRA → OC (mig 55) → INGRESO VALORIZADO                         │
│  rpc_registrar_ingreso_combustible_valorizado                      │
│  ├── Valida: proveedor activo, guía única, evidencia obligatoria,  │
│  │           meter_final >= meter_inicial,                         │
│  │           diferencia litros doc/medidos exige observación       │
│  ├── Recalcula CPP móvil del estanque                              │
│  ├── ↑ stock_teorico_lt, ↑ valor_total_stock, costo_promedio_lt    │
│  └──→ ingresos_combustible (con todos los snapshots)               │
│       combustible_kardex_valorizado (tipo=ingreso_compra)          │
└────────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌────────────────────────────────────────────────────────────────────┐
│  SALIDAS — 3 tipos posibles                                        │
│  rpc_registrar_salida_combustible_valorizada                       │
│                                                                    │
│   1. venta_externa     — cliente + retira + vale + CECO            │
│   2. carga_equipo_propio — equipo + km/horómetro + vale + CECO     │
│   3. despacho_cliente  — encadena con despachos_combustible        │
│                          (3 sellos + fotos salida + entrega)       │
│                                                                    │
│  ├── Aplica CPP vigente → costo_unitario_aplicado                  │
│  ├── ↓ stock_teorico_lt, ↓ valor_total_stock                       │
│  ├── CPP NO cambia (solo cambia con ingresos)                      │
│  └──→ salidas_combustible (con todos los snapshots)                │
│       combustible_kardex_valorizado                                │
│         (tipo=salida_venta / salida_equipo / salida_despacho)      │
└────────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌────────────────────────────────────────────────────────────────────┐
│  SALDO FÍSICO Y VALORIZADO                                         │
│  combustible_estanques (estado actual)                             │
│  + v_combustible_stock_valorizado_actual                           │
│  + v_combustible_kardex_valorizado (histórico completo)            │
│                                                                    │
│  Reconciliación contra varillaje físico (mig 50):                  │
│   - combustible_varillaje compara teórico vs medición física       │
│   - diferencias generan ajuste o merma                             │
└────────────────────────────────────────────────────────────────────┘
```

---

## 5. Cómo se valoriza cada salida

1. La RPC bloquea el estanque con `SELECT ... FOR UPDATE` (concurrencia segura).
2. Lee `costo_promedio_lt` actual del estanque.
3. `costo_unitario_aplicado = costo_promedio_lt`.
4. `valor_total_salida = litros_salida × costo_unitario_aplicado`.
5. Insert en `salidas_combustible` con **9 snapshots**: `costo_unitario_aplicado`, `valor_total_salida`, `costo_promedio_al_momento`, `stock_anterior_lt`, `stock_nuevo_lt`, `valor_stock_anterior`, `valor_stock_nuevo`, `kardex_valorizado_id`, evidencia.
6. Update en `combustible_estanques` (solo stock y valor, NO el CPP).
7. Insert en `combustible_kardex_valorizado` (inmutable, reconstruible).

**El cliente NO puede pasar costo manual.** El sistema lo asigna. Esto se valida en Zod (`salidaCombustibleValorizadaSchema` no acepta `costo_unitario` en el payload) y en RPC.

---

## 6. Cómo se audita el saldo físico y valorizado

### 6.1 Trinidad de fuentes de verdad

| Fuente | Información | Comparación |
|---|---|---|
| `combustible_estanques` | Stock + CPP + valor **actuales** | Estado vivo |
| `combustible_kardex_valorizado` | **Snapshot post-cada-movimiento** | Última fila debe coincidir con el estanque |
| `combustible_varillaje` (mig 50) | Medición **física** del operador | Debe coincidir con teórico (tolerancia configurable) |

### 6.2 Reconciliación obligatoria semanal (script en BLOCK K.4 de mig 57)

```sql
-- Si esta query devuelve filas, hay desincronización (investigar):
SELECT
    e.codigo,
    e.stock_teorico_lt   AS estanque_stock,
    (SELECT stock_lt_despues FROM combustible_kardex_valorizado
      WHERE estanque_id = e.id ORDER BY fecha_movimiento DESC LIMIT 1) AS kardex_stock,
    e.valor_total_stock  AS estanque_valor,
    (SELECT valor_stock_despues FROM combustible_kardex_valorizado
      WHERE estanque_id = e.id ORDER BY fecha_movimiento DESC LIMIT 1) AS kardex_valor
  FROM combustible_estanques e WHERE e.activo = true;
```

Los pares **deben coincidir exactamente**. Si no, alguien escribió en `combustible_estanques` saltándose la RPC.

### 6.3 Ejemplo de auditoría a una salida específica

```sql
-- "¿Qué pasó con la salida SCB-202605-00045 al Cliente Z?"
SELECT * FROM v_combustible_trazabilidad_salida WHERE folio_salida = 'SCB-202605-00045';
```

Devuelve:
- Datos de la salida (litros, costo, cliente, CECO, vale).
- Stock antes/después de la salida.
- CPP aplicado y stock valorizado antes/después.
- Despacho asociado (si aplica) con sellos y fotos.
- Lista de últimos 10 ingresos previos al estanque (informativo — formaron el CPP).

> ⚠️ La lista de "ingresos previos" **NO es asignación física** — es referencia informativa. El campo `combustible_kardex_valorizado` y `salidas_combustible` ya tienen el costo aplicado correcto.

---

## 7. Vistas/reportes para Administración y Finanzas

### 7.1 `v_combustible_kardex_valorizado` (mig 57 BLOCK J.1)

Kardex enriquecido con joins. Ideal para tabla operativa con filtros por estanque/fecha/tipo/cliente/CECO.

### 7.2 `v_combustible_trazabilidad_salida` (mig 57 BLOCK J.2)

Por cada salida: detalle CPP aplicado + ingresos previos que formaron ese CPP (informativo) + despacho con sellos si aplica.

### 7.3 `v_combustible_stock_valorizado_actual` (mig 57 BLOCK J.3)

Estado actual de cada estanque con: stock, CPP, valor, % llenado, último ingreso, última salida, último varillaje. **Tablero ejecutivo**.

---

## 8. Validaciones Zod listas

Archivo: `frontend/src/validations/combustible.ts` (extendido en FASE 5.4-B).

| Schema | Cubre |
|---|---|
| `stockInicialCombustibleSchema` | Stock inicial: estanque + litros + costo + observación obligatoria ≥5 caracteres |
| `ingresoCombustibleValorizadoSchema` | Ingreso con guía, evidencia obligatoria, validación cruzada meter/litros con observación si difiere |
| `salidaCombustibleValorizadaSchema` | Salida con CECO obligatorio, motivo ≥5, vale obligatorio, reglas según tipo (cliente, equipo, retira) |

### 8.1 Reglas críticas validadas

- 🔴 Litros ingreso > 0; costo unitario ≥ 0.
- 🔴 Litros salida > 0.
- 🔴 CECO obligatorio en toda salida.
- 🔴 Evidencia obligatoria (guía en ingreso, vale en salida, foto guía/vale URL).
- 🔴 Diferencia entre litros documentados y medidos exige observación ≥5 caracteres.
- 🔴 Venta externa requiere cliente + retira_nombre.
- 🔴 Carga equipo propio requiere equipo o descripción.
- 🔴 `meter_final >= meter_inicial`.
- 🔴 Stock inicial requiere observación ≥5 (no se puede reutilizar mensaje genérico).

---

## 9. Pruebas manuales (cuando se aplique SQL)

### Test 1 — Stock inicial
1. Como administrador, ejecutar `rpc_registrar_stock_inicial_combustible(EST-15K, 1000, 900, ..., 'Apertura piloto')`.
2. Verificar `combustible_estanques`: `stock_teorico_lt=1000`, `costo_promedio_lt=900.0000`, `valor_total_stock=900000`.
3. Verificar `combustible_kardex_valorizado` tiene 1 fila tipo `stock_inicial`.
4. Intentar registrar otro stock inicial sin anular el anterior → debe fallar.

### Test 2 — Ingreso recalcula CPP
1. Estado: 1000 lt a $900.
2. Ingreso 2000 lt a $1000 (proveedor ENEX, guía, foto).
3. Verificar:
   - `combustible_estanques.stock_teorico_lt = 3000`.
   - `combustible_estanques.costo_promedio_lt = 966.6667`.
   - `combustible_estanques.valor_total_stock = 2900000`.
   - `ingresos_combustible.costo_promedio_anterior = 900`, `costo_promedio_nuevo = 966.6667`.

### Test 3 — Salida usa CPP vigente
1. Estado: 3000 lt a $966,67.
2. Salida 500 lt para venta_externa Cliente Z, CECO=CECO-VENTA, vale.
3. Verificar:
   - `salidas_combustible.costo_unitario_aplicado = 966.6667`.
   - `salidas_combustible.valor_total_salida = 483333.5` (≈ $483.333).
   - `combustible_estanques.stock_teorico_lt = 2500`.
   - `combustible_estanques.costo_promedio_lt = 966.6667` (NO cambió).

### Test 4 — Costo manual prohibido
1. Cliente intenta enviar `costo_unitario_manual` en payload de salida.
2. Zod debe rechazar (`salidaCombustibleValorizadaSchema` no acepta ese campo).
3. RPC ignora cualquier costo del cliente; siempre lee `costo_promedio_lt`.

### Test 5 — Stock insuficiente
1. Estado: 100 lt disponibles.
2. Intentar salida 500 lt → debe fallar con `RAISE EXCEPTION 'Stock insuficiente en estanque ...'`.
3. No debe modificarse nada (rollback).

### Test 6 — Diferencia meter exige observación
1. Ingreso con `meter_inicial=100000`, `meter_final=102100`, `litros_ingreso=2000`. Diferencia 100 lt.
2. Sin observación → Zod rechaza.
3. Con observación "Compensación temperatura, conductor confirma" → pasa. Queda registrado en kardex.

### Test 7 — Reconciliación
1. Hacer 3 ingresos y 5 salidas mezcladas.
2. Ejecutar query de §6.2.
3. Debe devolver 0 filas (estanque y kardex coinciden).

---

## 10. Roles responsables

| Acción | Roles autorizados |
|---|---|
| Registrar stock inicial | administrador, subgerente_operaciones |
| Anular stock inicial | administrador (con justificación) |
| Registrar ingreso compra | administrador, bodeguero, operador_abastecimiento, supervisor, jefe_mantenimiento, subgerente_operaciones |
| Registrar salida — venta_externa | administrador, operador_abastecimiento, subgerente_operaciones (con autorizado_por) |
| Registrar salida — carga_equipo_propio | administrador, operador_abastecimiento, supervisor, planificador |
| Registrar salida — despacho_cliente | administrador, operador_abastecimiento, jefe_mantenimiento |
| Registrar ajuste | **solo administrador** |
| Confirmar entrega despacho | conductor del despacho o administrador |

---

## 11. Riesgos y plan de implementación

| ID | Sev | Riesgo | Mitigación |
|---|---|---|---|
| C01 | 🔴 | mig 55 (combustible parte) NO está aplicada → mig 57 falla por FK a `proveedores`, `centros_costo`, `ingresos_combustible`, `salidas_combustible`, `despachos_combustible` | **Aplicar primero mig 55 BLOCKS A-C + G-I** |
| C02 | 🟠 | Estanques con stock actual `stock_teorico_lt > 0` pero sin `costo_promedio_lt` requieren stock_inicial controlado o el primer ingreso lo establece (con observación) | Plan de migración: registrar stock_inicial con costo histórico estimado por administrador antes de habilitar las nuevas RPCs |
| C03 | 🟠 | Concurrencia: 2 salidas simultáneas del mismo estanque → mitigado por `FOR UPDATE` | Probar con script de stress en staging |
| C04 | 🟡 | Reconciliación estanque vs kardex podría fallar si alguien hace UPDATE directo a estanques saltándose RPC | Restringir UPDATE de `combustible_estanques.stock_teorico_lt` solo via RPC. Considerar trigger AFTER UPDATE que valide |
| C05 | 🟡 | Frontend de stock inicial / ingreso valorizado / salida valorizada no existe | Implementar incrementalmente (ver §12) |
| C06 | 🟡 | El CPP se redondea a 4 decimales — pueden acumularse fracciones de centavo | Aceptable para CLP. Reconciliación detecta si se vuelve material |
| C07 | 🟡 | Si stock llega a 0, qué hacer con el CPP: mantener como informativo o llevar a 0 | Decisión actual: **mantener como referencia informativa** (último CPP) y `valor_total_stock=0` (consistente con stock=0) |

### 11.1 Plan de implementación recomendado

**Sprint 1 (1 semana, staging):**
1. Aplicar mig 55 BLOCKS A-C + G-I + J + L (proveedores, CECO, ingresos/salidas/despachos combustible + folios + RPC salida bodega).
2. Aplicar mig 57 BLOCKS A-J (todos).
3. Para cada estanque existente con stock > 0: registrar `combustible_stock_inicial` con costo histórico estimado por admin (justificación documentada).
4. Probar tests 1-7.

**Sprint 2 (1 semana, frontend):**
5. UI stock inicial: pantalla solo admin/subgerente con form simple.
6. UI ingreso valorizado: pantalla mostrando CPP antes/después, valor total calculado, evidencia obligatoria.
7. UI salida valorizada: pantalla mostrando CPP vigente + valor estimado pre-submit + valor real post-submit.
8. UI kardex: tabla con filtros y export a Excel.

**Sprint 3 (capacitación):**
9. Capacitar a Gustavo (bodega) y operador de abastecimiento.
10. Operación supervisada por administrador durante primera semana en producción.
11. Reconciliación diaria semana 1, semanal después.

---

## 12. Frontend pendiente (servicios + tipos mínimos)

> **No implementado en FASE 5.4-B.** Esta sección documenta lo necesario para Sprint 2.

### 12.1 Servicios sugeridos en `frontend/src/lib/services/combustible.ts`

```typescript
// Pendiente de implementar tras aplicar mig 55+57:
export async function registrarStockInicial(input: StockInicialCombustibleInput) {
  return supabase.rpc('rpc_registrar_stock_inicial_combustible', { ... })
}

export async function registrarIngresoValorizado(input: IngresoCombustibleValorizadoInput) {
  return supabase.rpc('rpc_registrar_ingreso_combustible_valorizado', { ... })
}

export async function registrarSalidaValorizada(input: SalidaCombustibleValorizadaInput) {
  return supabase.rpc('rpc_registrar_salida_combustible_valorizada', { ... })
}

export async function getKardexValorizado(filters?: KardexFilters) {
  return supabase.from('v_combustible_kardex_valorizado').select('*')...
}
```

### 12.2 Pantallas necesarias

| Ruta | Descripción |
|---|---|
| `/dashboard/inventario/combustible/stock-inicial` | Solo admin. Form con estanque + litros + costo + obs + documento |
| `/dashboard/inventario/combustible/ingreso` | Reformatear pantalla actual con preview de CPP antes/después |
| `/dashboard/inventario/combustible/salida` | Nueva pantalla unificada por tipo de salida |
| `/dashboard/inventario/combustible/kardex` | Tabla con filtros + export Excel |

---

## 13. Archivos modificados en FASE 5.4-B

```
A  database/schema/57_combustible_promedio_ponderado_trazabilidad.sql  (NO destructivo)
M  frontend/src/validations/combustible.ts                              (+3 schemas FASE 5.4-B)
A  COMBUSTIBLE_COSTEO_PROMEDIO_TRAZABILIDAD.md                          (este documento)
M  AUDITORIA_TECNICA.md                                                 (sección 20)
M  COMBUSTIBLE_TRAZABILIDAD_CLASE_MUNDIAL.md                            (referencia a FASE 5.4-B)
```

**Cero formularios frontend modificados. Cero SQL ejecutado.**

---

## 14. Verificación

- `npm run typecheck` → ✅ 0 errores.
- `npm run build` → ✅ 37 rutas generadas, build limpio.
- SQL `57_*.sql` → creado, **NO ejecutado** (todo comentado).
- Validaciones Zod → 3 schemas nuevos en `combustible.ts`.

---

## 15. Resumen claro para Administración y Finanzas

> **El combustible NO se asigna físicamente a una compra específica** porque está mezclado en el estanque.
>
> **Sí se puede auditar:** qué compras construyeron el costo promedio del estanque, cada salida con su cliente/equipo/CECO, vale, guía, foto, sellos del despacho, y el saldo físico y valorizado posterior a cada movimiento.
>
> **Cada salida se cobra al costo promedio vigente** del estanque al momento de la operación. Ese costo solo cambia con nuevos ingresos, nunca con salidas.
>
> **Reconciliación física** se hace por varillaje (medición física) vs stock teórico contable. Las diferencias se ajustan con justificación.
