-- ============================================================================
-- MIG517 · Ajustes a la escalera MB según el manual oficial (Actros Euro 5)
-- ============================================================================
--
-- Manuel (04-09-2026): «investigar cómo correctamente es la tabla de MB,
-- comparar con la que tenemos nosotros ahora y hacer una comparación, para
-- poder aplicar». La comparación completa está en
-- docs/COMPARACION_TABLA_MB_VS_SICOM.md (fuente: Manual de mantenimiento
-- Actros Euro 5, MB do Brasil / Kaufmann, sistema Telligent).
--
-- Lo que el manual corrige de nuestra tabla (MIG510):
--  1. VÁLVULAS: el manual las pide en el 1er M y luego CADA 4 M (≈2400 h),
--     no cada 8 (nuestro SM4 4800). → se mueven de SM4 a SM3; la absorción
--     (MIG513) las arrastra a 4800/9600/19200 sin duplicar.
--  2. ADBLUE: el Euro 5 lleva filtro de AdBlue (240.000 km o 2 años) y
--     calibración de bomba. No estaba en ninguna pauta. → SM3.
--  3. CUBOS DELANTEROS (J1 anual): grasa, retenes, rodamientos, juego axial.
--     No estaba. → SM3, anotado «máx. 12 meses».
--  4. FILTRO DE AIRE: el manual NO sopla el elemento (lo microperfora y el
--     polvo mata el turbo): se revisa la saturación y se limpia la válvula
--     de descarga. → se reescribe el ítem de SM1 en TODAS las pautas MB.
--  5. SECADOR: el manual lo pide anual (J1); queda anotado «máx. 12 meses»
--     en el ítem de SM3.
--
-- El primer servicio Z1 (asentamiento de camión nuevo) queda documentado en
-- la comparación; no se crea pauta porque la flota ya está rodada.
-- ============================================================================

BEGIN;

-- ── 1 · Reescrituras por texto de ítem (todas las pautas MB activas) ────────
-- Filtro de aire: revisar y limpiar la válvula, NO soplar el elemento.
UPDATE pautas_fabricante p
   SET items_checklist = (
        SELECT jsonb_agg(
            CASE WHEN e = 'Revision/soplado filtro de aire primario (cambiar si el indicador lo pide)'
                 THEN to_jsonb('Revision de saturacion del filtro de aire y limpieza de la valvula de descarga de polvo (NO soplar el elemento; cambiar si el indicador lo pide)'::text)
                 WHEN e = 'Cambio cartucho secador de aire'
                 THEN to_jsonb('Cambio cartucho secador de aire (max. 12 meses)'::text)
                 ELSE to_jsonb(e) END ORDER BY ord)
          FROM jsonb_array_elements_text(p.items_checklist) WITH ORDINALITY t(e, ord))
 WHERE p.activo
   AND jsonb_typeof(p.items_checklist) = 'array'
   AND EXISTS (SELECT 1 FROM modelos mo JOIN marcas ma ON ma.id = mo.marca_id
                WHERE mo.id = p.modelo_id AND ma.nombre ILIKE '%mercedes%')
   AND (p.items_checklist ? 'Revision/soplado filtro de aire primario (cambiar si el indicador lo pide)'
     OR p.items_checklist ? 'Cambio cartucho secador de aire');

-- ── 2 · Válvulas: salen de SM4 (4800 h)… ────────────────────────────────────
UPDATE pautas_fabricante p
   SET items_checklist = (
        SELECT jsonb_agg(to_jsonb(e) ORDER BY ord)
          FROM jsonb_array_elements_text(p.items_checklist) WITH ORDINALITY t(e, ord)
         WHERE e <> 'Calibracion juego de valvulas')
 WHERE p.activo
   AND p.nombre LIKE '%SM4%'
   AND p.items_checklist ? 'Calibracion juego de valvulas'
   AND EXISTS (SELECT 1 FROM modelos mo JOIN marcas ma ON ma.id = mo.marca_id
                WHERE mo.id = p.modelo_id AND ma.nombre ILIKE '%mercedes%');

