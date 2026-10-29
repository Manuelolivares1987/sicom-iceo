-- ============================================================================
-- MIG665 · Entrega de unidades: acta simple por camión (fotos + llaves + firma)
-- ----------------------------------------------------------------------------
-- Pedido de Manuel (29-10-2026): entregar aljibes de Calama a SQM. Hersaly
-- (jefe de operaciones Calama) está en terreno: elige QUÉ camiones entrega
-- (no siempre son todos), saca las fotos de cada uno, anota cuántas llaves
-- recibe el cliente y que las copias quedan en Pillado, y quien recibe firma
-- una vez (nombre, RUT, firma) para todos los camiones de esa entrega.
--
-- Queda un acta por camión (folio ENT-AAAA-NNNN), imprimible en PDF.
-- El contrato NO cambia (siguen con Esmax; SQM es quien recibe en faena):
-- esto no toca activos.estado ni contratos.
--
-- Fotos obligatorias por camión: frente, atrás, lado izquierdo, lado derecho,
-- cabina, tablero (km/horómetro) y llaves. Se validan en la RPC, no en la UI.
-- ============================================================================

CREATE SEQUENCE IF NOT EXISTS public.seq_entrega_unidad;

CREATE TABLE IF NOT EXISTS public.entregas_unidad (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    folio              TEXT NOT NULL UNIQUE,
    lote_id            UUID NOT NULL,              -- los camiones firmados juntos
    activo_id          UUID NOT NULL REFERENCES public.activos(id),
    fecha              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    lugar              TEXT,
    empresa_recibe     TEXT NOT NULL,
    recibe_nombre      TEXT NOT NULL,
    recibe_rut         TEXT NOT NULL,
    recibe_cargo       TEXT,
    firma_url          TEXT NOT NULL,
    km                 NUMERIC,
    horometro          NUMERIC,
    llaves_entregadas  INT NOT NULL CHECK (llaves_entregadas >= 1),
    copias_en_pillado  INT NOT NULL DEFAULT 0 CHECK (copias_en_pillado >= 0),
    observaciones      TEXT,
    fotos              JSONB NOT NULL,              -- [{tipo, url}]
    estado             TEXT NOT NULL DEFAULT 'firmada' CHECK (estado IN ('firmada', 'anulada')),
    anulada_motivo     TEXT,
    entregado_por      UUID NOT NULL DEFAULT auth.uid(),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_entregas_unidad_activo ON public.entregas_unidad (activo_id, fecha DESC);

ALTER TABLE public.entregas_unidad ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_entregas_unidad_sel ON public.entregas_unidad;
CREATE POLICY pol_entregas_unidad_sel ON public.entregas_unidad
    FOR SELECT TO authenticated USING (public.fn_tiene_permiso_modulo('flota', 'view'));
REVOKE ALL ON public.entregas_unidad FROM anon, authenticated;
GRANT SELECT ON public.entregas_unidad TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_entrega_unidad_puede()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
    SELECT fn_tiene_permiso_modulo('flota', 'create', ARRAY[
        'administrador','gerencia','subgerente_operaciones','jefe_operaciones','jefe_mantenimiento','planificador'])
$$;
GRANT EXECUTE ON FUNCTION public.fn_entrega_unidad_puede() TO authenticated;

-- p_camiones: [{activo_id, km, horometro, llaves, copias, observaciones, fotos:[{tipo,url}]}]
-- p_recibe:   {empresa, nombre, rut, cargo, firma_url}
CREATE OR REPLACE FUNCTION public.rpc_entrega_unidades_registrar(p_camiones JSONB, p_recibe JSONB, p_lugar TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_lote   UUID := gen_random_uuid();
    v_cam    JSONB;
    v_falta  TEXT[];
    v_pat    TEXT;
    v_folio  TEXT;
    v_out    JSONB := '[]'::jsonb;
    c_tipos  CONSTANT TEXT[] := ARRAY['frente','atras','izquierda','derecha','cabina','tablero','llaves'];
BEGIN
    IF NOT fn_entrega_unidad_puede() THEN
        RAISE EXCEPTION 'Sin permiso para registrar entregas de unidades.' USING ERRCODE = '42501';
    END IF;
    IF jsonb_typeof(p_camiones) <> 'array' OR jsonb_array_length(p_camiones) = 0 THEN
        RAISE EXCEPTION 'Seleccione al menos un camión.';
    END IF;
    IF length(btrim(coalesce(p_recibe->>'nombre', ''))) < 3 THEN RAISE EXCEPTION 'Falta el nombre de quien recibe.'; END IF;
    IF length(btrim(coalesce(p_recibe->>'rut', ''))) < 7 THEN RAISE EXCEPTION 'Falta el RUT de quien recibe.'; END IF;
    IF coalesce(p_recibe->>'firma_url', '') = '' THEN RAISE EXCEPTION 'Falta la firma de quien recibe.'; END IF;
    IF length(btrim(coalesce(p_recibe->>'empresa', ''))) < 2 THEN RAISE EXCEPTION 'Falta la empresa que recibe.'; END IF;

    FOR v_cam IN SELECT * FROM jsonb_array_elements(p_camiones) LOOP
        SELECT patente INTO v_pat FROM activos WHERE id = (v_cam->>'activo_id')::uuid;
        IF v_pat IS NULL THEN RAISE EXCEPTION 'Camión no encontrado.'; END IF;
        SELECT array_agg(t) INTO v_falta FROM unnest(c_tipos) t
         WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce(v_cam->'fotos', '[]')) f
                            WHERE f->>'tipo' = t AND coalesce(f->>'url', '') <> '');
        IF v_falta IS NOT NULL THEN
            RAISE EXCEPTION '%: faltan fotos (%).', v_pat, array_to_string(v_falta, ', ');
        END IF;
        IF coalesce((v_cam->>'llaves')::int, 0) < 1 THEN
            RAISE EXCEPTION '%: indique cuántas llaves recibe el cliente.', v_pat;
        END IF;

        v_folio := 'ENT-' || to_char(NOW() AT TIME ZONE 'America/Santiago', 'YYYY') || '-'
                   || lpad(nextval('seq_entrega_unidad')::text, 4, '0');
        INSERT INTO entregas_unidad (folio, lote_id, activo_id, lugar, empresa_recibe, recibe_nombre, recibe_rut,
                                     recibe_cargo, firma_url, km, horometro, llaves_entregadas, copias_en_pillado,
                                     observaciones, fotos)
        VALUES (v_folio, v_lote, (v_cam->>'activo_id')::uuid, nullif(btrim(p_lugar), ''),
                btrim(p_recibe->>'empresa'), btrim(p_recibe->>'nombre'), upper(btrim(p_recibe->>'rut')),
                nullif(btrim(coalesce(p_recibe->>'cargo', '')), ''), p_recibe->>'firma_url',
                nullif(v_cam->>'km', '')::numeric, nullif(v_cam->>'horometro', '')::numeric,
                (v_cam->>'llaves')::int, coalesce(nullif(v_cam->>'copias', '')::int, 0),
                nullif(btrim(coalesce(v_cam->>'observaciones', '')), ''), v_cam->'fotos');
        v_out := v_out || jsonb_build_object('patente', v_pat, 'folio', v_folio);
    END LOOP;
    RETURN jsonb_build_object('lote_id', v_lote, 'actas', v_out);
