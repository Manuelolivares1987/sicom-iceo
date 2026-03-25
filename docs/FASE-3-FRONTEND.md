# FASE 3 — DISEÑO FRONTEND RESPONSIVE

## Sistema Integral de Control Operacional, Mantenimiento, Inventario e ICEO (SICOM-ICEO)
### Pillado Empresas — Trayectoria y Compromiso

---

## 1. IDENTIDAD VISUAL

### 1.1 Colores Corporativos

| Color | HEX | Tailwind Token | Uso |
|-------|-----|----------------|-----|
| Verde Pillado | #2D8B3D | `pillado-green-500` | Botones primarios, sidebar activo, acciones principales |
| Naranjo Pillado | #E87722 | `pillado-orange-500` | Botones secundarios, alertas, notificaciones |
| Gris oscuro | #111827 | `gray-900` | Sidebar background, textos principales |
| Blanco | #FFFFFF | `white` | Cards, fondos de contenido |
| Gris claro | #F9FAFB | `gray-50` | Fondo general de la app |

### 1.2 Colores Funcionales

| Función | Color | Token | Uso |
|---------|-------|-------|-----|
| Semáforo Verde | #16A34A | `semaforo-verde` | Operativo, OK, activo |
| Semáforo Amarillo | #F59E0B | `semaforo-amarillo` | En mantención, por vencer |
| Semáforo Rojo | #DC2626 | `semaforo-rojo` | Fuera servicio, vencido, error |
| ICEO Excelencia | #7C3AED | `iceo-excelencia` | Score >= 95 |
| ICEO Bueno | #16A34A | `iceo-bueno` | Score 85-94 |
| ICEO Aceptable | #F59E0B | `iceo-aceptable` | Score 70-84 |
| ICEO Deficiente | #DC2626 | `iceo-deficiente` | Score < 70 |

### 1.3 Tipografía

- **Principal:** Inter (Google Fonts) — limpia, legible, profesional
- **Monospace:** JetBrains Mono — para folios OT, códigos, datos técnicos
- **Tamaños móvil:** base 16px, inputs mínimo 16px (evita zoom en iOS)

### 1.4 Logo

- **Header/Sidebar:** `logo_empresa_2.png` (fondo transparente, ~40px alto)
- **Login:** `logo_empresa_2.png` (200px ancho, centrado)
- **Favicon:** Derivado del ícono del logo

---

## 2. ESTRUCTURA DE ARCHIVOS

```
frontend/src/
├── app/
│   ├── globals.css                          # Estilos globales + Tailwind
│   ├── layout.tsx                           # Root layout (metadata, fonts)
│   ├── page.tsx                             # Redirect a login/dashboard
│   ├── login/
│   │   └── page.tsx                         # Pantalla de login
│   └── dashboard/
│       ├── layout.tsx                       # AppShell (sidebar + header)
│       ├── page.tsx                         # Dashboard Gerencial
│       ├── ordenes-trabajo/
│       │   ├── page.tsx                     # Lista de OTs
│       │   └── [id]/page.tsx               # Detalle OT (tabs)
│       ├── inventario/
│       │   ├── page.tsx                     # Dashboard inventario
│       │   └── salida/page.tsx             # Salida con escáner
│       ├── activos/
│       │   └── page.tsx                     # Lista de activos
│       └── iceo/
│           └── page.tsx                     # Dashboard ICEO
├── components/
│   ├── layout/
│   │   ├── sidebar.tsx                      # Sidebar colapsable
│   │   ├── header.tsx                       # Barra superior
│   │   └── app-shell.tsx                    # Shell principal
│   └── ui/
│       ├── button.tsx                       # Botones con variantes
│       ├── badge.tsx                        # Badges de estado
│       ├── card.tsx                         # Cards
│       ├── input.tsx                        # Inputs con label/error
│       ├── select.tsx                       # Select dropdown
│       ├── modal.tsx                        # Modal/Dialog
│       ├── table.tsx                        # Tabla responsive
│       ├── spinner.tsx                      # Loading spinner
│       ├── semaforo.tsx                     # Indicador semáforo
│       └── gauge.tsx                        # Gauge ICEO (SVG)
├── lib/
│   ├── supabase.ts                          # Cliente Supabase
│   └── utils.ts                             # Utilidades (formato, colores)
├── types/
│   └── database.ts                          # Tipos TypeScript del esquema
└── public/
    └── images/
        ├── logo.jpg                         # Logo principal
        └── logo_empresa_2.png              # Logo fondo transparente
```

