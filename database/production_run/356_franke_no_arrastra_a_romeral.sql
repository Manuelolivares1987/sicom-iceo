-- ============================================================================
-- MIG356 · Corrección de MIG355: el LCSX-78 existe dos veces, y una es de
--          Romeral
-- ----------------------------------------------------------------------------
-- MIG355 amarró a Franke todos los estanques cuya patente fuera HHWB-44,
-- LCSX-78 o HHWB-42. Se llevó uno de más: el mismo camión LCSX-78 está
-- representado por DOS estanques distintos, porque los dos módulos lo dieron de
-- alta por su lado.
--
--   CAM-LCSX78    creado por MIG130, módulo Franke.   0 cierres.
--   ROM-LCSX-78   creado por MIG317, faena Romeral.   9 cierres, 1 contador
--                 con 9 lecturas, y referenciado por nombre en la ingesta de
--                 Orpak (MIG328).
--
-- Al mover ROM-LCSX-78 a Franke, la ronda de cierre de Romeral perdió un punto
-- y nueve cierres firmados quedaron colgando de un estanque de otra faena. Se
-- devuelve tal cual estaba: clave `lcsx78`, orden 70, grupo propio, operación
-- Romeral. Y se borra el contador que MIG355 le agregó, que no alcanzó a
-- registrar ninguna lectura.
--
-- LO QUE NO SE ARREGLA ACÁ, PORQUE NO ES UN ERROR DE MIGRACIÓN
-- El camión físico está en Franke: el informe de gestión de julio lo declara
-- «camión de reemplazo, operativo en faena», la entrega de turno del 06-12 de
-- agosto lo muestra trabajando, y el Mini Cierre de agosto de Romeral ya no lo
-- nombra — sus estaciones son Bimodal, Mina, Camión 18, Camión 67, Mochila 440
-- y Camión 85. O sea: en Romeral el punto sigue abierto en el sistema y vacío
-- en terreno, y hay un Camión 85 operando que el sistema no conoce.
--
-- Eso se decide en la faena, no en una migración: dar de baja un punto de
-- medición le cambia la ronda al supervisor de turno, y dar de alta otro
-- necesita su capacidad, su contador y su numeral de partida. Queda anotado en
-- el propio registro para que se resuelva con nombre y fecha.
-- ============================================================================

BEGIN;

-- ── 1. ROM-LCSX-78 vuelve a Romeral, con los valores de MIG317/324/334 ─────
UPDATE public.combustible_estanques
   SET faena_id     = (SELECT id FROM public.faenas WHERE codigo = 'FAE-CMP-ROMERAL'),
       operacion    = 'Romeral',
       clave_cierre = 'lcsx78',
       orden_cierre = 70,
       grupo_cuadre = 'lcsx78',
       updated_at   = NOW()
 WHERE codigo = 'ROM-LCSX-78';

-- ── 2. Fuera el contador que MIG355 le colgó de más ───────────────────────
-- Se borra sólo si no alcanzó a usarse en ningún cierre. Si alguien ya midió
-- con él, se queda y hay que mirarlo a mano — borrar una lectura firmada no lo
-- decide una migración.
DELETE FROM public.combustible_faena_medidores m
 USING public.combustible_estanques e
 WHERE m.estanque_id = e.id
   AND e.codigo   = 'ROM-LCSX-78'
   AND m.surtidor = 'S1'
   AND m.numero   = 'Metter'
   AND NOT EXISTS (SELECT 1 FROM public.combustible_faena_cierre_medidor cm
                    WHERE cm.medidor_id = m.id);

-- ── 3. Queda escrito lo que hay que decidir en terreno ─────────────────────
INSERT INTO public.combustible_faena_pendiente
       (faena_id, texto, origen, pedido_por, prioridad)
SELECT f.id,
       'El camión LCSX-78 (Camión 78) sigue como punto de medición de Romeral, pero opera en '
    || 'Franke desde antes de julio y el Mini Cierre de agosto ya no lo nombra. Decidir si se '
    || 'da de baja el punto. En el mismo Mini Cierre aparece un «Camión 85» con stock que el '
    || 'sistema no conoce: si está operando, hay que darlo de alta con su capacidad, su '
    || 'contador y su numeral de partida.',
       'sistema', 'MIG356', 'alta'
  FROM public.faenas f
 WHERE f.codigo = 'FAE-CMP-ROMERAL'
   AND NOT EXISTS (
       SELECT 1 FROM public.combustible_faena_pendiente p
        WHERE p.faena_id = f.id AND p.pedido_por = 'MIG356' AND p.estado = 'abierto');

COMMIT;

-- ── Verificación ──────────────────────────────────────────────────────────
-- SELECT e.codigo, e.patente, f.codigo AS faena, e.clave_cierre, e.orden_cierre,
--        e.grupo_cuadre, e.operacion,
--        (SELECT count(*) FROM combustible_faena_medidores m WHERE m.estanque_id = e.id) AS medidores
--   FROM combustible_estanques e
--   LEFT JOIN faenas f ON f.id = e.faena_id
--  WHERE e.patente = 'LCSX-78';
