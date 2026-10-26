-- 652 — Volvo: la mantención va cada 400 h (2026-10-26).
--
-- Manuel: «todas las mantenciones de Volvo son cada 400 horas». Revierte la
-- decisión del 23-10 (MIG647: Volvo a 300 h como el resto de la flota). Volvo
-- pide 394 h; la compañía lo deja en 400.
--
-- Qué cambia (solo Volvo: FMX 420, VM 350, FH 540 y el programa del FMX 540):
--   1. Escalera 300/600/1.200/2.400 → 400/800/1.600/3.200 (misma estructura y
--      absorción: cada peldaño es el doble del anterior). Los servicios de
--      COMPONENTE no se tocan: eje 3.000 h / anual y caja I-Shift 4.800 h / 2
--      años son del fabricante, no de la escalera (MIG510).
--   2. Los planes de cada camión copian la frecuencia de la pauta al crearse
--      (gotcha MIG513): se sincronizan. La línea base (última ejecución) no se
--      toca: la próxima queda en base + 400.
--   3. programa_servicio (repuestos por servicio, MIG647): intervalo 400.
--   4. fn_intervalo_mantencion_horas(activo): el intervalo del equipo — el
--      del programa de su modelo; si no tiene, el menor peldaño por horas de sus
--      planes; si no, 300. Lo usan la recepción del taller (próximo horómetro
--      de la pauta, B11) y la vigencia por defecto del certificado de
--      mantención, que tenían 300 fijo.

-- ── 1. Escalera Volvo ────────────────────────────────────────────────────────
CREATE TEMP TABLE _volvo_escalera ON COMMIT DROP AS
SELECT p.id, p.frecuencia_horas AS h_viejo,
       CASE p.frecuencia_horas WHEN 300 THEN 400 WHEN 600 THEN 800 WHEN 1200 THEN 1600 WHEN 2400 THEN 3200 END AS h_nuevo
  FROM pautas_fabricante p
  JOIN modelos mo ON mo.id = p.modelo_id
  JOIN marcas ma ON ma.id = mo.marca_id
 WHERE ma.nombre ILIKE '%volvo%'
   AND p.frecuencia_horas IN (300, 600, 1200, 2400)
   AND p.frecuencia_km IS NULL;  -- la escalera manda por horómetro; el «PM 10.000 km» no entra

DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n FROM _volvo_escalera;
    IF n = 0 THEN RAISE NOTICE 'MIG652: escalera Volvo ya estaba en 400 h'; END IF;
END $$;

UPDATE pautas_fabricante p
   SET frecuencia_horas = e.h_nuevo,
       nombre = replace(replace(p.nombre, e.h_viejo::int || 'h', e.h_nuevo::int || 'h'),
                        e.h_viejo::int || ' horas', e.h_nuevo::int || ' horas')
  FROM _volvo_escalera e
 WHERE e.id = p.id;

-- ── 2. Planes de cada camión ─────────────────────────────────────────────────
UPDATE planes_mantenimiento pm
   SET frecuencia_horas = e.h_nuevo,
       nombre = replace(replace(pm.nombre, e.h_viejo::int || 'h', e.h_nuevo::int || 'h'),
                        e.h_viejo::int || ' horas', e.h_nuevo::int || ' horas'),
       updated_at = NOW()
  FROM _volvo_escalera e
 WHERE pm.pauta_fabricante_id = e.id;

-- Verificación: ningún plan Volvo puede quedar con otra frecuencia que su pauta.
DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n
      FROM planes_mantenimiento pm
      JOIN pautas_fabricante p ON p.id = pm.pauta_fabricante_id
      JOIN modelos mo ON mo.id = p.modelo_id
      JOIN marcas ma ON ma.id = mo.marca_id
     WHERE ma.nombre ILIKE '%volvo%' AND pm.frecuencia_horas IS DISTINCT FROM p.frecuencia_horas;
    IF n > 0 THEN RAISE EXCEPTION 'MIG652: % planes Volvo desincronizados de su pauta', n; END IF;
END $$;

-- ── 3. Programa de servicio (repuestos) ──────────────────────────────────────
UPDATE programa_servicio ps
   SET intervalo_horas = 400,
       notas = 'Intervalo SICOM 400 h (Volvo 394 h). Operaciones y cadencias según Volvo.',
       updated_at = NOW()
  FROM modelos mo JOIN marcas ma ON ma.id = mo.marca_id
 WHERE mo.id = ps.modelo_id AND ma.nombre ILIKE '%volvo%';

-- ── 4. Intervalo de mantención del equipo ────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_intervalo_mantencion_horas(p_activo_id uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT coalesce(
        (SELECT ps.intervalo_horas FROM activos a JOIN programa_servicio ps ON ps.modelo_id = a.modelo_id WHERE a.id = p_activo_id),
        (SELECT min(pm.frecuencia_horas) FROM planes_mantenimiento pm
          WHERE pm.activo_id = p_activo_id AND pm.activo_plan AND pm.frecuencia_horas >= 100
            AND pm.frecuencia_km IS NULL),
        300);
$function$;
REVOKE ALL ON FUNCTION public.fn_intervalo_mantencion_horas(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_intervalo_mantencion_horas(uuid) TO authenticated;

-- La recepción del taller (B11, MIG496) dejaba «próximo horómetro de la pauta»
-- = lectura + 300 fijo. Ahora + el intervalo del equipo.
DO $$
DECLARE v_def text := pg_get_functiondef('public.rpc_taller_registrar_medidores'::regproc);
        v_n   int  := (length(v_def) - length(replace(v_def, 'p_horometro + 300', ''))) / length('p_horometro + 300');
BEGIN
    IF position('fn_intervalo_mantencion_horas' IN v_def) > 0 THEN RETURN; END IF;
    IF v_n <> 2 THEN RAISE EXCEPTION 'MIG652: esperaba 2 «p_horometro + 300» en rpc_taller_registrar_medidores, hay %', v_n; END IF;
    EXECUTE replace(v_def, 'p_horometro + 300', 'p_horometro + fn_intervalo_mantencion_horas(v_activo)');
END $$;

SELECT json_build_object(
  'pautas', (SELECT json_agg(json_build_object('modelo', mo.nombre, 'pauta', p.nombre, 'h', p.frecuencia_horas,
                'planes', (SELECT count(*) FROM planes_mantenimiento pm WHERE pm.pauta_fabricante_id = p.id AND pm.activo_plan))
              ORDER BY mo.nombre, p.frecuencia_horas)
               FROM pautas_fabricante p JOIN modelos mo ON mo.id = p.modelo_id JOIN marcas ma ON ma.id = mo.marca_id
              WHERE ma.nombre ILIKE '%volvo%' AND p.activo),
  'programa', (SELECT json_agg(json_build_object('modelo', mo.nombre, 'intervalo', ps.intervalo_horas))
                 FROM programa_servicio ps JOIN modelos mo ON mo.id = ps.modelo_id JOIN marcas ma ON ma.id = mo.marca_id
                WHERE ma.nombre ILIKE '%volvo%'),
  'intervalo_TRDP97', (SELECT fn_intervalo_mantencion_horas(id) FROM activos WHERE patente = 'TRDP-97'),
  'intervalo_un_MB', (SELECT fn_intervalo_mantencion_horas(a.id) FROM activos a JOIN modelos mo ON mo.id = a.modelo_id
                        JOIN marcas ma ON ma.id = mo.marca_id WHERE ma.nombre ILIKE '%mercedes%' LIMIT 1)
) AS resultado;
