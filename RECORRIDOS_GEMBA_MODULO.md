# Módulo Recorridos Gemba — SICOM-ICEO

Digitaliza los recorridos de terreno del área de Prevención de Riesgos para **taller y faenas**, con checklists por cargo, plan de acción con seguimiento y KPIs de cumplimiento.

## Qué incluye

| Archivo | Descripción |
|---|---|
| `database/production_run/288_recorridos_gemba.sql` | Tablas, RLS por permiso de módulo, vistas de resumen y seeds de las 3 plantillas |
| `database/production_run/289_gemba_jefes_operaciones_calidad.sql` | Reorienta los checklists de los jefes: operación y calidad del equipo, no seguridad |
| `database/production_run/290_gemba_cadencia_diaria_jt.sql` | Cadencia por checklist + el del Jefe de Taller partido en núcleo fijo diario y bloque rotativo |
| `database/production_run/291_gemba_prevencion_diaria_y_mensual.sql` | Prevención: caminata diaria de conducta + inspección planificada mensual |
| `frontend/src/lib/services/gemba.ts` | Servicio Supabase (tipos, queries, mutaciones) |
| `frontend/src/hooks/use-gemba.ts` | Hooks react-query |
| `frontend/src/app/dashboard/prevencion/gemba/page.tsx` | Lista de recorridos + KPIs + plan de acción global |
| `frontend/src/app/dashboard/prevencion/gemba/nuevo/page.tsx` | Iniciar recorrido (plantilla, taller/faena, foco) |
| `frontend/src/app/dashboard/prevencion/gemba/[id]/page.tsx` | Ejecución del checklist, hallazgos y cierre |
| `frontend/src/app/dashboard/prevencion/page.tsx` | (modificado) botón de acceso al módulo |

## Modelo de datos

- **`gemba_plantillas`** — checklists por cargo, secciones e ítems en JSONB. `roles TEXT[]` dice a qué rol se le propone cada uno. Seeds:

  | Código | Rol | Cadencia | Foco | Tamaño |
  |---|---|---|---|---|
  | `GEMBA-PREV-DIA` | `prevencionista` | **diaria** | **Conducta**: observar una tarea completa, hablar con quien la hace, corregir en el momento | 6 ítems |
  | `GEMBA-PREV` | `prevencionista` | **mensual** | **Seguridad, inspección planificada**: EPP, 5S, máquinas, eléctrico, SUSPEL, emergencias, ergonomía, conductas | 36 ítems |
  | `GEMBA-JT` | `jefe_mantenimiento` | **diaria** | **Operación y calidad del equipo**: cumplimiento del plan, qué frena el trabajo, calidad de lo ejecutado, gate de salida al cliente | 11-12 por día (30 en la semana) |
  | `GEMBA-JOP` | `jefe_operaciones` | **quincenal** | **El sistema y el cliente**: compromiso cumplido, calidad de lo entregado, el taller como sistema, obstáculos del equipo, faena | 23 ítems |

  **Prevención lleva dos y no una rotativa (MIG291):** el checklist del Jefe de Taller se puede repartir en la semana porque es de operación; una inspección planificada a la que le falta un bloque deja de servir como evidencia del programa preventivo. Por eso la caminata diaria es una plantilla aparte y la inspección va entera una vez al mes.

  **Rotación (MIG290).** Una sección con `"dia"` en el JSONB (1 = lunes … 5 = viernes) solo se carga ese día; sin `dia` es fija. El recorrido diario del Jefe de Taller son 7 ítems fijos + el bloque del día, y en la semana cubre el taller completo. Un checklist de 28 ítems diarios no se hace: se marca todo "cumple" sin mirar. Fin de semana sin bloque → solo el núcleo fijo.

  **Aviso de cadencia.** La portada del módulo compara el último recorrido propio contra la cadencia de su checklist y avisa cuando toca ("Todavía no has hecho el recorrido de hoy"). Se calcula sobre los datos existentes, sin un programa aparte que mantener.

  Los tres recorren, pero **no buscan lo mismo**: la inspección de seguridad es del prevencionista; los jefes miran que el trabajo fluya y que el equipo salga impecable. En los checklists de los jefes queda un solo ítem de seguridad ("no se tolera el riesgo evidente"), no una inspección.

  Los ítems de los jefes están escritos contra cosas que el sistema ya sabe (plan taller, OT, pauta, vale de bodega, NC, checklist de entrega, certificado, informe de salida): el recorrido se puede contrastar con el dato en vez de quedar en impresión.
