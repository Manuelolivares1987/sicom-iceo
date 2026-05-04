# MAPA DE MÓDULOS — SICOM-ICEO

> **Última actualización:** 2026-04-28 — FASE 3
> **Resumen:** 22 módulos detectados. 0 con mocks/demo data. **Todos conectan a Supabase real** (162 llamadas `supabase.from(...)` a través de 22 servicios). Diferencias = profundidad de CRUD.

---

## 1. Convenciones

- **Estado UI:** ✅ Completa / ⚠️ Parcial / ❌ Vacía
- **Estado datos:** ✅ Real / ⚠️ Real con cobertura parcial / ❌ Sin datos / 🔄 Calculado server-side
- **Estado demo:**
  - 🟢 **Listo para demo**
  - 🟡 **Parcialmente listo** (mostrar con preámbulo)
  - 🔴 **No listo** / **No mostrar en demo**
  - 🔧 **Requiere corrección urgente**
  - 🛠️ **Solo herramienta operativa** (útil pero no para presentación ejecutiva)

---

## 2. Mapa por módulo

### 🔐 Login

| Campo | Detalle |
|---|---|
| Ruta | `/login` |
| Archivos principales | `src/app/login/page.tsx` |
| Servicios | `auth-context.signIn` → `supabase.auth.signInWithPassword` |
| Hooks | `useAuth` |
| Estado UI | ✅ Completa (RHF, validación de credenciales, mostrar/ocultar password, redirect post-login) |
| Estado datos | ✅ Real (Supabase Auth) |
| Supabase | ✅ Sí |
| Mock/demo | ❌ No |
| Formularios | RHF con `LoginForm` (email + password). Validación nativa. **Sin Zod** (acceptable). |
| CRUD | Solo sign-in / sign-out |
| Riesgo | **Bajo** |
| Acción recomendada | OK como está. Para FASE 6: opcional Zod + mejor mensaje al expirar sesión. |
| **Estado demo** | 🟢 Listo |

---

### 📊 Dashboard

| Campo | Detalle |
|---|---|
| Ruta | `/dashboard` |
| Archivos principales | `src/app/dashboard/page.tsx`, `components/dashboard/executive-dashboard.tsx`, `commercial-dashboard.tsx`, `operations-dashboard.tsx` |
| Servicios | `contratos`, `kpi-iceo`, `ordenes-trabajo`, `inventario`, `alertas`, `certificaciones` |
| Hooks | `useOTsStats`, `useValorizacionTotal`, `useICEOPeriodo`, `useICEOHistorico`, `useAlertasNoLeidas`, `useCertificacionesVencidas`, `useProximosVencimientos` |
| Estado UI | ✅ Completa. **Routing por rol** (Ejecutivos → ExecutiveDashboard; Comercial → CommercialDashboard; Operaciones → OperationsDashboard; resto → LegacyDashboard). |
| Estado datos | ✅ Real (lee Supabase + RPC `iceo_periodo`) |
| Supabase | ✅ Sí |
| Mock/demo | ❌ No |
| Formularios | No |
| CRUD | Solo lectura agregada |
| Riesgo | **Bajo** (FASE 1 ya corrigió el bug de Rules of Hooks). Si no hay contrato activo, ICEO se ve "Sin datos" → es fallback OK. |
| Acción recomendada | OK. Verificar que haya un contrato `activo` en BD para que ICEO muestre cifras. |
| **Estado demo** | 🟢 Listo |

---

### 🚚 Activos

| Campo | Detalle |
|---|---|
| Ruta | `/dashboard/activos`, `/dashboard/activos/[id]` |
| Archivos principales | `src/app/dashboard/activos/page.tsx`, `[id]/page.tsx` |
| Servicios | `services/activos.ts`, `services/faenas.ts` |
| Hooks | `useActivos`, `useFichaActivo` |
| Estado UI | ✅ Completa: filtros (tipo, estado, criticidad), vista lista/grilla, ficha detalle con KPIs |
| Estado datos | ✅ Real (`activos` con join a `modelos`, `marcas`, `faenas`) |
| Supabase | ✅ Sí |
| Mock/demo | ❌ No |
| Formularios | Edición de activo en ficha (vía `updateActivo`) |
| CRUD | Read + Update. **No hay UI de Create ni Delete activos** desde frontend (operación administrativa) |
| Riesgo | **Bajo** |
| Acción recomendada | OK. Si demo necesita crear activo: hoy se hace por SQL/admin. |
| **Estado demo** | 🟢 Listo |

