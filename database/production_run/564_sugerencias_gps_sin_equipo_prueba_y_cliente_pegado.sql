-- ============================================================================
-- MIG564 · Sugerencias GPS sin el equipo de prueba + JGBY-10 sin cliente pegado
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL (15-09-2026)
-- 1. «En sugerencias GPS intento cambiar pero no se realiza el cambio»: quiere
--    dejar al JGBY-10 «Sin contrato» y en Fiabilidad sigue saliendo AURA.
-- 2. «De ese informe saca al camión de prueba».
--
-- LO QUE ENCONTRÉ
-- 1. JGBY-10 YA está sin contrato (contrato_id NULL desde la devolución del
--    04-08-2026), pero activos.cliente_actual quedó pegado en 'AURA'. La
--    pantalla de Fiabilidad muestra `contrato.cliente ?? cliente_actual`, así
--    que sigue diciendo AURA. Y el modal Cambiar Estado sólo llama al RPC de
--    contrato cuando contrato_id CAMBIA: elegir «Sin contrato» sobre un equipo
--    que ya está en NULL es «sin cambio» para el modal → no llama a nada → el
--    cliente pegado no se limpia nunca. (El RPC sí sabe re-sincronizar el
--    cliente en su rama sin_cambio; el que no lo llamaba era el frontend.)
--    Acá se corrige el dato; el modal se corrige en el mismo PR.
-- 2. PRUEBA-01 (TEST-01) aparecía en la bandeja de sugerencias porque
--    fn_sugerencias_estado_gps filtra por tipo y estado, no por es_prueba.
--    Al «Cerrar día · toda la flota» el planificador le escribió un estado
--    diario (15-09, 'D'), y con eso entra al denominador de disponibilidad
--    del día. MIG530 lo permite a propósito (para probar) y lo limpia de
--    noche, pero Manuel pide que no esté en la bandeja: se excluye de la
--    función y se borra el estado diario que le quedó hoy.
-- ============================================================================

BEGIN;

-- ── 0 · Foto previa ─────────────────────────────────────────────────────────
DO $chk$
DECLARE r RECORD;
BEGIN
    SELECT patente, contrato_id, cliente_actual INTO r
      FROM activos WHERE patente = 'JGBY-10';
    RAISE NOTICE 'ANTES JGBY-10: contrato_id=% cliente_actual=%', r.contrato_id, r.cliente_actual;
    FOR r IN SELECT a.patente, count(e.*) n
               FROM activos a LEFT JOIN estado_diario_flota e ON e.activo_id = a.id
              WHERE a.es_prueba GROUP BY a.patente
    LOOP RAISE NOTICE 'ANTES prueba %: % estados diarios', r.patente, r.n; END LOOP;
END $chk$;

-- ── 1 · La bandeja de sugerencias ignora al equipo de prueba ───────────────
-- Misma firma que MIG112 → CREATE OR REPLACE, no hay que re-otorgar permisos.
CREATE OR REPLACE FUNCTION public.fn_sugerencias_estado_gps(p_fecha date DEFAULT CURRENT_DATE)
 RETURNS TABLE(activo_id uuid, patente text, equipamiento text, estado_actual character,
               estado_sugerido character, estado_guardado character, zona text,
               gps_ts timestamp with time zone, coincide boolean)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT
    a.id,
    a.patente::text,
    a.nombre::text,
    prev.estado_codigo AS estado_actual,
    COALESCE(fn_estado_por_geocerca(a.id), prev.estado_codigo, 'D')::character(1) AS estado_sugerido,
    (SELECT e.estado_codigo FROM estado_diario_flota e
       WHERE e.activo_id = a.id AND e.fecha = p_fecha LIMIT 1) AS estado_guardado,
    (SELECT g.nombre FROM gps_geocercas g
       WHERE g.activo AND ga.latitud IS NOT NULL
         AND fn_punto_en_geocerca(ga.latitud, ga.longitud, g.id)
       ORDER BY (g.tipo = 'faena_cliente') DESC, g.radio_m ASC LIMIT 1) AS zona,
    ga.ts_gps,
    (prev.estado_codigo = COALESCE(fn_estado_por_geocerca(a.id), prev.estado_codigo, 'D')) AS coincide
  FROM activos a
  LEFT JOIN gps_estado_actual ga ON ga.activo_id = a.id
  LEFT JOIN LATERAL (
    SELECT e.estado_codigo
      FROM estado_diario_flota e
     WHERE e.activo_id = a.id AND e.fecha < p_fecha
     ORDER BY e.fecha DESC LIMIT 1
  ) prev ON true
  WHERE a.estado <> 'dado_baja'
    AND a.tipo IN ('camion_cisterna','camion','camioneta','lubrimovil','equipo_menor')
    AND NOT COALESCE(a.es_prueba, false)   -- MIG564: el equipo de prueba no se planifica
  ORDER BY a.patente;
