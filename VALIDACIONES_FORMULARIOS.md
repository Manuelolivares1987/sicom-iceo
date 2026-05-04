# VALIDACIONES Y FORMULARIOS — SICOM-ICEO

> **Última actualización:** 2026-04-30 — FASE 6
> **Resumen:** Biblioteca Zod completa (12 dominios) creada y lista para uso incremental. Cero formularios refactorizados durante el piloto operativo.

---

## 1. Hallazgo principal

Auditoría con `grep "useForm|zodResolver|react-hook-form"` reveló que **solo 2 archivos** usan React Hook Form en todo el frontend:

| Archivo | RHF | Zod | Estado |
|---|---|---|---|
| `src/components/ot/crear-ot-modal.tsx` | ✅ | ✅ | Completo |
| `src/app/login/page.tsx` | ✅ | ❌ | Validación manual con `register` + mensaje genérico |

**El resto del sistema usa validación manual** con `useState` + checks ad-hoc dentro del `handleSubmit`. Este patrón funciona en operación pero tiene 3 debilidades:
1. Mensajes de error inconsistentes entre formularios.
2. Validaciones cruzadas (ej. fecha_fin > fecha_inicio) repartidas en múltiples lugares.
3. Riesgo de aceptar datos incompletos si se omite un check.

### Decisión de FASE 6

> **No refactorizar masivamente formularios durante el piloto.** Construir la **biblioteca Zod completa** lista para usar en cada formulario que se toque a futuro (ya sea por bug, mejora o nueva feature). Plan de aplicación incremental.

---

## 2. Formularios auditados

### 2.1 Formularios con validación robusta hoy

| Formulario | Archivo | RHF | Zod | Validación |
|---|---|---|---|---|
| Crear OT | `components/ot/crear-ot-modal.tsx` | ✅ | ✅ inline | tipo, activo_id, prioridad, fecha_programada, responsable, observaciones |
| Movimiento combustible (ingreso/despacho) | `app/dashboard/inventario/combustible/movimiento/page.tsx` | ❌ | ⚠️ schema existe | Schemas ya en `validations/combustible.ts` pero formulario usa `useState` |
| Varillaje combustible | `app/dashboard/inventario/combustible/varillaje/page.tsx` | ❌ | ⚠️ schema existe | Idem |
| Salida inventario | `app/dashboard/inventario/salida/page.tsx` | ❌ | ⚠️ schema existe | Schema en `validations/inventario.ts` pero formulario usa `useState` |
| Conteo inventario | `app/dashboard/inventario/conteo/page.tsx` | ❌ | ❌ | Validación manual |

### 2.2 Formularios con validación manual

| Formulario | Archivo | Riesgo de datos malos |
|---|---|---|
| Login | `app/login/page.tsx` | Bajo (Supabase Auth valida credenciales en el server) |
| Cambiar Estado Flota | `components/flota/cambiar-estado-modal.tsx` | Medio — `motivo` solo `.trim()`. Fecha futura con `min` HTML. Sin Zod. |
| Crear plantilla checklist | `app/dashboard/admin/checklist-templates/page.tsx` | Bajo — solo `nombre.trim()` |
| Editar usuario | `components/admin/editar-usuario-modal.tsx` | Bajo — campos preselectados desde la BD |
| Crear certificación | `app/dashboard/cumplimiento/page.tsx` | Medio — sin validación de fecha_vencimiento >= fecha_emision |
| Crear ruta de abastecimiento | `app/dashboard/abastecimiento/page.tsx` | Medio — sin validación cruzada |
| Crear medidor combustible | `app/dashboard/inventario/combustible/medidores/page.tsx` | Bajo |
| Inspección recepción | `app/dashboard/flota/inspeccion-recepcion/[informeId]/page.tsx` | Medio — sin validación de horómetros final > inicial |
| Aprobar verificación ready-to-rent | `app/dashboard/flota/aprobar/[otId]/page.tsx` | **Bajo** — la BD valida con `chk_doble_firma` + RPC `fn_aprobar_verificacion_disponibilidad` |