END $$;
REVOKE ALL ON FUNCTION public.rpc_entrega_unidades_registrar(JSONB, JSONB, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_entrega_unidades_registrar(JSONB, JSONB, TEXT) TO authenticated;

-- Anular un acta mal hecha (queda el registro, con motivo).
CREATE OR REPLACE FUNCTION public.rpc_entrega_unidad_anular(p_id UUID, p_motivo TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
    IF NOT fn_entrega_unidad_puede() THEN
        RAISE EXCEPTION 'Sin permiso para anular entregas.' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(coalesce(p_motivo, ''))) < 5 THEN RAISE EXCEPTION 'Escriba el motivo de la anulación.'; END IF;
    UPDATE entregas_unidad SET estado = 'anulada', anulada_motivo = btrim(p_motivo)
     WHERE id = p_id AND estado = 'firmada';
END $$;
REVOKE ALL ON FUNCTION public.rpc_entrega_unidad_anular(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_entrega_unidad_anular(UUID, TEXT) TO authenticated;

CREATE OR REPLACE VIEW public.v_entregas_unidad AS
SELECT e.*, a.patente, a.codigo AS activo_codigo, a.tipo_equipamiento::text AS tipo_equipamiento,
       mo.nombre AS modelo, ma.nombre AS marca,
       coalesce(u.nombre_completo, u.email) AS entregado_por_nombre
  FROM entregas_unidad e
  JOIN activos a ON a.id = e.activo_id
  LEFT JOIN modelos mo ON mo.id = a.modelo_id
  LEFT JOIN marcas ma ON ma.id = mo.marca_id
  LEFT JOIN usuarios_perfil u ON u.id = e.entregado_por
 WHERE public.fn_tiene_permiso_modulo('flota', 'view');
REVOKE ALL ON public.v_entregas_unidad FROM anon;
GRANT SELECT ON public.v_entregas_unidad TO authenticated;

-- Fotos y firma en evidencias-verificacion/entregas/ (bucket público, MIG166).
DROP POLICY IF EXISTS "storage_entregas_auth_insert" ON storage.objects;
CREATE POLICY "storage_entregas_auth_insert" ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'evidencias-verificacion' AND (storage.foldername(name))[1] = 'entregas');

SELECT count(*) AS actas FROM public.entregas_unidad;
