-- ============================================================================
-- MIG419 · Si el papel no dice vencimiento, va sin vencimiento
-- ----------------------------------------------------------------------------
-- LO QUE CORRIGIÓ MANUEL
-- 26-08-2026: «los certificados SEC que indicas, no es correcto, el papel no
-- indica vencimiento, entonces apégate a lo que indica el documento y si no
-- indica, coloca sin vencimiento».
--
-- Esto revierte una decisión anterior, y hay que decirlo con todas sus letras.
-- El 25-08 se acordó la regla de 2 años para los papeles que no declaran
-- vigencia, y MIG412 la aplicó sola a 86 certificados. Manuel revisó el
-- resultado contra los documentos y la regla no se sostiene: un certificado SEC
-- que no dice vencimiento no vence a los dos años, simplemente no lo dice.
--
-- Poner una fecha inventada es peor que no poner ninguna. Una fecha falsa se ve
-- igual que una verdadera en la pantalla, en el QR y en el informe que firma el
-- cliente. Nadie vuelve a mirarla. La regla de 2 años estaba fabricando
-- exactamente el problema que se salió a arreglar: 86 papeles que dicen algo
-- que su documento no dice.
--
-- ── LO QUE PASA A SER LA REGLA ─────────────────────────────────────────────
--   · El documento declara vencimiento  →  esa fecha, y sólo esa
--   · El documento NO declara vencimiento →  SIN VENCIMIENTO
--   · El documento no se puede leer      →  falta la fecha, alguien lo abre
--
-- Tres estados, ninguno inventado. El tercero es el único que pide trabajo
-- humano, y es trabajo real: abrir un escaneo y leerlo.
--
-- ── LO QUE SE DESHACE ──────────────────────────────────────────────────────
-- Los 86 aplicados por regla vuelven a «sin vencimiento», que es lo que su
-- documento respalda. Los 55 leídos del documento se quedan: esos sí dicen su
-- fecha. Y el automatismo deja de aplicar la regla: de ahora en adelante sólo
-- escribe fechas que estén escritas en el papel.
-- ============================================================================

BEGIN;

-- ── 1. Un origen nuevo: lo verificamos y el papel no vence ────────────────
ALTER TABLE public.certificaciones DROP CONSTRAINT IF EXISTS chk_cert_fecha_origen;
ALTER TABLE public.certificaciones ADD CONSTRAINT chk_cert_fecha_origen CHECK (
  fecha_origen IS NULL OR fecha_origen IN (
    'documento',        -- la fecha está escrita en el papel
    'regla_2_anios',    -- [MIG419] en desuso; se conserva por los que quedaron en historial
    'manual',           -- alguien la escribió a mano
    'carga_inicial',    -- venía de la carga masiva de abril
    -- [MIG419] Se abrió el documento y NO declara vencimiento. Es una
    -- conclusión verificada, no un hueco: distinta de «nadie lo ha mirado».
    'documento_sin_vencimiento'
  ));

-- ── 2. Deshacer las 86 fechas puestas por regla ───────────────────────────
UPDATE certificaciones
   SET fecha_vencimiento  = '2099-12-31'::date,
       fecha_origen       = 'documento_sin_vencimiento',
       fecha_origen_nota  = 'MIG419 · el documento no declara vencimiento. '
                          || 'La fecha anterior (' || to_char(fecha_vencimiento::date,'DD-MM-YYYY')
                          || ') salía de la regla de 2 años, que se descartó por indicación de '
                          || 'Manuel el 26-08-2026: si el papel no lo dice, no se inventa.',
       vigencia_dudosa    = FALSE,
       vigencia_dudosa_nota = NULL,
       updated_at         = NOW()
 WHERE fecha_origen = 'regla_2_anios';

-- Las propuestas por regla que quedaban pendientes ya no van a aplicarse.
UPDATE certificacion_propuestas
   SET estado = 'descartada', resuelto_at = NOW(),
       nota_resolucion = 'MIG419: la regla de 2 años se descartó. Si el documento no declara vencimiento, va sin vencimiento.'
 WHERE estado = 'pendiente' AND confianza = 'regla_2_anios';

-- ── 3. «Sin vencimiento» no es «falta la fecha» ───────────────────────────
-- Sin esto, las 86 filas caerían en el CASE de sin_fecha (tienen 2099, archivo,
-- y un tipo que caduca) y volverían a pedir trabajo que ya está hecho.
CREATE OR REPLACE VIEW public.v_certificacion_actual AS
 SELECT DISTINCT ON (c.activo_id, c.tipo) c.id,
    c.activo_id, c.tipo, c.numero_certificado, c.entidad_certificadora,
    c.fecha_emision, c.fecha_vencimiento, c.estado, c.archivo_url, c.notas,
    c.bloqueante, c.created_at, c.updated_at, c.created_by,
        CASE
            -- [MIG419] Se leyó el papel y no declara vencimiento. Está resuelto.
            WHEN c.fecha_origen = 'documento_sin_vencimiento' THEN 'no_aplica'::text
            -- [MIG416] Una vigencia que no se sostiene vale lo mismo que no tener fecha.
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

