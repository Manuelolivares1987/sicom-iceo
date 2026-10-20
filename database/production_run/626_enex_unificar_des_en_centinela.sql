-- ============================================================================
-- MIG626 — Centinela: las 3 instalaciones de «Nueva Centinela (DES)» se unifican
-- ----------------------------------------------------------------------------
-- El contrato (CONTRATO + ANEXO NCEN) lista 11 instalaciones de combustible en
-- Centinela, igual que la planilla diaria. El anexo del 11-09-2025 solo
-- rebautiza el sector «Encuentro» como Desarrollo Encuentro Sulfuro (DES),
-- con otro N° de contrato minero; no agrega instalaciones. La faena NCEN_DES
-- tenía 3 copias de instalaciones de Centinela, por eso la Gantt mostraba 15
-- filas en vez de 11:
--   EESS Oxidos/MANTENIMIENTO DE EESS         → EESS Óxido
--   Semi Movil Esperanza Sur/ MASTER METER…   → Semimóvil Esperanza Sur (Receptora)
--       (ESM la programó el 20-07, un día antes que la otra de Esperanza Sur:
--        son las dos semimóviles, como en la planilla 04-ago Nueva / 05-ago Receptora)
--   Semi Movil OXE/MASTER METER…              → Semimóvil Encuentro, que pasa a
--       llamarse «Semimóvil Encuentro (OXE · DES)»
-- Se mueven programaciones, reprogramaciones y tareas de plan; ninguna tiene
-- ejecución y ningún destino tiene el mismo servicio en el mismo mes, así que
-- no hay duplicados. Las 3 de DES quedan inactivas (no se borran).
-- ============================================================================

CREATE TEMP TABLE _map (origen UUID, destino UUID) ON COMMIT DROP;

INSERT INTO _map
SELECT o.id, d.id
  FROM (VALUES
          ('EESS Oxidos/%',              'EESS Óxido'),
          ('Semi Movil Esperanza Sur/%', 'Semimóvil Esperanza Sur (Receptora)'),
          ('Semi Movil OXE/%',           'Semimóvil Encuentro')
       ) v(patron, destino)
  JOIN enex_instalaciones o ON o.nombre LIKE v.patron
  JOIN enex_faenas fo ON fo.id = o.faena_id AND fo.codigo = 'NCEN_DES'
  JOIN enex_instalaciones d ON d.nombre = v.destino
  JOIN enex_faenas fd ON fd.id = d.faena_id AND fd.codigo = 'CENTINELA'
 WHERE o.activo;

DO $$
BEGIN
  IF (SELECT count(*) FROM _map) NOT IN (0, 3) THEN
    RAISE EXCEPTION 'MIG626: se esperaban 3 pares origen→destino, hay %', (SELECT count(*) FROM _map);
  END IF;
  IF EXISTS (SELECT 1 FROM enex_programaciones p JOIN _map m ON m.origen = p.instalacion_id
              JOIN enex_ejecuciones e ON e.programacion_id = p.id) THEN
    RAISE EXCEPTION 'MIG626: hay programaciones de DES con ejecución; revisar a mano';
  END IF;
END $$;

UPDATE enex_programaciones  t SET instalacion_id = m.destino FROM _map m WHERE t.instalacion_id = m.origen;
UPDATE enex_reprogramaciones t SET instalacion_id = m.destino FROM _map m WHERE t.instalacion_id = m.origen;
UPDATE enex_plan_tareas     t SET instalacion_id = m.destino FROM _map m WHERE t.instalacion_id = m.origen;

UPDATE enex_instalaciones i SET activo = false, updated_at = now()
  FROM _map m WHERE i.id = m.origen;

UPDATE enex_instalaciones i
   SET nombre = 'Semimóvil Encuentro (OXE · DES)', updated_at = now()
  FROM enex_faenas f
 WHERE f.id = i.faena_id AND f.codigo = 'CENTINELA' AND i.nombre = 'Semimóvil Encuentro';

-- Verificación: Centinela debe quedar con 11 instalaciones de combustible y DES con 0.
SELECT f.codigo, count(*) FILTER (WHERE i.tipo <> 'camion') AS instalaciones,
       count(*) FILTER (WHERE i.tipo = 'camion') AS camiones
  FROM enex_faenas f
  LEFT JOIN enex_instalaciones i ON i.faena_id = f.id AND i.activo AND i.linea = 'combustible'
 WHERE f.codigo IN ('CENTINELA', 'NCEN_DES')
 GROUP BY f.codigo ORDER BY f.codigo;
