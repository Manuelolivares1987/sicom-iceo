-- ============================================================================
-- MIG625 — Planificación ENEX: todas las zonas de combustibles de la planilla
-- ----------------------------------------------------------------------------
-- La Gantt de /dashboard/enex/planificacion arma sus filas con el maestro
-- enex_instalaciones. Spence y Lomas Bayas Combustibles no tenían ninguna
-- instalación cargada, por lo que esas faenas no aparecían; en Centinela
-- faltaba el segundo semimóvil de Esperanza Sur.
--
-- Fuente: Plan Trimestral/Planificacion_Diaria_Ago-Oct_2026_V1.xlsx
-- (hojas CENTINELA, SPENCE, LOMAS BAYAS + hoja DETALLE POR PUNTO para las
-- patentes de camiones). Solo maestro: no se crean programaciones.
-- Patentes «por confirmar» de la planilla NO se crean (2 en Spence, 2 en LB).
-- Lubricantes (LB_LUB) no se toca. Idempotente.
-- ============================================================================

-- Inserta si no existe ya una instalación con ese nombre (o esa patente) en la faena.
CREATE TEMP TABLE _zonas (faena TEXT, nombre TEXT, tipo TEXT, patente TEXT, orden INT) ON COMMIT DROP;
INSERT INTO _zonas VALUES
  -- Spence (cuadrilla combustibles, bloques mié–vie)
  ('SPENCE',  'EESS S1 (EDS Spence · Isla 1 e Isla 2)', 'eess',      NULL, 1),
  ('SPENCE',  'Petrolera P1',                            'petrolera', NULL, 2),
  ('SPENCE',  'Instalación Enaex (Orica)',               'petrolera', NULL, 3),
  ('SPENCE',  'TK 120 SX',                               'petrolera', NULL, 4),
  ('SPENCE',  'Aljibe SZBD35', 'camion', 'SZBD35', 11),
  ('SPENCE',  'Aljibe SZBD71', 'camion', 'SZBD71', 12),
  ('SPENCE',  'Aljibe SZBD72', 'camion', 'SZBD72', 13),
  ('SPENCE',  'Aljibe SZBK99', 'camion', 'SZBK99', 14),
  ('SPENCE',  'Aljibe SZBS34', 'camion', 'SZBS34', 15),
  ('SPENCE',  'Aljibe SZBS36', 'camion', 'SZBS36', 16),
  -- Lomas Bayas — Combustibles (bloque S37)
  ('LB_COMB', 'Semimóvil Fortuna',                        'semimovil', NULL, 1),
  ('LB_COMB', 'EESS Valle Amanda',                        'eess',      NULL, 2),
  ('LB_COMB', 'Brazo de carga Valle Amanda (Petrolera)',  'petrolera', NULL, 3),
  ('LB_COMB', 'Aljibe LBDR85', 'camion', 'LBDR85', 11),
  ('LB_COMB', 'Aljibe RXYR41', 'camion', 'RXYR41', 12),
  -- Centinela: la planilla distingue SM Esperanza Sur «Nueva» y «Receptora»
  ('CENTINELA', 'Semimóvil Esperanza Sur (Receptora)', 'semimovil', NULL, 8);

-- El semimóvil Esperanza Sur que ya existía pasa a llamarse «(Nueva)», como en la planilla.
UPDATE enex_instalaciones i
   SET nombre = 'Semimóvil Esperanza Sur (Nueva)', updated_at = now()
  FROM enex_faenas f
 WHERE f.id = i.faena_id AND f.codigo = 'CENTINELA' AND i.nombre = 'Semimóvil Esperanza Sur';

INSERT INTO enex_instalaciones (faena_id, codigo, nombre, tipo, linea, patente, frecuencia_meses, orden)
SELECT f.id, z.patente, z.nombre, z.tipo, 'combustible', z.patente, 3, z.orden
  FROM _zonas z
  JOIN enex_faenas f ON f.codigo = z.faena
 WHERE NOT EXISTS (
   SELECT 1 FROM enex_instalaciones i
    WHERE i.faena_id = f.id
      AND (i.nombre = z.nombre OR (z.patente IS NOT NULL AND i.patente = z.patente)));

-- Verificación: instalaciones activas de combustibles por faena.
SELECT f.codigo, count(*) FILTER (WHERE i.tipo <> 'camion') AS instalaciones,
       count(*) FILTER (WHERE i.tipo = 'camion') AS camiones
  FROM enex_faenas f
  JOIN enex_instalaciones i ON i.faena_id = f.id AND i.activo AND i.linea = 'combustible'
 GROUP BY f.codigo ORDER BY f.codigo;
