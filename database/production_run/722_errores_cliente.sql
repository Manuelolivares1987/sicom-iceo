-- ============================================================================
-- MIG722 — Errores de la app reportados por el propio teléfono (20-11-2026)
-- ----------------------------------------------------------------------------
-- Franke: la app mostraba «La app no pudo abrir» en un teléfono y no se podía
-- reproducir desde la oficina. Como hace WhatsApp con sus informes de fallo,
-- la pantalla de error manda el error exacto + equipo + versión a la base.
--
-- Escritura SOLO por la función (SECURITY DEFINER, textos acotados). Nadie lee
-- por la API: se consulta desde la base. Funciona también sin sesión (anon),
-- que es justamente el caso del teléfono que no logra entrar.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.errores_cliente (
  id          BIGSERIAL PRIMARY KEY,
  creado_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  usuario_id  UUID,
  tipo        TEXT NOT NULL,
  mensaje     TEXT,
  stack       TEXT,
  url         TEXT,
  user_agent  TEXT,
  build       TEXT,
  extra       JSONB
);
CREATE INDEX IF NOT EXISTS errores_cliente_creado_idx ON public.errores_cliente (creado_at DESC);

ALTER TABLE public.errores_cliente ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.errores_cliente FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.rpc_registrar_error_cliente(
  p_tipo TEXT, p_mensaje TEXT, p_stack TEXT, p_url TEXT, p_user_agent TEXT, p_build TEXT, p_extra JSONB DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- Freno simple: un teléfono en bucle no llena la tabla (máx. 500 por hora en total).
  IF (SELECT count(*) FROM errores_cliente WHERE creado_at > now() - interval '1 hour') >= 500 THEN
    RETURN;
  END IF;
  INSERT INTO errores_cliente (usuario_id, tipo, mensaje, stack, url, user_agent, build, extra)
  VALUES (auth.uid(), left(coalesce(p_tipo, 'error'), 40), left(p_mensaje, 2000), left(p_stack, 6000),
          left(p_url, 500), left(p_user_agent, 400), left(p_build, 40),
          CASE WHEN p_extra IS NULL OR length(p_extra::text) > 4000 THEN NULL ELSE p_extra END);
END $$;

REVOKE ALL ON FUNCTION public.rpc_registrar_error_cliente(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpc_registrar_error_cliente(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB) TO anon, authenticated;

SELECT 'MIG722 ok' AS resultado;
