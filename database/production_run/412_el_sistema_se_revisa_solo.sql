-- ============================================================================
-- MIG412 · El sistema se revisa solo
-- ----------------------------------------------------------------------------
-- LO QUE PREGUNTÓ MANUEL
-- 26-08-2026: «¿es factible que el mismo sistema chequee, más que estar
-- supeditado a que alguien haga la pega?».
--
-- Es la pregunta correcta. Todo lo construido hasta acá deja el trabajo listo
-- para que una persona lo apruebe — y esa persona es justamente la que no lo
-- hizo durante dos años. Las 141 fechas que el lector ya sacó de los documentos
-- están esperando 141 clics que nadie tiene agendados.
--
-- ── LO QUE EL SISTEMA PUEDE HACER SOLO, Y LO QUE NO ─────────────────────────
-- Cuando el documento DICE su fecha, pedirle a alguien que la confirme no
-- agrega nada: sólo demora. El sistema la escribe.
--
-- Cuando el documento NO la dice y se usó la regla de 2 años, es un supuesto —
-- pero es el supuesto que se acordó. También se aplica, y queda marcado como
-- regla, no como lectura: `fecha_origen` distingue las dos para siempre.
--
-- Lo que NO se toca solo:
--
--   · Los certificados BLOQUEANTES. Hoy no hay ninguno entre las propuestas,
--     pero mañana puede haberlo: una fecha automática que deja un camión
--     detenido tiene que pasar por una persona. La regla queda escrita antes de
--     que haga falta.
--   · Los 273 escaneos. Sin texto no hay nada que leer, y el sistema no
--     inventa.
--
-- ── VERIFICADO ANTES DE AUTOMATIZAR ────────────────────────────────────────
--     alta ............ 55 pendientes · 12 quedarían vencidas · 0 bloqueantes
--     regla_2_anios ... 86 pendientes · 11 quedarían vencidas · 0 bloqueantes
--
-- Ninguna detiene un equipo. Por eso se puede.
--
-- ── LO QUE SE VENCE SOLO, SE AVISA SOLO ────────────────────────────────────
-- Un papel que lleva 30 días sin fecha deja de ser un pendiente y pasa a ser un
-- problema. El cron avisa una vez por papel y no vuelve a insistir mientras ese
-- aviso siga sin leer: repetir todos los días es la forma más segura de enseñar
-- a la gente a ignorar los avisos. Sobre 60 días el aviso pasa a crítico.
-- ============================================================================

BEGIN;

-- ── 1. Aplicar solo lo que se puede aplicar solo ──────────────────────────
CREATE OR REPLACE FUNCTION public.fn_certificados_aplicar_automaticas()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    r RECORD; v_emision DATE; v_deducida BOOLEAN;
    v_doc INT := 0; v_regla INT := 0; v_venc INT := 0; v_saltadas INT := 0;
BEGIN
    FOR r IN
        SELECT p.id AS prop_id, p.certificacion_id, p.vencimiento_propuesto,
               p.emision_propuesta, p.confianza, p.regla,
               c.fecha_emision, c.bloqueante, c.tipo::text AS tipo,
               COALESCE(a.patente, a.codigo) AS patente
          FROM certificacion_propuestas p
          JOIN certificaciones c ON c.id = p.certificacion_id
          JOIN activos a ON a.id = c.activo_id
         WHERE p.estado = 'pendiente'
           AND p.vencimiento_propuesto IS NOT NULL
           AND p.confianza IN ('alta','regla_2_anios')
           -- Sólo sobre papeles que siguen sin fecha: si alguien ya la escribió
           -- a mano, su trabajo manda sobre el automático.
           AND c.fecha_vencimiento >= '2099-01-01'::date
    LOOP
        -- Un certificado bloqueante detiene un equipo: eso lo decide una persona.
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
               fecha_origen      = CASE WHEN r.confianza = 'alta' THEN 'documento' ELSE 'regla_2_anios' END,
               fecha_origen_nota = 'Aplicada automáticamente: ' || COALESCE(r.regla, r.confianza)
                                 || CASE WHEN v_deducida THEN ' · emisión deducida (vencimiento menos 2 años)' ELSE '' END,
               updated_at        = NOW()
         WHERE id = r.certificacion_id;

        UPDATE certificacion_propuestas
           SET estado = 'aceptada', resuelto_at = NOW(),
               nota_resolucion = 'Aplicada por el sistema'
         WHERE id = r.prop_id;

        IF r.confianza = 'alta' THEN v_doc := v_doc + 1; ELSE v_regla := v_regla + 1; END IF;
        IF r.vencimiento_propuesto < CURRENT_DATE THEN v_venc := v_venc + 1; END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'leidas_del_documento', v_doc, 'por_regla', v_regla,
        'quedaron_vencidas', v_venc, 'saltadas_por_bloqueantes', v_saltadas);
