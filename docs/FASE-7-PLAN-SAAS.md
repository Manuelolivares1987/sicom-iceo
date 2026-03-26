# FASE 7 — PLAN DE EVOLUCIÓN SAAS

## SICOM-ICEO: De Solución Single-Tenant a Plataforma SaaS Multi-Tenant

**Versión:** 1.0
**Fecha:** Marzo 2026
**Clasificación:** Confidencial — Documento para stakeholders e inversores
**Cliente actual:** Pillado Empresas (operación minera en producción)

---

## ÍNDICE

1. [Visión SaaS](#1-visión-saas)
2. [Arquitectura Multi-Tenant](#2-arquitectura-multi-tenant)
3. [Modelo de Negocio](#3-modelo-de-negocio)
4. [Roadmap de Producto (12 meses)](#4-roadmap-de-producto-12-meses)
5. [Stack Técnico para Escala](#5-stack-técnico-para-escala)
6. [Estrategia de Migración](#6-estrategia-de-migración)
7. [Seguridad y Compliance](#7-seguridad-y-compliance)
8. [Equipo Necesario](#8-equipo-necesario)
9. [Métricas de Éxito](#9-métricas-de-éxito)
10. [Riesgos y Mitigaciones](#10-riesgos-y-mitigaciones)

---

## 1. VISIÓN SAAS

### 1.1 Contexto del Mercado

La industria minera en Chile y Latinoamérica opera bajo contratos de servicio altamente regulados donde empresas contratistas proveen combustibles, lubricantes y mantenimiento de plataformas fijas y móviles. Actualmente, la gestión operacional de estos contratos se realiza con planillas Excel, papel y sistemas ERP genéricos que no capturan la realidad del terreno.

No existe una solución vertical SaaS que integre:
- Control operacional de abastecimiento de combustibles y lubricantes
- Mantenimiento preventivo y correctivo de plataformas (islas, estanques, surtidores, cisterna, lubrimóviles)
- Inventario valorizado con trazabilidad completa
- Medición automatizada de excelencia operacional (ICEO)

### 1.2 De Single-Tenant a Plataforma

SICOM-ICEO opera actualmente para **Pillado Empresas** en producción, gestionando contratos de servicio en faenas mineras chilenas. El sistema ya resuelve problemas reales: 33 tablas PostgreSQL, 21+ funciones de cálculo KPI/ICEO, flujo completo de órdenes de trabajo con evidencia fotográfica, inventario valorizado con Kardex, y modo offline para operaciones en terreno.

**La oportunidad:** Cada empresa contratista de servicios mineros enfrenta los mismos problemas. Pillado Empresas no es la excepción sino la regla. La validación en producción con un cliente real es la base para escalar.

### 1.3 Propuesta de Valor

| Para | Problema | Solución SICOM-ICEO |
|------|----------|---------------------|
| **Gerente de contrato** | No tiene visibilidad de cumplimiento contractual en tiempo real | Dashboard ICEO con semáforos por área, alertas de incumplimiento, trazabilidad completa |
| **Supervisor de faena** | Gestiona OTs en papel, pierde evidencia, no tiene control de inventario | App móvil con modo offline, checklists digitales, captura fotográfica con GPS |
| **Jefe de mantenimiento** | No puede predecir fallas ni controlar costos por activo | Planes preventivos automáticos por km/horas/tiempo, costeo por OT, historial de activo |
| **Gerencia general** | No puede demostrar cumplimiento ante mandante minero | Reportes PDF/Excel automáticos, ICEO certificable, auditoría completa |
| **Mandante minero** | No tiene cómo auditar al contratista en tiempo real | Portal de lectura con KPIs del contrato (feature Enterprise) |

### 1.4 Mercado Objetivo

**Segmento primario:** Empresas contratistas que proveen servicios de combustible, lubricación y mantenimiento a operaciones mineras en Chile.

**Tamaño estimado del mercado:**
- Chile: ~120 empresas contratistas activas en gran minería (Codelco, BHP, Anglo American, Antofagasta Minerals, etc.)
- Perú: ~80 empresas en operaciones similares
- Colombia, México, Brasil: ~200 empresas combinadas
- **TAM Latinoamérica:** ~400 empresas potenciales
- **SAM (Chile + Perú):** ~200 empresas
- **SOM (Year 1-3):** 5 a 30 empresas

**Segmento secundario (futuro):** Empresas de mantenimiento industrial, flotas de transporte de combustible, distribuidoras de lubricantes.

---

## 2. ARQUITECTURA MULTI-TENANT

### 2.1 Estrategia de Aislamiento: Shared Database, Row-Level Isolation

La arquitectura multi-tenant se implementa con **base de datos compartida y aislamiento por filas** mediante `organization_id` (tenant_id) en cada tabla, reforzado por **Supabase RLS (Row-Level Security)**.

Esta estrategia se elige porque:
- SICOM-ICEO ya usa 29 políticas RLS en Supabase — la base está construida
- El esquema actual (33 tablas) es lo suficientemente contenido para compartir
- Reduce costos operacionales vs. una base de datos por tenant
- Permite benchmarking cruzado (feature diferenciador del plan Enterprise)

```
┌───────────────────────────────────────────────────────────────────┐
│                    CAPA DE ENRUTAMIENTO                           │
│                                                                   │
│   pillado.sicom.cl ──→ org_id: uuid-pillado                      │
│   acme.sicom.cl ──────→ org_id: uuid-acme                        │
│   minserv.sicom.cl ──→ org_id: uuid-minserv                      │
│                                                                   │
│   Middleware Next.js resuelve subdominio → organization_id        │
│   JWT de Supabase incluye org_id en claims personalizados         │
└───────────────────────────┬───────────────────────────────────────┘
                            │
                            ▼
┌───────────────────────────────────────────────────────────────────┐
│                     SUPABASE (PostgreSQL)                          │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  TABLA: organizations (NUEVA)                                │  │
│  │  - id (UUID, PK)                                             │  │
│  │  - nombre                                                    │  │
│  │  - slug (UNIQUE) → para subdominio                           │  │
│  │  - plan (starter/professional/enterprise)                    │  │
│  │  - stripe_customer_id                                        │  │
│  │  - configuracion (JSONB)                                     │  │
│  │  - activo (boolean)                                          │  │
│  │  - created_at                                                │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                   │
│  Cada tabla existente recibe columna: organization_id (FK)        │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │  POLÍTICA RLS (ejemplo para contratos):                      │ │
│  │                                                              │ │
│  │  CREATE POLICY "tenant_isolation_contratos"                  │ │
│  │  ON contratos                                                │ │
│  │  FOR ALL                                                     │ │
│  │  USING (                                                     │ │
│  │    organization_id = (                                       │ │
│  │      auth.jwt() -> 'app_metadata' ->> 'organization_id'     │ │
│  │    )::uuid                                                   │ │
│  │  );                                                          │ │
│  └──────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────┘
```

### 2.2 Tablas Afectadas

Las 33 tablas actuales se agrupan así para la migración:

| Grupo | Tablas | Acción |
|-------|--------|--------|
| **Contractual** | `contratos`, `faenas`, `bodegas`, `configuracion_iceo` | Agregar `organization_id`, migrar datos de Pillado |
| **Usuarios** | `usuarios_perfil` | Agregar `organization_id`, vincular con `organizations` |
| **Activos** | `activos`, `marcas`, `modelos`, `pautas_fabricante`, `planes_mantenimiento`, `certificaciones` | `marcas` y `modelos` se comparten globalmente (catálogo). Resto: agregar `organization_id` |
| **OTs** | `ordenes_trabajo`, `historial_estado_ot`, `checklist_ot`, `evidencias_ot` | Agregar `organization_id` (heredan del contrato, pero se replica por rendimiento en queries) |
| **Inventario** | `productos`, `stock_bodega`, `movimientos_inventario`, `kardex`, `conteos_inventario`, `conteo_detalle` | `productos` puede ser compartido (catálogo). Resto: `organization_id` |
| **KPI/ICEO** | `kpi_diarios`, `iceo_mensual`, todas las tablas de compliance | Agregar `organization_id` |
| **Nuevas** | `organizations`, `subscriptions`, `invoices`, `audit_log_global` | Crear desde cero |

### 2.3 Subdomain Routing

```typescript
// middleware.ts (Next.js)
import { NextRequest, NextResponse } from 'next/server';

export function middleware(request: NextRequest) {
  const hostname = request.headers.get('host') || '';
  const subdomain = hostname.split('.')[0];

  // Subdominio "app" → pantalla de login/registro global
  if (subdomain === 'app' || subdomain === 'www') {
    return NextResponse.next();
  }

  // Subdominio de tenant → inyectar en headers para que
  // el layout resuelva el organization_id
  const response = NextResponse.next();
  response.headers.set('x-tenant-slug', subdomain);
  return response;
}
```

### 2.4 Modificación del JWT de Supabase

Al registrar o invitar un usuario a una organización, se almacena `organization_id` en `app_metadata` del JWT:

```sql
-- Al crear usuario en una organización
UPDATE auth.users
SET raw_app_meta_data = raw_app_meta_data ||
  jsonb_build_object('organization_id', 'uuid-de-la-org')
WHERE id = 'user-uuid';
```

Esto permite que **todas las políticas RLS** filtren automáticamente por tenant sin modificar queries en el frontend.

### 2.5 Límites por Plan

```sql
CREATE TABLE plan_limits (
  plan_type TEXT PRIMARY KEY, -- 'starter', 'professional', 'enterprise'
  max_contratos INTEGER,
  max_faenas INTEGER,
  max_activos INTEGER,
  max_usuarios INTEGER,
  tiene_api BOOLEAN DEFAULT FALSE,
  tiene_iceo BOOLEAN DEFAULT FALSE,
  tiene_reportes_avanzados BOOLEAN DEFAULT FALSE,
  tiene_integraciones BOOLEAN DEFAULT FALSE,
  sla_uptime NUMERIC(4,2) -- 99.00, 99.90, 99.99
);

-- Función de validación antes de INSERT
CREATE OR REPLACE FUNCTION check_plan_limit()
RETURNS TRIGGER AS $$
DECLARE
  current_count INTEGER;
  max_allowed INTEGER;
  org_plan TEXT;
BEGIN
  SELECT plan INTO org_plan FROM organizations WHERE id = NEW.organization_id;
  -- Lógica de validación según tabla y plan...
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

---

## 3. MODELO DE NEGOCIO

### 3.1 Planes y Precios

| Característica | Starter | Professional | Enterprise |
|---|---|---|---|
| **Precio mensual** | **$500 USD** | **$1.500 USD** | **$3.500+ USD** |
| **Precio anual** (descuento 15%) | $5.100 USD/año | $15.300 USD/año | Negociable |
| Contratos | 1 | 5 | Ilimitado |
| Faenas | 3 | 10 | Ilimitado |
| Activos | 50 | 200 | Ilimitado |
| Usuarios | 5 | 20 | Ilimitado |
| Órdenes de trabajo | Ilimitado | Ilimitado | Ilimitado |
| Dashboard operacional | Básico | Completo + KPI | Completo + KPI + BI |
| Cálculo ICEO | No | Mensual automatizado | Tiempo real + histórico |
| Reportes | PDF básico | PDF + Excel + programados | Custom + API |
| Inventario valorizado | Kardex básico | Kardex + CPP + conteos | Completo + integraciones ERP |
| Modo offline (PWA) | Parcial | Completo | Completo + sync prioritario |
| API REST pública | No | Lectura | Lectura + Escritura |
| Integraciones | No | Webhooks | SAP, Oracle, ERP custom |
| Portal mandante | No | No | Incluido |
| Soporte | Email (48h) | Email + chat (8h) | Dedicado + SLA (2h) |
| SLA uptime | 99.0% | 99.5% | 99.9% |
| Almacenamiento evidencias | 10 GB | 50 GB | 500 GB |
| Retención de datos | 1 año | 3 años | 7 años |
| Onboarding | Self-service | Asistido (2 sesiones) | Dedicado (proyecto) |

### 3.2 Justificación de Precios

Un contrato de servicio minero típico en Chile factura entre $50.000 y $500.000 USD mensuales. SICOM-ICEO representa entre el **0.1% y el 1%** de la facturación contractual, mientras ofrece:
- Reducción de pérdidas por despachos no trazados (típicamente 2-5% del combustible)
- Eliminación de multas por incumplimiento documental ($5.000-$50.000 USD por evento)
- Reducción de tiempo administrativo en reportería (40-60 horas/mes → 5 horas/mes)

**El ROI se paga solo con evitar una multa contractual al año.**

### 3.3 Proyecciones de Ingresos (Escenario Conservador)

#### Año 1: Validación de Mercado

| Mes | Clientes Starter | Clientes Professional | Clientes Enterprise | MRR | ARR |
|-----|-----|-----|-----|-----|-----|
| M1-M3 | 1 (Pillado migrado) | 0 | 0 | $500 | $6.000 |
| M4-M6 | 2 | 1 | 0 | $2.500 | $30.000 |
| M7-M9 | 2 | 2 | 0 | $4.000 | $48.000 |
| M10-M12 | 2 | 2 | 1 | $7.500 | $90.000 |
| **Total Year 1** | | | **5 clientes** | **$7.500** | **$90.000** |

#### Año 2: Crecimiento

| Trimestre | Starter | Professional | Enterprise | MRR | ARR |
|-----------|---------|-------------|-----------|-----|-----|
| Q1 | 3 | 4 | 2 | $14.500 | $174.000 |
| Q2 | 4 | 5 | 3 | $19.500 | $234.000 |
| Q3 | 4 | 6 | 3 | $21.500 | $258.000 |
| Q4 | 4 | 7 | 4 | $26.500 | $318.000 |
| **Total Year 2** | | | **15 clientes** | **$26.500** | **$318.000** |

#### Año 3: Escala Regional

| Trimestre | Starter | Professional | Enterprise | MRR | ARR |
|-----------|---------|-------------|-----------|-----|-----|
| Q1 | 5 | 10 | 5 | $35.000 | $420.000 |
| Q2 | 6 | 12 | 6 | $42.000 | $504.000 |
| Q3 | 6 | 13 | 7 | $49.000 | $588.000 |
| Q4 | 6 | 15 | 9 | $57.000 | $684.000 |
| **Total Year 3** | | | **30 clientes** | **$57.000** | **$684.000** |

### 3.4 Unit Economics

| Métrica | Year 1 | Year 2 | Year 3 |
|---------|--------|--------|--------|
| ARPU (promedio por cliente/mes) | $1.500 | $1.767 | $1.900 |
| CAC estimado | $3.000 | $4.000 | $5.000 |
| LTV (churn 5% mensual → 20 meses promedio) | $30.000 | $35.340 | $38.000 |
| LTV:CAC ratio | 10:1 | 8.8:1 | 7.6:1 |
| Payback period | 2 meses | 2.3 meses | 2.6 meses |
| Gross margin (estimado) | 75% | 78% | 82% |

**Nota:** El LTV:CAC ratio superior a 3:1 es excelente para SaaS B2B. El sector minero tiene baja rotación de proveedores, lo que reduce el churn natural.

---

## 4. ROADMAP DE PRODUCTO (12 MESES)

### Q1: Fundación Multi-Tenant (Meses 1-3)

**Objetivo:** Transformar SICOM-ICEO de single-tenant a multi-tenant y habilitar la primera venta nueva.

| Semana | Entregable | Detalle |
|--------|-----------|---------|
| S1-S2 | **Tabla `organizations` y migración de esquema** | Agregar `organization_id` a las 33 tablas existentes, migrar datos de Pillado Empresas como primer tenant |
| S3-S4 | **Políticas RLS multi-tenant** | Reescribir las 29 políticas RLS existentes para incluir filtro `organization_id` vía JWT claims |
| S5-S6 | **Subdomain routing** | Middleware Next.js para resolución `{cliente}.sicom.cl`, configuración DNS wildcard |
| S7-S8 | **Onboarding wizard** | Flujo de registro: crear organización → configurar primer contrato → invitar usuarios → setup inicial de activos |
| S9-S10 | **Integración Stripe** | Checkout por plan, gestión de suscripciones, webhooks para activación/suspensión, portal de billing |
| S11-S12 | **Panel de administración de tenant** | Gestión de usuarios, roles, configuración de la organización, uso de recursos vs. límites del plan |

**Criterio de éxito Q1:** Pillado Empresas operando sin regresión en el nuevo esquema multi-tenant + 1 cliente nuevo en onboarding.

### Q2: Diferenciación Competitiva (Meses 4-6)

**Objetivo:** Features que justifiquen el precio y generen lock-in.

| Semana | Entregable | Detalle |
|--------|-----------|---------|
| S13-S15 | **App móvil mejorada (PWA avanzado)** | Experiencia nativa en Android/iOS: notificaciones push, acceso a cámara optimizado, instalación desde browser. Evaluación de React Native para features específicos (Bluetooth para lectores de pistola) |
| S16-S18 | **Modo offline completo** | Extender la cola offline actual: sincronización bidireccional robusta, resolución de conflictos, indicador de estado, cache selectivo por faena. Actualmente SICOM maneja offline parcial con Service Worker + IndexedDB — llevar a 100% de operaciones de terreno |
| S19-S20 | **API REST pública v1** | Endpoints documentados con OpenAPI/Swagger para lectura de OTs, activos, KPIs, inventario. Autenticación por API keys vinculadas a organización. Rate limiting por plan |
| S21-S22 | **Notificaciones push + alertas configurables** | OT vencida, stock bajo mínimo, certificación por vencer, ICEO bajo umbral, activo fuera de servicio. Canales: push (PWA), email, webhook |
| S23-S24 | **Mejoras en OTs y checklists** | Templates de checklists compartibles entre organizaciones (marketplace interno), checklists condicionales (si falla X → ejecutar checklist Y), firma digital mejorada |

**Criterio de éxito Q2:** 3+ clientes activos, NPS > 40, adopción de modo offline > 80% en operaciones de terreno.

### Q3: Inteligencia Operacional (Meses 7-9)

**Objetivo:** Transformar datos operacionales en ventaja competitiva.

| Semana | Entregable | Detalle |
|--------|-----------|---------|
| S25-S27 | **Dashboard BI avanzado** | Visualizaciones interactivas: tendencias de ICEO por período, análisis de Pareto de fallas, heatmap de incidentes por faena, curvas de confiabilidad por tipo de activo. Drill-down desde contrato → faena → activo → OT |
| S28-S30 | **Predicción de fallas (ML básico)** | Modelo basado en historial de OTs correctivas + horas de uso + patrones estacionales. Alertas tipo: "Surtidor S-003 tiene 78% de probabilidad de falla en los próximos 15 días basado en historial de activos similares." Implementación con Edge Functions + modelo pre-entrenado (TensorFlow.js o API externa) |
| S31-S33 | **Alertas inteligentes** | Motor de reglas configurable por organización: combinación de condiciones (si ICEO < 85% AND OTs pendientes > 10 AND stock combustible < 20%) → notificar a gerente de contrato + crear OT de revisión automática |
| S34-S36 | **Benchmarking entre contratos** | Comparación anónima de KPIs entre contratos del mismo tipo (solo Enterprise). Métricas: MTBF, MTTR, cumplimiento de PM, costos por activo. Permite que mandantes y contratistas comparen rendimiento vs. industria |

**Criterio de éxito Q3:** Feature de predicción de fallas como diferenciador clave en pitch comercial. Al menos 1 caso documentado de falla prevenida.

### Q4: Escala y Expansión (Meses 10-12)

**Objetivo:** Preparar la plataforma para crecimiento regional y enterprise.

| Semana | Entregable | Detalle |
|--------|-----------|---------|
| S37-S39 | **Marketplace de integraciones** | Conectores pre-construidos: SAP PM (módulo de mantenimiento), Oracle EBS, Microsoft Dynamics. Framework de integración para que clientes Enterprise conecten sus ERPs. Foco inicial: exportar OTs cerradas y costos a ERP |
| S40-S42 | **White-label para distribuidores** | Permite que distribuidoras de combustible (Copec, Shell, ENEX en Chile) ofrezcan SICOM-ICEO con su marca a sus clientes contratistas. Modelo: revenue share 70/30 |
| S43-S45 | **Soporte multi-idioma** | Internacionalización completa: español (default), inglés (para mandantes internacionales como BHP, Anglo American), portugués (para expansión a Brasil). Incluye formatos de número, fecha, moneda |
| S46-S48 | **Preparación ISO 27001** | Gap analysis, implementación de controles faltantes, documentación de políticas, selección de auditor. La certificación completa se proyecta para Q2 del Año 2 |

**Criterio de éxito Q4:** 5+ clientes activos pagando, pipeline de 10+ leads calificados, al menos 1 acuerdo white-label en negociación.

---

## 5. STACK TÉCNICO PARA ESCALA

### 5.1 Estado Actual vs. Objetivo

```
ESTADO ACTUAL (Single-Tenant)              ESTADO OBJETIVO (SaaS Multi-Tenant)
────────────────────────────               ─────────────────────────────────────

Next.js 14 (App Router)          ──→       Next.js 14+ (mantener, es sólido)
├── Tailwind CSS + shadcn/ui     ──→       Mantener (agregar sistema de themes)
├── Zustand + TanStack Query     ──→       Mantener (agregar cache multi-tenant)
├── React Hook Form + Zod        ──→       Mantener
├── Recharts                     ──→       Recharts + Tremor (dashboards BI)
├── html5-qrcode                 ──→       Mantener + Bluetooth API
└── next-pwa + Workbox           ──→       Mantener + Background Sync API

Supabase                         ──→       Supabase (mantener como core)
├── Auth + RLS                   ──→       Auth + RLS multi-tenant + SSO (Enterprise)
├── PostgreSQL + RPC             ──→       PostgreSQL + read replicas
├── Storage Buckets              ──→       Storage + CDN (Cloudflare R2 backup)
├── Realtime Subscriptions       ──→       Mantener (filtrado por org_id)
└── Edge Functions               ──→       Edge Functions + Queue workers

Netlify                          ──→       Evaluar migración a Vercel
├── CDN + Deploy                 ──→       Edge Functions + ISR mejorado
├── Preview deploys              ──→       Preview deploys por PR
└── Build desde GitHub           ──→       GitHub Actions + deploy

                                 AGREGAR:
                                 ├── Redis (Upstash) → cache, rate limiting, sessions
                                 ├── Queue system (Inngest o Trigger.dev) → cálculos
                                 │   pesados de ICEO, generación de reportes, sync offline
                                 ├── Sentry → error tracking + performance monitoring
                                 ├── PostHog → product analytics + feature flags
                                 ├── Resend → emails transaccionales
                                 ├── Stripe → billing + subscriptions
                                 └── GitHub Actions → CI/CD pipeline completo
```

### 5.2 Decisiones Técnicas Clave

**Por qué mantener Supabase (no migrar a AWS/GCP):**
- Las 29 políticas RLS ya escritas representan semanas de trabajo. Migrar a otro PostgreSQL gestionado pierde Supabase Auth + RLS integration
- Supabase ofrece read replicas desde su plan Pro ($25/mes + compute)
- Edge Functions de Supabase manejan la lógica pesada actual (reportes PDF, procesamiento de lecturas, notificaciones)
- El costo de Supabase Pro ($25/mes) + Team ($599/mes para producción) es fracción vs. equivalente en AWS

**Por qué considerar Vercel sobre Netlify:**
- Next.js es de Vercel — soporte de primera clase para App Router, Server Actions, ISR
- Edge Functions de Vercel tienen mejor integración con middleware (subdomain routing)
- Vercel Pro ($20/usuario/mes) incluye analytics, speed insights, y preview comments
- **Decisión:** Migrar a Vercel en Q1, aprovechando que no hay lock-in relevante en Netlify

**Redis (Upstash) — necesidades específicas:**
- Cache de configuración de tenant (evitar query a `organizations` en cada request)
- Rate limiting por API key (plan Professional y Enterprise)
- Cache de cálculos KPI intermedios (los recálculos diarios via `pg_cron` son pesados)
- Session storage para datos de subdominio

**Sistema de colas — necesidades específicas:**
- Generación asíncrona de reportes PDF/Excel (actualmente bloquea Edge Functions)
- Recálculo de ICEO mensual para múltiples tenants (actualmente `pg_cron` ejecuta secuencialmente)
- Procesamiento de sincronización offline en lote
- Envío de notificaciones masivas

### 5.3 Infraestructura de CI/CD

```yaml
# .github/workflows/deploy.yml (estructura)
name: SICOM-ICEO CI/CD

on:
  push:
    branches: [main, staging]
  pull_request:
    branches: [main]

jobs:
  test:
    # Unit tests + integration tests
    # Validación de migraciones SQL contra esquema
    # Lint + type-check

  preview:
    # Deploy preview en Vercel para cada PR
    # Supabase branch database (preview)

  staging:
    # Deploy a staging.sicom.cl
    # Migraciones automáticas en Supabase staging
    # Smoke tests automatizados

  production:
    # Deploy a producción (manual approval)
    # Migraciones con rollback plan
    # Health checks post-deploy
    # Notificación al equipo
```

---

## 6. ESTRATEGIA DE MIGRACIÓN

### 6.1 Plan de Migración: Single-Tenant → Multi-Tenant

La migración se ejecuta en **5 fases con zero-downtime**, manteniendo Pillado Empresas operando durante todo el proceso.

#### Fase 1: Preparación (Semana 1-2)

```sql
-- 1. Crear tabla organizations
CREATE TABLE organizations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL, -- para subdominio
  plan TEXT NOT NULL DEFAULT 'professional',
  stripe_customer_id TEXT,
  configuracion JSONB DEFAULT '{}',
  activo BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Insertar Pillado como primera organización
INSERT INTO organizations (nombre, slug, plan)
VALUES ('Pillado Empresas', 'pillado', 'professional');
```

#### Fase 2: Agregar columnas (Semana 2-3)

```sql
-- Para cada tabla (ejemplo con contratos):
ALTER TABLE contratos
  ADD COLUMN organization_id UUID REFERENCES organizations(id);

-- Rellenar con ID de Pillado para datos existentes
UPDATE contratos
  SET organization_id = (SELECT id FROM organizations WHERE slug = 'pillado');

-- Hacer NOT NULL después de migrar
ALTER TABLE contratos
  ALTER COLUMN organization_id SET NOT NULL;

-- Crear índice para rendimiento
CREATE INDEX idx_contratos_org ON contratos(organization_id);
```

**Repetir para las 33 tablas** (script automatizado). Tablas compartidas (`marcas`, `modelos`, `productos` base) reciben tratamiento especial: se agregan como catálogo global con `organization_id IS NULL` para items compartidos.

#### Fase 3: Reescribir RLS (Semana 3-4)

```sql
-- Ejemplo: política actual (single-tenant)
DROP POLICY IF EXISTS "Usuarios ven contratos de su faena" ON contratos;

-- Nueva política multi-tenant
CREATE POLICY "tenant_isolation_contratos" ON contratos
FOR ALL USING (
  organization_id = (
    auth.jwt() -> 'app_metadata' ->> 'organization_id'
  )::uuid
);

-- Política adicional para rol admin global (soporte SICOM)
CREATE POLICY "superadmin_contratos" ON contratos
FOR ALL USING (
  (auth.jwt() -> 'app_metadata' ->> 'role') = 'superadmin'
);
```

#### Fase 4: Actualizar JWT y Auth (Semana 4-5)

```sql
-- Función que se ejecuta al crear/actualizar usuario
CREATE OR REPLACE FUNCTION set_user_organization()
RETURNS TRIGGER AS $$
BEGIN
  -- Setear organization_id en app_metadata del JWT
  UPDATE auth.users
  SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb) ||
    jsonb_build_object('organization_id', NEW.organization_id::text)
  WHERE id = NEW.user_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

#### Fase 5: Cutover (Semana 5-6)

1. **DNS:** Configurar `pillado.sicom.cl` como CNAME → deploy principal
2. **Middleware:** Activar subdomain routing en Next.js
3. **Testing:** Suite de tests E2E verificando que Pillado Empresas funciona idéntico
4. **Rollback plan:** Feature flag para desactivar multi-tenancy y volver a single-tenant en < 5 minutos

### 6.2 Estrategia Zero-Downtime

| Riesgo | Mitigación |
|--------|-----------|
| Columnas nuevas rompen queries existentes | `organization_id` se agrega como nullable → se rellena → se hace NOT NULL. En ningún momento se rompe el esquema |
| Políticas RLS nuevas bloquean a usuarios | Deploy con feature flag: las políticas nuevas coexisten con las actuales. Se activan por toggle |
| JWT sin `organization_id` | Fallback: si el JWT no tiene `organization_id`, usar lookup en `usuarios_perfil` → `organization_id`. Migración gradual de tokens |
| Caída durante migración SQL | Cada ALTER TABLE es transaccional en PostgreSQL. Si falla, rollback automático |

### 6.3 Testing Strategy

| Nivel | Herramienta | Cobertura |
|-------|-------------|-----------|
| **Unit tests** | Vitest | Funciones de cálculo KPI/ICEO, validaciones Zod, utilidades |
| **Integration tests** | Vitest + Supabase local | Políticas RLS (verificar aislamiento entre tenants), funciones PostgreSQL, triggers |
| **E2E tests** | Playwright | Flujo completo: login → crear OT → completar checklist → subir evidencia → cerrar OT → verificar KPI. Ejecutar para cada tenant |
| **Security tests** | Tests RLS dedicados | Intentar acceder a datos de Tenant A desde sesión de Tenant B. Debe fallar en 100% de los casos |
| **Load tests** | k6 | Simular 50 usuarios concurrentes por tenant, 10 tenants simultáneos |
| **Smoke tests** | Playwright (subset) | Post-deploy: verificar login, listar OTs, crear OT, ver dashboard — por tenant |

---

## 7. SEGURIDAD Y COMPLIANCE

### 7.1 Seguridad por Capas

```
┌─────────────────────────────────────────────────────────────────────┐
│  CAPA 1: RED Y TRANSPORTE                                          │
│  ├── HTTPS/TLS 1.3 en todos los endpoints (Vercel/Netlify SSL)     │
│  ├── HSTS habilitado                                                │
│  ├── Certificados gestionados automáticamente por plataforma        │
│  └── Wildcard SSL para *.sicom.cl                                   │
├─────────────────────────────────────────────────────────────────────┤
│  CAPA 2: AUTENTICACIÓN                                              │
│  ├── Supabase Auth con bcrypt (passwords)                           │
│  ├── Refresh tokens con rotación                                    │
│  ├── MFA (TOTP) obligatorio para roles admin y supervisor           │
│  ├── SSO (SAML/OIDC) para plan Enterprise                           │
│  └── Sesiones con expiración configurable por organización          │
├─────────────────────────────────────────────────────────────────────┤
│  CAPA 3: AUTORIZACIÓN                                               │
│  ├── RLS de PostgreSQL (aislamiento de datos por tenant)            │
│  ├── Roles por organización (admin, supervisor, técnico, lectura)   │
│  ├── Permisos granulares por módulo (contratos, OTs, inventario)    │
│  └── API keys con scopes limitados                                  │
├─────────────────────────────────────────────────────────────────────┤
│  CAPA 4: DATOS                                                      │
│  ├── Encryption at rest: AES-256 (Supabase/AWS default)             │
│  ├── Encryption in transit: TLS 1.3                                 │
│  ├── Campos sensibles (RUT, datos personales): pgcrypto             │
│  ├── Backups automáticos: diarios (Supabase) + export semanal a S3  │
│  └── Logs de auditoría inmutables (tabla audit_log)                 │
├─────────────────────────────────────────────────────────────────────┤
│  CAPA 5: APLICACIÓN                                                 │
│  ├── Validación con Zod en cliente y servidor                       │
│  ├── Sanitización de inputs (XSS prevention)                        │
│  ├── CSRF tokens en formularios                                     │
│  ├── Rate limiting por IP y por API key                             │
│  ├── Content Security Policy headers                                │
│  └── Dependency scanning (Dependabot + npm audit)                   │
└─────────────────────────────────────────────────────────────────────┘
```

### 7.2 Roadmap SOC 2 Type II

| Fase | Período | Actividades |
|------|---------|------------|
| **Readiness Assessment** | Meses 1-2 | Evaluación de gaps contra Trust Service Criteria. Documentar controles existentes |
| **Remediación** | Meses 3-6 | Implementar controles faltantes: gestión de accesos, change management, incident response, vendor management |
| **Monitoreo** | Meses 6-9 | Período de observación con controles activos. Evidencia continua |
| **Auditoría Type I** | Mes 10 | Auditoría puntual — verifica diseño de controles |
| **Período de observación** | Meses 10-16 | Mínimo 6 meses de operación documentada |
| **Auditoría Type II** | Mes 16-18 | Auditoría completa — verifica diseño y operación efectiva |

**Costo estimado:** $15.000-$30.000 USD (auditoría) + $5.000-$10.000 USD (herramienta de compliance como Vanta o Drata).

### 7.3 Backup y Recuperación

| Métrica | Objetivo | Implementación |
|---------|----------|----------------|
| **RPO** (Recovery Point Objective) | 1 hora | Supabase point-in-time recovery (PITR) en plan Pro + WAL archiving |
| **RTO** (Recovery Time Objective) | 4 horas | Procedimiento documentado de restauración. Testear trimestralmente |
| **Retención de backups** | 30 días (PITR) + 1 año (snapshots semanales) | Snapshots exportados a S3 con lifecycle policy |
| **Backup de evidencias** | Replicación cross-region | Supabase Storage con replicación + backup a Cloudflare R2 |
| **Test de restauración** | Trimestral | Restaurar backup en ambiente aislado y validar integridad |

### 7.4 Privacidad y Regulaciones LATAM

| Regulación | País | Impacto en SICOM-ICEO | Acción |
|-----------|------|----------------------|--------|
| **Ley 19.628** (Protección de Datos Personales) | Chile | RUT, nombres, firmas de técnicos son datos personales | Consent al registro, derecho de eliminación, cifrado de campos sensibles |
| **Ley 21.719** (nueva ley de datos Chile, vigente 2026) | Chile | Requisitos más estrictos: DPO, evaluaciones de impacto, notificación de brechas | Designar DPO, implementar DPIA, plan de respuesta a incidentes |
| **LGPD** (Lei Geral de Proteção de Dados) | Brasil | Aplica si operamos en Brasil (Year 3) | Base legal para procesamiento, derechos ARCO, DPO |
| **Ley 29733** | Perú | Similar a regulación chilena | Consent, registro de bases de datos, seguridad |

### 7.5 Penetration Testing

| Tipo | Frecuencia | Alcance |
|------|-----------|---------|
| **Automated scanning** | Semanal | OWASP ZAP contra staging |
| **Vulnerability assessment** | Trimestral | Infraestructura + aplicación (Supabase, Vercel, DNS) |
| **Penetration test externo** | Anual | Firma especializada (presupuesto: $8.000-$15.000 USD). Foco en: aislamiento multi-tenant, escalación de privilegios, API abuse |
| **Bug bounty** | Continuo (Year 2+) | Programa privado en HackerOne/Bugcrowd. Bounties: $100-$2.000 |

---

## 8. EQUIPO NECESARIO

### 8.1 Fase 1: Fundación (Meses 0-6)

| Rol | Dedicación | Responsabilidades | Costo mensual estimado (Chile) |
|-----|-----------|-------------------|-------------------------------|
| **Full-stack Developer Senior** | 100% | Implementación multi-tenant, reescritura RLS, subdomain routing, integración Stripe, API pública. Debe dominar PostgreSQL + Next.js + Supabase | $4.000-$5.500 USD |
| **DevOps / SRE** | 50% → 100% | CI/CD pipeline, monitoreo, migración a Vercel, configuración DNS wildcard, Redis, cola de tareas, backups | $3.500-$5.000 USD |
| **Product Designer** | 50% | Onboarding wizard, panel admin tenant, mejoras UX mobile, sistema de themes para white-label | $2.500-$3.500 USD |
| **Customer Success** | 50% | Onboarding de primeros clientes, documentación, soporte nivel 1, feedback loop con producto | $2.000-$3.000 USD |
| **Subtotal Fase 1** | | | **$12.000-$17.000 USD/mes** |

### 8.2 Fase 2: Crecimiento (Meses 6-12)

| Rol | Dedicación | Responsabilidades | Costo mensual estimado |
|-----|-----------|-------------------|----------------------|
| Equipo Fase 1 (4 personas) | 100% | Continuidad | $14.000-$19.000 USD |
| **+1 Backend Developer** | 100% | API pública, integraciones ERP (SAP, Oracle), motor de ML para predicción de fallas, optimización de queries para multi-tenant | $3.500-$5.000 USD |
| **+1 Frontend Developer** | 100% | Dashboard BI avanzado, PWA mejorado, internacionalización, componentes de benchmarking | $3.000-$4.500 USD |
| **+1 Sales / Business Development** | 100% | Prospección en sector minero, demos, ciclo de venta enterprise, relación con distribuidoras para white-label | $2.500-$4.000 USD (+ comisiones) |
| **+1 Support Engineer** | 100% | Soporte nivel 1-2, documentación técnica, onboarding técnico, monitoreo de salud de tenants | $2.000-$3.000 USD |
| **Subtotal Fase 2** | | | **$25.000-$35.500 USD/mes** |

### 8.3 Estructura Organizacional Objetivo (Mes 12)

```
CEO / Founder
├── CTO (puede ser el Full-stack Senior inicial)
│   ├── Full-stack Developer Senior
│   ├── Backend Developer
│   ├── Frontend Developer
│   └── DevOps/SRE
├── Head of Product (puede ser el Designer inicial)
│   └── Product Designer
├── Head of Sales
│   └── Customer Success
│       └── Support Engineer
└── Finance/Admin (externo o part-time)
```

**Total headcount Mes 12:** 8-9 personas
**Burn rate mensual (equipo + infra + operaciones):** $30.000-$42.000 USD

---

## 9. MÉTRICAS DE ÉXITO

### 9.1 Métricas Financieras

| Métrica | Target Year 1 | Target Year 2 | Target Year 3 |
|---------|--------------|---------------|---------------|
| **MRR** (Monthly Recurring Revenue) | $7.500 | $26.500 | $57.000 |
| **ARR** (Annual Recurring Revenue) | $90.000 | $318.000 | $684.000 |
| **Gross Revenue Churn** (mensual) | < 3% | < 2% | < 1.5% |
| **Net Revenue Retention** | > 100% | > 110% | > 120% |
| **Gross Margin** | > 70% | > 75% | > 80% |
| **CAC Payback** | < 4 meses | < 3 meses | < 3 meses |

### 9.2 Métricas de Producto

| Métrica | Target Q2 | Target Q4 | Target Year 2 |
|---------|----------|----------|---------------|
| **DAU/MAU** (Daily/Monthly Active Users) | > 50% | > 60% | > 65% |
| **Time to Value** (días desde signup hasta primera OT cerrada) | < 14 días | < 7 días | < 3 días |
| **Feature Adoption: OTs** | > 90% | > 95% | > 95% |
| **Feature Adoption: Inventario** | > 60% | > 75% | > 85% |
| **Feature Adoption: ICEO** | > 30% | > 50% | > 70% |
| **Feature Adoption: Modo Offline** | > 40% | > 60% | > 80% |
| **Uptime** | 99.0% | 99.5% | 99.9% |
| **P95 Response Time** | < 500ms | < 300ms | < 200ms |

### 9.3 Métricas de Satisfacción

| Métrica | Target Year 1 | Target Year 2 | Target Year 3 |
|---------|--------------|---------------|---------------|
| **NPS** (Net Promoter Score) | > 30 | > 45 | > 55 |
| **CSAT** (Customer Satisfaction) | > 4.0/5.0 | > 4.3/5.0 | > 4.5/5.0 |
| **Time to Resolution** (soporte) | < 48h | < 24h | < 8h (Enterprise: 2h) |
| **Tickets por cliente/mes** | < 5 | < 3 | < 2 |

### 9.4 Métricas de Crecimiento

| Métrica | Target Year 1 | Target Year 2 | Target Year 3 |
|---------|--------------|---------------|---------------|
| **Clientes activos** | 5 | 15 | 30 |
| **Pipeline calificado** | 15 leads | 40 leads | 80 leads |
| **Win rate** | > 25% | > 30% | > 35% |
| **Sales cycle** (días promedio) | 90 | 60 | 45 |
| **Referral rate** | 10% | 20% | 30% |

---

## 10. RIESGOS Y MITIGACIONES

### 10.1 Riesgos Técnicos

| Riesgo | Probabilidad | Impacto | Mitigación |
|--------|-------------|---------|-----------|
| **Rendimiento de base de datos con múltiples tenants** | Media | Alto | Índices compuestos `(organization_id, ...)` en todas las tablas. Read replicas para queries pesadas (dashboards, reportes). Monitoreo continuo de query performance. Particionamiento de tablas grandes (movimientos_inventario, kardex) si superan 10M filas |
| **Aislamiento de datos comprometido** | Baja | Crítico | RLS como barrera primaria (PostgreSQL, no aplicación). Tests automatizados de aislamiento en CI/CD. Penetration test anual enfocado en cross-tenant access. Auditoría de queries que bypassen Supabase client |
| **Migración rompe operación de Pillado** | Media | Alto | Feature flags para rollback instantáneo. Ambiente staging con copia de producción. Migración fuera de horario operacional (faenas operan en turnos: migrar en ventana de cambio de turno, 2-4 AM) |
| **Deuda técnica por velocidad de desarrollo** | Alta | Medio | Code reviews obligatorios. Coverage mínimo de 60% en lógica de negocio. Refactoring sprints cada 6 semanas. Documentación de decisiones arquitectónicas |
| **Dependencia de Supabase** | Baja | Alto | Supabase es open-source. En caso extremo, se puede migrar a PostgreSQL autohosteado + GoTrue (auth) + PostgREST. Evitar uso de features propietarias sin alternativa |

### 10.2 Riesgos de Mercado

| Riesgo | Probabilidad | Impacto | Mitigación |
|--------|-------------|---------|-----------|
| **Competencia de CMMS establecidos** (SAP PM, Maximo, Fiix, UpKeep) | Alta | Medio | SICOM-ICEO no compite como CMMS genérico. El diferenciador es la verticalización: ICEO, gestión de contratos de combustible/lubricantes, compliance minero chileno. Los CMMS grandes no resuelven esto |
| **Ciclo de venta largo en minería** | Alta | Medio | Free trial de 30 días con datos de demo realistas (seed data ya incluye datos de minería chilena). Casos de éxito documentados con Pillado Empresas. Targeting a nivel de gerente de contrato (no a nivel corporativo) |
| **Resistencia al cambio en operaciones** | Alta | Medio | UX diseñada para técnicos en terreno (botones grandes, flujos simples, modo offline). Onboarding presencial en faena para primeros clientes. Videos tutoriales por rol. Transición gradual (módulo por módulo) |
| **Concentración en un solo sector** | Media | Medio | Arquitectura genérica permite pivotar a otros sectores industriales (energía, construcción, transporte). Pero mantener foco en minería durante Year 1-2 es crítico para product-market fit |

### 10.3 Riesgos Operacionales

| Riesgo | Probabilidad | Impacto | Mitigación |
|--------|-------------|---------|-----------|
| **Soporte a escala con equipo pequeño** | Alta | Alto | Documentación exhaustiva + base de conocimiento. Chatbot con FAQ. Soporte tiered: self-service → email → videollamada. Automatizar onboarding al máximo |
| **Onboarding costoso por cliente** | Media | Medio | Wizard de onboarding que guía paso a paso (crear contrato → importar activos CSV → configurar usuarios). Templates de checklists por industria. Datos de ejemplo pre-cargados |
| **Key person risk** (dependencia del desarrollador principal) | Alta | Crítico | Documentación de arquitectura y decisiones. Code reviews. Pair programming. Knowledge sharing sessions semanales. Contratar segundo developer antes de mes 6 |

### 10.4 Riesgos Financieros

| Riesgo | Probabilidad | Impacto | Mitigación |
|--------|-------------|---------|-----------|
| **Burn rate supera ingresos por más de 18 meses** | Media | Alto | Fases de contratación ligadas a MRR milestones. No contratar Fase 2 hasta alcanzar $10K MRR. Mantener runway mínimo de 12 meses |
| **Churn alto en primeros clientes** | Media | Alto | Quarterly Business Reviews con cada cliente. Monitoreo proactivo de uso (alertar si un tenant deja de usar el sistema). Contratos anuales con descuento incentivan retención |
| **Pricing incorrecto** | Media | Medio | Empezar con pricing flexible (descuentos caso a caso). Ajustar basado en willingness-to-pay de primeros 5 clientes. Grandfather pricing para early adopters |

---

## RESUMEN EJECUTIVO: TIMELINE E INVERSIÓN

### Timeline de 18 Meses

```
MES  1  2  3  4  5  6  7  8  9  10 11 12 13 14 15 16 17 18
     ├──────────┤
     │ MIGRACIÓN MULTI-TENANT
     │ (Pillado operando en nueva arquitectura)
     │
     ├─────────────────────┤
     │ ONBOARDING + BILLING + PRIMER CLIENTE NUEVO
     │
                ├──────────────────────┤
                │ PWA + OFFLINE + API + NOTIFICACIONES
                │
                           ├──────────────────────┤
                           │ BI + ML + BENCHMARKING
                           │
                                      ├──────────────────────┤
                                      │ INTEGRACIONES + i18n │
                                      │ + WHITE-LABEL + ISO  │

     ├────────────────────┤
     │ EQUIPO FASE 1 (4p) │
                           ├─────────────────────────────────┤
                           │ EQUIPO FASE 2 (8p)              │
```

### Inversión Requerida

| Concepto | Meses 0-6 | Meses 6-12 | Meses 12-18 | Total |
|----------|-----------|-----------|------------|-------|
| **Equipo** | $84.000 | $180.000 | $216.000 | $480.000 |
| **Infraestructura** (Supabase, Vercel, Redis, servicios) | $3.000 | $6.000 | $12.000 | $21.000 |
| **Legal** (términos de servicio, privacidad, contratos) | $5.000 | $2.000 | $3.000 | $10.000 |
| **Seguridad** (pentest, compliance tools) | $2.000 | $8.000 | $20.000 | $30.000 |
| **Marketing y ventas** | $3.000 | $12.000 | $18.000 | $33.000 |
| **Contingencia** (15%) | $14.550 | $31.200 | $40.350 | $86.100 |
| **Total** | **$111.550** | **$239.200** | **$309.350** | **$660.100** |

### Punto de Equilibrio

Con un burn rate promedio de **$36.700/mes** y un crecimiento conservador de clientes:

- **Break-even operacional** (MRR cubre costos operacionales): **Mes 14-16** (~$26.500 MRR con 15 clientes)
- **Break-even total** (ingresos acumulados cubren inversión total): **Mes 22-24**

### Retorno de Inversión

| Escenario | Inversión Total | ARR Year 3 | Valoración estimada (5x ARR) | ROI |
|-----------|----------------|-----------|-------------------------------|-----|
| **Conservador** | $660.000 | $684.000 | $3.420.000 | 5.2x |
| **Base** | $660.000 | $1.000.000 | $5.000.000 | 7.6x |
| **Optimista** | $660.000 | $1.500.000 | $7.500.000 | 11.4x |

---

### Conclusión

SICOM-ICEO tiene una ventaja competitiva poco frecuente: **un producto validado en producción real con un cliente pagando** en un mercado vertical con dolor medible y pocos competidores especializados. La transformación a SaaS multi-tenant no requiere reescribir el sistema — requiere extenderlo. El esquema PostgreSQL, las políticas RLS, las funciones de cálculo ICEO y la infraestructura PWA offline ya existen y funcionan.

El riesgo principal no es técnico sino comercial: ejecutar la transición sin perder la operación de Pillado Empresas y demostrar tracción con 5 clientes en 12 meses. Con un equipo de 4 personas iniciales y una inversión controlada de ~$110K en los primeros 6 meses, la apuesta es asimétrica: downside limitado, upside significativo en un mercado que todavía opera con planillas Excel.

**La pregunta no es si el mercado necesita SICOM-ICEO. La pregunta es si podemos ejecutar lo suficientemente rápido para capturar la ventana de oportunidad.**

---

*Documento preparado para evaluación de stakeholders e inversores.*
*SICOM-ICEO — Sistema Integral de Control Operacional, Mantenimiento, Inventario e ICEO*
*Marzo 2026*
