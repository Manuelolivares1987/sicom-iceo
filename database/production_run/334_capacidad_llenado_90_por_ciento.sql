-- ============================================================================
-- MIG334 · La capacidad máxima de llenado no era la que usa el formulario
-- ----------------------------------------------------------------------------
-- Generando el FORM AC 066 desde el sistema y poniéndolo al lado del que hoy
-- llenan a mano, las capacidades no coincidían:
--
--     estanque        formulario     sistema
--     Isla Mina 1     67.500          67.500   ✓
--     Isla Mina 2     27.000          29.000
--     Bimodal         45.900          50.000
--     Casa Fuerza     27.000          29.000
--     Camiones        13.500          14.500
--
-- El formulario usa 90 % de la capacidad nominal en TODOS los puntos, sin
-- excepción. No es un número arbitrario: es el margen de expansión que se deja
-- en un estanque de combustible. El diésel se dilata cerca de 0,086 % por
-- grado, así que un estanque cargado al tope en la noche rebalsa al mediodía.
-- La regla de llenar hasta el 90 % es el estándar de la industria y es lo que
-- CMP declara.
--
-- Nuestro maestro tenía valores puestos a ojo (96,7 %, 98 %) que hacían dos
-- daños: el KPI de llenado salía más bajo del real, y —lo importante— un
-- estanque al 95 % de su nominal aparecía como «todavía hay espacio» cuando en
-- verdad ya estaba sobre el límite seguro.
--
-- Mina 1 ya estaba bien, lo que confirma que el 90 % es la regla y no una
-- coincidencia.
-- ============================================================================

BEGIN;

UPDATE public.combustible_estanques
   SET capacidad_llenado_lt = round(capacidad_lt * 0.9),
       updated_at = NOW()
 WHERE faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-CMP-ROMERAL')
   AND capacidad_lt IS NOT NULL
   AND capacidad_llenado_lt IS DISTINCT FROM round(capacidad_lt * 0.9);

COMMENT ON COLUMN public.combustible_estanques.capacidad_llenado_lt IS
  'Capacidad maxima de llenado: 90% de la nominal. El 10% restante es el margen de expansion termica del combustible, no capacidad disponible. MIG334.';

-- Un estanque sobre su capacidad de llenado no es un dato de color: es una
-- condicion que hay que corregir antes de la proxima recepcion.
CREATE OR REPLACE VIEW public.v_comb_faena_sobre_llenado AS
SELECT c.faena_id, c.fecha, e.nombre AS estanque,
       p.mf AS stock, e.capacidad_llenado_lt, e.capacidad_lt,
       round(100.0 * p.mf / NULLIF(e.capacidad_llenado_lt, 0), 1) AS pct_de_llenado
FROM combustible_faena_cierre c
JOIN combustible_faena_cierre_punto p ON p.cierre_id = c.id
JOIN combustible_estanques e ON e.id = p.estanque_id
WHERE NOT p.sin_medicion AND p.mf IS NOT NULL
  AND e.capacidad_llenado_lt IS NOT NULL
  AND p.mf > e.capacidad_llenado_lt;

GRANT SELECT ON public.v_comb_faena_sobre_llenado TO authenticated;

COMMIT;
