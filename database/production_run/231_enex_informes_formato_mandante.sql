-- ============================================================================
-- SICOM-ICEO | 231 — ENEX: informes con formato del mandante + PDF almacenado
-- ============================================================================
-- Pedido de Manuel (con los formatos reales del mandante en mano):
--   · Calibración → "CERTIFICADO VERIFICACIÓN DE VOLÚMENES DE MEDIDORES /
--     CONTROL DE SELLOS NCh1436" (PN.OM.DM.MN.F.01): las pautas de calibración
--     se rehacen para capturar EXACTAMENTE los campos del certificado
--     (identificación, seguridad previa, totalizadores, 6 corridas medidor vs
--     patrón, sellos y cierre). Basado además en PRO-CAL-001-F1 Rev.1 del Pack.
--   · Mantención → "OT MANTENIMIENTO INTERMEDIO" (Kizeo): pautas Semimóvil y
--     Petrolera se rehacen con los bloques del formato (estanques, tubería y
--     válvulas, tableros eléctricos) + pauta técnica del Pack SST-PO-005-F1.
--     EESS y Truck Shop conservan su pauta y suman "Datos del servicio".
--   · El informe PDF generado se guarda en el bucket documentos/enex-informes
--     y su URL en enex_ejecuciones.informe_pdf_url (para correo automático).
-- destructivo-ok: UPDATEs intencionales — desactivan ítems de pautas que se
-- reemplazan por la versión alineada al formato del mandante (no se borran:
-- las ejecuciones históricas siguen referenciando sus ítems).
-- ============================================================================

-- ── 1. URL del informe PDF en la ejecución ──────────────────────────────────
ALTER TABLE enex_ejecuciones ADD COLUMN IF NOT EXISTS informe_pdf_url TEXT;

CREATE OR REPLACE FUNCTION rpc_enex_guardar_informe_pdf(p_ejecucion_id uuid, p_url text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    UPDATE enex_ejecuciones SET informe_pdf_url = p_url, updated_at = NOW() WHERE id = p_ejecucion_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Ejecución no encontrada'; END IF;
    RETURN jsonb_build_object('success', true);
END $$;
GRANT EXECUTE ON FUNCTION rpc_enex_guardar_informe_pdf(uuid, text) TO authenticated;

-- Storage: los informes PDF los sube cualquier usuario autenticado a la
-- carpeta enex-informes del bucket público 'documentos'.
DROP POLICY IF EXISTS storage_enex_informes_insert ON storage.objects;
CREATE POLICY storage_enex_informes_insert ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'documentos' AND (storage.foldername(name))[1] = 'enex-informes');
DROP POLICY IF EXISTS storage_enex_informes_update ON storage.objects;
CREATE POLICY storage_enex_informes_update ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'documentos' AND (storage.foldername(name))[1] = 'enex-informes');

-- ── 2. Pautas de CALIBRACIÓN → campos del certificado NCh1436 ───────────────
DO $$
DECLARE
    v_pauta RECORD;
    v_orden INT;
