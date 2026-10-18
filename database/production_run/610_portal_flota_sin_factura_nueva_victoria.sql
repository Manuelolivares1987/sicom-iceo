-- ============================================================================
-- 610_portal_flota_sin_factura_nueva_victoria.sql
-- ----------------------------------------------------------------------------
-- 1. El portal de flota no muestra la factura de compra (Manuel 2026-10-18:
--    "no visibilizar la factura"). Trae el precio y el banco del leasing: es
--    papel interno. La lista de tipos ocultos vive en UNA función para que
--    lista, ficha y conteos no se desalineen.
--    OJO: el QR público del equipo (rpc_documentos_activo_publico) NO se toca
--    aquí — sigue mostrando todo. Decisión pendiente de Manuel.
-- 2. Faena Nueva Victoria (SQM) para los 6 Renault C440 de ESMAX. Sin
--    coordenadas: no se inventan; se cargan cuando haya geocerca.
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_portal_flota_tipo_oculto(p_tipo TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$ SELECT p_tipo IN ('factura_compra') $$;
REVOKE ALL ON FUNCTION fn_portal_flota_tipo_oculto(TEXT) FROM PUBLIC, anon, authenticated;

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

-- ── 2. Faena Nueva Victoria ─────────────────────────────────────────────────
INSERT INTO faenas (contrato_id, codigo, nombre, ubicacion, region, comuna, estado)
SELECT id, 'FAE-NUEVAVICTORIA', 'Nueva Victoria — SQM (Esmax)', 'SQM Nueva Victoria',
       'Tarapacá', 'Pozo Almonte', 'activa'
  FROM contratos WHERE codigo = 'CTR-ESMAX-2025'
   AND NOT EXISTS (SELECT 1 FROM faenas WHERE codigo = 'FAE-NUEVAVICTORIA');

UPDATE activos
   SET faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-NUEVAVICTORIA'),
       ubicacion_actual = 'Nueva Victoria (SQM)',
       operacion = 'Calama',
       notas = replace(notas, 'Faena y operación por asignar.', 'Faena Nueva Victoria (SQM), MIG610.')
 WHERE codigo IN ('CC-20-04','CC-20-05','CC-20-06','CC-20-07','CC-20-08','CC-20-09');

SELECT (SELECT count(*) FROM activos a JOIN faenas f ON f.id = a.faena_id
         WHERE f.codigo = 'FAE-NUEVAVICTORIA') AS camiones_en_nueva_victoria;