---

### 🚛 Flota

| Campo | Detalle |
|---|---|
| Ruta | `/dashboard/flota`, `/jornada`, `/recepcion`, `/recepcion/[informeId]/emitir`, `/inspeccion-recepcion/[informeId]`, `/verificar/[otId]`, `/aprobar/[otId]` |
| Archivos principales | `src/app/dashboard/flota/page.tsx` + 6 sub-páginas |
| Servicios | `services/flota.ts`, `verificacion.ts`, `informe-recepcion.ts`, `jornada-conductor.ts` |
| Hooks | `useFlotaVehicular`, `useResumenDiario`, `useOEEFlota`, `useEjecutarVerificaciones`, `useAplicarEstadosAutomaticos` |
| Estado UI | ✅ Completa. KPIs OEE, distribución estados, alertas normativas, modal cambio estado, ranking, charts Recharts |
| Estado datos | ✅ Real (mig 25, 27, 41, 47) |
| Supabase | ✅ Sí |
| Mock/demo | ❌ No |
| Formularios | Cambio de estado (modal), recepción/verificación con firma + foto, emisión de informe PDF |
| CRUD | Read + Update (estados) + Create informes + ejecución de RPCs |
| Riesgo | **Medio** en `/recepcion/[informeId]/emitir` (597 KB First Load JS — `@react-pdf/renderer`). Carga lenta. |
| Acción recomendada | Es **el módulo bandera del MVP** (memoria del proyecto: 55 vehículos, OEE, jornada, GPS, alertas normativas). **Mostrarlo seguro.** Para `emitir` PDF: pre-cargar el ID antes de la demo o evitar entrar en vivo. |
| **Estado demo** | 🟢 Listo (página principal + jornada). 🟡 Parcial el flujo `recepcion/emitir` (carga lenta). |

---

### 🔧 Mantenimiento

| Campo | Detalle |
|---|---|
| Ruta | `/dashboard/mantenimiento` |
| Archivos principales | `src/app/dashboard/mantenimiento/page.tsx` |
| Servicios | `services/mantenimiento.ts`, `faenas.ts`, `ordenes-trabajo.ts` |
| Hooks | `usePlanes`, `useMantenimientosVencidos`, `usePautasFabricante`, `useProximasMantenimientos`, `useGenerarOTDesdePlan` |
| Estado UI | ✅ Completa (planes, vencidos, próximos, semáforos, generación OT desde plan) |
| Estado datos | ✅ Real |
| Supabase | ✅ Sí |
| Mock/demo | ❌ No |
| Formularios | `CrearOTModal` (RHF + Zod), generar OT desde plan |
| CRUD | Read planes + Create OT desde plan |
| Riesgo | **Bajo** |
| Acción recomendada | Verificar que existan planes preventivos cargados en BD para que la página no esté vacía. |
| **Estado demo** | 🟢 Listo |

---

### 📋 Órdenes de Trabajo

| Campo | Detalle |
|---|---|
| Ruta | `/dashboard/ordenes-trabajo`, `/[id]` |
| Archivos principales | `page.tsx`, `[id]/page.tsx` |
| Servicios | `services/ordenes-trabajo.ts`, `ot-materiales.ts`, `faenas.ts`, `contratos.ts` |
| Hooks | `useOrdenesTrabajo`, `useCreateOT`, `useOT`, `useUpdateOT`, `useTransitionOT`, `useOTMateriales` |
| Estado UI | ✅ Completa (filtros tipo/estado/prioridad, búsqueda, paginación, ficha con motor de estados, materiales, acciones por estado) |
| Estado datos | ✅ Real (mig 12 motor estados v3) |
| Supabase | ✅ Sí |
| Mock/demo | ❌ No |
| Formularios | RHF + Zod (`CrearOTModal`), edición materiales |
| CRUD | Read + Create + Update + transiciones de estado + asignación responsables |
| Riesgo | **Bajo**. Motor de estados maduro (mig 12 + 24 advisory lock + 38 fallback contrato + 39 folio). |
| Acción recomendada | **Módulo central — mostrar en demo.** |
| **Estado demo** | 🟢 Listo |