-- ── 4. Lo mismo en el QR del cliente ──────────────────────────────────────
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
           -- [MIG419] Se abrió el papel y no declara vencimiento: eso es lo que
           -- se le dice al cliente, no «falta la fecha».
           WHEN c.fecha_origen = 'documento_sin_vencimiento' THEN 'permanente'
           -- [MIG417] Una vigencia que no se sostiene vale lo mismo que no tener fecha.
           WHEN c.vigencia_dudosa THEN 'sin_fecha'
           -- [MIG410] Papel cargado, de un tipo que caduca, sin fecha anotada.
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
   ORDER BY c.tipo, c.fecha_vencimiento DESC NULLS LAST, c.created_at DESC
$function$;

-- ── 5. El automatismo deja de inventar ────────────────────────────────────
-- Sólo escribe fechas que están escritas en el papel.
CREATE OR REPLACE FUNCTION public.fn_certificados_aplicar_automaticas()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    r RECORD; v_emision DATE; v_deducida BOOLEAN;
    v_doc INT := 0; v_venc INT := 0; v_saltadas INT := 0;
BEGIN
    FOR r IN
        SELECT p.id AS prop_id, p.certificacion_id, p.vencimiento_propuesto,
               p.emision_propuesta, p.confianza, p.regla,
               c.fecha_emision, c.bloqueante, c.tipo::text AS tipo
          FROM certificacion_propuestas p
          JOIN certificaciones c ON c.id = p.certificacion_id
         WHERE p.estado = 'pendiente'
           AND p.vencimiento_propuesto IS NOT NULL
           -- [MIG419] Sólo 'alta': la fecha tiene que estar escrita en el
           -- documento. La regla de 2 años se descartó.
           AND p.confianza = 'alta'
           AND c.fecha_vencimiento >= '2099-01-01'::date
    LOOP
        IF COALESCE(r.bloqueante, FALSE) THEN
            v_saltadas := v_saltadas + 1;
            CONTINUE;
        END IF;

        v_deducida := FALSE;
        v_emision := r.emision_propuesta;
        IF v_emision IS NULL OR v_emision > r.vencimiento_propuesto THEN
            IF r.fecha_emision >= '2099-01-01'::date OR r.fecha_emision > r.vencimiento_propuesto THEN
                v_emision := (r.vencimiento_propuesto - INTERVAL '2 years')::date;
                v_deducida := TRUE;
            ELSE
                v_emision := r.fecha_emision;
            END IF;
        END IF;

        UPDATE certificaciones
           SET fecha_vencimiento = r.vencimiento_propuesto,
               fecha_emision     = v_emision,
               fecha_origen      = 'documento',
               fecha_origen_nota = 'Aplicada automáticamente: ' || COALESCE(r.regla, r.confianza)
                                 || CASE WHEN v_deducida THEN ' · emisión deducida' ELSE '' END,
               updated_at        = NOW()
         WHERE id = r.certificacion_id;

        UPDATE certificacion_propuestas
           SET estado = 'aceptada', resuelto_at = NOW(), nota_resolucion = 'Aplicada por el sistema'
         WHERE id = r.prop_id;

        v_doc := v_doc + 1;
        IF r.vencimiento_propuesto < CURRENT_DATE THEN v_venc := v_venc + 1; END IF;
    END LOOP;

    RETURN jsonb_build_object('leidas_del_documento', v_doc, 'por_regla', 0,
        'quedaron_vencidas', v_venc, 'saltadas_por_bloqueantes', v_saltadas);
END $function$;

COMMENT ON FUNCTION public.fn_certificados_aplicar_automaticas() IS
  'MIG419: escribe SOLO fechas escritas en el documento. La regla de 2 años se descartó: si el papel no declara vencimiento, va sin vencimiento.';

DO $r$
DECLARE v_sv INT; v_sf INT; v_na INT; v_vg INT; v_vc INT;
BEGIN
    SELECT count(*) INTO v_sv FROM certificaciones WHERE fecha_origen='documento_sin_vencimiento';
    SELECT count(*) FILTER (WHERE estado_real::text='sin_fecha'),
           count(*) FILTER (WHERE estado_real::text='no_aplica'),
           count(*) FILTER (WHERE estado_real::text='vigente'),
           count(*) FILTER (WHERE estado_real::text='vencido')
      INTO v_sf, v_na, v_vg, v_vc FROM v_certificacion_actual;
    RAISE NOTICE 'Sin vencimiento (verificado): % | sin_fecha: % | no_aplica: % | vigente: % | vencido: %',
        v_sv, v_sf, v_na, v_vg, v_vc;
END
$r$;

COMMIT;
