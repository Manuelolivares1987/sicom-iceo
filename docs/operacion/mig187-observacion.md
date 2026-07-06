# Observación MIG187 (comportamiento futuro de valorización de combustible)

**Fecha:** 2026-07-05 · Read-only sobre prod. MIG188 **desautorizada** (no regulariza histórico este sprint).

## Estado

| Estanque | Demo | Stock (lt) | Valor columna | Diff vs (stock×CPP) |
|---|---|---|---|---|
| EST-1K | no | 117.00 | 94 700.00 | **+94 644.07** (residuo bug C5) |
| EST-15K | no | 986.00 | 4 493.33 | **+4 027.54** (residuo bug C5) |
| EST-600, CAM-HHWB42/44, CAM-JGBY10/KVWD27/LCSX78 | no | 0 | 0 | 0 |
| CAM-DEMO-1/2 | **sí (excluidos)** | — | — | — |

- Movimientos de combustible últimas 48 h: **1**; **post-despliegue: 0**.

## Interpretación

MIG187 corrige el **comportamiento futuro**: toda salida/traspaso nuevo actualizará `valor_total_stock` junto con los litros. Las diferencias de EST-1K/EST-15K son el **residuo histórico** del bug (litros correctos, valor inflado) que **MIG188 regularizaría** — pendiente de ventana separada con dry-run + autorización.

**Acción de observación (48 h):** al primer movimiento real en EST-1K/EST-15K, confirmar que `valor_total_stock` baja proporcional al CPP (no solo litros). Registrar antes/después.
