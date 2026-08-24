-- ============================================================================
-- MIG384 · El LCSX-78 sale de Romeral y el Camión 85 no vuelve
-- ----------------------------------------------------------------------------
-- Los dos huecos que MIG360 dejó abiertos como pendientes, resueltos con la
-- decisión de operaciones:
--
--   · El LCSX-78 opera en Franke desde antes de julio. Sale de Romeral.
--   · El «Camión 85» que aparecía en el Mini Cierre de agosto era un camión
--     spot que ya se llevaron. No se da de alta.
--
-- SE DESACTIVA, NO SE BORRA
-- El punto ROM-LCSX-78 tiene 9 cierres firmados de junio 2026 colgando. Esa es
-- historia real de la faena: si se borra el estanque, esos cierres pierden a
-- qué punto se referían y el mes de junio deja de poder explicarse. Desactivar
-- lo saca de todo lo que mira hacia adelante —el cierre del turno, el momento
-- cero, los trasvasijes— y deja intacto lo que mira hacia atrás.
--
-- EL CAMIÓN NO SE QUEDA SIN CASA
-- El mismo camión ya existe como `CAM-LCSX78` en la faena Franke, activo y con
-- su orden de cierre. No hay que crear nada: lo que sobraba era el punto
-- duplicado en Romeral, que es justo lo que MIG355/356 dejó a medio resolver.
--
-- ESTO DESTRABA EL ARRANQUE
-- El momento cero se declara una vez y no se puede repetir. Con esto la faena
-- queda con los 6 puntos que de verdad opera, y el supervisor puede varillar
-- sabiendo que está anclando la lista correcta.
-- ============================================================================

BEGIN;

-- ── 1. El punto sale de la faena ──────────────────────────────────────────
UPDATE public.combustible_estanques
   SET activo = FALSE,
       observaciones = COALESCE(observaciones || ' | ', '')
                     || 'MIG384 (2026-08-24): sale de Romeral por decisión de operaciones — '
                     || 'el camión opera en Franke desde antes de julio y allá está como CAM-LCSX78. '
                     || 'Se desactiva en vez de borrarse porque tiene 9 cierres firmados de junio 2026.',
       updated_at = NOW()
 WHERE codigo = 'ROM-LCSX-78';

-- Su medidor deja de pedirse en el cierre.
UPDATE public.combustible_faena_medidores m
   SET activo = FALSE
  FROM public.combustible_estanques e
 WHERE e.id = m.estanque_id AND e.codigo = 'ROM-LCSX-78';

-- ── 2. Que el camión sí tenga casa ────────────────────────────────────────
-- No se crea nada: se verifica. Si el punto de Franke no estuviera activo,
-- desactivar el de Romeral dejaría al camión sin ningún lugar donde registrar.
DO $verif$
DECLARE v_ok BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM public.combustible_estanques e
          JOIN public.faenas f ON f.id = e.faena_id
         WHERE e.patente = 'LCSX-78' AND e.activo AND f.codigo = 'FAE-FRANCKE'
    ) INTO v_ok;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'El LCSX-78 no tiene punto activo en Franke: no se puede sacar de Romeral sin dejarlo sin casa.';
    END IF;
    RAISE NOTICE 'El LCSX-78 queda operando en Franke (CAM-LCSX78).';
END
$verif$;

-- ── 3. Los pendientes se cierran con la decisión escrita ──────────────────
UPDATE public.combustible_faena_pendiente p
   SET estado = 'cerrado',
       cerrado_at = NOW(),
       cerrado_comentario = 'MIG384: el LCSX-78 sale de Romeral (opera en Franke, allá está como '
                          || 'CAM-LCSX78); el punto queda desactivado, no borrado, por sus 9 cierres '
                          || 'de junio. El «Camión 85» era un camión spot que ya se llevaron: no se '
                          || 'da de alta.'
  FROM public.faenas f
 WHERE f.id = p.faena_id
   AND f.codigo = 'FAE-CMP-ROMERAL'
   AND p.estado <> 'cerrado'
   AND p.texto LIKE '%Camión 85%';

-- ── 4. Cómo queda la faena para el momento cero ───────────────────────────
DO $r$
DECLARE v_n INT; v_lista TEXT;
BEGIN
    SELECT count(*), string_agg(e.codigo, ', ' ORDER BY e.orden_cierre)
      INTO v_n, v_lista
      FROM public.combustible_estanques e
      JOIN public.faenas f ON f.id = e.faena_id
     WHERE f.codigo = 'FAE-CMP-ROMERAL' AND e.activo;
    RAISE NOTICE 'Romeral queda con % puntos activos: %', v_n, v_lista;

    IF EXISTS (SELECT 1 FROM public.combustible_stock_inicial si
                 JOIN public.combustible_estanques e ON e.id = si.estanque_id
                WHERE e.codigo = 'ROM-LCSX-78' AND NOT si.anulado) THEN
        RAISE WARNING 'Ojo: el ROM-LCSX-78 ya tenía momento cero declarado. Revisar antes de varillar.';
    END IF;
END
$r$;

COMMIT;