**Total: 28 archivos fuente**

---

## 3. MAPA DE PANTALLAS

### 3.1 Pantallas Implementadas (Fase 3)

```
LOGIN
  └── Autenticación Supabase

DASHBOARD (requiere auth)
  ├── Dashboard Gerencial ─────── /dashboard
  ├── Órdenes de Trabajo
  │   ├── Lista + Filtros ──────── /dashboard/ordenes-trabajo
  │   └── Detalle OT (tabs) ───── /dashboard/ordenes-trabajo/[id]
  ├── Inventario
  │   ├── Dashboard + Tabs ─────── /dashboard/inventario
  │   └── Salida (escáner) ──────── /dashboard/inventario/salida
  ├── Activos ───────────────────── /dashboard/activos
  └── ICEO Dashboard ────────────── /dashboard/iceo
```

### 3.2 Pantallas Pendientes (se agregan en fases posteriores)

```
  ├── Contratos ──────────────────── /dashboard/contratos
  ├── Mantenimiento
  │   ├── Preventivo (planes PM) ── /dashboard/mantenimiento/preventivo
  │   └── Correctivo ────────────── /dashboard/mantenimiento/correctivo
  ├── Abastecimiento ────────────── /dashboard/abastecimiento
  ├── Cumplimiento ──────────────── /dashboard/cumplimiento
  ├── KPI Detalle ───────────────── /dashboard/kpi
  ├── Reportes ──────────────────── /dashboard/reportes
  ├── Auditoría ─────────────────── /dashboard/auditoria
  └── Administración
      ├── Usuarios ──────────────── /dashboard/admin/usuarios
      ├── Parámetros ────────────── /dashboard/admin/parametros
      └── Config KPI/ICEO ────────── /dashboard/admin/kpi-config
```

---

## 4. WIREFRAMES DESCRIPTIVOS

### 4.1 Login

```
┌─────────────────────────────────────────────┐
│        Fondo gradiente verde oscuro          │
│                                              │
│     ┌─────────────────────────────────┐      │
│     │                                 │      │
│     │    [Logo Pillado Empresas]      │      │
│     │         200px ancho             │      │
│     │                                 │      │
│     │      ══ SICOM-ICEO ══          │      │
│     │  Sistema Integral de Control    │      │
│     │       Operacional              │      │
│     │                                 │      │
│     │  ┌───────────────────────────┐  │      │
│     │  │ 📧 Correo electrónico    │  │      │
│     │  └───────────────────────────┘  │      │
│     │                                 │      │
│     │  ┌───────────────────────────┐  │      │
│     │  │ 🔒 Contraseña        👁  │  │      │
│     │  └───────────────────────────┘  │      │
│     │                                 │      │
│     │  ┌───────────────────────────┐  │      │
│     │  │    INICIAR SESIÓN  ████  │  │      │
│     │  └───────────────────────────┘  │      │
│     │                                 │      │
│     └─────────────────────────────────┘      │
│                                              │
│   Pillado Empresas © 2026                    │
│   Trayectoria y Compromiso                   │
└─────────────────────────────────────────────┘
```

### 4.2 Dashboard Gerencial (Desktop)

