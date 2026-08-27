-- ============================================================================
-- MIG429 · Manda el papel más nuevo, no el de fecha más lejana
-- ----------------------------------------------------------------------------
-- LO QUE PREGUNTÓ MANUEL
-- 27-08-2026: «si yo actualizo en esta página, ¿se actualiza lo que se ve en el
-- QR?».
--
-- Se verificó, y la respuesta era «sí, salvo justo en el caso que importa».
--
-- ── LO QUE SE ENCONTRÓ AL PROBARLO ─────────────────────────────────────────
-- Corregir la fecha a mano llega al QR al instante: se probó sobre un papel
-- vencido y pasó de «vencido hasta 03-04-2025» a «vigente hasta 01-10-2027» en
-- la misma transacción.
--
-- Pero subir el papel corregido NO. Renovar crea una versión nueva (MIG272/273)
-- y quien manda se elige así:
--
--     ORDER BY fecha_vencimiento DESC, created_at DESC
--
-- Es decir, gana la fecha MÁS LEJANA, no el documento más nuevo. Probado sobre
-- el FJTJ-61: con una revisión técnica cargada hasta 09-01-2027, al subir el
-- papel corregido con vigencia menor el QR siguió mostrando 09-01-2027.
--
-- Y ésa es exactamente la dirección de esta auditoría. El JDKH-31 figuraba
-- vigente hasta 31-12-2026 y su papel dice abril: subir el papel bueno habría
-- parecido que funcionó y el camión habría seguido en verde. Sin ningún aviso.
--
-- ── LA REGLA CORRECTA ──────────────────────────────────────────────────────
-- Manda el último documento cargado. Es lo que significa renovar, y es lo que
-- el propio comentario de MIG273 decía que hacía: «solo la última de cada tipo
-- rige». La implementación decía otra cosa.
--
-- Como desempate, cuando dos versiones se cargaron en el mismo instante —pasa
-- con la carga masiva de abril— se mantiene el criterio viejo.
--
-- ── IMPACTO MEDIDO ANTES DE APLICAR ────────────────────────────────────────
-- 75 pares (equipo, tipo) tienen más de una versión. Con la regla nueva
-- cambiaría el elegido en 0 de los 75: hoy el más nuevo ya es el de fecha más
-- lejana en todos. O sea que esto no mueve ningún dato: sólo cierra la puerta.
--
-- Riesgo asumido: si alguien sube por error un papel viejo, ahora ese manda. Es
-- visible y se arregla subiendo el bueno. Lo contrario —una corrección que no
-- se aplica y nadie lo nota— no se arregla, porque nadie se entera.
-- ============================================================================

BEGIN;

CREATE OR REPLACE VIEW public.v_certificacion_actual AS
 SELECT DISTINCT ON (c.activo_id, c.tipo) c.id,
    c.activo_id, c.tipo, c.numero_certificado, c.entidad_certificadora,
    c.fecha_emision, c.fecha_vencimiento, c.estado, c.archivo_url, c.notas,
    c.bloqueante, c.created_at, c.updated_at, c.created_by,
        CASE
            WHEN c.fecha_origen = 'documento_sin_vencimiento' THEN 'no_aplica'::text
            WHEN c.vigencia_dudosa THEN 'sin_fecha'::text
            WHEN (c.fecha_vencimiento IS NULL OR c.fecha_vencimiento >= '2099-01-01'::date) AND c.archivo_url IS NOT NULL AND COALESCE(tv.vence, false) THEN 'sin_fecha'::text
            WHEN c.fecha_vencimiento IS NULL OR c.fecha_vencimiento >= '2099-01-01'::date THEN 'no_aplica'::text
            WHEN c.fecha_vencimiento < CURRENT_DATE THEN 'vencido'::text
            WHEN c.fecha_vencimiento <= (CURRENT_DATE + 30) THEN 'por_vencer'::text
            ELSE 'vigente'::text
        END::estado_documento_enum AS estado_real,
    CASE WHEN c.vigencia_dudosa THEN NULL
         ELSE c.fecha_vencimiento - CURRENT_DATE END AS dias_restantes
   FROM certificaciones c
     LEFT JOIN v_certificado_tipo_vence tv ON tv.tipo = c.tipo
  -- [MIG429] Manda el último cargado, no el de fecha más lejana. Antes, subir
  -- un papel corregido con vigencia MENOR no cambiaba nada y nadie se enteraba.
  ORDER BY c.activo_id, c.tipo, c.created_at DESC, c.fecha_vencimiento DESC NULLS LAST;

