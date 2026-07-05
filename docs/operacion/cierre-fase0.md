# Cierre operativo — Fase 0 (estado real)

**Fecha:** 2026-07-05 · **Estado:** desplegada en producción (bundle 185/186/187/189). MIG188 **no** ejecutada.

## Corrección del informe de despliegue

- Redacción correcta de la métrica de seguridad:
  **48 funciones anónimas inseguras → 0; 2 funciones QR permanecen públicas mediante allowlist controlada** (`rpc_guardar_checklist_publico`, `rpc_checklist_cliente_guardar`).
- **No** se declara "sin riesgos abiertos": el respaldo pre-despliegue aún **no está almacenado externamente** (copia local cifrada únicamente).

## Pendientes operativos (abiertos)

| # | Pendiente | Responsable | Estado |
|---|---|---|---|
| 1 | Copia **externa** del backup cifrado (fuera del PC y de Supabase) | Operación | abierto |
| 2 | Confirmar **backups administrados de Supabase** en el panel | Operación | abierto |
| 3 | Prueba real del **correo de fiabilidad** post-despliegue | Operación | abierto |
| 4 | Observación de **movimientos reales de combustible** 48 h (litros y valor bajan juntos con MIG187) | Operación | abierto |

## Riesgos residuales

- Las 2 funciones QR siguen aceptando escritura pública sin límites/rate-limit → **Sprint 1 Plataforma, frente 3**.
- Sin backups automáticos ni restauración programada → **frente 1**.
- Tablas núcleo sin RLS (`no_conformidades`, `estado_diario_flota`, etc.) → **frente 5**.

Este documento se cierra cuando los 4 pendientes operativos estén resueltos.