```
┌──────────────────────────────────────────────────────────────────────┐
│ [≡] SICOM-ICEO          🔍 Buscar...           🔔(3) [MO]          │
├────────────┬─────────────────────────────────────────────────────────┤
│            │                                                         │
│ [Logo]     │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐  │
│ SICOM-ICEO │  │ICEO      │ │OTs       │ │Cumpl. PM │ │Inventario│  │
│            │  │  92.7    │ │  47      │ │  94.2%   │ │$124.5M   │  │
│ Dashboard  │  │  ▲ 2.1   │ │  ▼ 3     │ │  ▲ 1.8   │ │  ▲ 5.2M  │  │
│ Contratos  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘  │
│ Activos    │                                                         │
│ OTs ●      │  ┌─────────────────────┐ ┌─────────────────────┐      │
│ Mantenim.  │  │ ICEO Tendencia      │ │ OTs por Estado      │      │
│ Inventario │  │                     │ │                     │      │
│ Abastecim. │  │ 📈 Line chart      │ │ 🍩 Donut chart     │      │
│ Cumplim.   │  │ 6 meses             │ │ con leyenda         │      │
│ KPI        │  │                     │ │                     │      │
│ ICEO       │  └─────────────────────┘ └─────────────────────┘      │
│ Reportes   │                                                         │
│ Auditoría  │  ┌─────────────────────┐ ┌─────────────────────┐      │
│ Admin      │  │ ⚠ OTs Vencidas    │ │ 📋 Vencimientos     │      │
│            │  │                     │ │                     │      │
│ ───────    │  │ OT-202603-00034 🔴 │ │ SEC Surt-003  🟡   │      │
│ [MO]       │  │ OT-202603-00028 🔴 │ │ Rev.Téc CT-001 🟡  │      │
│ Manuel O.  │  │ OT-202603-00041 🔴 │ │ SOAP LM-002   🟢  │      │
│ Admin      │  └─────────────────────┘ └─────────────────────┘      │
│ [Salir]    │                                                         │
└────────────┴─────────────────────────────────────────────────────────┘
```

### 4.3 Dashboard Gerencial (Móvil)

```
┌──────────────────────┐
│ [≡]  SICOM    🔔 [M] │
├──────────────────────┤
│ ┌──────────────────┐ │
│ │ ICEO    92.7  ▲  │ │
│ └──────────────────┘ │
│ ┌──────────────────┐ │
│ │ OTs Activas  47  │ │
│ └──────────────────┘ │
│ ┌──────────────────┐ │
│ │ PM       94.2%   │ │
│ └──────────────────┘ │
│ ┌──────────────────┐ │
│ │ Inv.    $124.5M  │ │
│ └──────────────────┘ │
│                      │
│ ┌──────────────────┐ │
│ │ ICEO Tendencia   │ │
│ │ 📈 Chart         │ │
│ └──────────────────┘ │
│                      │
│ ┌──────────────────┐ │
│ │ OTs por Estado   │ │
│ │ 🍩 Chart         │ │
│ └──────────────────┘ │
│ ...                  │
└──────────────────────┘
```

### 4.4 Detalle OT (Desktop)

```
┌──────────────────────────────────────────────────────────────────────┐
│ [≡] Dashboard > Órdenes de Trabajo > OT-202603-00012                │
├────────────┬─────────────────────────────────────────────────────────┤
│  Sidebar   │                                                         │
│            │  OT-202603-00012                                        │
│            │  [Preventivo] [Alta] [En Ejecución]                    │
│            │                                                         │
│            │  Activo: Cisterna-001 (Volvo FH 540)                   │
│            │  Faena: Mina Principal    Responsable: J. Pérez         │
│            │  Programada: 15/03/2026   Inicio: 15/03 08:30          │
│            │                                                         │
│            │  ┌──────────┬──────────┬──────────┬──────────┐         │
│            │  │Checklist │Evidencias│Materiales│Historial │         │
│            │  └──────────┴──────────┴──────────┴──────────┘         │
│            │                                                         │
│            │  ☑ Inspección visual nivel aceite motor    [OK]  📷    │
│            │  ☑ Verificar presión neumáticos            [OK]  📷    │
│            │  ☐ Cambio filtro aceite CAT 1R-0751       [   ] 📷    │
│            │  ☐ Cambio aceite motor Shell Rimula R4    [   ] 📷    │
│            │  ☐ Verificar sistema frenos               [   ]        │
│            │  ☐ Inspección mangueras hidráulicas       [   ]        │
│            │                                                         │
│            │  ┌──────────────────────────────────────────┐          │
│            │  │ [Pausar]  [Finalizar ✓]  [No Ejecutada] │          │
│            │  └──────────────────────────────────────────┘          │
└────────────┴─────────────────────────────────────────────────────────┘
```

### 4.5 Salida de Inventario (Móvil — optimizado para terreno)

