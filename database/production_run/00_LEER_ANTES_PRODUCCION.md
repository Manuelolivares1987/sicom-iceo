# 00 — LEER ANTES DE EJECUTAR EN PRODUCCIÓN

> 🛑 **Este procedimiento se ejecutará sobre la base de PRODUCCIÓN real.**
> 🛑 **No hay staging.** Cualquier error puede afectar a usuarios reales.
> 🛑 **Tampoco hay rollback automático completo:** depende de tu backup previo.

---

## Reglas absolutas

1. ⛔ **NO ejecutar si no hay backup confirmado** (paso `01_backup_obligatorio.md`).
2. ⛔ **NO ejecutar si hay usuarios trabajando** en el sistema.
3. ⛔ **NO ejecutar todo en una sola sesión.** Pausa entre bloques para validar.
4. ⛔ **NO ejecutar mig 52 Blocks B/C/D** (no incluidos en este procedimiento).
5. ⛔ **NO ejecutar el seed de capas FIFO** sin Finanzas validando costos.
6. ⛔ **NO ejecutar el seed de stock inicial combustible** sin litros físicos verificados (varillaje) + costo histórico validado.
7. ⛔ **Si un precheck falla, STOP.** Investigar antes de continuar.
8. ⛔ **Si una validación falla, STOP.** No avanzar al siguiente apply.

---

## Ventana recomendada

| Día / hora | Comentario |
|---|---|
| **Sábado 18:00 – 23:00** | Sin operación, ventana cómoda. |
| **Domingo 09:00 – 13:00** | Buffer si rebalsa. |
| **Lunes 06:00** | Validación rápida y comunicación de retoma. |

**Evitar:** lunes a viernes 08:00–20:00 (operación activa). Evitar último día del mes (cierre).

---

## Orden de ejecución

| # | Archivo | Tipo | Crítico | Pausa después |
|---|---|---|---|---|
| 01 | `01_backup_obligatorio.md` | Manual | 🔴 | Confirmar backup |
| 02 | `02_prechecks_produccion_safe.sql` | Solo lectura | 🔴 | Revisar diagnóstico |
| 03 | `03_bitacora_ejecucion.sql` | DDL ligero | 🟢 | — |
| 04 | `04_apply_mig55_produccion.sql` | DDL + funciones | 🔴 | Revisar logs |
| 05 | `05_validate_mig55_produccion.sql` | Solo lectura + ROLLBACK | 🔴 | Confirmar OK |
| 06 | `06_seed_datos_maestros_produccion.sql` | INSERT idempotente | 🟡 | — |
| 07 | `07_apply_mig56_fifo_produccion.sql` | DDL + función FIFO | 🔴 | Revisar logs |
| 08 | `08_validate_mig56_fifo_produccion.sql` | Solo lectura + ROLLBACK | 🔴 | Confirmar OK |
| 09 | `09_seed_capas_iniciales_fifo_produccion.sql` | **MANUAL con Finanzas** | 🔴 | Reconciliar |
| 10 | `10_apply_mig57_combustible_cpp_produccion.sql` | DDL + RPC | 🔴 | Revisar logs |
| 11 | `11_validate_mig57_combustible_cpp_produccion.sql` | Solo lectura + ROLLBACK | 🔴 | Confirmar OK |
| 12 | `12_seed_stock_inicial_combustible_produccion.sql` | **MANUAL con Finanzas** | 🔴 | Reconciliar |
| 13 | `13_validate_roles_dashboards_produccion.sql` | Solo lectura | 🟡 | — |
| 14 | `14_optional_mig52_blockA_qr_publico_produccion.sql` | **OPCIONAL — no ejecutar salvo decisión** | ⚪ | — |
| 15 | `15_checklist_go_no_go_produccion.md` | Doc final | 🔴 | Decidir GO/NO GO |
| 16 | `16_monitoring_post_deploy.sql` | Solo lectura | 🟢 | A 1h, 24h, 7d |

---

## Cómo detener (criterios STOP)

🛑 Detener inmediatamente si:

- Cualquier query reporta `ERROR` o `EXCEPTION` no esperada.
- `current_database()` no apunta al proyecto correcto.
- Un usuario reporta que el sistema dejó de funcionar.
- Una validación devuelve filas que indican desincronización.
- Login con cualquier rol deja de funcionar.
- Stock aparece negativo en cualquier producto.

→ Si ocurre cualquiera: **NO avanzar al siguiente paso.** Revertir si es posible (cada apply tiene rollback comentado al final). Si no se puede revertir: contactar respaldo Supabase + comunicar usuarios.

---

## Cómo registrar bitácora

Cada paso ejecutado debe registrarse en la tabla `operacion_migraciones_log` (creada en paso `03`). Adicionalmente:

1. Tomar **screenshot del SQL Editor** después de ejecutar cada script.
2. Anotar en `15_checklist_go_no_go_produccion.md` (sección Bitácora):
   - Fecha y hora exactas.
   - Script ejecutado.
   - Resultado (OK / FALLA / PARCIAL).
   - Observaciones.
3. Guardar todo en una carpeta local `produccion_2026-05-XX/` con:
   - Screenshots.
   - Backup pre-ejecución (link/archivo).
   - Output de cada query de validación.

---

## Archivos que NO ejecutar

| Archivo | Razón |
|---|---|
| `13_optional_mig52_blockA_qr_publico_produccion.sql` (#14 en orden) | Solo si se decide habilitar QR público en terreno + se actualiza frontend |
| Cualquier script con `mig 52 Block B/C/D` | NO incluidos. Requieren auditoría seguridad dedicada |
| Cualquier script de FASE 5.6 con `npm audit fix --force` | Riesgo de breaking changes en deps |

---

## Equipo y disponibilidad

| Rol | Disponibilidad mínima |
|---|---|
| Administrador (Manuel) | Toda la ventana — ejecuta SQL |
| Finanzas | Disponible para validar costos (paso 09 y 12) |
| Bodeguero (Gustavo) | Lunes mañana para pruebas reales |
| Planificador (Eduardo) | Lunes mañana para pruebas reales |

---

## Antes de empezar

- [ ] Leí este archivo completo.
- [ ] Confirmé que `current_database()` apunta a producción.
- [ ] Tengo el backup obligatorio (paso 01).
- [ ] No hay usuarios activos.
- [ ] Tengo Finanzas disponible para paso 09 y 12.
- [ ] Tengo carpeta local para guardar evidencia.
- [ ] Tengo 4-6 horas continuas para la ventana.

→ Si **TODOS** marcados, proceder al paso `01_backup_obligatorio.md`.
