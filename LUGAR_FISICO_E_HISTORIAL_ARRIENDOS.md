# Lugar físico + Historial de arriendos del equipo

> **Fecha:** 2026-06-16 · **Migración:** 145 · **Pedido:** comercial

## Qué resuelve

1. **Lugar físico del camión** (además del contrato): faena estructurada
   (`activos.faena_id`, con coordenadas) + detalle libre (`activos.ubicacion_actual`).
2. **Al pasar a `en_recepcion` o `disponible`**: ver el **último que lo arrendó y dónde**.
3. **Historial de arriendos** del equipo (cliente, lugar, inicio, fin, días).

## Cómo está hecho (sin doble captura)

Se reconstruye desde `historico_estado_activo` (ya registra cada cambio de
`estado_comercial`). MIG 145:

- Enriquece `historico_estado_activo` con `faena_id`, `cliente`, `ubicacion_lugar`
  y actualiza el trigger `fn_registrar_historico_estado_activo` para que capture
  ese snapshot (cliente del activo o del contrato; faena y lugar del activo) en
  cada cambio de estado.
- **Vista `v_historial_arriendos`**: cada período de uso (`arrendado` / `leasing`
  / `uso_interno`) con cliente, lugar, faena, inicio, fin (= siguiente cambio,
  NULL = vigente) y días.
- **Vista `v_activo_ultimo_arriendo`**: el último período por equipo →
  "quién lo tuvo y dónde".

## Datos iniciales (Excel "Status cam")

`database/scripts/cargar-status-cam.mjs`: por patente, fija
`cliente_actual` (col H) + `ubicacion_actual` (col I, lugar físico), calza la
faena del contrato cuando el nombre coincide, y deja una línea base en
`historico_estado_activo` (`origen='importado'`, idempotente) para que el
"último arriendo" e historial muestren la foto de hoy.

Uso:
```
SUPABASE_DB_URL=... NODE_PATH=<node_modules con pg y exceljs> \
  node database/scripts/cargar-status-cam.mjs
```

## Frontend (ficha del activo)

- Header: línea **"Lugar físico"** (faena · ubicación).
- Banner **"Último arriendo"** cuando el equipo está en recepción/disponible.
- Tab **Historial → "Historial de arriendos"** (tabla cliente/lugar/tipo/desde/hasta/días).
- Hooks `useUltimoArriendo` / `useHistorialArriendos`, servicio `lib/services/arriendos.ts`.

## Orden de aplicación

1. `database/production_run/145_lugar_fisico_e_historial_arriendos.sql`
2. `node database/scripts/cargar-status-cam.mjs` (carga inicial desde el Excel)

## Nota

El historial automático cubre los cambios de estado **desde MIG 59 en adelante**
+ la línea base del Excel. El "lugar físico" en cada cambio futuro se captura del
valor que tenga el activo al momento; conviene que el modal de cambio de estado
permita ajustar faena/ubicación (mejora futura sugerida).
