-- ============================================================================
-- 104_fn_flota_en_mantenimiento.sql
-- ----------------------------------------------------------------------------
-- Lista de vehiculos de flota cuyo ULTIMO dia en la matriz esta en mantencion
-- (M = mantencion >1d, T = taller correctivo, F = fuera de servicio), con:
--   - dias_mantencion: dias consecutivos en M/T/F hasta el ultimo dia
--   - ultimo_contrato: contrato del activo (codigo · cliente) o el cliente de
--     la matriz (ej "Contrato CMP", "Rentamaq") si no hay contrato_id ligado
--   - motivo: motivo_override real (no el de la carga Excel) u observacion
-- Para la seccion "Patentes en mantencion" del reporte por correo. El detalle
-- fino se ve en el link al reporte interactivo. Solo lectura, authenticated.
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_flota_en_mantenimiento()
RETURNS TABLE(
    activo_id        UUID,
    patente          TEXT,
    equipamiento     TEXT,
    estado_codigo    TEXT,
    dias_mantencion  INTEGER,
    ultimo_contrato  TEXT,
    motivo           TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
    WITH ed AS (
        SELECT e.activo_id, e.fecha, e.estado_codigo, e.cliente,
               e.motivo_override, e.observacion,
               ROW_NUMBER() OVER (PARTITION BY e.activo_id ORDER BY e.fecha DESC) AS rn
        FROM estado_diario_flota e
    ),
    ult AS (  -- ultimo dia por activo, solo flota en M/T/F
        SELECT ed.*
        FROM ed
        JOIN activos a ON a.id = ed.activo_id
        WHERE ed.rn = 1
          AND ed.estado_codigo IN ('M','T','F')
          AND a.estado <> 'dado_baja'
          AND a.tipo IN ('camion_cisterna','camion','camioneta','lubrimovil','equipo_menor')
    ),
    primer_no_mant AS (  -- rn del dia mas reciente NO-mantencion por activo
        SELECT activo_id, MIN(rn) AS rn0
        FROM ed
        WHERE estado_codigo NOT IN ('M','T','F')
        GROUP BY activo_id
    )
    SELECT
        u.activo_id,
        a.patente,
        a.tipo_equipamiento::text,
        u.estado_codigo::text,
        COALESCE(p.rn0 - 1, (SELECT COUNT(*)::int FROM ed WHERE ed.activo_id = u.activo_id))::int AS dias_mantencion,
        COALESCE(
            NULLIF(TRIM(ct.codigo || ' · ' || ct.cliente), '·'),
            NULLIF(u.cliente, ''),
            'Sin contrato'
        ) AS ultimo_contrato,
        CASE
            WHEN u.motivo_override IS NULL OR u.motivo_override ILIKE 'Importado reportabilidad%'
                THEN COALESCE(NULLIF(TRIM(u.observacion), ''), '—')
            ELSE u.motivo_override
        END AS motivo
    FROM ult u
    JOIN activos a       ON a.id = u.activo_id
    LEFT JOIN contratos ct ON ct.id = a.contrato_id
    LEFT JOIN primer_no_mant p ON p.activo_id = u.activo_id
    ORDER BY dias_mantencion DESC, a.patente
$$;

COMMENT ON FUNCTION fn_flota_en_mantenimiento IS
    'Vehiculos de flota en mantencion (M/T/F) el ultimo dia, con dias consecutivos, ultimo contrato/cliente y motivo. Para la seccion de mantencion del reporte por correo. MIG104.';

GRANT EXECUTE ON FUNCTION fn_flota_en_mantenimiento TO authenticated;

SELECT * FROM fn_flota_en_mantenimiento();

NOTIFY pgrst, 'reload schema';