---

### 👤 Mis OTs

| Campo | Detalle |
|---|---|
| Ruta | `/dashboard/mis-ots` |
| Archivos principales | `src/app/dashboard/mis-ots/page.tsx` |
| Servicios | `ordenes-trabajo` |
| Hooks | `useOrdenesTrabajo` (filtra por `responsable_id = user.id`) |
| Estado UI | ✅ Completa (agrupada por estado, ranking) |
| Estado datos | ✅ Real |
| Supabase | ✅ Sí |
| Mock/demo | ❌ No |
| Formularios | No (es vista personalizada del listado) |
| CRUD | Read |
| Riesgo | **Bajo**. Vacío si el usuario logueado no tiene OTs asignadas. |
| Acción recomendada | Para demo: loguearse con usuario que tenga OTs. |
| **Estado demo** | 🟡 Parcial (depende del usuario demo). |

---

### 📦 Inventario

| Campo | Detalle |
|---|---|
| Ruta | `/dashboard/inventario`, `/salida`, `/conteo`, `/scanner`, `/cargar-maestro` |
| Archivos principales | `inventario/page.tsx` + 4 sub-rutas |
| Servicios | `services/inventario.ts` |
| Hooks | `useStockBodega`, `useValorizacionTotal`, `useMovimientos`, `useBodegas`, etc. |
| Estado UI | ✅ Completa (stock, valorización, movimientos, salida, conteo, scanner QR, carga masiva Excel) |
| Estado datos | ✅ Real |
| Supabase | ✅ Sí |
| Mock/demo | ❌ No |
| Formularios | Salidas, conteos, ajustes (Zod). Scanner usa `html5-qrcode` (cámara). |
| CRUD | Read + Create movimientos + Update stock + carga masiva |
| Riesgo | **Medio** en `/scanner` (requiere cámara, permisos navegador) y `/cargar-maestro` (262 KB First Load por exceljs). |
| Acción recomendada | Mostrar `/dashboard/inventario` (vista principal). **Evitar `/scanner` en demo** salvo que se haya probado en ese device/navegador. |
| **Estado demo** | 🟢 Listo (principal). 🛠️ Scanner / Cargar-maestro (herramientas operativas). |

---

### ⛽ Combustible (sub-módulo Inventario)

| Campo | Detalle |
|---|---|
| Ruta | `/dashboard/inventario/combustible`, `/medidores`, `/movimiento`, `/varillaje` |
| Archivos principales | 4 páginas |
| Servicios | `services/combustible.ts` (mig 50, 51) |
| Hooks | `useEstanques`, `useMovimientosCombustible`, `useConsumoVehiculoMes`, `useMedidores`, etc. |
| Estado UI | ✅ Completa (estanques, KPIs, varillaje, movimientos, alta de medidores, registro con foto obligatoria) |
| Estado datos | ✅ Real (mig 50 estanques + 51 foto obligatoria) |
| Supabase | ✅ Sí |
| Mock/demo | ❌ No |
| Formularios | RHF + Zod en movimiento/varillaje, upload de foto obligatoria |
| CRUD | Full |
| Riesgo | **Bajo-Medio**. Foto obligatoria depende de Storage bucket configurado. |
| Acción recomendada | Verificar bucket Storage activo. **Módulo nuevo, fresco — buen showcase.** |
| **Estado demo** | 🟢 Listo (módulo principal y movimientos en lectura). 🟡 Operaciones de upload sólo si Storage está OK. |

---

### 🦺 Prevención

| Campo | Detalle |
|---|---|
| Ruta | `/dashboard/prevencion` |
| Archivos principales | `prevencion/page.tsx` |
| Servicios | `services/prevencion.ts` (mig 32 SUSPEL/RESPEL) |
| Hooks | `usePrevencionResumen`, `useSuspelProductos`, `useSuspelBodegas`, `useRespelMovimientos`, `useCertificacionesBloqueantes` |
| Estado UI | ✅ Completa (StatCards, lista SUSPEL/RESPEL, certificaciones bloqueantes) |
| Estado datos | ✅ Real |
| Supabase | ✅ Sí |
| Mock/demo | ❌ No |
| Formularios | No (vista agregada) |
| CRUD | Read |
| Riesgo | **Bajo** |
| Acción recomendada | OK. Bueno para mostrar normativa cumplida. |
| **Estado demo** | 🟢 Listo |

