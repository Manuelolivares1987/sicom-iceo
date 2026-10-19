-- 622 — Llegó el TC8 del WBGD-30 (INTECIL 759405, serie 39822, 20.000 L): la
-- capacidad queda confirmada y se retira la nota interna de MIG615.
UPDATE activos
   SET notas = replace(notas, ' | Capacidad 20.000 L por confirmar: falta el TC8 del estanque.', '')
 WHERE patente = 'WBGD-30';

SELECT patente, position('falta el TC8' in coalesce(notas, '')) > 0 AS nota_pendiente
  FROM activos WHERE codigo BETWEEN 'CC-20-04' AND 'CC-20-09' ORDER BY patente;