```
┌──────────────────────┐
│ [←] Salida Inventario│
├──────────────────────┤
│                      │
│  ┌──────────────────┐│
│  │                  ││
│  │   📷 ESCANEAR   ││
│  │    PRODUCTO      ││
│  │                  ││
│  └──────────────────┘│
│                      │
│  OT Asociada *       │
│  ┌──────────────────┐│
│  │ OT-202603-00012  ││
│  │ PM Cisterna-001  ││
│  └──────────────────┘│
│  ⚠ OBLIGATORIO       │
│                      │
│  Producto *          │
│  ┌──────────────────┐│
│  │ Shell Rimula R4  ││
│  │ Stock: 450 L     ││
│  │ CPP: $4.200/L    ││
│  └──────────────────┘│
│                      │
│  Cantidad *          │
│  ┌──────────────────┐│
│  │      40          ││
│  └──────────────────┘│
│  Total: $168.000     │
│                      │
│  Bodega *            │
│  ┌──────────────────┐│
│  │ BOD-MP-01        ││
│  └──────────────────┘│
│                      │
│  ┌──────────────────┐│
│  │                  ││
│  │ REGISTRAR SALIDA ││
│  │        ████      ││
│  │                  ││
│  └──────────────────┘│
│                      │
│  👤 M. Olivares      │
│  📅 25/03/2026 14:32 │
│  📍 Faena Mina Ppal  │
└──────────────────────┘
```

### 4.6 ICEO Dashboard (Desktop)

```
┌──────────────────────────────────────────────────────────────────────┐
│ [≡] Dashboard > ICEO                                                 │
├────────────┬─────────────────────────────────────────────────────────┤
│  Sidebar   │                                                         │
│            │              ┌──────────────────┐                      │
│            │              │    ╭─────────╮   │                      │
│            │              │   ╱    92.7   ╲  │                      │
│            │              │  ╱             ╲ │                      │
│            │              │ ████████████▓▓░░ │                      │
│            │              │     BUENO 🟢     │                      │
│            │              │  Marzo 2026      │                      │
│            │              │ Incentivo: ✅     │                      │
│            │              └──────────────────┘                      │
│            │                                                         │
│            │  ┌───────────┐ ┌───────────┐ ┌───────────┐            │
│            │  │  Área A   │ │  Área B   │ │  Área C   │            │
│            │  │  96.25    │ │  83.00    │ │  100.0    │            │
│            │  │  ████████ │ │  ██████▓▓ │ │  █████████│            │
│            │  │ Adm.Comb. │ │ Ptos.Fij. │ │ Ptos.Móv. │            │
│            │  └───────────┘ └───────────┘ └───────────┘            │
│            │                                                         │
│            │  KPI Detalle — Área A ▼                                │
│            │  ┌─────┬────────┬──────┬─────┬──────┬─────┬────┐      │
│            │  │Cód. │KPI     │Valor │Meta │Cumpl.│Punt.│Bloq│      │
│            │  ├─────┼────────┼──────┼─────┼──────┼─────┼────┤      │
│            │  │A1   │Dif.Inv │0.3%  │0.5% │100%  │100  │    │      │
│            │  │A4   │Normativ│100%  │100% │100%  │100  │ 🔒 │      │
│            │  │A5   │Abastec │92%   │95%  │96.8% │75   │    │      │
│            │  └─────┴────────┴──────┴─────┴──────┴─────┴────┘      │
│            │                                                         │
│            │  ┌─────────────────────┐ ┌─────────────────────┐      │
│            │  │ Tendencia ICEO      │ │ Bloqueantes         │      │
│            │  │ 📈 6 meses          │ │ A4 Normativo   ✅   │      │
│            │  │                     │ │ B1 Disponib.   ✅   │      │
│            │  │                     │ │ B4 Certific.   ✅   │      │
│            │  │                     │ │ B6 Incidentes  ✅   │      │
│            │  │                     │ │ C1 Flota       ✅   │      │
│            │  │                     │ │ C6 Doc.Legal   ✅   │      │
│            │  │                     │ │ C7 Accidentes  ✅   │      │
│            │  └─────────────────────┘ └─────────────────────┘      │
└────────────┴─────────────────────────────────────────────────────────┘
```

---

## 5. COMPONENTES UI IMPLEMENTADOS

