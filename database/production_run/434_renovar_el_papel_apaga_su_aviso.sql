-- ============================================================================
-- MIG434 · Renovar el papel apaga su aviso
-- ----------------------------------------------------------------------------
-- Siguiendo la pregunta de Manuel —«si actualizo el sistema con un archivo,
-- ¿este va a actualizar todo?»— se revisó la cadena entera. Casi todo sí:
--
--   Control documental   vencido → vigente     al instante
--   la ficha del equipo  vencido → vigente     al instante
--   el QR del cliente    vencido → vigente     al instante
--   el resumen del equipo 3 vencidos → 2       al instante
--   el papel anterior     queda en el historial
--
-- Lo que NO se actualizaba era la campanita. El aviso «Documento VENCIDO:
-- Análisis Gases — GCHT-12» se queda ahí después de haber renovado el papel,
-- hasta que caduque a los 45 días o alguien lo marque leído a mano.
--
-- Son 683 avisos de documentos sin leer hoy. Cada papel que se arregle esta
-- semana va a dejar el suyo colgado. Un aviso que sigue pidiendo algo que ya se
-- hizo es peor que no tenerlo: enseña a ignorar la campanita.
--
-- ── CUÁNDO SE APAGA ────────────────────────────────────────────────────────
-- Cuando el papel de ese equipo y ese tipo deja de estar vencido o sin fecha.
-- Se mira el estado resultante, no el hecho de haber subido algo: cargar un
-- papel que también está vencido no apaga nada, y así debe ser.
--
-- Se apaga marcándolo leído con un motivo, no borrándolo: el aviso existió y
-- alguien lo resolvió, y eso vale la pena que quede.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_certificacion_apaga_su_aviso()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_estado TEXT; v_n INT;
BEGIN
    -- El estado que quedó vigente para ese equipo y ese tipo, que no siempre es
    -- el de la fila recién tocada: manda el último cargado (MIG429).
    SELECT v.estado_real::text INTO v_estado
      FROM v_certificacion_actual v
     WHERE v.activo_id = NEW.activo_id AND v.tipo = NEW.tipo;

    IF v_estado IS NULL OR v_estado IN ('vencido', 'sin_fecha') THEN
        RETURN NEW;   -- sigue habiendo problema: el aviso se queda
    END IF;

    UPDATE alertas
       SET leida = TRUE,
           motivo_cierre = 'El documento se renovó: quedó ' || v_estado || '.'
     WHERE NOT leida
       AND entidad_tipo = 'activo'
       AND entidad_id = NEW.activo_id
       AND tipo IN ('doc_vencido', 'doc_por_vencer', 'doc_sin_fecha')
       -- El aviso nombra el tipo de papel en el título; sin esto se apagarían
       -- también los avisos de los otros documentos del mismo camión.
       AND lower(translate(titulo, 'áéíóúÁÉÍÓÚ', 'aeiouAEIOU'))
           LIKE '%' || lower(translate(replace(NEW.tipo::text, '_', ' '), 'áéíóú', 'aeiou')) || '%';
    GET DIAGNOSTICS v_n = ROW_COUNT;

    -- El aviso de «documentos vencidos» del equipo habla de todos juntos: sólo
    -- se apaga cuando el camión ya no tiene ninguno vencido.
    IF NOT EXISTS (
        SELECT 1 FROM v_certificacion_actual v
         WHERE v.activo_id = NEW.activo_id AND v.estado_real::text = 'vencido') THEN
        UPDATE alertas
           SET leida = TRUE, motivo_cierre = 'El equipo ya no tiene documentos vencidos.'
         WHERE NOT leida AND entidad_tipo = 'activo' AND entidad_id = NEW.activo_id
           AND tipo = 'doc_vencidos_equipo';
    END IF;

    RETURN NEW;
END $function$;

-- Va después de los otros dos triggers BEFORE (limpiar_duda, z_estandar) porque
-- necesita leer el estado ya calculado con la fila nueva adentro.
DROP TRIGGER IF EXISTS trg_certificacion_apaga_aviso ON public.certificaciones;
CREATE TRIGGER trg_certificacion_apaga_aviso
  AFTER INSERT OR UPDATE OF fecha_vencimiento, vigencia_dudosa, fecha_origen
  ON public.certificaciones
  FOR EACH ROW EXECUTE FUNCTION public.fn_certificacion_apaga_su_aviso();

-- ── Los que ya están resueltos y siguen encendidos ────────────────────────
-- Barrido de una vez: avisos de documentos vencidos sobre equipos que ya no
-- tienen ninguno vencido.
UPDATE alertas a
   SET leida = TRUE, motivo_cierre = 'MIG434: el equipo ya no tiene documentos vencidos.'
 WHERE NOT a.leida AND a.tipo = 'doc_vencidos_equipo' AND a.entidad_tipo = 'activo'
   AND NOT EXISTS (SELECT 1 FROM v_certificacion_actual v
                    WHERE v.activo_id = a.entidad_id AND v.estado_real::text = 'vencido');

DO $r$
DECLARE v_activo UUID; v_r JSONB; v_antes INT; v_despues INT;
BEGIN
    RAISE NOTICE 'Avisos de documentos sin leer despues del barrido: %',
      (SELECT count(*) FROM alertas WHERE NOT leida
        AND tipo IN ('doc_vencido','doc_por_vencer','doc_sin_fecha','doc_vencidos_equipo'));

    -- Probarlo: renovar un papel vencido y ver si su aviso se apaga.
    SELECT a.entidad_id INTO v_activo FROM alertas a
     WHERE NOT a.leida AND a.tipo='doc_vencido' AND a.entidad_tipo='activo'
       AND a.titulo ILIKE '%Analisis Gases%' LIMIT 1;
    IF v_activo IS NOT NULL THEN
        SELECT count(*) INTO v_antes FROM alertas
         WHERE NOT leida AND entidad_id=v_activo AND tipo='doc_vencido' AND titulo ILIKE '%Analisis Gases%';
        PERFORM set_config('request.jwt.claims',
          json_build_object('sub',(SELECT id FROM usuarios_perfil WHERE rol='administrador' AND activo LIMIT 1),
                            'role','authenticated')::text, true);
        v_r := rpc_renovar_certificacion(v_activo, 'analisis_gases'::tipo_certificacion_enum,
                 CURRENT_DATE::date, (CURRENT_DATE + 180)::date, 'http://prueba434/x.pdf',
                 NULL, NULL, NULL, NULL, 'manual');
        SELECT count(*) INTO v_despues FROM alertas
         WHERE NOT leida AND entidad_id=v_activo AND tipo='doc_vencido' AND titulo ILIKE '%Analisis Gases%';
        RAISE NOTICE 'Prueba: al renovar, los avisos de ese papel pasaron de % a %', v_antes, v_despues;
        DELETE FROM certificaciones WHERE archivo_url='http://prueba434/x.pdf';
    END IF;
END
$r$;

COMMIT;