-- ── 3 · …y entran a SM3 (2400 h), junto con AdBlue y cubos delanteros ───────
UPDATE pautas_fabricante p
   SET items_checklist = p.items_checklist
       || CASE WHEN p.items_checklist ? 'Calibracion juego de valvulas' THEN '[]'::jsonb
               ELSE jsonb_build_array('Calibracion juego de valvulas') END
       || CASE WHEN p.items_checklist ? 'Cambio filtro de AdBlue y calibracion de bomba AdBlue (Euro 5)' THEN '[]'::jsonb
               ELSE jsonb_build_array('Cambio filtro de AdBlue y calibracion de bomba AdBlue (Euro 5)') END
       || CASE WHEN p.items_checklist ? 'Cambio de grasa y retenes de cubos de rueda delanteros; verificar rodamientos y juego axial (max. 12 meses)' THEN '[]'::jsonb
               ELSE jsonb_build_array('Cambio de grasa y retenes de cubos de rueda delanteros; verificar rodamientos y juego axial (max. 12 meses)') END
 WHERE p.activo
   AND p.nombre LIKE '%SM3%'
   AND p.nombre NOT LIKE '%Accelo%'
   AND EXISTS (SELECT 1 FROM modelos mo JOIN marcas ma ON ma.id = mo.marca_id
                WHERE mo.id = p.modelo_id
                  AND ma.nombre ILIKE '%mercedes%'
                  AND (mo.nombre ILIKE '%actros%' OR mo.nombre ILIKE '%axor%' OR mo.nombre ILIKE '%atego%'));

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE v_n INT;
BEGIN
    -- Ninguna pauta MB activa sigue diciendo «soplado».
    SELECT count(*) INTO v_n FROM pautas_fabricante p
     WHERE p.activo AND p.items_checklist::text ILIKE '%soplado%'
       AND EXISTS (SELECT 1 FROM modelos mo JOIN marcas ma ON ma.id = mo.marca_id
                    WHERE mo.id = p.modelo_id AND ma.nombre ILIKE '%mercedes%');
    IF v_n > 0 THEN RAISE EXCEPTION 'FALLO: % pautas MB siguen con soplado', v_n; END IF;

    -- Las válvulas están en TODOS los SM3 de Actros/Axor/Atego y en ningún SM4.
    SELECT count(*) INTO v_n FROM pautas_fabricante p
     WHERE p.activo AND p.nombre LIKE '%SM3%' AND p.nombre NOT LIKE '%Accelo%'
       AND NOT p.items_checklist ? 'Calibracion juego de valvulas'
       AND EXISTS (SELECT 1 FROM modelos mo JOIN marcas ma ON ma.id = mo.marca_id
                    WHERE mo.id = p.modelo_id AND ma.nombre ILIKE '%mercedes%'
                      AND (mo.nombre ILIKE '%actros%' OR mo.nombre ILIKE '%axor%' OR mo.nombre ILIKE '%atego%'));
    IF v_n > 0 THEN RAISE EXCEPTION 'FALLO: % SM3 sin valvulas', v_n; END IF;

    SELECT count(*) INTO v_n FROM pautas_fabricante p
     WHERE p.activo AND p.nombre LIKE '%SM4%'
       AND p.items_checklist ? 'Calibracion juego de valvulas';
    IF v_n > 0 THEN RAISE EXCEPTION 'FALLO: % SM4 todavia con valvulas', v_n; END IF;

    -- AdBlue y cubos quedaron en los SM3 grandes.
    SELECT count(*) INTO v_n FROM pautas_fabricante p
     WHERE p.activo AND p.nombre LIKE '%SM3%' AND p.nombre NOT LIKE '%Accelo%'
       AND p.items_checklist ? 'Cambio filtro de AdBlue y calibracion de bomba AdBlue (Euro 5)'
       AND p.items_checklist ? 'Cambio de grasa y retenes de cubos de rueda delanteros; verificar rodamientos y juego axial (max. 12 meses)'
       AND EXISTS (SELECT 1 FROM modelos mo JOIN marcas ma ON ma.id = mo.marca_id
                    WHERE mo.id = p.modelo_id AND ma.nombre ILIKE '%mercedes%');
    RAISE NOTICE 'MIG517 OK · % pautas SM3 con valvulas + AdBlue + cubos; soplado erradicado', v_n;
    IF v_n = 0 THEN RAISE EXCEPTION 'FALLO: ningun SM3 recibio los items nuevos'; END IF;
END
$mig$;

COMMIT;