### 2.3 Formularios faltantes (CRUD no implementado en frontend)

| Dominio | Razón |
|---|---|
| Crear/editar Activos | CRUD se maneja por SQL/admin, no hay UI completa |
| Crear/editar Contratos | Solo lectura |
| Crear/editar Pautas Fabricante | Solo lectura |
| Crear/editar Planes Mantenimiento | Solo lectura desde UI; se crean desde lógica de negocio |
| Crear SUSPEL/RESPEL | Solo lectura |

---

## 3. Validaciones existentes en `src/validations/` (estado pre-FASE 6)

| Archivo | Schemas | Líneas | Uso real |
|---|---|---|---|
| `ot.ts` | `crearOTSchema`, `noEjecucionSchema`, `finalizarSchema`, `cerrarSupervisorSchema` | 44 | Solo `crearOTSchema` consumido por `crear-ot-modal.tsx` |
| `inventario.ts` | `salidaSchema`, `entradaSchema`, `ajusteSchema` | 38 | NO consumidos (formularios usan validación manual) |
| `combustible.ts` | `movimientoIngresoSchema`, `movimientoDespachoSchema`, `varillajeSchema` | 82 | NO consumidos (idem) |
| `index.ts` | re-export | 3 | Solo exporta ot e inventario |

---

## 4. Validaciones agregadas en FASE 6

> **Cero formularios modificados.** Solo se agregan archivos nuevos en `src/validations/`. La biblioteca queda lista para uso incremental.

| Archivo nuevo | Schemas exportados | Cobertura |
|---|---|---|
| `validations/activos.ts` | `activoCrearSchema`, `activoEditarSchema`, `actualizarMetricasSchema` | Alta y edición de activos, actualización de métricas (km/horas/ciclos) |
| `validations/mantenimiento.ts` | `planMantenimientoSchema`, `generarOTDesdePlanSchema`, `pautaFabricanteSchema` | Planes PM, generación OT desde plan, pautas |
| `validations/certificaciones.ts` | `certificacionSchema` | Alta y edición de certificación con regla `vencimiento >= emision` |
| `validations/abastecimiento.ts` | `rutaDespachoSchema`, `updateRutaEstadoSchema`, `abastecimientoSchema` | Rutas + transiciones + abastecimientos |
| `validations/contratos.ts` | `contratoSchema` | Alta de contrato con regla `fecha_fin > fecha_inicio` |
| `validations/prevencion.ts` | `suspelProductoSchema`, `respelMovimientoSchema` | SUSPEL/RESPEL |
| `validations/flota.ts` | `cambiarEstadoFlotaSchema`, `aprobarVerificacionSchema` | Cambio de estado (con regla "OT auto solo M/T/F") + ready-to-rent (horómetro final > inicial, road test ≥ 5 min) |
| `validations/checklists.ts` | `checklistItemSchema`, `checklistTemplateCrearSchema`, `checklistTemplateOperativoSchema`, `respuestaItemSchema` | Plantillas + respuestas. **`checklistTemplateOperativoSchema` exige ≥1 ítem para uso operativo** (cumple regla del spec) |
| `validations/admin.ts` | `editarUsuarioSchema`, `crearUsuarioPerfilSchema` | Edición de usuario + alta de perfil. RUT validado por regex `12.345.678-9` |
| `validations/index.ts` | re-export de los 12 dominios | Punto único de import |

### Reglas mínimas comunes