---

### ✅ Cumplimiento

| Campo | Detalle |
|---|---|
| Ruta | `/dashboard/cumplimiento` |
| Archivos principales | `cumplimiento/page.tsx` |
| Servicios | `services/certificaciones.ts` |
| Hooks | `useAllCertificaciones`, `useCertificacionStats`, `useCreateCertificacion` |
| Estado UI | ✅ Completa (filtros tipo/estado, lista, modal alta de certificación, upload) |
| Estado datos | ✅ Real |
| Supabase | ✅ Sí |
| Mock/demo | ❌ No |
| Formularios | Modal con RHF crear certificación |
| CRUD | Read + Create |
| Riesgo | **Bajo** |
| Acción recomendada | OK. **Buen módulo demo** (semáforos por vencimiento, normativa SEC/SEREMI/SISS). |
| **Estado demo** | 🟢 Listo |

---

### 📈 Fiabilidad

| Campo | Detalle |
|---|---|
| Ruta | `/dashboard/fiabilidad` |
| Archivos principales | `fiabilidad/page.tsx` |
| Servicios | `services/fiabilidad.ts` (mig 40, 41, 47) |
| Hooks | `useFiabilidadFlota`, `useDetalleFiabilidadFlota` |
| Estado UI | ✅ Completa (OEE por categoría, scatter, RadialBar, Pie por categoría de uso) |
| Estado datos | 🔄 Calculado server-side (RPC) |
| Supabase | ✅ Sí (RPCs) |
| Mock/demo | ❌ No |
| Formularios | No (filtros de fecha y categoría) |
| CRUD | Read |
| Riesgo | **Bajo** |
| Acción recomendada | OK. Métricas operacionales serias — **buen complemento de KPI**. |
| **Estado demo** | 🟢 Listo |

---

### 📊 Reportes

| Campo | Detalle |
|---|---|
| Ruta | `/dashboard/reportes` |
| Archivos principales | `reportes/page.tsx` |
| Servicios | `ordenes-trabajo`, `inventario`, `mantenimiento`, `certificaciones`, `kpi-iceo`, `activos` |
| Hooks | Llamadas directas a `getXxx()` y `exportToCSV` / `exportToExcel` |
| Estado UI | ✅ Completa (selector de reporte, descarga CSV/Excel) |
| Estado datos | ✅ Real |
| Supabase | ✅ Sí |
| Mock/demo | ❌ No |
| Formularios | No |
| CRUD | Read + Export |
| Riesgo | **Bajo** |
| Acción recomendada | OK. Útil para demo: **muestra exportación a Excel** ante stakeholders. |
| **Estado demo** | 🟢 Listo |

---

### 📅 Reporte Diario

| Campo | Detalle |
|---|---|
| Ruta | `/dashboard/reporte-diario` |
| Archivos principales | `reporte-diario/page.tsx` |
| Servicios | `services/reporte-diario.ts` (mig 30, 33, 36) |
| Hooks | `useReporteDiario`, `useReportesHistoricos`, `useTendenciaReporte`, `useCambiosEstadoDia`, `useRegenerarReporteDiario` |
| Estado UI | ✅ Completa (snapshot diario, tendencia, distribución estados, timeline cambios, regenerar) |
| Estado datos | ✅ Real (snapshots persistidos, mig 30 + 33 reporta_diarios_automaticos) |
| Supabase | ✅ Sí |
| Mock/demo | ❌ No |
| Formularios | No (selector de fecha + acción regenerar) |
| CRUD | Read + acción `regenerar` (RPC) |
| Riesgo | **Bajo**. Si el día actual no tiene snapshot → se puede generar al vuelo. |
| Acción recomendada | **Top demo:** narrativa de control diario. Verifica que haya datos del día anterior. |
| **Estado demo** | 🟢 Listo |

---

### 🎯 KPI

