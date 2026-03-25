# FASE 4 — BACKEND, SERVICIOS Y LÓGICA DE NEGOCIO

## Sistema Integral de Control Operacional, Mantenimiento, Inventario e ICEO (SICOM-ICEO)
### Pillado Empresas — Trayectoria y Compromiso

---

## 1. RESUMEN

La Fase 4 conecta el frontend con Supabase y establece toda la lógica de negocio real del sistema.

### Archivos creados: 22

| Categoría | Archivos | Descripción |
|-----------|----------|-------------|
| Contextos | 2 | Auth (Supabase Auth) + Query Provider (TanStack) |
| Servicios | 9 | Capa de datos para cada módulo |
| Hooks | 7 | React Query hooks para cache y mutaciones |
| Actualizaciones | 4 | Páginas conectadas a datos reales |

---

## 2. ARQUITECTURA DE CAPAS

```
┌─────────────────────────────────────────────────┐
│                   PÁGINAS (UI)                   │
│  dashboard, OTs, inventario, activos, ICEO       │
└──────────────────────┬──────────────────────────┘
                       │ usa hooks
┌──────────────────────▼──────────────────────────┐
│              REACT QUERY HOOKS                    │
│  Cache, loading states, mutations, invalidation   │
│  Polling de alertas cada 30s                      │
└──────────────────────┬──────────────────────────┘
                       │ llama servicios
┌──────────────────────▼──────────────────────────┐
│              SERVICIOS (lib/services)              │
│  Lógica de negocio, validaciones, type assertions │
│  REGLA: salida sin OT = error                     │
│  REGLA: cierre OT valida evidencia+checklist      │
└──────────────────────┬──────────────────────────┘
                       │ Supabase JS SDK
┌──────────────────────▼──────────────────────────┐
│                   SUPABASE                        │
│  PostgreSQL + Auth + Storage + RPC + RLS          │
│  Triggers validan reglas en servidor              │
└─────────────────────────────────────────────────┘
```

---

## 3. AUTENTICACIÓN

### Flujo:
1. Usuario accede a `/login`
2. Ingresa email + contraseña
3. `AuthProvider` llama `supabase.auth.signInWithPassword`
4. Si OK, carga perfil desde `usuarios_perfil`
5. Redirect a `/dashboard`
6. Todas las rutas `/dashboard/*` protegidas por `useRequireAuth()`

### Archivos:
- `contexts/auth-context.tsx` — Provider con user, perfil, signIn, signOut
- `contexts/query-provider.tsx` — TanStack Query con staleTime 5min
- `hooks/use-require-auth.ts` — Redirect si no autenticado

---

## 4. SERVICIOS DE DATOS

### 4.1 Órdenes de Trabajo (`services/ordenes-trabajo.ts`)

**Operaciones:**
- CRUD completo de OTs con joins (activo, faena, responsable)
- Transiciones de estado: iniciar, pausar, finalizar, no ejecutar, cerrar supervisor
- Checklist: lectura y actualización de ítems
- Evidencias: upload a Supabase Storage + registro en BD
- Materiales: consulta de movimientos asociados
- Historial: log de transiciones de estado
- Stats: conteo por estado para dashboard

**Reglas enforced en frontend + backend:**
- `noEjecutarOT()` requiere `causa_no_ejecucion` obligatoria
- `finalizarOT()` — trigger PostgreSQL valida evidencia + checklist + firma
- `cerrarOTSupervisor()` registra supervisor_id y fecha_cierre

### 4.2 Inventario (`services/inventario.ts`)

**Operaciones:**
- Productos con búsqueda por código de barras
- Stock por bodega con joins
- Valorización total (SUM valor_total)
- Movimientos: entrada, salida, ajuste
- Kardex por producto/bodega
- Conteos de inventario

**Regla crítica — Salida de inventario:**
```typescript
// VALIDACIÓN FRONTEND (service layer)
if (!ot_id) throw new Error('No se permite salida sin OT asociada')
if (!usuario_id) throw new Error('Usuario no autenticado')
if (stockActual < cantidad) throw new Error('Stock insuficiente')

// VALIDACIÓN BACKEND (trigger PostgreSQL)
// validar_salida_inventario() — bloquea INSERT sin ot_id
```

### 4.3 KPI e ICEO (`services/kpi-iceo.ts`)