| Regla | Aplicada en |
|---|---|
| `string().trim()` en obligatorios | activos, mantenimiento, certificaciones, abastecimiento, contratos, prevencion, admin |
| IDs como UUID válido | todos donde aplica |
| Fechas con `min(10)` formato `YYYY-MM-DD` | certificaciones, contratos, mantenimiento, prevencion |
| `fecha_fin > fecha_inicio` (refine) | contratos |
| `fecha_vencimiento >= fecha_emision` (refine) | certificaciones |
| Horómetro final > inicial (refine) | flota.aprobarVerificacion, ya en combustible.movimiento |
| Cantidades `nonnegative()` o `positive()` | inventario, combustible, abastecimiento, prevencion |
| Anio fabricación 1950 ≤ x ≤ año+1 | activos |
| Largos máximos en strings | todos (motivo 500, observaciones 1000-2000) |
| Estados/prioridades con `z.enum(...)` | ot, flota, abastecimiento, contratos, etc. |
| RUT con regex chileno | admin |
| Email válido | admin |
| Plantilla checklist exige ≥1 ítem para operación | checklists.checklistTemplateOperativoSchema |
| Cambio "Disponible" sin checklist no se valida en Zod (lo bloquea trigger BD) | documentado |

---

## 5. Formularios donde NO se aplicó cambio (y motivo)

> **Decisión deliberada para no romper piloto operativo en curso.**

| Formulario | Por qué no se tocó |
|---|---|
| Cambiar Estado Flota | En operación con Eduardo (planificador) y otros. Cambio reciente (FASE 5.2). Aplicar Zod requeriría refactor del flujo de estados anidados (motivo, requiereOT, crearOT, ot_responsable_id) y validar contra `usePermissions` para fecha pasada. **Riesgo > beneficio en piloto.** |
| Salida / Entrada / Ajuste inventario | Schemas ya existían en `validations/inventario.ts` pero los formularios usan validación manual. Aplicar zodResolver requiere migrar el formulario a RHF. **Refactor mediano.** |
| Movimiento / Varillaje combustible | Idem (schemas existen, formulario manual). Crítico para Gustavo (bodega) — cualquier cambio puede romper la captura de fotos del medidor. |
| Crear OT desde modal | **Ya tiene Zod.** ✅ |
| Crear plantilla checklist | Cambio reciente (FASE 5.2). Validación manual mínima funciona. Zod aquí es opcional. |
| Editar usuario admin | Cambio reciente (FASE 5.1). Funciona. Aplicar Zod sería mejora cosmética. |
| Inspección recepción | Formulario complejo con múltiples secciones (checklist + costos + fotos). Refactor riesgoso. |
| Aprobar verificación ready-to-rent | La defensa real está en BD (mig 45 + `chk_doble_firma`). UI agregar Zod sería redundante. |
| Conteo inventario | Formulario operativo activo en el piloto con Gustavo. No tocar. |
| Crear ruta abastecimiento | No hay reportes de error operativos. |
| Crear certificación (modal Cumplimiento) | Funciona; agregar Zod requeriría refactor menor. |

---

## 6. Riesgos de datos corregidos en FASE 6

**Estructuralmente, ninguno** — porque no se aplicaron los schemas a formularios. Lo que sí queda **listo y disponible** para reducir riesgo cuando se aplique:

- `certificacionSchema` previene `fecha_vencimiento < fecha_emision` (corrige cargas con fechas invertidas).
- `contratoSchema` previene `fecha_fin <= fecha_inicio`.
- `cambiarEstadoFlotaSchema` previene crear OT automática para estados que no son M/T/F.
- `checklistTemplateOperativoSchema` previene marcar como operativa una plantilla con 0 ítems.
- `aprobarVerificacionSchema` previene horómetro final ≤ inicial y road test < 5 min.
- `actualizarMetricasSchema` exige al menos un valor a actualizar (no submit vacío).

---

## 7. Riesgos pendientes

