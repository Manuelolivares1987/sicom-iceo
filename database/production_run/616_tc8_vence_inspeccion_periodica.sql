-- 616 — El TC8 vence con la «Fecha Inspección Periódica» que declara el papel
-- (5 años desde la emisión). Manuel 2026-10-19: que quede pendiente y avise.
--  1) Estándar 60 meses → al cargar un TC8 la plataforma propone emisión + 5 años.
--  2) Los 3 TC8 de ESMAX, cargados sin vencimiento, pasan a emisión + 60 meses
--     (cae dentro del mes que dice cada papel).
INSERT INTO certificado_vigencia_estandar (tipo, meses, fuente)
VALUES ('tc8_sec', 60,
        'TC8 INTECIL 757408 / 759405 / 761011 (ESMAX): «Fecha Inspección Periódica» = emisión + 5 años.')
ON CONFLICT (tipo) DO UPDATE SET meses = EXCLUDED.meses, fuente = EXCLUDED.fuente;

UPDATE certificaciones c
   SET fecha_vencimiento = (c.fecha_emision + INTERVAL '60 months')::date,
       estado            = 'vigente'::estado_documento_enum,
       fecha_origen      = 'documento',
       fecha_origen_nota = 'Leído del papel: Fecha Inspección Periódica ' || x.mes || ' · ' || c.fecha_origen_nota,
       notas             = 'Certificado de producción del estanque, 20.000 L (DOT MC-306). Inspección periódica: ' || x.mes || '.'
  FROM activos a,
       (VALUES ('WBFZ-22', 'agosto 2031'), ('WBGD-20', 'septiembre 2031'), ('WBGD-30', 'septiembre 2031')) AS x(patente, mes)
 WHERE a.id = c.activo_id AND a.patente = x.patente
   AND c.tipo = 'tc8_sec' AND c.anulado_at IS NULL
   AND c.fecha_origen = 'documento_sin_vencimiento';

SELECT a.patente, c.numero_certificado, c.fecha_emision::text, c.fecha_vencimiento::text,
       c.estado::text, c.vigencia_observacion
  FROM certificaciones c JOIN activos a ON a.id = c.activo_id
 WHERE c.tipo = 'tc8_sec' AND c.anulado_at IS NULL AND a.codigo BETWEEN 'CC-20-04' AND 'CC-20-09'
 ORDER BY 1;