BEGIN
  FOR v_pauta IN SELECT id, codigo FROM enex_pautas WHERE codigo IN ('PAUTA-CAL-CAM','PAUTA-CAL-EESS','PAUTA-CAL-PET')
  LOOP
    UPDATE enex_pauta_items SET activo = false WHERE pauta_id = v_pauta.id;

    -- Bloque 0: identificación del surtidor / camión / petrolera
    INSERT INTO enex_pauta_items (pauta_id, bloque, bloque_orden, orden, codigo, descripcion, periodicidad, tipo_campo, requiere_foto, obligatorio) VALUES
      (v_pauta.id, '0. Identificación del surtidor', 0, 1,  'ID.SELLO_AJUSTE', 'Sello ajuste N°',                               'trimestral', 'texto', false, true),
      (v_pauta.id, '0. Identificación del surtidor', 0, 2,  'ID.SELLOS_CAB',   'Sellos cabezal N°',                             'trimestral', 'texto', false, false),
      (v_pauta.id, '0. Identificación del surtidor', 0, 3,  'ID.SELLOS_CPO',   'Sellos cabezal cuerpo medidor',                 'trimestral', 'texto', false, false),
      (v_pauta.id, '0. Identificación del surtidor', 0, 4,  'ID.MODELO',       'Modelo medidor / N° serie',                     'trimestral', 'texto', false, true),
      (v_pauta.id, '0. Identificación del surtidor', 0, 5,  'ID.COMBUSTIBLE',  'Tipo de combustible',                           'trimestral', 'texto', false, true),
      (v_pauta.id, '0. Identificación del surtidor', 0, 6,  'ID.SURTIDOR',     'Surtidor N° / Boca N°',                         'trimestral', 'texto', false, false),
      (v_pauta.id, '0. Identificación del surtidor', 0, 7,  'ID.TANQUE',       'Tanque N°',                                     'trimestral', 'texto', false, false);

    -- Bloque 1: seguridad previa (Pack PRO-CAL-001-F1)
    INSERT INTO enex_pauta_items (pauta_id, bloque, bloque_orden, orden, codigo, descripcion, periodicidad, tipo_campo, requiere_foto, obligatorio) VALUES
      (v_pauta.id, '1. Seguridad previa', 1, 1, 'SEG.1', 'ART/AST firmada y permiso de trabajo vigente',                    'trimestral', 'ok_nook', false, true),
      (v_pauta.id, '1. Seguridad previa', 1, 2, 'SEG.2', 'Área segregada (conos/barreras) y señalizada',                    'trimestral', 'ok_nook', false, true),
      (v_pauta.id, '1. Seguridad previa', 1, 3, 'SEG.3', 'Extintor PQS ≥10 kg operativo en el punto',                       'trimestral', 'ok_nook', false, true),
      (v_pauta.id, '1. Seguridad previa', 1, 4, 'SEG.4', 'Puesta a tierra conectada y verificada',                          'trimestral', 'ok_nook', false, true),
      (v_pauta.id, '1. Seguridad previa', 1, 5, 'SEG.5', 'EPP completo según estándar de faena',                            'trimestral', 'ok_nook', false, true),
      (v_pauta.id, '1. Seguridad previa', 1, 6, 'SEG.6', 'Inspección visual: sin fugas ni derrames',                        'trimestral', 'ok_nook', false, true),
      (v_pauta.id, '1. Seguridad previa', 1, 7, 'SEG.7', 'Certificado del patrón/matraz vigente',                           'trimestral', 'ok_nook', false, true),
      (v_pauta.id, '1. Seguridad previa', 1, 8, 'SEG.8', 'Patrón nivelado (burbuja) sobre superficie estable',              'trimestral', 'ok_nook', false, true),
      (v_pauta.id, '1. Seguridad previa', 1, 9, 'SEG.9', 'Línea purgada, sin aire; eliminador operativo',                   'trimestral', 'ok_nook', false, true);

    -- Bloque 2: totalizadores y recirculación
    INSERT INTO enex_pauta_items (pauta_id, bloque, bloque_orden, orden, codigo, descripcion, periodicidad, tipo_campo, unidad, requiere_foto, obligatorio) VALUES
      (v_pauta.id, '2. Totalizadores', 2, 1, 'TOT.INI', 'Totalizador inicio',   'trimestral', 'medicion', 'L', true,  true),
      (v_pauta.id, '2. Totalizadores', 2, 2, 'TOT.FIN', 'Totalizador final',    'trimestral', 'medicion', 'L', true,  true),
      (v_pauta.id, '2. Totalizadores', 2, 3, 'TOT.REC', 'Litros recirculados',  'trimestral', 'medicion', 'L', false, true);

    -- Bloque 3: corridas medidor vs patrón (6 corridas — certificado NCh1436)
    v_orden := 0;
    FOR i IN 1..6 LOOP
      v_orden := v_orden + 1;
      INSERT INTO enex_pauta_items (pauta_id, bloque, bloque_orden, orden, codigo, descripcion, periodicidad, tipo_campo, unidad, requiere_foto, obligatorio) VALUES
        (v_pauta.id, '3. Corridas medidor vs patrón', 3, v_orden, 'C' || i || '.MED', 'Corrida ' || i || ' — Lectura litros MEDIDOR', 'trimestral', 'medicion', 'L', false, i <= 3),
        (v_pauta.id, '3. Corridas medidor vs patrón', 3, v_orden + 100, 'C' || i || '.PAT', 'Corrida ' || i || ' — Lectura litros PATRÓN', 'trimestral', 'medicion', 'L', false, i <= 3);
    END LOOP;
    -- reordenar patrón intercalado tras medidor
    UPDATE enex_pauta_items SET orden = (orden - 100) * 2
      WHERE pauta_id = v_pauta.id AND bloque_orden = 3 AND orden > 100 AND activo;
    UPDATE enex_pauta_items SET orden = orden * 2 - 1
      WHERE pauta_id = v_pauta.id AND bloque_orden = 3 AND orden <= 6 AND codigo LIKE '%.MED' AND activo;

    -- Bloque 4: sellos y cierre
    INSERT INTO enex_pauta_items (pauta_id, bloque, bloque_orden, orden, codigo, descripcion, periodicidad, tipo_campo, requiere_foto, obligatorio) VALUES
      (v_pauta.id, '4. Sellos y cierre', 4, 1, 'CIE.SELLOS_OK', 'Inspección de sellos conforme (íntegros y legibles)', 'trimestral', 'ok_nook', true,  true),
      (v_pauta.id, '4. Sellos y cierre', 4, 2, 'CIE.SELLO_NVO', 'Sello nuevo instalado N° (si se reemplazó)',          'trimestral', 'texto',  false, false),
      (v_pauta.id, '4. Sellos y cierre', 4, 3, 'CIE.AJUSTE',    '¿Requirió ajuste? (detalle)',                          'trimestral', 'texto',  false, false),
      (v_pauta.id, '4. Sellos y cierre', 4, 4, 'CIE.OBS',       'Observaciones del certificado',                        'trimestral', 'texto',  false, false);
    RAISE NOTICE 'Pauta % reconstruida (certificado NCh1436)', v_pauta.codigo;
  END LOOP;