END $function$;

COMMENT ON FUNCTION public.fn_certificados_aplicar_automaticas() IS
  'MIG412: escribe las fechas que el lector sacó de los documentos. Nunca toca certificados bloqueantes ni papeles cuya fecha ya escribió una persona.';

-- ── 2. Lo que lleva mucho sin fecha, se escala ────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_certificados_escalar_sin_fecha()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE r RECORD; u RECORD; v_n INT := 0; v_dias INT;
BEGIN
    FOR r IN
        SELECT v.id AS cert_id, v.tipo::text AS tipo, a.id AS activo_id,
               COALESCE(a.patente, a.codigo) AS patente,
               (CURRENT_DATE - c.created_at::date) AS dias
          FROM v_certificacion_actual v
          JOIN certificaciones c ON c.id = v.id
          JOIN activos a ON a.id = v.activo_id
         WHERE v.estado_real::text = 'sin_fecha'
           AND a.estado <> 'dado_baja'::estado_activo_enum
           -- Desde los 30 días. No es un hito exacto a propósito: los papeles
           -- ya cargados llevan meses, y un «exactamente 30 días» los habría
           -- dejado fuera para siempre. Lo que evita el spam es el guard de más
           -- abajo: si ya hay un aviso sin leer de ESE papel, no se crea otro.
           AND (CURRENT_DATE - c.created_at::date) >= 30
    LOOP
        v_dias := r.dias;
        FOR u IN
            SELECT id FROM usuarios_perfil
             WHERE activo = true AND rol IN ('administrador','subgerente_operaciones','jefe_mantenimiento','prevencionista')
        LOOP
            -- Sin repetir: si ya se avisó de este papel y sigue sin leer, se
            -- actualiza en vez de apilar otro.
            IF NOT EXISTS (
                SELECT 1 FROM alertas
                 WHERE tipo = 'doc_sin_fecha' AND entidad_id = r.cert_id
                   AND destinatario_id = u.id AND NOT leida) THEN
                INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id,
                                     destinatario_id, requiere_accion, leida, created_at)
                VALUES ('doc_sin_fecha',
                        'Papel sin vigencia: ' || r.patente,
                        'El ' || replace(r.tipo, '_', ' ') || ' del ' || r.patente ||
                        ' lleva ' || v_dias || ' días cargado sin fecha de vencimiento. ' ||
                        'Nadie sabe si está vigente. Se revisa en Flota → Control documental.',
                        CASE WHEN v_dias >= 60 THEN 'critical' ELSE 'warning' END,
                        'certificacion', r.cert_id, u.id, true, false, NOW());
                v_n := v_n + 1;
            END IF;
        END LOOP;
    END LOOP;
    RETURN jsonb_build_object('avisos_creados', v_n);
END $function$;

-- ── 3. Todos los días, a las 5:40 ─────────────────────────────────────────
DO $r$
BEGIN
    PERFORM cron.unschedule('certificados-autoaplicar');
EXCEPTION WHEN OTHERS THEN NULL;
END
$r$;

SELECT cron.schedule('certificados-autoaplicar', '40 5 * * *', $cron$
    DO $job$
    DECLARE v_ini TIMESTAMPTZ := clock_timestamp(); v_a JSONB; v_e JSONB;
    BEGIN
        v_a := public.fn_certificados_aplicar_automaticas();
        v_e := public.fn_certificados_escalar_sin_fecha();
        INSERT INTO log_jobs_automaticos (job_name, resultado, registros_procesados, detalles, duracion_ms)
        VALUES ('certificados-autoaplicar', 'ok',
                COALESCE((v_a->>'leidas_del_documento')::int,0) + COALESCE((v_a->>'por_regla')::int,0),
                v_a || v_e, EXTRACT(MILLISECONDS FROM clock_timestamp() - v_ini)::INTEGER);
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO log_jobs_automaticos (job_name, resultado, error_mensaje)
        VALUES ('certificados-autoaplicar', 'error', SQLERRM);
    END $job$;
$cron$);

COMMIT;
