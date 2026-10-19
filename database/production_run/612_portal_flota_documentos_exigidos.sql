-- ============================================================================
-- 612_portal_flota_documentos_exigidos.sql
-- ----------------------------------------------------------------------------
-- Manuel 2026-10-19, revisando el portal:
--  1. «Para todos los equipos dice al día y eso no es así»: un camión sin RT,
--     SOAP ni permiso salía al día porque sólo se miraba lo cargado. Ahora la
--     cuenta declara qué documentos EXIGE su contrato (documentos_exigidos,
--     igual que portales_prevencion.documentos_basicos: lo define el cliente,
--     no el sistema) y lo que falte se informa como pendiente.
--     ESMAX: RT, SOAP, permiso de circulación y programa de mantenimiento.
--  2. «Los certificados Renault dicen Otro»: los papeles SALFA se nombran
--     «Cert. Salfa - <lo que certifica>». Para los tipos fijos se usa tipo_otro
--     sólo como nombre: fn_certificado_clave ignora tipo_otro fuera de 'otra',
--     así que no cambia qué versión es la vigente.
-- Requiere 612a (tipo programa_mantenimiento). ADITIVA, IDEMPOTENTE.
-- ============================================================================

ALTER TABLE portal_flota_cuentas
    ADD COLUMN IF NOT EXISTS documentos_exigidos TEXT[] NOT NULL DEFAULT '{}';

UPDATE portal_flota_cuentas
   SET documentos_exigidos = ARRAY['revision_tecnica','soap','permiso_circulacion','programa_mantenimiento']
 WHERE email = 'esmax@pillado.cl';

-- Lista: los conteos tampoco cuentan lo oculto.
CREATE OR REPLACE FUNCTION rpc_portal_flota_equipos(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_c portal_flota_cuentas;
BEGIN
    v_c := fn_portal_flota_cuenta(p_token);

    RETURN jsonb_build_object(
        'cuenta', jsonb_build_object(
            'nombre', v_c.nombre, 'empresa', v_c.empresa, 'email', v_c.email,
            'debe_cambiar', v_c.debe_cambiar_password),
        'generado_at', NOW(),
        'equipos', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'activo_id',     a.id,
                'patente',       COALESCE(a.patente, a.codigo),
                'codigo',        a.codigo,
                'nombre',        a.nombre,
                'tipo',          COALESCE(a.tipo_equipamiento::text, a.tipo::text),
                'marca_modelo',  NULLIF(trim(concat_ws(' ', mar.nombre, mo.nombre)), ''),
                'anio',          a.anio_fabricacion,
                'docs_total',    d.total,
                'docs_vencidos', d.vencidos,
                'docs_por_vencer', d.por_vencer,
                'docs_sin_fecha',  d.sin_fecha,
                'docs_pendientes', (SELECT count(*) FROM unnest(v_c.documentos_exigidos) t
                                     WHERE NOT EXISTS (SELECT 1 FROM rpc_documentos_activo_publico(a.id) x
                                                        WHERE x.tipo = t)),
                'ultima_mantencion', h.fecha
              ) ORDER BY COALESCE(a.patente, a.codigo))
              FROM activos a
              LEFT JOIN modelos mo  ON mo.id  = a.modelo_id
              LEFT JOIN marcas  mar ON mar.id = mo.marca_id
              CROSS JOIN LATERAL (
                  SELECT count(*)                                        AS total,
                         count(*) FILTER (WHERE x.estado = 'vencido')    AS vencidos,
                         count(*) FILTER (WHERE x.estado = 'por_vencer') AS por_vencer,
                         count(*) FILTER (WHERE x.estado = 'sin_fecha')  AS sin_fecha
                    FROM rpc_documentos_activo_publico(a.id) x
                   WHERE NOT fn_portal_flota_tipo_oculto(x.tipo)
              ) d
              LEFT JOIN LATERAL (
                  SELECT max(y.fecha) AS fecha FROM rpc_historial_mantenimiento_publico(a.id) y
              ) h ON true
             WHERE a.id IN (SELECT fn_portal_flota_activos(v_c))
        ), '[]'::jsonb)
    );
END;
$$;