END $$;

-- ── 3. Pautas de MANTENCIÓN Semimóvil y Petrolera → formato OT Kizeo ────────
DO $$
DECLARE v_pauta RECORD;
BEGIN
  FOR v_pauta IN SELECT id, codigo FROM enex_pautas WHERE codigo IN ('PAUTA-MANT-SM','PAUTA-MANT-PET')
  LOOP
    UPDATE enex_pauta_items SET activo = false WHERE pauta_id = v_pauta.id;

    INSERT INTO enex_pauta_items (pauta_id, bloque, bloque_orden, orden, codigo, descripcion, periodicidad, tipo_campo, requiere_foto, obligatorio) VALUES
      -- Datos del servicio (encabezado del formato del mandante)
      (v_pauta.id, '0. Datos del servicio', 0, 1, 'DS.MOTIVO',   'Motivo del llamado',                      'trimestral', 'texto', false, true),
      (v_pauta.id, '0. Datos del servicio', 0, 2, 'DS.HORA_INI', 'Hora inicio (hh:mm)',                     'trimestral', 'texto', false, true),
      (v_pauta.id, '0. Datos del servicio', 0, 3, 'DS.HORA_FIN', 'Hora término (hh:mm)',                    'trimestral', 'texto', false, true),
      (v_pauta.id, '0. Datos del servicio', 0, 4, 'DS.RUT_TEC',  'Técnico(s) ejecutor(es): RUT(s)',         'trimestral', 'texto', false, true),
      -- Bloques del formato OT MANTENIMIENTO INTERMEDIO (mandante)
      (v_pauta.id, '1. Estanques verticales / horizontales', 1, 1, 'EST.1', 'Limpieza y reapriete de conexiones a tierra',                    'trimestral', 'ok_nook', false, true),
      (v_pauta.id, '1. Estanques verticales / horizontales', 1, 2, 'EST.2', 'Revisión de medidor mecánico de nivel / telemedición y control', 'trimestral', 'ok_nook', false, true),
      (v_pauta.id, '1. Estanques verticales / horizontales', 1, 3, 'EST.3', 'Revisión de fundación',                                          'trimestral', 'ok_nook', false, true),
      (v_pauta.id, '1. Estanques verticales / horizontales', 1, 4, 'EST.4', 'Revisión de anclajes',                                           'trimestral', 'ok_nook', false, true),
      (v_pauta.id, '2. Tubería y válvulas', 2, 1, 'TUB.1', 'Pruebas de presión',                    'trimestral', 'ok_nook', false, true),
      (v_pauta.id, '2. Tubería y válvulas', 2, 2, 'TUB.2', 'Revisión de operación de válvulas',     'trimestral', 'ok_nook', false, true),
      (v_pauta.id, '3. Tableros eléctricos', 3, 1, 'TAB.1', 'Limpieza exterior e interior',          'trimestral', 'ok_nook', false, true),
      (v_pauta.id, '3. Tableros eléctricos', 3, 2, 'TAB.2', 'Apriete de bornes de protectores',      'trimestral', 'ok_nook', false, true),
      (v_pauta.id, '3. Tableros eléctricos', 3, 3, 'TAB.3', 'Revisión de luces piloto',              'trimestral', 'ok_nook', false, true),
      (v_pauta.id, '3. Tableros eléctricos', 3, 4, 'TAB.4', 'Revisión de parada de emergencia',      'trimestral', 'ok_nook', false, true),
      -- Pauta técnica complementaria (Pack SST-PO-005-F1, nivel técnico)
      (v_pauta.id, '4. Bombas y medición', 4, 1, 'BOM.1', 'Colador/strainer: canastillo limpio, malla sin roturas, o-ring en buen estado', 'trimestral', 'ok_nook', false, true),
      (v_pauta.id, '4. Bombas y medición', 4, 2, 'BOM.2', 'Filtros de despacho cambiados o verificados; caudal normal',                    'trimestral', 'ok_nook', false, true),
      (v_pauta.id, '4. Bombas y medición', 4, 3, 'BOM.3', 'Sellos de calibrador y pulser íntegros; sin fugas por tapas/prensaestopas',     'trimestral', 'ok_nook', false, true),
      (v_pauta.id, '4. Bombas y medición', 4, 4, 'BOM.4', 'Totalizador conciliado contra registros',                                       'trimestral', 'ok_nook', false, true),
      (v_pauta.id, '4. Bombas y medición', 4, 5, 'BOM.5', 'Eliminador de aire: flotador/asiento limpios, venteo operativo',                'trimestral', 'ok_nook', false, false),
      (v_pauta.id, '5. Pistolas y mangueras', 5, 1, 'PIS.1', 'Pistolas: cuerpo sin grietas, gatillo/traba y corte automático operativos', 'trimestral', 'ok_nook', false, true),
      (v_pauta.id, '5. Pistolas y mangueras', 5, 2, 'PIS.2', 'Mangueras sin cortes/ampollas, swivel y breakaway en buen estado',          'trimestral', 'ok_nook', false, true),
      -- Registro fotográfico del trabajo (Imágenes del formato)
      (v_pauta.id, '6. Registro fotográfico', 6, 1, 'FOT.1', 'Foto de trabajos 1', 'trimestral', 'ok_nook', true, true),
      (v_pauta.id, '6. Registro fotográfico', 6, 2, 'FOT.2', 'Foto de trabajos 2', 'trimestral', 'ok_nook', true, false),
      (v_pauta.id, '6. Registro fotográfico', 6, 3, 'FOT.3', 'Foto de trabajos 3', 'trimestral', 'ok_nook', true, false);
    RAISE NOTICE 'Pauta % reconstruida (OT mantenimiento intermedio)', v_pauta.codigo;
  END LOOP;