- **`gemba_recorridos`** — cada recorrido: fecha, taller o faena (`faena_id` → `faenas`), sector, responsable (`usuarios_perfil`), foco, estado `en_curso`/`cerrado`.
- **`gemba_respuestas`** — ítems pre-cargados desde la plantilla al iniciar; `cumple` / `no_cumple` / `no_aplica` + observación.
- **`gemba_hallazgos`** — plan de acción: hallazgo, acción correctiva, responsable, fecha compromiso, estado `abierta`/`en_proceso`/`cerrada`.
- **Vistas:** `vw_gemba_recorrido_resumen` (% cumplimiento por recorrido, sin contar N/A) y `vw_gemba_kpi` (recorridos del mes, hallazgos abiertos/vencidos, % cumplimiento 90 días **ponderado por ítem**).

## Quién puede qué

La escritura la decide el permiso **`create` del módulo `prevencion`**, vía `fn_gemba_puede_gestionar()` → `fn_tiene_permiso_modulo` (MIG126). Defaults: `administrador`, `prevencionista`, `jefe_mantenimiento`, `jefe_operaciones`. Se agregan o quitan roles desde **Admin → Perfiles y roles**, sin migración.

La misma lista está en `use-permissions.ts` (`prevencion.create`). **Si las dos se separan, el botón aparece y la base rechaza al guardar** — mantenerlas alineadas.

Dos reglas que viven en la base, no en la pantalla:
- **Un recorrido cerrado es inmutable**: no se editan sus ítems ni se reabre (solo `administrador` puede corregir un cierre por error).
- **El plan de acción sigue vivo después del cierre**: las acciones se cierran semanas después, y el responsable de una acción puede avanzarla aunque no gestione el módulo.

Ninguna tabla tiene policy de DELETE: un recorrido no se borra.

## Instalación

1. **Base de datos**: `node database/scripts/aplicar-migracion.mjs database/production_run/288_recorridos_gemba.sql`. Requiere `fn_set_updated_at`, `fn_tiene_permiso_modulo`, `faenas` y `usuarios_perfil`. Es idempotente: re-aplicarla también re-afirma el mapeo checklist→rol.
2. **Frontend**: sin dependencias nuevas.
3. **Navegación**: cuelga de Prevención (`/dashboard/prevencion/gemba`), botón "Recorridos Gemba". Para entrada propia en la sidebar:
   ```ts
   { label: 'Recorridos Gemba', href: '/dashboard/prevencion/gemba', icon: Footprints, module: 'prevencion' },
   ```

## Flujo de uso

1. **Nuevo recorrido** → el checklist del cargo viene preseleccionado (los otros siguen disponibles: a veces se cubre al otro). La pantalla dice qué toca hoy ("Hoy es martes: fijas + Calidad de lo ejecutado — 11 ítems"). Se elige lugar (taller o faena), sector, acompañantes y foco. Al iniciar se pre-cargan los ítems del día.
2. **En terreno** (móvil) → Cumple / No cumple / N/A + observación. Al marcar **No cumple** se abre el registro del hallazgo con acción correctiva, responsable y fecha compromiso.
3. **Cierre** → solo cuando no quedan ítems pendientes; guarda hora de término y bloquea el checklist.
4. **Seguimiento** → KPIs y plan de acción global en la portada del módulo.

## Pendiente

**Fase 1 — que sirva en terreno**
- Foto por ítem y por hallazgo (el resto del sistema es evidencia fotográfica; sin foto no se puede verificar el cierre).
- Offline (reusar el patrón de `use-offline-checklist` / `enex-db`): en faena hay mala señal y hoy cada tap es un round-trip.
- Hallazgo → NC/OT en un clic, y acciones vencidas a la campanita (MIG283). Hoy `gemba_hallazgos` es un silo aparte del mundo de mantenimiento.
- Un "No cumple" puede quedar sin hallazgo (el modal tiene "Omitir" y el gate de cierre solo cuenta pendientes).

**Fase 2 — que sea Lean y no una auditoría**
- Recordatorio fuera de la app (correo o campanita) cuando toca el recorrido: hoy el aviso solo aparece al entrar al módulo.
- Verificación de eficacia al cerrar una acción (quién verificó + foto), que alimente el ítem 3.2 del checklist del Jefe de Operaciones.
- Tendencia por ítem/sección (los 5 que más fallan en 90 días) → materia prima de la reunión de mejora.
- Cambiar el KPI estrella de "% cumplimiento" a "obstáculos levantados / resueltos en plazo / verificados": el % premia marcar *cumple*.
- Enganchar los ítems de los jefes con el dato del sistema (que el ítem "los vales pendientes llevan menos de 24 h" muestre la lista al lado, en vez de que el jefe lo verifique de memoria).
- Sacar la sección de faena de `GEMBA-JOP` a su propia plantilla, en vez de marcarla N/A en cada recorrido de taller.
- Administración de plantillas desde UI (hoy se editan por SQL en `gemba_plantillas.secciones`).
