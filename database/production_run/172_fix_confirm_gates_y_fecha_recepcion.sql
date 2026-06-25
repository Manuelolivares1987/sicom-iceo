-- ============================================================================
-- SICOM-ICEO | 172 — Fix: confirmar día NO debe disparar gates + fecha_recepcion
-- ----------------------------------------------------------------------------
-- Síntomas (al "Confirmar / Cerrar día" en Sugerencias GPS):
--   • GCHT-12 / HKSR-81: gate "ARRENDADO requiere Check-List ENTREGA V02".
--   • TRDP-97: gate "READY-TO-RENT requiere verificación".
--   • SVBJ-55: null en informes_recepcion.fecha_recepcion (NOT NULL).
--
-- CAUSA RAÍZ: MIG168 hizo que rpc_confirmar_estado_dia (confirmación masiva de
-- sugerencias GPS) actualice activos.estado_comercial. Los gates y el trigger
-- de auto-recepción disparan en UPDATE OF estado_comercial → la confirmación
-- masiva (que solo registra la realidad diaria) quedó bloqueada.
--
-- FIX:
--   1. rpc_confirmar_estado_dia vuelve a NO tocar estado_comercial; solo
--      sincroniza categoria_uso (lo que necesita Fiabilidad) y SOLO para estados
--      comerciales A/C/L/U/V. Así NO dispara los gates ni la auto-recepción.
--      Los gates siguen activos en el modal "Contrato"
--      (rpc_actualizar_estado_diario_manual), que es la acción deliberada.
--   2. informes_recepcion.fecha_recepcion con DEFAULT CURRENT_DATE: el trigger
--      trg_auto_iniciar_recepcion inserta sin esa columna (bug histórico de
--      MIG55). Con el default, el flujo de recepción del modal deja de fallar.
-- IDEMPOTENTE.
-- ============================================================================

-- ── 1. fecha_recepcion con default (arregla SVBJ-55) ────────────────────────
ALTER TABLE informes_recepcion ALTER COLUMN fecha_recepcion SET DEFAULT CURRENT_DATE;

-- ── 2. rpc_confirmar_estado_dia: solo categoria_uso, sin estado_comercial ────
CREATE OR REPLACE FUNCTION public.rpc_confirmar_estado_dia(
    p_activo_id uuid,
    p_fecha     date,
    p_estado    character
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
BEGIN
  INSERT INTO estado_diario_flota
    (activo_id, fecha, estado_codigo, override_manual, calculado_auto, motivo_override, actualizado_por, actualizado_at)
  VALUES
    (p_activo_id, p_fecha, p_estado, true, false, 'Confirmado por planificador (sugerencia GPS)', auth.uid(), now())
  ON CONFLICT (activo_id, fecha) DO UPDATE
    SET estado_codigo = EXCLUDED.estado_codigo, override_manual = true, calculado_auto = false,
        motivo_override = EXCLUDED.motivo_override, actualizado_por = auth.uid(),
        actualizado_at = now(), updated_at = now();

  -- Sincronizar SOLO la categoría comercial (para el informe de Fiabilidad).
  -- NO se toca estado_comercial: hacerlo dispararía los gates de checklist /
  -- ready-to-rent y la auto-recepción, que son para la acción deliberada del
  -- modal, no para registrar la realidad diaria desde Sugerencias GPS.
  IF p_estado IN ('A','C','L','U','V') THEN
    UPDATE activos a
       SET categoria_uso = CASE p_estado
              WHEN 'A' THEN 'arriendo_comercial'::categoria_uso_enum
              WHEN 'C' THEN 'arriendo_comercial'::categoria_uso_enum
              WHEN 'L' THEN 'leasing_operativo'::categoria_uso_enum
              WHEN 'U' THEN 'uso_interno'::categoria_uso_enum
              WHEN 'V' THEN 'venta'::categoria_uso_enum
              ELSE a.categoria_uso END,
           updated_at = now()
     WHERE a.id = p_activo_id
       AND a.categoria_uso IS DISTINCT FROM (CASE p_estado
              WHEN 'A' THEN 'arriendo_comercial'::categoria_uso_enum
              WHEN 'C' THEN 'arriendo_comercial'::categoria_uso_enum
              WHEN 'L' THEN 'leasing_operativo'::categoria_uso_enum
              WHEN 'U' THEN 'uso_interno'::categoria_uso_enum
              WHEN 'V' THEN 'venta'::categoria_uso_enum END);
  END IF;
END $function$;

NOTIFY pgrst, 'reload schema';

-- ── 3. Validación ───────────────────────────────────────────────────────────
SELECT
  (SELECT column_default FROM information_schema.columns
    WHERE table_name='informes_recepcion' AND column_name='fecha_recepcion') AS fecha_recepcion_default,
  (SELECT count(*) FROM pg_proc WHERE proname='rpc_confirmar_estado_dia') AS rpc_ok;