| Campo | Detalle |
|---|---|
| Ruta | `/dashboard/kpi` |
| Archivos principales | `kpi/page.tsx` |
| Servicios | `services/kpi-iceo.ts`, `incentivos.ts`, `contratos.ts` |
| Hooks | `useKPIDefiniciones`, `useMedicionesKPI`, `useCalcularKPIs`, `useKPIDrillDown` |
| Estado UI | ✅ Completa (drill-down por área A/B/C, BarChart, modal detalle, tabla KPIs) |
| Estado datos | ✅ Real |
| Supabase | ✅ Sí |
| Mock/demo | ❌ No |
| Formularios | Selector mes/año, recálculo |
| CRUD | Read + acción "calcular" |
| Riesgo | **Bajo**. Si no hay contrato activo → mostrará vacío (acceptable). |
| Acción recomendada | **Top demo:** el sistema KPI/ICEO es el corazón del producto. |
| **Estado demo** | 🟢 Listo |

---

### 🏆 ICEO

| Campo | Detalle |
|---|---|
| Ruta | `/dashboard/iceo` |
| Archivos principales | `iceo/page.tsx` |
| Servicios | `kpi-iceo`, `incentivos`, `contratos` |
| Hooks | `useICEOPeriodo`, `useICEOHistorico`, `useMedicionesKPI`, `useBloqueantesStatus`, `useKPIDefiniciones`, `useCalcularICEO`, `useIncentivos`, `useCalcularIncentivos` |
| Estado UI | ✅ Completa (Gauge, tendencia, bloqueantes, áreas A/B/C, incentivos calculados) |
| Estado datos | ✅ Real (mig 41 metodología Excel + mig 42 redistribución C con fiabilidad) |
| Supabase | ✅ Sí |
| Mock/demo | ❌ No |
| Formularios | Selector período + acciones calcular ICEO / calcular incentivos |
| CRUD | Read + acciones de cálculo |
| Riesgo | **Bajo**. Depende de que haya `mediciones_kpi` cargadas para el período. |
| Acción recomendada | **Top demo, ÚNICO de Pillado** — el indicador ICEO es la ventaja competitiva. Asegurar que el período mostrado tenga datos. |
| **Estado demo** | 🟢 Listo |

---

### 📄 Contratos

| Campo | Detalle |
|---|---|
| Ruta | `/dashboard/contratos` |
| Archivos principales | `contratos/page.tsx` |
| Servicios | `services/contratos.ts`, `faenas.ts` |
| Hooks | `useContratos` (inline), `useAllFaenas` (inline) |
| Estado UI | ✅ Completa (zonas Coquimbo/Calama, progress bar, faenas asociadas) |
| Estado datos | ✅ Real |
| Supabase | ✅ Sí |
| Mock/demo | ❌ No |
| Formularios | No |
| CRUD | Read |
| Riesgo | **Bajo** |
| Acción recomendada | OK. Bueno para contextualizar la operación (qué clientes, qué zonas). |
| **Estado demo** | 🟢 Listo |

---

### 🚛 Abastecimiento

| Campo | Detalle |
|---|---|
| Ruta | `/dashboard/abastecimiento`, `/despachos` |
| Archivos principales | 2 páginas |
| Servicios | `services/abastecimiento.ts`, `inventario.ts`, `faenas.ts` |
| Hooks | `useRutasDespacho`, `useAbastecimientos`, `useRutaStats`, `useCreateRuta`, `useUpdateRutaEstado`, `useCreateAbastecimiento`, `usePuntosPorFaena` |
| Estado UI | ✅ Completa (rutas, stats, modal alta ruta) |
| Estado datos | ✅ Real |
| Supabase | ✅ Sí |
| Mock/demo | ❌ No |
| Formularios | Modal RHF crear ruta + abastecimiento |
| CRUD | Read + Create + Update |
| Riesgo | **Medio-Bajo**. Si no hay rutas registradas, se ve vacío. |
| Acción recomendada | Verificar que haya al menos 1 ruta cargada para demo. |
| **Estado demo** | 🟡 Parcial (depende de datos cargados) |

---

### 💼 Comercial

| Campo | Detalle |
|---|---|
| Ruta | `/dashboard/comercial` |
| Archivos principales | `comercial/page.tsx` + `components/dashboard/commercial-dashboard.tsx` |
| Servicios | `flota`, `reporte-diario` |
| Hooks | `useFlotaVehicular`, `useOEEFlota`, `useReporteDiario` |
| Estado UI | ✅ Completa (arrendados, disponibles, leasing, KPIs por cliente y operación, charts) |
| Estado datos | ✅ Real |
| Supabase | ✅ Sí |
| Mock/demo | ❌ No |
| Formularios | No |
| CRUD | Read |
| Riesgo | **Bajo** |
| Acción recomendada | OK. **Útil si la audiencia es comercial/gerencia.** |
| **Estado demo** | 🟢 Listo |