| Componente | Archivo | Descripción |
|------------|---------|-------------|
| Button | `ui/button.tsx` | 5 variantes (primary verde, secondary naranjo, outline, danger, ghost), 3 tamaños, loading state |
| Badge | `ui/badge.tsx` | Variantes para estado OT, criticidad, semáforo, ICEO, brand colors |
| Card | `ui/card.tsx` | Card/Header/Title/Content/Footer, shadow-sm, rounded-xl |
| Input | `ui/input.tsx` | Label + error + helper, focus verde, min-h 44px mobile |
| Select | `ui/select.tsx` | Dropdown con misma estética que input |
| Modal | `ui/modal.tsx` | Portal, fullscreen mobile, max-w-lg desktop, ESC para cerrar |
| Table | `ui/table.tsx` | Responsive horizontal scroll, filas striped opcionales |
| Spinner | `ui/spinner.tsx` | SVG animado, 3 tamaños |
| Semáforo | `ui/semaforo.tsx` | Dot de estado operacional + variante ICEO |
| Gauge | `ui/gauge.tsx` | SVG semicircular para ICEO, gradiente de color, animado |

---

## 6. RESPONSIVE BREAKPOINTS

| Breakpoint | Ancho | Diseño |
|-----------|-------|--------|
| Mobile | < 640px | 1 columna, sidebar como drawer, botones full-width, cards apiladas |
| Tablet | 640-1024px | 2 columnas, sidebar colapsable, tablas scrollables |
| Desktop | > 1024px | 4 columnas max, sidebar expandido (w-64), tablas completas |

### Adaptaciones clave por dispositivo:

**Móvil (terreno):**
- Botones mínimo 48px alto (touch target)
- Inputs mínimo 44px alto
- Sidebar como drawer overlay con backdrop
- OTs se muestran como cards, no tabla
- Escáner usa cámara del dispositivo
- Formularios de una columna
- Botón de acción sticky en bottom

**Tablet (supervisión):**
- Sidebar colapsable a íconos
- Grids de 2 columnas
- Tablas con scroll horizontal
- Dashboards con 2 gráficos por fila

**Desktop (gestión/gerencia):**
- Sidebar expandido permanente
- Grids hasta 4 columnas
- Tablas completas sin scroll
- Dashboards con todos los widgets visibles

---

## 7. NAVEGACIÓN

### 7.1 Sidebar (13 secciones)

| Ícono | Sección | Ruta |
|-------|---------|------|
| LayoutDashboard | Dashboard | /dashboard |
| FileText | Contratos | /dashboard/contratos |
| Cog | Activos | /dashboard/activos |
| ClipboardList | Órdenes de Trabajo | /dashboard/ordenes-trabajo |
| Wrench | Mantenimiento | /dashboard/mantenimiento |
| Package | Inventario | /dashboard/inventario |
| Fuel | Abastecimiento | /dashboard/abastecimiento |
| ShieldCheck | Cumplimiento | /dashboard/cumplimiento |
| BarChart3 | KPI | /dashboard/kpi |
| Gauge | ICEO | /dashboard/iceo |
| FileSpreadsheet | Reportes | /dashboard/reportes |
| Eye | Auditoría | /dashboard/auditoria |
| Settings | Administración | /dashboard/admin |

### 7.2 Header

- Hamburger menu (mobile) + breadcrumbs (desktop)
- Campana de notificaciones con contador badge naranjo
- Avatar de usuario con dropdown (perfil, cerrar sesión)

---

## 8. STACK FRONTEND

| Tecnología | Versión | Propósito |
|-----------|---------|-----------|
| Next.js | 14.2 | Framework React (App Router, SSG para Netlify) |
| React | 18.3 | UI library |
| TypeScript | 5.5 | Tipado estático |
| Tailwind CSS | 3.4 | Estilos utilitarios |
| class-variance-authority | 0.7 | Variantes de componentes |
| clsx + tailwind-merge | - | Merge de clases CSS |
| Supabase JS | 2.45 | Cliente de base de datos + auth |
| Zustand | 4.5 | Estado global |
| TanStack Query | 5.50 | Cache de servidor |
| React Hook Form | 7.52 | Formularios |
| Zod | 3.23 | Validación de esquemas |
| Recharts | 2.12 | Gráficos |
| Lucide React | 0.400 | Iconos |
| html5-qrcode | 2.3 | Escáner de códigos de barras |
| @react-pdf/renderer | 3.4 | Generación PDF |
| ExcelJS | 4.4 | Generación Excel |
| date-fns | 3.6 | Manejo de fechas |

---

*Documento generado para SICOM-ICEO — Fase 3 — Diseño Frontend Responsive*
*Versión 1.0 — Marzo 2026*
