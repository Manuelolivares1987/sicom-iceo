-- ============================================================================
-- MIG661 · Tarjeta Aramco: TSTB-48 fuera del análisis de rendimiento
-- ----------------------------------------------------------------------------
-- Camioneta bencinera sin GPS que desde julio carga casi solo en Lo Barnechea y
-- Las Condes. Manuel (28-10-2026): sacarla del análisis, igual que TCRB-71.
-- Las cargas se siguen guardando; solo salen de las vistas (MIG660).
-- ============================================================================

INSERT INTO public.combustible_tarjeta_excluidas (patente, motivo)
VALUES ('TSTB48', 'Fuera del análisis (pedido de gerencia)')
ON CONFLICT (patente) DO NOTHING;

SELECT patente, motivo FROM public.combustible_tarjeta_excluidas ORDER BY patente;