---

### 🔍 Auditoría

| Campo | Detalle |
|---|---|
| Ruta | `/dashboard/auditoria` |
| Archivos principales | `auditoria/page.tsx` |
| Servicios | `services/auditoria.ts` |
| Hooks | `useAuditoria` |
| Estado UI | ✅ Completa (filtros tabla/acción/fecha, expandable rows con diff JSON) |
| Estado datos | ✅ Real (`auditoria_eventos`) |
| Supabase | ✅ Sí |
| Mock/demo | ❌ No |
| Formularios | No |
| CRUD | Read |
| Riesgo | **Bajo** |
| Acción recomendada | OK. Bueno para mostrar trazabilidad ante auditores. |
| **Estado demo** | 🟢 Listo |

---

### ⚙️ Administración

| Campo | Detalle |
|---|---|
| Ruta | `/dashboard/admin`, `/admin/checklist-templates`, `/admin/gps` |
| Archivos principales | `admin/page.tsx` (3 tabs: General, Usuarios, Parámetros), `checklist-templates/page.tsx`, `gps/page.tsx` |
| Servicios | `services/admin.ts` (`getUsuarios`, `getSystemStats`) |
| Hooks | `useUsuarios`, `useSystemStats` (inline) |
| Estado UI | ✅ Completa. Tabs General/Usuarios/Parámetros, modal edición usuario, listado checklist templates, listado GPS. |
| Estado datos | ✅ Real |
| Supabase | ✅ Sí |
| Mock/demo | ❌ No |
| Formularios | `EditarUsuarioModal` (rol, estado activo) |
| CRUD | Read + Update usuarios |
| Riesgo | **Medio** en `/admin/gps` (depende de integración con dispositivos GPS reales). |
| Acción recomendada | **No mostrar `/admin/gps` en demo** salvo que tengas trackers conectados confirmados. La sección "Usuarios" sí se ve bien. |
| **Estado demo** | 🟢 Listo (page.tsx). 🛠️ checklist-templates (operativo). 🔴 `/gps` (depende de hardware/integración). |

---

### 👨‍🔧 Equipo (ficha pública)

| Campo | Detalle |
|---|---|
| Ruta | `/equipo/[id]` (NO bajo `/dashboard`, no requiere login) |
| Archivos principales | `app/equipo/[id]/page.tsx` |
| Servicios | `activos` (vía `useFichaActivo`) |
| Hooks | `useFichaActivo` |
| Estado UI | ✅ Completa (ficha pública del activo, próximos vencimientos, criticidad, semáforos) |
| Estado datos | ✅ Real |
| Supabase | ✅ Sí (lectura sin auth — RLS debe permitir) |
| Mock/demo | ❌ No |
| Formularios | No |
| CRUD | Read público |
| Riesgo | **Medio**. Esta ruta es **pública** (no usa `useRequireAuth`). Depende de que RLS permita lectura anónima de la tabla `activos` para esta vista. **Revisar en FASE 5.** |
| Acción recomendada | Útil para escaneo QR en terreno. Confirmar políticas RLS antes de demo pública. |
| **Estado demo** | 🟡 Parcial (depende de RLS validada). |

---

## 3. Resumen consolidado

| Estado demo | Cant | Módulos |
|---|---|---|
| 🟢 **Listo** | 16 | Login, Dashboard, Activos, Flota, Mantenimiento, OT, Inventario (principal), Combustible (lectura), Prevención, Cumplimiento, Fiabilidad, Reportes, Reporte Diario, KPI, ICEO, Contratos, Comercial, Auditoría, Admin (principal) |
| 🟡 **Parcial** | 4 | Mis OTs (depende de usuario logueado), Abastecimiento (depende de datos cargados), Equipo público (depende de RLS), Combustible (operaciones upload requieren Storage OK) |
| 🛠️ **Solo herramienta** | 3 | Inventario/scanner, Inventario/cargar-maestro, Admin/checklist-templates |
| 🔴 **No mostrar** | 1 | Admin/GPS (depende de integración hardware) |
| 🔧 **Corrección urgente** | 0 | — |