CREATE OR REPLACE FUNCTION public.rpc_documentos_activo_publico(p_activo_id uuid)
RETURNS TABLE(
    tipo text, numero_certificado text, entidad text,
    fecha_emision date, fecha_vencimiento date, dias_restantes integer,
    estado text, archivo_url text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT DISTINCT ON (c.tipo)
         c.tipo::text, c.numero_certificado::text, c.entidad_certificadora::text,
         c.fecha_emision,
         CASE WHEN c.vigencia_dudosa OR c.fecha_vencimiento >= DATE '2099-01-01' THEN NULL
              ELSE c.fecha_vencimiento END,
         CASE WHEN c.vigencia_dudosa OR c.fecha_vencimiento >= DATE '2099-01-01' THEN NULL
              ELSE (c.fecha_vencimiento - CURRENT_DATE)::int END,
         CASE
           WHEN c.fecha_origen = 'documento_sin_vencimiento' THEN 'permanente'
           WHEN c.vigencia_dudosa THEN 'sin_fecha'
           WHEN (c.fecha_vencimiento IS NULL OR c.fecha_vencimiento >= DATE '2099-01-01')
                AND c.archivo_url IS NOT NULL
                AND NOT fn_certificado_tipo_permanente(c.tipo::text)
             THEN 'sin_fecha'
           WHEN c.fecha_vencimiento IS NULL OR c.fecha_vencimiento >= DATE '2099-01-01' THEN 'permanente'
           WHEN c.fecha_vencimiento < CURRENT_DATE THEN 'vencido'
           WHEN c.fecha_vencimiento <= CURRENT_DATE + 45 THEN 'por_vencer'
           ELSE 'vigente'
         END,
         c.archivo_url
    FROM certificaciones c
   WHERE c.activo_id = p_activo_id
   -- [MIG429] Mismo criterio que adentro: el QR del cliente y la pantalla del
   -- planificador tienen que estar mirando el mismo papel.
   ORDER BY c.tipo, c.created_at DESC, c.fecha_vencimiento DESC NULLS LAST
$function$;

COMMENT ON FUNCTION public.rpc_documentos_activo_publico(uuid) IS
  'MIG417/419/429: el QR publico. Manda el ultimo documento cargado. Ojo: la columna de salida se llama `entidad`, no `entidad_certificadora`.';

DO $r$
DECLARE v_a UUID; v_r TEXT; v_v INT; v_sf INT;
BEGIN
    SELECT count(*) FILTER (WHERE estado_real::text='vencido'),
           count(*) FILTER (WHERE estado_real::text='sin_fecha')
      INTO v_v, v_sf FROM v_certificacion_actual;
    RAISE NOTICE 'Tras el cambio: vencidos %, sin_fecha % (mismos que antes: el criterio no movio datos)', v_v, v_sf;

    -- Prueba viva: subir un papel corregido con vigencia MENOR ahora sí manda.
    SELECT a.id INTO v_a FROM activos a JOIN certificaciones c ON c.activo_id=a.id
     WHERE COALESCE(a.patente,a.codigo)='FJTJ-61' AND c.tipo::text='revision_tecnica' LIMIT 1;
    INSERT INTO certificaciones (activo_id, tipo, fecha_emision, fecha_vencimiento, archivo_url, bloqueante)
    VALUES (v_a, 'revision_tecnica', (CURRENT_DATE-200)::date, (CURRENT_DATE+5)::date, 'http://prueba/corregido.pdf', true);
    SELECT estado||' hasta '||COALESCE(fecha_vencimiento::text,'—') INTO v_r
      FROM rpc_documentos_activo_publico(v_a) WHERE tipo='revision_tecnica';
    RAISE NOTICE 'Prueba: el QR tras subir un corregido con vigencia menor -> %', v_r;
    -- La prueba no queda: se borra la fila inventada.
    DELETE FROM certificaciones WHERE archivo_url = 'http://prueba/corregido.pdf';
END
$r$;

COMMIT;
