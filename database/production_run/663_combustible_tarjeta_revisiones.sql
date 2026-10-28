-- ============================================================================
-- MIG663 · Tarjeta Aramco: revisión de alertas (Fase 2 de rendimiento)
-- ----------------------------------------------------------------------------
-- Lo ya revisado deja de aparecer como pendiente y queda registro de quién lo
-- revisó y por qué. Se revisa una CARGA con alerta o un VEHÍCULO en un MES
-- (lo que marca la lista «Para revisar»).
--   justificada → sale de pendientes (p. ej. «viaje a Copiapó»)
--   escalada    → sigue visible, marcada, para seguimiento
-- Pueden revisar los mismos roles que suben el Excel (fn_comb_tarjeta_puede_cargar).
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.combustible_tarjeta_revisiones (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    carga_id    UUID REFERENCES public.combustible_tarjeta_cargas(id) ON DELETE CASCADE,
    patente     TEXT,                    -- como se ve en SICOM (KVDK-21), para vehículo-mes
    mes         DATE,                    -- primer día del mes
    estado      TEXT NOT NULL CHECK (estado IN ('justificada', 'escalada')),
    comentario  TEXT NOT NULL CHECK (length(btrim(comentario)) >= 3),
    created_by  UUID NOT NULL DEFAULT auth.uid(),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK ((carga_id IS NOT NULL AND patente IS NULL AND mes IS NULL)
        OR (carga_id IS NULL AND patente IS NOT NULL AND mes IS NOT NULL AND mes = date_trunc('month', mes)::date))
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_comb_tarjeta_rev_carga ON public.combustible_tarjeta_revisiones (carga_id)
    WHERE carga_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_comb_tarjeta_rev_vehiculo_mes ON public.combustible_tarjeta_revisiones (patente, mes)
    WHERE carga_id IS NULL;

ALTER TABLE public.combustible_tarjeta_revisiones ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_comb_tarjeta_rev_sel ON public.combustible_tarjeta_revisiones;
CREATE POLICY pol_comb_tarjeta_rev_sel ON public.combustible_tarjeta_revisiones
    FOR SELECT TO authenticated USING (public.fn_costos_operacion_puede_ver());
REVOKE ALL ON public.combustible_tarjeta_revisiones FROM anon, authenticated;
GRANT SELECT ON public.combustible_tarjeta_revisiones TO authenticated;

-- Guardar (o cambiar) la revisión: una por carga o por vehículo-mes. La última manda.
CREATE OR REPLACE FUNCTION public.rpc_combustible_tarjeta_revisar(
    p_carga_id UUID, p_patente TEXT, p_mes DATE, p_estado TEXT, p_comentario TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_id UUID;
BEGIN
    IF NOT fn_comb_tarjeta_puede_cargar() THEN
        RAISE EXCEPTION 'Sin permiso para revisar alertas de combustible.' USING ERRCODE = '42501';
    END IF;
    IF p_estado NOT IN ('justificada', 'escalada') THEN RAISE EXCEPTION 'Estado no válido: %', p_estado; END IF;
    IF length(btrim(coalesce(p_comentario, ''))) < 3 THEN RAISE EXCEPTION 'Escriba un comentario: qué se revisó.'; END IF;

    IF p_carga_id IS NOT NULL THEN
        DELETE FROM combustible_tarjeta_revisiones WHERE carga_id = p_carga_id;
        INSERT INTO combustible_tarjeta_revisiones (carga_id, estado, comentario)
        VALUES (p_carga_id, p_estado, btrim(p_comentario)) RETURNING id INTO v_id;
    ELSE
        IF p_patente IS NULL OR p_mes IS NULL THEN RAISE EXCEPTION 'Falta la carga o el vehículo y el mes.'; END IF;
        DELETE FROM combustible_tarjeta_revisiones WHERE carga_id IS NULL AND patente = p_patente
           AND mes = date_trunc('month', p_mes)::date;
        INSERT INTO combustible_tarjeta_revisiones (patente, mes, estado, comentario)
        VALUES (p_patente, date_trunc('month', p_mes)::date, p_estado, btrim(p_comentario)) RETURNING id INTO v_id;
    END IF;
    RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public.rpc_combustible_tarjeta_revisar(UUID, TEXT, DATE, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_combustible_tarjeta_revisar(UUID, TEXT, DATE, TEXT, TEXT) TO authenticated;

-- Deshacer una revisión (vuelve a pendiente).
CREATE OR REPLACE FUNCTION public.rpc_combustible_tarjeta_revision_borrar(p_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
    IF NOT fn_comb_tarjeta_puede_cargar() THEN
        RAISE EXCEPTION 'Sin permiso para revisar alertas de combustible.' USING ERRCODE = '42501';
    END IF;
    DELETE FROM combustible_tarjeta_revisiones WHERE id = p_id;
END $$;
REVOKE ALL ON FUNCTION public.rpc_combustible_tarjeta_revision_borrar(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_combustible_tarjeta_revision_borrar(UUID) TO authenticated;

-- Con el nombre de quién revisó.
CREATE OR REPLACE VIEW public.v_combustible_tarjeta_revisiones AS
SELECT r.id, r.carga_id, r.patente, r.mes, r.estado, r.comentario, r.created_at,
       coalesce(u.nombre_completo, u.email) AS revisado_por
  FROM combustible_tarjeta_revisiones r
  LEFT JOIN usuarios_perfil u ON u.id = r.created_by
 WHERE public.fn_costos_operacion_puede_ver();
GRANT SELECT ON public.v_combustible_tarjeta_revisiones TO authenticated;