END $$;

-- ── 4. EESS y Truck Shop: agregar "Datos del servicio" + registro fotográfico ─
DO $$
DECLARE v_pauta RECORD;
BEGIN
  FOR v_pauta IN SELECT id, codigo FROM enex_pautas WHERE codigo IN ('PAUTA-MANT-EESS','PAUTA-LUB')
  LOOP
    IF NOT EXISTS (SELECT 1 FROM enex_pauta_items WHERE pauta_id = v_pauta.id AND codigo = 'DS.MOTIVO' AND activo) THEN
      INSERT INTO enex_pauta_items (pauta_id, bloque, bloque_orden, orden, codigo, descripcion, periodicidad, tipo_campo, requiere_foto, obligatorio) VALUES
        (v_pauta.id, '0. Datos del servicio', 0, 1, 'DS.MOTIVO',   'Motivo del llamado',              'trimestral', 'texto', false, true),
        (v_pauta.id, '0. Datos del servicio', 0, 2, 'DS.HORA_INI', 'Hora inicio (hh:mm)',             'trimestral', 'texto', false, true),
        (v_pauta.id, '0. Datos del servicio', 0, 3, 'DS.HORA_FIN', 'Hora término (hh:mm)',            'trimestral', 'texto', false, true),
        (v_pauta.id, '0. Datos del servicio', 0, 4, 'DS.RUT_TEC',  'Técnico(s) ejecutor(es): RUT(s)', 'trimestral', 'texto', false, true),
        (v_pauta.id, '9. Registro fotográfico', 9, 1, 'FOT.1', 'Foto de trabajos 1', 'trimestral', 'ok_nook', true, true),
        (v_pauta.id, '9. Registro fotográfico', 9, 2, 'FOT.2', 'Foto de trabajos 2', 'trimestral', 'ok_nook', true, false);
      RAISE NOTICE 'Pauta %: bloques Datos del servicio + fotos agregados', v_pauta.codigo;
    END IF;
  END LOOP;
END $$;

DO $$ BEGIN RAISE NOTICE 'MIG231 OK: pautas alineadas al formato del mandante + informe_pdf_url'; END $$;