$function$;

COMMENT ON FUNCTION public.fn_sugerencias_estado_gps(date) IS
  'Bandeja del planificador: estado sugerido por GPS/geocerca por equipo y fecha. '
  'Excluye dados de baja y el equipo de prueba (es_prueba, MIG564).';

-- ── 2 · El estado diario que le quedó al equipo de prueba se va ────────────
DELETE FROM estado_diario_flota e
 USING activos a
 WHERE a.id = e.activo_id AND a.es_prueba;

-- ── 3 · JGBY-10: limpiar el cliente pegado ──────────────────────────────────
-- Se usa el mismo RPC que usa el modal: contrato ya en NULL → rama sin_cambio
-- → re-sincroniza cliente_actual a 'Sin contrato' (convención de la flota:
-- 21 equipos sin contrato ya lo tienen así).
DO $fix$
DECLARE v_id UUID; v_res JSONB;
BEGIN
    SELECT id INTO v_id FROM activos WHERE patente = 'JGBY-10';
    IF v_id IS NULL THEN RAISE EXCEPTION 'JGBY-10 no existe'; END IF;
    IF (SELECT contrato_id FROM activos WHERE id = v_id) IS NOT NULL THEN
        RAISE EXCEPTION 'JGBY-10 tiene contrato asignado: esta migración esperaba contrato_id NULL';
    END IF;
    v_res := rpc_cambiar_contrato_activo(v_id, NULL,
               'MIG564: cliente_actual quedó en AURA tras la devolución del 04-08-2026; se limpia');
    RAISE NOTICE 'JGBY-10 rpc_cambiar_contrato_activo → %', v_res;
END $fix$;

-- ── Verificación ────────────────────────────────────────────────────────────
DO $ver$
DECLARE r RECORD; v_n INT;
BEGIN
    SELECT patente, contrato_id, cliente_actual INTO r FROM activos WHERE patente = 'JGBY-10';
    IF r.cliente_actual IS DISTINCT FROM 'Sin contrato' THEN
        RAISE EXCEPTION 'FALLO: JGBY-10 sigue con cliente_actual=%', r.cliente_actual;
    END IF;
    RAISE NOTICE 'DESPUÉS JGBY-10: contrato_id=% cliente_actual=%', r.contrato_id, r.cliente_actual;

    SELECT count(*) INTO v_n FROM fn_sugerencias_estado_gps(CURRENT_DATE) s
      JOIN activos a ON a.id = s.activo_id WHERE a.es_prueba;
    IF v_n > 0 THEN RAISE EXCEPTION 'FALLO: el equipo de prueba sigue en la bandeja'; END IF;

    SELECT count(*) INTO v_n FROM estado_diario_flota e JOIN activos a ON a.id = e.activo_id WHERE a.es_prueba;
    IF v_n > 0 THEN RAISE EXCEPTION 'FALLO: el equipo de prueba sigue con estados diarios'; END IF;

    SELECT count(*) INTO v_n FROM fn_sugerencias_estado_gps(CURRENT_DATE);
    RAISE NOTICE 'bandeja hoy: % equipos (sin el de prueba) · estados diarios del equipo de prueba: 0', v_n;
END $ver$;

COMMIT;
