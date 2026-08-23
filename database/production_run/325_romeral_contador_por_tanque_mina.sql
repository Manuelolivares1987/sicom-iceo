-- ============================================================================
-- MIG325 · Cada tanque de la isla tiene su contador, y aun así se cuadran juntos
-- ----------------------------------------------------------------------------
-- EL ERROR DE CARGA (mío, en MIG317)
--   Asigné los dos contadores de la Estación Isla Mina al Tanque 1, leyendo la
--   hoja de agosto donde ambos aparecen como "Mina S1 N° 1" y "Mina S1 N° 2".
--   Los datos de junio de la app dicen otra cosa:
--
--       junio  mina1  cli1 = 23.811.019      agosto  Mina S1 N° 1 = 24.400.737
--       junio  mina2  cli1 = 20.060.392      agosto  Mina S1 N° 2 = 20.100.472
--
--   Son los mismos dos contadores, dos meses después. El N° 1 es del Tanque 1 y
--   el N° 2 es del Tanque 2. Cada tanque tiene el suyo.
--
-- POR QUÉ IGUAL SE CUADRAN JUNTOS
--   Corregir la asignación no explica el patrón de junio, que sigue en pie:
--
--       08-06   TK1 +5.178   TK2 −5.112   suma  +66
--       07-06   TK1 +4.067   TK2 −3.855   suma +212
--       01-06   TK1 +2.701   TK2 −2.416   suma +285
--
--   Cada tanque descuadra por miles y los dos errores se anulan. Con contadores
--   propios y correctamente asignados, eso sólo tiene una explicación: los dos
--   estanques están interconectados. Se despacha por una bomba, el nivel baja
--   en los dos, y cuánto bajó cada uno no lo decide el contador.
--
--   O sea: el contador de cada tanque mide bien lo que salió por SU bomba, pero
--   la varilla de ese tanque no mide lo que salió por esa bomba — mide lo que
--   se movió en ese estanque, que incluye el trasiego entre ambos.
--
--   Comparados juntos los mismos 9 días van de 66 a 584 L. De miles a centenas.
--   Ese es el error real de leer dos varillas en tanques de 75.000 y 30.000 L.
--
--   El libro y el FORM AC 066 ya los tratan como una unidad: "Estación Isla
--   Mina" y "KPI Pesados" (105.000 = 75.000 + 30.000). El grupo de cuadre de
--   MIG324 se mantiene; lo que cambia es de dónde sale cada numeral.
-- ============================================================================

BEGIN;

-- El segundo contador de la isla es del Tanque 2, no del Tanque 1.
UPDATE public.combustible_faena_medidores m
   SET estanque_id = (SELECT e.id FROM combustible_estanques e WHERE e.codigo = 'ROM-MINA-2'),
       surtidor    = 'S1',
       numero      = 'N° 2',
       etiqueta    = 'Mina TK2 · contador',
       orden       = 1
  FROM combustible_estanques e
 WHERE m.estanque_id = e.id
   AND e.codigo = 'ROM-MINA-1'
   AND m.numero = 'N° 2';

UPDATE public.combustible_faena_medidores m
   SET etiqueta = 'Mina TK1 · contador'
  FROM combustible_estanques e
 WHERE m.estanque_id = e.id AND e.codigo = 'ROM-MINA-1';

-- El comentario del grupo, con la razón correcta.
COMMENT ON COLUMN public.combustible_estanques.grupo_cuadre IS
  'Estanques que se cuadran juntos porque estan interconectados: se despacha por una bomba y el nivel baja en los dos, asi que la varilla de cada uno no corresponde a su propio contador. Separados dan errores de miles de litros que se cancelan. MIG324/325.';

COMMIT;
