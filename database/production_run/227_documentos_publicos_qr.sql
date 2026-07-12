-- ============================================================================
-- SICOM-ICEO | 227 — Documentos del equipo en la ficha pública (QR)
-- ============================================================================
-- rpc_documentos_activo_publico: lista los documentos vigentes del equipo
-- (último por tipo) para la ficha pública /equipo/[id] que abre el QR.
-- Cualquier persona con el QR puede ver los documentos y su vigencia.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.rpc_documentos_activo_publico(p_activo_id uuid)
RETURNS TABLE (
    tipo              text,
    numero_certificado text,
    entidad           text,
    fecha_emision     date,
    fecha_vencimiento date,
    dias_restantes    int,
    estado            text,
    archivo_url       text
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT DISTINCT ON (c.tipo)
         c.tipo::text,
         c.numero_certificado::text,
         c.entidad_certificadora::text,
         c.fecha_emision,
         c.fecha_vencimiento,
         (c.fecha_vencimiento - CURRENT_DATE)::int AS dias_restantes,
         CASE
           WHEN c.fecha_vencimiento IS NULL THEN 'sin_fecha'
           WHEN c.fecha_vencimiento < CURRENT_DATE THEN 'vencido'
           WHEN c.fecha_vencimiento <= CURRENT_DATE + 45 THEN 'por_vencer'
           ELSE 'vigente'
         END AS estado,
         c.archivo_url
    FROM certificaciones c
   WHERE c.activo_id = p_activo_id
   ORDER BY c.tipo, c.fecha_vencimiento DESC NULLS LAST, c.created_at DESC
$$;

GRANT EXECUTE ON FUNCTION rpc_documentos_activo_publico(uuid) TO anon, authenticated;

DO $$ BEGIN RAISE NOTICE 'MIG227 OK: documentos del equipo visibles en la ficha pública QR'; END $$;
