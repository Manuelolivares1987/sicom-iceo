-- ============================================================================
-- MIG516 · El QR público también entiende la vigencia por horas
-- ============================================================================
-- Gotcha conocido (MIG-anteriores): rpc_documentos_activo_publico calcula los
-- estados APARTE de v_certificacion_actual — si se arregla un solo lado, el
-- cliente sigue viendo otra cosa. MIG514 metió la vigencia por horas en la
-- vista; acá se mete la MISMA regla en el QR: si el papel tiene
-- horometro_vence, el estado se calcula contra el horómetro real del equipo
-- (vencido si lo pasó, por vencer si le quedan ≤ 50 h) y la fecha no se
-- muestra (el centinela 2099 no es información).
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_documentos_activo_publico(p_activo_id uuid)
 RETURNS TABLE(tipo text, numero_certificado text, entidad text, fecha_emision date,
               fecha_vencimiento date, dias_restantes integer, estado text,
               archivo_url text, etiqueta text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT DISTINCT ON (fn_certificado_clave(c.tipo::text, c.tipo_otro))
         c.tipo::text, c.numero_certificado::text, c.entidad_certificadora::text,
         c.fecha_emision,
         CASE WHEN c.horometro_vence IS NOT NULL
                OR c.vigencia_dudosa OR c.fecha_vencimiento >= DATE '2099-01-01' THEN NULL
              ELSE c.fecha_vencimiento END,
         CASE WHEN c.horometro_vence IS NOT NULL
                OR c.vigencia_dudosa OR c.fecha_vencimiento >= DATE '2099-01-01' THEN NULL
              ELSE (c.fecha_vencimiento - CURRENT_DATE)::int END,
         CASE
           -- [MIG514/516] Vigencia por horas: manda el horómetro del equipo.
           WHEN c.horometro_vence IS NOT NULL THEN
             CASE WHEN COALESCE(a.horas_uso_actual, 0) >= c.horometro_vence THEN 'vencido'
                  WHEN COALESCE(a.horas_uso_actual, 0) >= c.horometro_vence - 50 THEN 'por_vencer'
                  ELSE 'vigente' END
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
         c.archivo_url,
         fn_certificado_etiqueta(c.tipo::text, c.tipo_otro)
    FROM certificaciones c
    LEFT JOIN activos a ON a.id = c.activo_id
   WHERE c.activo_id = p_activo_id
     AND c.anulado_at IS NULL          -- [MIG486]
   ORDER BY fn_certificado_clave(c.tipo::text, c.tipo_otro),
            c.created_at DESC, c.fecha_vencimiento DESC NULLS LAST
$function$;

-- ── Verificación: emitir por horas y mirar por el QR ────────────────────────
DO $mig$
DECLARE v_activo UUID; v_id UUID; v_estado TEXT; v_fecha DATE;
BEGIN
    SELECT id INTO v_activo FROM activos
     WHERE horas_uso_actual IS NOT NULL AND horas_uso_actual > 100 AND fecha_baja IS NULL LIMIT 1;

    INSERT INTO activo_certificados (activo_id, tipo_codigo, numero, fecha_emision, ciudad, datos,
                                     operador_nombre, firma_operador_url, jefe_nombre, firma_jefe_url,
                                     horometro_emision, vigencia_horas, created_by)
    SELECT v_activo, 'ultima_mantencion', 996, CURRENT_DATE, 'Coquimbo', '{}'::jsonb,
           'prueba', 'x', 'prueba', 'x', a.horas_uso_actual, 300,
           (SELECT id FROM usuarios_perfil WHERE rol='administrador' AND activo LIMIT 1)
      FROM activos a WHERE a.id = v_activo
    RETURNING id INTO v_id;

    SELECT d.estado, d.fecha_vencimiento INTO v_estado, v_fecha
      FROM rpc_documentos_activo_publico(v_activo) d
     WHERE d.archivo_url = '/certificado/' || v_id;
    RAISE NOTICE 'QR público con certificado por horas → estado=% · fecha=% (esperado: vigente, sin fecha)', v_estado, v_fecha;
    IF v_estado IS DISTINCT FROM 'vigente' OR v_fecha IS NOT NULL THEN
        RAISE EXCEPTION 'FALLO: el QR no entendió la vigencia por horas (estado=%, fecha=%)', v_estado, v_fecha;
    END IF;

    DELETE FROM certificaciones WHERE archivo_url = '/certificado/' || v_id;
    DELETE FROM activo_certificados WHERE id = v_id;
    RAISE NOTICE 'MIG516 OK · el QR y el control documental cuentan la misma historia';
END
$mig$;

COMMIT;
