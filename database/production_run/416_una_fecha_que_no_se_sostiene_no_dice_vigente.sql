-- ============================================================================
-- MIG416 · Una fecha que no se sostiene no puede decir «vigente»
-- ----------------------------------------------------------------------------
-- MIG415 dejó a medias lo importante. Corrigió los cuatro certificados de
-- hermeticidad que se pudieron leer, y para los otros doce dejó una propuesta y
-- quiso mandar un aviso. Dos problemas con eso:
--
--   1. Esos doce camiones YA tenían un aviso de papeles sin vigencia (MIG413).
--      Un segundo aviso del mismo tipo sobre el mismo equipo rompe la regla de
--      «uno por camión» que se acababa de escribir: el próximo cron habría
--      reescrito uno encima del otro.
--
--   2. Y era el arreglo débil. Mientras la fecha siga en la base, el QR que
--      escanea el cliente y la ficha del equipo siguen diciendo VIGENTE en
--      verde sobre un certificado bloqueante cuya vigencia se sabe mal
--      calculada. El aviso queda en la campanita de cuatro personas; el verde
--      lo ve cualquiera que escanee el camión.
--
-- ── LA MARCA VA EN EL DATO, NO EN EL AVISO ─────────────────────────────────
-- `vigencia_dudosa` marca el certificado, y `v_certificacion_actual` lo reporta
-- como `sin_fecha`. Con eso lo recogen solos, sin tocar una línea más:
--
--     · el QR público  → «VIGENCIA POR CONFIRMAR» en vez de verde (MIG410)
--     · la ficha       → «Falta la fecha, revisar el archivo»
--     · Control documental → lo sube arriba en la lista del camión
--     · el escalamiento diario → lo suma al aviso que ya existe (MIG413)
--
-- Un solo aviso por camión, y la información correcta en las cuatro pantallas.
--
-- ── LAS FECHAS NO SE BORRAN ────────────────────────────────────────────────
-- La fecha original queda intacta en la tabla. No se sabe que sea falsa: se
-- sabe que no se puede sostener. Cuando alguien abra el escaneo y anote la
-- fecha real, `rpc_certificacion_fijar_fecha` limpia la marca y el papel vuelve
-- a decir lo que corresponda.
-- ============================================================================

BEGIN;

ALTER TABLE public.certificaciones
  ADD COLUMN IF NOT EXISTS vigencia_dudosa      BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS vigencia_dudosa_nota TEXT;

COMMENT ON COLUMN public.certificaciones.vigencia_dudosa IS
  'MIG416: la fecha cargada no se sostiene contra lo que dicen los documentos del mismo tipo. Se reporta como sin_fecha hasta que alguien lea el archivo.';

-- ── La vista respeta la marca ─────────────────────────────────────────────
CREATE OR REPLACE VIEW public.v_certificacion_actual AS
 SELECT DISTINCT ON (c.activo_id, c.tipo) c.id,
    c.activo_id, c.tipo, c.numero_certificado, c.entidad_certificadora,
    c.fecha_emision, c.fecha_vencimiento, c.estado, c.archivo_url, c.notas,
    c.bloqueante, c.created_at, c.updated_at, c.created_by,
        CASE
            -- Una vigencia que no se sostiene vale lo mismo que no tener fecha.
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
  ORDER BY c.activo_id, c.tipo, c.fecha_vencimiento DESC NULLS LAST, c.created_at DESC;

-- ── Marcar las hermeticidades que no se pudieron sostener ─────────────────
UPDATE certificaciones c
   SET vigencia_dudosa = TRUE,
       vigencia_dudosa_nota =
         'MIG416 · cargado con ' || (c.fecha_vencimiento::date - c.fecha_emision::date)
         || ' días de vigencia. Los 5 certificados de hermeticidad que se pudieron leer '
         || '(DJKL-18, DCHD-83, KVWD-27, SVBJ-57, TCJV-15) dicen todos 6 meses. '
         || 'Es un escaneo sin texto: hay que abrir el archivo y anotar la fecha del papel.',
       updated_at = NOW()
  FROM activos a
 WHERE a.id = c.activo_id
   AND c.tipo::text = 'hermeticidad'
   AND c.id IN (SELECT id FROM v_certificacion_actual)
   AND a.estado <> 'dado_baja'::estado_activo_enum
   AND c.fecha_origen IS DISTINCT FROM 'documento'
   AND c.fecha_emision < '2099-01-01'::date
   AND (c.fecha_vencimiento::date - c.fecha_emision::date) > 200;

-- ── Anotar la fecha real limpia la marca ──────────────────────────────────
-- Si alguien abre el escaneo y escribe la fecha, deja de ser dudosa: eso es
-- exactamente lo que se le estaba pidiendo.
CREATE OR REPLACE FUNCTION public.fn_certificacion_limpiar_duda()
RETURNS TRIGGER LANGUAGE plpgsql AS $function$
BEGIN
    IF NEW.vigencia_dudosa
       AND NEW.fecha_vencimiento IS DISTINCT FROM OLD.fecha_vencimiento
       AND NEW.fecha_vencimiento < '2099-01-01'::date THEN
        NEW.vigencia_dudosa := FALSE;
        NEW.vigencia_dudosa_nota := NULL;
    END IF;
    RETURN NEW;
END $function$;

DROP TRIGGER IF EXISTS trg_certificacion_limpiar_duda ON public.certificaciones;
CREATE TRIGGER trg_certificacion_limpiar_duda
  BEFORE UPDATE ON public.certificaciones
  FOR EACH ROW EXECUTE FUNCTION public.fn_certificacion_limpiar_duda();

DO $r$
DECLARE v_d INT; v_sf INT; v_v INT;
BEGIN
    SELECT count(*) INTO v_d FROM certificaciones WHERE vigencia_dudosa;
    SELECT count(*) INTO v_sf FROM v_certificacion_actual WHERE estado_real::text='sin_fecha';
    SELECT count(*) INTO v_v  FROM v_certificacion_actual v JOIN certificaciones c ON c.id=v.id
     WHERE c.tipo::text='hermeticidad' AND v.estado_real::text='vigente';
    RAISE NOTICE 'Marcados como dudosos: % | sin_fecha total: % | hermeticidades que aun dicen VIGENTE: %',
        v_d, v_sf, v_v;
END
$r$;

COMMIT;
