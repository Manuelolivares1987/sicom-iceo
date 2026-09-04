-- ============================================================================
-- MIG529 · Un equipo de PRUEBA que no afecta en nada al sistema
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL (04-09-2026)
-- «Quiero que crees una patente para hacer pruebas y que no afecte en nada
-- al sistema.»
--
-- EL DISEÑO — por qué no contamina:
--   · KPIs de disponibilidad y reporte diario: cuentan solo equipos con
--     estado del día del planificador. El equipo de prueba NO recibe estados
--     diarios → nunca entra al denominador (misma lógica que hace inocuo no
--     cargar un estado).
--   · Portal del cliente / QR: qr_publico_habilitado = false.
--   · Checklist cliente semanal: cubre arrendado/leasing → estado_comercial
--     NULL lo deja fuera.
--   · Verificaciones ready-to-rent: solo estado_comercial 'disponible' → NULL
--     lo deja fuera.
--   · Motor de preventivas: sin modelo y sin planes → no genera nada.
--   · Cobertura de mantenimiento: la vista de cobertura se parcha para
--     excluir es_prueba (si no, aparecería como «sin modelo» ensuciando el
--     100 % logrado en MIG79-84).
--   · Control documental: sin papeles → no tiene filas.
--   · GPS/sugerencias: sin tracker → invisible.
--
-- La marca `activos.es_prueba` deja el equipo identificable y borrable
-- limpio. REGLAS DE USO (quedan en el nombre del equipo y acá):
--   NO asignarle contrato, ni estado diario del planificador, ni plan
--   preventivo, ni GPS. Todo lo demás (OTs, checklists, planes de taller,
--   informes, vales) se puede probar libremente.
-- ============================================================================

BEGIN;

-- ── 1 · La marca ────────────────────────────────────────────────────────────
ALTER TABLE activos ADD COLUMN IF NOT EXISTS es_prueba BOOLEAN NOT NULL DEFAULT false;
COMMENT ON COLUMN activos.es_prueba IS
'Equipo de laboratorio (MIG529): existe solo para probar flujos. Sin contrato, sin estados diarios, sin planes ni GPS; excluido de las vistas de flota. Borrable junto con sus OTs.';

-- ── 2 · La cobertura de mantenimiento lo ignora ─────────────────────────────
DO $p$
DECLARE v_def TEXT;
        v_viejo TEXT := 'WHERE a.estado <> ''dado_baja''::estado_activo_enum';
        v_nuevo TEXT := 'WHERE a.estado <> ''dado_baja''::estado_activo_enum AND NOT COALESCE(a.es_prueba, false)';
BEGIN
    SELECT pg_get_viewdef('v_mantenimiento_cobertura_resumen'::regclass, true) INTO v_def;
    IF position(v_viejo IN v_def) = 0 THEN
        RAISE EXCEPTION 'FALLO: no encontré el filtro de activos vivos en la vista de cobertura';
    END IF;
    IF position(v_viejo IN substring(v_def FROM position(v_viejo IN v_def) + length(v_viejo))) > 0 THEN
        RAISE EXCEPTION 'FALLO: el filtro aparece más de una vez — parchar a mano';
    END IF;
    EXECUTE 'CREATE OR REPLACE VIEW v_mantenimiento_cobertura_resumen AS ' || replace(v_def, v_viejo, v_nuevo);
    RAISE NOTICE 'cobertura de mantenimiento: es_prueba excluido';
END $p$;

-- ── 3 · El equipo ───────────────────────────────────────────────────────────
DO $mig$
DECLARE v_id UUID; v_marca UUID; v_modelo UUID; v_antes RECORD; v_despues RECORD; v_n INT;
BEGIN
    -- Marca y modelo de laboratorio (modelo_id es NOT NULL). Sin pautas de
    -- fabricante: el motor de preventivas no tiene nada que mirar aquí.
    SELECT id INTO v_marca FROM marcas WHERE nombre = 'PRUEBA';
    IF v_marca IS NULL THEN
        INSERT INTO marcas (nombre) VALUES ('PRUEBA') RETURNING id INTO v_marca;
    END IF;
    SELECT id INTO v_modelo FROM modelos WHERE marca_id = v_marca AND nombre = 'Modelo de Prueba';
    IF v_modelo IS NULL THEN
        INSERT INTO modelos (marca_id, nombre, tipo_activo)
        VALUES (v_marca, 'Modelo de Prueba', 'camion_cisterna') RETURNING id INTO v_modelo;
    END IF;
    -- Foto de los números ANTES, para demostrar que nada se mueve.
    SELECT (SELECT count(*) FROM v_checklist_cliente_cumplimiento)      AS chk,
           (SELECT count(*) FROM v_equipos_pendientes_verificacion)     AS verif,
           (SELECT COALESCE(sum(1),0) FROM v_mantenimiento_cobertura_resumen) AS cob
      INTO v_antes;

    SELECT id INTO v_id FROM activos WHERE codigo = 'TEST-01';
    IF v_id IS NULL THEN
        INSERT INTO activos (codigo, patente, nombre, tipo, estado, estado_comercial,
                             modelo_id, qr_publico_habilitado, es_prueba,
                             horas_uso_actual, kilometraje_actual)
        VALUES ('TEST-01', 'PRUEBA-01', 'CAMIÓN DE PRUEBA — NO OPERACIONAL (solo testing)',
                'camion_cisterna', 'operativo', NULL,
                v_modelo, false, true, 1000, 10000)
        RETURNING id INTO v_id;
        RAISE NOTICE 'equipo de prueba creado: % (TEST-01 / PRUEBA-01)', v_id;
    ELSE
        UPDATE activos SET es_prueba = true, qr_publico_habilitado = false WHERE id = v_id;
        RAISE NOTICE 'equipo de prueba ya existía: %', v_id;
    END IF;

    -- ── Verificación: no se movió ningún número ─────────────────────────────
    SELECT (SELECT count(*) FROM v_checklist_cliente_cumplimiento)      AS chk,
           (SELECT count(*) FROM v_equipos_pendientes_verificacion)     AS verif,
           (SELECT COALESCE(sum(1),0) FROM v_mantenimiento_cobertura_resumen) AS cob
      INTO v_despues;

    IF v_antes.chk <> v_despues.chk OR v_antes.verif <> v_despues.verif OR v_antes.cob <> v_despues.cob THEN
        RAISE EXCEPTION 'FALLO: el equipo de prueba movió un contador (chk %→%, verif %→%, cobertura %→%)',
            v_antes.chk, v_despues.chk, v_antes.verif, v_despues.verif, v_antes.cob, v_despues.cob;
    END IF;

    -- Ni el QR ni el historial público lo entregan.
    SELECT count(*) INTO v_n FROM rpc_historial_mantenimiento_publico(v_id);
    IF v_n > 0 THEN RAISE EXCEPTION 'FALLO: el QR público entrega el equipo de prueba'; END IF;

    RAISE NOTICE 'MIG529 OK · TEST-01/PRUEBA-01 listo: invisible para cliente, KPIs, cobertura y verificaciones';
END
$mig$;

COMMIT;
