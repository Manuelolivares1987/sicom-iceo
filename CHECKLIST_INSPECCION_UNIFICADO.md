# Checklist de Inspección Unificado (CL-INSPECCION-V03)

> **Fecha:** 2026-06-16 · **Migraciones:** 142 (esquema) + 143 (seed + gates)
> **Origen:** pestaña *Recepcion* del Excel oficial
> `Copia de 01 - Camion Aljibe Agua Industrial (Revisado).xlsx`

## Qué es

Una **única lista de inspección** que reemplaza a `CL-RECEPCION-V02` y pasa a ser
la fuente de verdad **tanto para recepción como para calidad**. De sus ítems
marcados `no_ok` nacen las **No Conformidades** (cableado existente, MIG 141).

- **11 bloques del Excel** + **1 bloque nuevo de pruebas operativas**.
- **Tiempo en minutos por ítem** (columna del Excel): subtotal por bloque y total.
  **Total recepción = 550 min** (sin pruebas operativas) + 84 min de pruebas.
- Cada ítem enriquecido con: instrumento de captura, default de recobro
  (cliente / empresa / compartido / evaluar), categoría de calidad
  (documentación / técnica) y si es **crítico** (bloquea aprobación del gate).

## Bloques (orden de despliegue)

| # | Bloque | enum | min | Notas |
|---|--------|------|-----|-------|
| 1 | Documentación y certificaciones | `b1_documentacion` | 24 | categoría = documentación |
| 2 | Estado exterior y cabina | `b2_estado_exterior` | 145 | |
| 3 | Motor y niveles | `b3_motor_niveles` | 132 | |
| 4 | Sistema eléctrico | `b_sistema_electrico` *(nuevo)* | 41 | |
| 5 | Revisión de fugas por componente | `b_fugas` *(nuevo)* | 16 | |
| 6 | Sistemas específicos del equipamiento | `b4_sistema_equipo` | 85 | solo `aljibe_agua` |
| 7 | Seguridad activa | `b5_seguridad_activa` | 32 | |
| 8 | Diagnóstico electrónico | `b6_diagnostico_electronico` | 22 | |
| 9 | Inventario y elementos de seguridad | `b_inventario_seguridad` *(nuevo)* | 18 | |
| 10 | Kit de invierno (opcional) | `b_kit_invierno` *(nuevo)* | 12 | obligatorio = false |
| 11 | **Pruebas operativas** | `b_pruebas_operativas` *(nuevo)* | 84 | ruta / recirculación / regadío |
| 12 | Cierre y responsabilidades | `b7_cierre_recepcion` | 23 | |

## Pruebas operativas — "según corresponda"

Aplican por `tipo_equipamiento` del activo (filtro automático en
`fn_inicializar_checklist_v2`):

| Prueba | `prueba_tipo` | Equipos a los que aplica |
|--------|---------------|--------------------------|
| **Ruta** | `ruta` | aljibe_agua, aljibe_combustible, pluma_grua, ampliroll, tracto, camioneta |
| **Recirculación** | `recirculacion` | aljibe_agua, aljibe_combustible |
| **Regadío** (aspersores / barra / cañón) | `regadio` | aljibe_agua |

## Una sola plantilla para recepción y calidad

| Flujo | Cómo consume la plantilla |
|-------|---------------------------|
| **Recepción / devolución** | El trigger de `estado_comercial='en_recepcion'` crea la instancia desde el template activo (V03), filtrando ítems por equipo. Items `no_ok` → NC (MIG 141). |
| **Auditoría de calidad (Gate 2)** | `fn_iniciar_auditoria_calidad` copia los ítems del template activo filtrados por equipo. Mapea bloque→categoría, hereda `critico` y auto-valida documentación contra `certificaciones` vía `cert_tipo`. |
| **Chequeo cruzado (Gate 1)** | `fn_crear_chequeo_cruzado` copia los ítems **técnicos** del template (excluye documentación, que no aplica a verificar trabajo en curso), filtrados por equipo. |

Ambos gates tienen *fallback* a su plantilla legacy si el template no aportara ítems.

## Orden de aplicación en producción

1. `database/production_run/142_checklist_inspeccion_unificado_schema.sql`
2. `database/production_run/143_checklist_inspeccion_unificado_seed.sql`

> Van en 2 archivos porque Postgres no permite usar valores de enum recién
> agregados en la misma transacción. La query de validación al final de 143
> debe devolver `minutos_sin_pruebas = 550` y `activo_v03 = true`.

## Nota operativa a evaluar

El chequeo cruzado de fin de turno hereda ~170 ítems técnicos (el equipo aljibe
agua tiene el set completo). Es lo solicitado ("una sola plantilla"), pero si en
terreno resulta pesado para una verificación de avance, se puede acotar Gate 1 a
un subconjunto (p. ej. solo bloques tocados por la OT) sin afectar recepción ni
la auditoría de calidad.