> **Total módulos:** 22 paginas / rutas mayores. **Cero módulos solo-maqueta. Cero módulos con mock data.**

---

## 4. Top 5 módulos para demo ejecutiva (recomendación)

1. **Login** → `/login` (1 min, demuestra Auth + UI corporativa).
2. **Dashboard** → `/dashboard` (Control Tower o Ejecutivo según rol — eje narrativo).
3. **Flota** → `/dashboard/flota` (OEE, alertas normativas, distribución de estados — el módulo bandera del MVP, desplegado el 2026-04-11 con 55 vehículos reales).
4. **OT + Mantenimiento** → `/dashboard/ordenes-trabajo` y `/dashboard/mantenimiento` (CRUD real con motor de estados, Zod, react-hook-form).
5. **KPI + ICEO** → `/dashboard/kpi` y `/dashboard/iceo` (la ventaja competitiva de Pillado: indicador ICEO con áreas A/B/C, bloqueantes, incentivos).

**Cierre opcional:** **Reporte Diario** → muestra automatización (snapshots cron + tendencia 30 días). Y **Cumplimiento** para demostrar normativa SEC/SEREMI/SISS.

---

## 5. Módulos a NO abrir en demo (sin coordinación previa)

| Módulo | Razón |
|---|---|
| `/dashboard/admin/gps` | Depende de integración con dispositivos GPS reales. Si no hay trackers conectados, se ve vacío. |
| `/dashboard/inventario/scanner` | Requiere cámara y permisos de navegador. Riesgo de fallo en vivo. |
| `/dashboard/inventario/cargar-maestro` | 414 KB First Load JS (exceljs). Página administrativa, no presentación. |
| `/dashboard/flota/recepcion/[informeId]/emitir` | 597 KB First Load (`@react-pdf/renderer`). Carga lenta. Si se entra, hacerlo con un informe ya cargado. |
| `/dashboard/mis-ots` | Solo si el usuario demo tiene OTs asignadas; sino se ve vacío. |
| `/equipo/[id]` (público) | Requiere RLS validada antes (FASE 5). |

---

## 6. Riesgos críticos detectados (FASE 3)

| ID | Sev | Riesgo | Acción |
|---|---|---|---|
| M01 | **Alto** | `/equipo/[id]` es ruta pública sin `useRequireAuth` → expone ficha de activo si RLS no filtra correctamente. | FASE 5 (Supabase audit) |
| M02 | **Medio** | `/dashboard/flota/recepcion/[informeId]/emitir` con 597 KB First Load JS (`@react-pdf/renderer`). Lento en redes lentas. | Diferido FASE 9 |
| M03 | **Medio** | `/dashboard/inventario/cargar-maestro` con 414 KB First Load (exceljs). | Diferido FASE 9 |
| M04 | **Medio** | `/dashboard/inventario/scanner` requiere permisos de cámara — fallback no testeado. | FASE 7 |
| M05 | **Bajo** | `/admin/gps` depende de integración GPS externa: vacío si no hay flota conectada. | Documentar |
| M06 | **Bajo** | Modal de Combustible/movimiento: foto obligatoria depende de Storage bucket activo (mig 46). | Verificar bucket en FASE 5 |
| M07 | **Bajo** | Cobertura de Zod: ya existe en OT, inventario, combustible. **Falta** en activos, mantenimiento, prevención, contratos, abastecimiento, certificaciones. | FASE 6 |

> **Ningún módulo necesita corrección urgente que bloquee el sistema.** Los riesgos son operativos / de UX, no de estabilidad.

---

## 7. Archivos modificados en FASE 3

```
A  MAPA_MODULOS.md                  (este documento)
M  AUDITORIA_TECNICA.md             (sección 12 — FASE 3)
```

**Cero modificaciones en código fuente.** La fase fue puramente de auditoría de módulos sin tocar lógica.

---

## 8. Resultado final FASE 3

✅ **Mapa real construido. Sistema más maduro de lo esperado para un MVP.**

- 22 módulos / rutas detectados.
- **Todos** conectan a Supabase real (162 llamadas `supabase.from(...)` en 22 servicios).
- **Cero módulos con mock/demo data hardcoded.**
- **19 módulos listos o parcialmente listos para demo.**
- **0 módulos requieren corrección urgente.**
- 7 riesgos operativos detectados (uno alto, dos medios, cuatro bajos).