CREATE OR REPLACE FUNCTION rpc_portal_flota_equipo(p_token TEXT, p_activo_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_c   portal_flota_cuentas;
    v_out JSONB;
BEGIN
    v_c := fn_portal_flota_cuenta(p_token);

    IF NOT EXISTS (SELECT 1 FROM fn_portal_flota_activos(v_c) id WHERE id = p_activo_id) THEN
        RAISE EXCEPTION 'Equipo no disponible para su cuenta.' USING ERRCODE = '42501';
    END IF;

    SELECT jsonb_build_object(
        'equipo', jsonb_build_object(
            'activo_id',    a.id,
            'patente',      COALESCE(a.patente, a.codigo),
            'codigo',       a.codigo,
            'nombre',       a.nombre,
            'tipo',         COALESCE(a.tipo_equipamiento::text, a.tipo::text),
            'marca_modelo', NULLIF(trim(concat_ws(' ', mar.nombre, mo.nombre)), ''),
            'anio',         a.anio_fabricacion,
            'vin',          a.vin_chasis,
            'motor',        a.numero_motor,
            'capacidad',    a.capacidad,
            'kilometraje',  a.kilometraje_actual,
            'horometro',    a.horas_uso_actual
        ),
        'documentos', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'tipo',              x.tipo,
                'etiqueta',          x.etiqueta,
                'numero',            x.numero_certificado,
                'entidad',           x.entidad,
                'fecha_emision',     x.fecha_emision,
                'fecha_vencimiento', x.fecha_vencimiento,
                'dias_restantes',    x.dias_restantes,
                'estado',            x.estado,
                'archivo_url',       x.archivo_url
              ) ORDER BY
                CASE x.estado WHEN 'vencido' THEN 0 WHEN 'sin_fecha' THEN 1
                              WHEN 'por_vencer' THEN 2 WHEN 'vigente' THEN 3 ELSE 4 END,
                x.etiqueta)
              FROM rpc_documentos_activo_publico(a.id) x
             WHERE NOT fn_portal_flota_tipo_oculto(x.tipo)
        ), '[]'::jsonb),
        -- [MIG612] Lo que el contrato exige y no está cargado. Sin esto la
        -- pantalla decía «al día» a un camión sin RT ni SOAP.
        'pendientes', COALESCE((
            SELECT jsonb_agg(t ORDER BY array_position(v_c.documentos_exigidos, t))
              FROM unnest(v_c.documentos_exigidos) t
             WHERE NOT EXISTS (SELECT 1 FROM rpc_documentos_activo_publico(a.id) x WHERE x.tipo = t)
        ), '[]'::jsonb),
        'mantenciones', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'fecha', y.fecha, 'tipo', y.tipo, 'titulo', y.titulo, 'detalle', y.detalle,
                'folio', y.folio, 'km', y.kilometraje, 'horas', y.horometro,
                'con_observacion', y.con_observacion
              ) ORDER BY y.fecha DESC NULLS LAST)
              FROM rpc_historial_mantenimiento_publico(a.id) y
        ), '[]'::jsonb)
    ) INTO v_out
      FROM activos a
      LEFT JOIN modelos mo  ON mo.id  = a.modelo_id
      LEFT JOIN marcas  mar ON mar.id = mo.marca_id
     WHERE a.id = p_activo_id;

    INSERT INTO portal_flota_eventos (cuenta_id, email, evento, activo_id)
    VALUES (v_c.id, v_c.email, 'ver_equipo', p_activo_id);

    RETURN v_out;
END;
$$;


-- ── Nombres SALFA ────────────────────────────────────────────────────────────
UPDATE certificaciones c
   SET tipo_otro = v.nombre
  FROM activos a,
       (VALUES ('%Certificado_BBM%',                     'Cert. Salfa - Conexiones Auxiliares (BBM)'),
               ('%Apriete_y_Torque%',                    'Cert. Salfa - Apriete y Torque de Ruedas'),
               ('%Cabina_Parabrisas%',                   'Cert. Salfa - Cabina, Parabrisas, Cinturones y Asiento'),
               ('%Certificado_de_Frenos%',               'Cert. Salfa - Frenado'),
               ('%Hermeticidad_de_Cabina%',              'Cert. Salfa - Hermeticidad de Cabina'),
               ('%Certificado_de_Operatividad%',         'Cert. Salfa - Operatividad'),
               ('%ADAS%',                                'Cert. Salfa - Asistente de Conducción (ADAS)')
       ) AS v(patron, nombre)
 WHERE a.id = c.activo_id
   AND a.codigo IN ('CC-20-04','CC-20-05','CC-20-06','CC-20-07','CC-20-08','CC-20-09')
   AND c.archivo_url LIKE v.patron
   AND c.anulado_at IS NULL;

SELECT (SELECT count(*) FROM certificaciones WHERE tipo_otro LIKE 'Cert. Salfa - %') AS salfa_renombrados,
       (SELECT documentos_exigidos FROM portal_flota_cuentas WHERE email = 'esmax@pillado.cl') AS exigidos;
