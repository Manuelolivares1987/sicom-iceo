-- 615 — La capacidad la ve el cliente (portal/QR): la nota «sin TC8 en carpeta:
-- confirmar» pasa a las notas internas del equipo (Manuel 2026-10-19).
UPDATE activos
   SET capacidad = '20.000 L 6x4',
       notas = COALESCE(notas, '') || ' | Capacidad 20.000 L por confirmar: falta el TC8 del estanque.'
 WHERE codigo BETWEEN 'CC-20-04' AND 'CC-20-09'
   AND capacidad LIKE '%confirmar%';

SELECT json_agg(patente || ': ' || capacidad ORDER BY patente) AS capacidades
  FROM activos WHERE codigo BETWEEN 'CC-20-04' AND 'CC-20-09';