| ID | Sev | Riesgo | Resolución |
|---|---|---|---|
| V01 | 🟠 | Inventario: salida/ajuste sin Zod en formulario actual; bodeguero podría enviar `cantidad=0` o motivo vacío | Migrar formulario a RHF + zodResolver con `salidaSchema` (post-piloto) |
| V02 | 🟠 | Combustible: ingreso/despacho con validación manual; foto obligatoria controlada por estado, no por schema | Migrar a RHF + zodResolver (post-piloto) |
| V03 | 🟡 | Cambio estado flota: motivo solo `.trim()` cliente; mínimo 5 caracteres está en Zod pero no aplicado | Aplicar Zod en próxima iteración del modal |
| V04 | 🟡 | Crear certificación: sin validación cruzada de fechas en cliente | Aplicar Zod cuando se toque el modal |
| V05 | 🟡 | Crear ruta abastecimiento: sin validación de fecha vs hoy | Aplicar Zod cuando se toque |
| V06 | 🟡 | Editar usuario: sin validación de RUT formato chileno | Aplicar `crearUsuarioPerfilSchema` cuando se toque |
| V07 | 🟢 | Plantilla checklist con 0 ítems puede asignarse a OT y dejarla sin validaciones | Aplicar `checklistTemplateOperativoSchema` cuando se agregue botón "Marcar operativa" |
| V08 | 🟢 | Login sin Zod (usa Supabase Auth) | Bajo riesgo; no urgente |
| V09 | 🟢 | Inspección recepción sin Zod en form complejo | Diferido; defensa real está en RPC |
| V10 | 🟡 | Doble submit: solo `crear-ot-modal` y `editar-usuario-modal` lo bloquean con `disabled={saving}` | Auditar todos los formularios y agregar disabled en submit cuando aplique. FASE 7. |

---

## 8. Recomendación para próximo sprint

### Plan de aplicación incremental (FASE 7 o sprint operativo)

**Orden sugerido (de más impacto a menos):**

1. **Cambio Estado Flota** (`cambiar-estado-modal.tsx`) — aplicar `cambiarEstadoFlotaSchema`. Es el flujo más crítico del piloto operativo.
2. **Salida / Ajuste de inventario** — migrar a RHF + `salidaSchema` / `ajusteSchema`. Reduce riesgo de movimientos malformados.
3. **Movimiento combustible** — migrar a RHF + schemas existentes. Defensa adicional sobre la foto obligatoria.
4. **Crear certificación** — aplicar `certificacionSchema`. Previene fechas invertidas.
5. **Editar usuario admin** — aplicar `editarUsuarioSchema` + RUT.

**Para cada migración seguir este patrón seguro:**

```tsx
// ANTES (validación manual):
const [nombre, setNombre] = useState('')
async function handleSubmit() {
  if (!nombre.trim()) { setError('...'); return }
  // ...
}

// DESPUÉS (RHF + Zod):
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { certificacionSchema, type CertificacionInput } from '@/validations'

const { register, handleSubmit, formState: { errors, isSubmitting } } =
  useForm<CertificacionInput>({ resolver: zodResolver(certificacionSchema) })

const onSubmit = async (data: CertificacionInput) => {
  // data ya viene validada
  await mutation.mutateAsync(data)
}

return (
  <form onSubmit={handleSubmit(onSubmit)}>
    <Input {...register('nombre')} error={errors.nombre?.message} />
    <Button disabled={isSubmitting}>Guardar</Button>
  </form>
)
```

**Antes de migrar cada formulario:**
- Probar el formulario actual en producción para confirmar que funciona.
- Migrar en una rama feature/`zod-<modulo>`.
- Probar el formulario migrado con los mismos datos.
- Mergear solo si no rompe el flujo conocido.

### Reglas operativas mientras tanto

- Si Eduardo o Gustavo reportan que un formulario aceptó datos malos → priorizar migración a Zod de ese formulario.
- No tocar formularios que no están reportando errores. La regla "if it works, don't refactor" aplica especialmente en piloto.

---

## 9. Verificación

- `npm run typecheck` → ✅ 0 errores.
- `npm run build` → ✅ 37 rutas generadas, build limpio.
- 9 archivos `.ts` nuevos en `src/validations/`.
- 1 archivo modificado: `src/validations/index.ts` (agrega 10 re-exports).
- 0 formularios tocados.