**Operaciones:**
- Mediciones KPI por período/contrato/faena
- ICEO del período con desglose por área
- Histórico ICEO para tendencias
- Cálculo de KPIs via RPC `calcular_todos_kpi`
- Cálculo de ICEO via RPC `calcular_iceo`
- Estado de bloqueantes

### 4.4 Otros servicios

| Servicio | Operaciones principales |
|----------|------------------------|
| `contratos.ts` | Lista, detalle, contrato activo |
| `faenas.ts` | Lista con filtro por contrato |
| `activos.ts` | CRUD con joins marca/modelo/faena |
| `certificaciones.ts` | CRUD + vencidas + próximos vencimientos |
| `alertas.ts` | Lista, no leídas, marcar leída, conteo |
| `auditoria.ts` | Log de eventos con filtros |

---

## 5. REACT QUERY HOOKS

### 5.1 Hooks de OTs (14 hooks)

| Hook | Tipo | Invalidaciones |
|------|------|----------------|
| `useOrdenesTrabajo(filters)` | Query | — |
| `useOrdenTrabajo(id)` | Query | — |
| `useOTsStats(faenaId)` | Query | — |
| `useChecklistOT(otId)` | Query | — |
| `useEvidenciasOT(otId)` | Query | — |
| `useMaterialesOT(otId)` | Query | — |
| `useHistorialOT(otId)` | Query | — |
| `useCreateOT()` | Mutation | ordenes-trabajo |
| `useIniciarOT()` | Mutation | orden-trabajo, ordenes-trabajo |
| `usePausarOT()` | Mutation | orden-trabajo, ordenes-trabajo |
| `useFinalizarOT()` | Mutation | orden-trabajo, ordenes-trabajo, ots-stats |
| `useNoEjecutarOT()` | Mutation | orden-trabajo, ordenes-trabajo |
| `useUpdateChecklistItem()` | Mutation | orden-trabajo |
| `useAddEvidencia()` | Mutation | orden-trabajo, evidencias-ot |

### 5.2 Hooks de Inventario (9 hooks)

| Hook | Tipo | Notas |
|------|------|-------|
| `useRegistrarSalida()` | Mutation | Invalida stock, movimientos, OT, kardex |
| `useRegistrarEntrada()` | Mutation | Invalida stock, movimientos, kardex |
| `useProductoByBarcode(code)` | Query | Para escáner |
| `useStockBodega(filters)` | Query | Filtro por bodega, bajo mínimo |
| `useValorizacionTotal(faena)` | Query | SUM valor_total |

### 5.3 Hook de Escáner (`use-scanner.ts`)

Soporta dos modos de entrada:
1. **Cámara del dispositivo** — via `Html5Qrcode`, lee códigos de barra y QR
2. **Pistola industrial (keyboard wedge)** — detecta input rápido (<50ms entre teclas)

---

## 6. PÁGINAS ACTUALIZADAS

### Dashboard Gerencial (`/dashboard`)
- ICEO gauge con dato real de `iceo_periodos`
- OTs activas desde `getOTsStats`
- Inventario valorizado desde `getValorizacionTotal`
- Tendencia ICEO desde `getICEOHistorico`
- Alertas no leídas
- Certificaciones por vencer

### Órdenes de Trabajo (`/dashboard/ordenes-trabajo`)
- Lista con filtros reales (tipo, estado, faena, prioridad)
- Detalle OT con tabs conectados a Supabase
- Acciones (iniciar, pausar, finalizar) con mutaciones
- Upload de evidencias a Supabase Storage
- Modal de "No Ejecutada" con causa obligatoria

### Inventario (`/dashboard/inventario`)
- Stock real por bodega con semáforos
- Movimientos reales con filtros
- Salida con escáner y validación OT obligatoria

### Activos (`/dashboard/activos`)
- Lista real con filtros por tipo, faena, estado, criticidad
- Cards con datos de marca/modelo via joins

### ICEO (`/dashboard/iceo`)
- Gauge con ICEO real del período
- Desglose por área desde mediciones
- Botón "Calcular ICEO" via RPC
- Selector de período (mes/año)
- Tendencia histórica

---

## 7. BUILD STATUS

```
✓ Compiled successfully
✓ 11/11 routes generated
✓ 0 type errors
✓ Total JS: ~280 KB first load (dashboard)
```

---

*Documento generado para SICOM-ICEO — Fase 4 — Backend y Lógica de Negocio*
*Versión 1.0 — Marzo 2026*
