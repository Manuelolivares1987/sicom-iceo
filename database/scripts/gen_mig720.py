"""Genera MIG720 desde las MISMAS listas de la propuesta (build_pauta.py)."""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_SQL = sys.argv[1]
MIG717 = sys.argv[2]
sys.argv = [sys.argv[0], os.path.join(HERE, "_tmp_pauta.xlsx")]
sys.path.insert(0, HERE)
import build_pauta as bp  # noqa: E402  (construye el libro de nuevo: inofensivo)

T, D = bp.T, bp.D
AC = "Aljibe combustible"
NIVELES = [("SL", 300, 30), ("SM1", 600, 90), ("SM2", 1200, 365), ("SM3", 2400, 730), ("SM4", 4800, 1460)]
NOMBRE_PF = {"SL": "Mack GU813E - Servicio SL (300h)", "SM1": "Mack GU813E - Servicio SM1 (600h)",
             "SM2": "Mack GU813E - Servicio SM2 (1200h)", "SM3": "Mack GU813E - Servicio SM3 (2400h)",
             "SM4": "Mack GU813E - Servicio SM4 (4800h)"}
PREV = {"SM1": "SL", "SM2": "SM1", "SM3": "SM2", "SM4": "SM3"}


def q(s):
    return "'" + s.replace("'", "''") + "'"


def texto_pf(v):
    n, sis, tarea, tipo, aplica, esp, ori, porq = v
    s = tarea + (" — " + esp if esp and esp != "—" else "")
    return ("[Solo aljibe de combustible] " + s) if aplica == AC else s


def items_pf(nivel):
    own = [texto_pf(v) for v in T if v[0] == nivel]
    return ([PREV[nivel] + " completo"] if nivel in PREV else []) + own


L = []
w = L.append
w("""-- ============================================================================
-- MIG720 — Pauta Mack GU 813 servicio severo (19-11-2026)
-- ----------------------------------------------------------------------------
-- Pedido y aprobado por Manuel (19-11): «cárgala completa»; en Franke el
-- mantenimiento es MIXTO (principalmente en faena, a veces se baja a Coquimbo).
-- Fuente: Pauta Pillado v1.0 (09-11) + datos reales de la flota
-- (research_notes/Pauta Mack severa/ — Excel de la propuesta y datos_flota_mack.md).
--
-- 1. pautas_fabricante (3 modelos Mack): SL/SM1/SM2/SM3 con las tareas nuevas
--    + SM4 (4.800 h), tope en días (30/90/365/730/1460). Escalera de la
--    compañía con absorción: cada nivel trae «<anterior> completo» (MIG494).
--    Se regeneran las plantillas de OT (fn_pauta_a_template versiona si ya
--    se usaron: las OT abiertas no cambian).
-- 2. planes de los 6 Mack: tope en días y SM4; la última ejecución se alinea
--    con la escalera (un SM3 hecho cuenta como SL/SM1/SM2). Los 3 de Franke
--    quedan SIN OT automática (el cron las duplicaría con la agenda de faena);
--    si se bajan a Coquimbo el taller abre la OT como siempre y su cierre
--    avanza el plan (trg_ot_cerrada_avanza_plan).
-- 3. Un servicio CERRADO en la app de faena avanza el plan del camión
--    (trg_faena_ejecucion_avanza_plan): faena y Coquimbo cuentan en la misma
--    escalera.
-- 4. v_faena_pauta_agenda: «lo que ocurra primero» también por días
--    (columna nueva faltan_dias al final).
-- 5. Franke: FRK-PM-300 pasa a ser el SL (0 ejecuciones: se reemplazan sus
--    ítems) + FRK-SM1-600 … FRK-SM4-4800 con los ítems acumulados.
-- 6. FRK-DIA-CP v2: 43 ítems; los actuales se actualizan EN SU LUGAR (hay un
--    borrador que los referencia) y se agregan 15.
-- ============================================================================
""")

# ---- 1. pautas_fabricante
w("-- 1. Pauta del fabricante ---------------------------------------------------")
w("DO $$\nDECLARE m RECORD; v_n INT;\nBEGIN")
w("  FOR m IN SELECT id, nombre FROM public.modelos WHERE nombre IN ('GU 813 autom','GU813E Mec','GU813E Allison') LOOP")
for nivel, h, d in NIVELES:
    js = q(json.dumps(items_pf(nivel), ensure_ascii=False)) + "::jsonb"
    if nivel != "SM4":
        w(f"    UPDATE public.pautas_fabricante SET items_checklist = {js}, frecuencia_dias = {d}, tipo_plan = 'mixto',")
        w(f"           descripcion = 'Servicio severo Mack GU 813 (MIG720): {nivel} {h} h o {d} días, lo que ocurra primero', updated_at = NOW()")
        w(f"     WHERE modelo_id = m.id AND nombre = {q(NOMBRE_PF[nivel])};")
        w("    GET DIAGNOSTICS v_n = ROW_COUNT;")
        w(f"    IF v_n <> 1 THEN RAISE EXCEPTION 'Modelo %: se esperaba 1 pauta {nivel} y hay %', m.nombre, v_n; END IF;")
    else:
        w(f"    IF NOT EXISTS (SELECT 1 FROM public.pautas_fabricante WHERE modelo_id = m.id AND nombre = {q(NOMBRE_PF[nivel])}) THEN")
        w("      INSERT INTO public.pautas_fabricante (modelo_id, nombre, tipo_plan, frecuencia_horas, frecuencia_dias, descripcion,")
        w("                                            items_checklist, duracion_estimada_hrs, activo, duracion_es_estimada)")
        w(f"      VALUES (m.id, {q(NOMBRE_PF[nivel])}, 'mixto', {h}, {d},")
        w(f"              'Servicio severo Mack GU 813 (MIG720): SM4 4800 h o 1460 días, lo que ocurra primero', {js}, 16, TRUE, TRUE);")
        w("    END IF;")
w("  END LOOP;")
w("""  -- Plantillas de OT (versiona las que ya tienen OT: las abiertas no cambian).
  PERFORM public.fn_pauta_a_template(pf.id)
     FROM public.pautas_fabricante pf JOIN public.modelos mo ON mo.id = pf.modelo_id
    WHERE mo.nombre IN ('GU 813 autom','GU813E Mec','GU813E Allison') AND pf.activo
      AND pf.nombre LIKE 'Mack GU813E - Servicio %';
END $$;
""")

# ---- 2. planes
w("""-- 2. Planes de los 6 Mack --------------------------------------------------------
DO $$
DECLARE v_n INT;
BEGIN
  -- Tope en días y tipo mixto, copiados de la pauta (los planes copian la frecuencia).
  UPDATE public.planes_mantenimiento pm
     SET frecuencia_dias = pf.frecuencia_dias, tipo_plan = 'mixto', updated_at = NOW()
    FROM public.pautas_fabricante pf
   WHERE pm.pauta_fabricante_id = pf.id AND pf.nombre LIKE 'Mack GU813E - Servicio %';

  -- SM4 para cada Mack que tiene la escalera (base = su último servicio registrado).
  INSERT INTO public.planes_mantenimiento (activo_id, pauta_fabricante_id, nombre, tipo_plan, frecuencia_horas, frecuencia_dias,
                                           anticipacion_dias, prioridad, ultima_ejecucion_fecha, ultima_ejecucion_km,
                                           ultima_ejecucion_horas, activo_plan)
  SELECT sl.activo_id, sm4.id, sm4.nombre, 'mixto', 4800, 1460, sl.anticipacion_dias, sl.prioridad,
         b.ultima_ejecucion_fecha, b.ultima_ejecucion_km, b.ultima_ejecucion_horas, sl.activo_plan
    FROM public.planes_mantenimiento sl
    JOIN public.pautas_fabricante psl ON psl.id = sl.pauta_fabricante_id AND psl.nombre = 'Mack GU813E - Servicio SL (300h)'
    JOIN public.pautas_fabricante sm4 ON sm4.modelo_id = psl.modelo_id AND sm4.nombre = 'Mack GU813E - Servicio SM4 (4800h)'
    CROSS JOIN LATERAL (SELECT x.ultima_ejecucion_fecha, x.ultima_ejecucion_km, x.ultima_ejecucion_horas
                          FROM public.planes_mantenimiento x
                         WHERE x.activo_id = sl.activo_id AND x.ultima_ejecucion_horas > 0
                         ORDER BY (x.frecuencia_horas >= 2400) DESC, x.ultima_ejecucion_horas DESC LIMIT 1) b
   WHERE NOT EXISTS (SELECT 1 FROM public.planes_mantenimiento z WHERE z.activo_id = sl.activo_id AND z.pauta_fabricante_id = sm4.id);
  GET DIAGNOSTICS v_n = ROW_COUNT; RAISE NOTICE 'SM4 creados: %', v_n;

  -- Absorción en la línea base: un servicio mayor hecho cuenta para los menores
  -- (frecuencia múltiplo). Nunca hacia atrás.
  UPDATE public.planes_mantenimiento p
     SET (ultima_ejecucion_horas, ultima_ejecucion_km, ultima_ejecucion_fecha) = (
            SELECT x.ultima_ejecucion_horas, COALESCE(x.ultima_ejecucion_km, p.ultima_ejecucion_km),
                   COALESCE(x.ultima_ejecucion_fecha, p.ultima_ejecucion_fecha)
              FROM public.planes_mantenimiento x
             WHERE x.activo_id = p.activo_id AND x.frecuencia_horas > 0 AND x.ultima_ejecucion_horas > 0
               AND x.frecuencia_horas % p.frecuencia_horas = 0
             ORDER BY x.ultima_ejecucion_horas DESC LIMIT 1),
         updated_at = NOW()
   WHERE p.frecuencia_horas > 0
     AND p.activo_id IN (SELECT pm.activo_id FROM public.planes_mantenimiento pm
                           JOIN public.pautas_fabricante pf ON pf.id = pm.pauta_fabricante_id
                          WHERE pf.nombre LIKE 'Mack GU813E - Servicio %')
     AND COALESCE(p.ultima_ejecucion_horas, 0) < (
            SELECT max(x.ultima_ejecucion_horas) FROM public.planes_mantenimiento x
             WHERE x.activo_id = p.activo_id AND x.frecuencia_horas > 0
               AND x.frecuencia_horas % p.frecuencia_horas = 0);
  GET DIAGNOSTICS v_n = ROW_COUNT; RAISE NOTICE 'Bases alineadas por absorción: %', v_n;

  -- Franke: sin OT automáticas (mixto, principalmente en faena).
  UPDATE public.planes_mantenimiento pm SET activo_plan = FALSE, updated_at = NOW()
    FROM public.activos a JOIN public.faenas f ON f.id = a.faena_id
   WHERE pm.activo_id = a.id AND f.codigo = 'FAE-FRANCKE' AND pm.frecuencia_horas > 0 AND pm.activo_plan;
  GET DIAGNOSTICS v_n = ROW_COUNT; RAISE NOTICE 'Planes Franke sin OT automática: %', v_n;
END $$;
""")

# ---- 3. trigger
w("""-- 3. Servicio cerrado en faena avanza el plan ----------------------------------
CREATE OR REPLACE FUNCTION public.fn_faena_ejecucion_avanza_plan()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE p RECORD;
BEGIN
    IF NEW.estado IS DISTINCT FROM 'cerrada' OR (TG_OP = 'UPDATE' AND OLD.estado = 'cerrada') THEN
        RETURN NEW;
    END IF;
    SELECT tipo, disparo_horas, disparo_km INTO p FROM public.faena_pauta WHERE id = NEW.pauta_id;
    IF p.tipo IS DISTINCT FROM 'programada' THEN RETURN NEW; END IF;

    -- Escalera con absorción: avanza el plan de igual frecuencia y los menores
    -- (frecuencia que divide al disparo). Nunca hacia atrás.
    IF p.disparo_horas IS NOT NULL AND NEW.horometro > 0 THEN
        UPDATE public.planes_mantenimiento pm
           SET ultima_ejecucion_horas = NEW.horometro,
               ultima_ejecucion_km    = COALESCE(NULLIF(NEW.kilometraje, 0), pm.ultima_ejecucion_km),
               ultima_ejecucion_fecha = NEW.fecha,
               updated_at = NOW()
         WHERE pm.activo_id = NEW.activo_id AND pm.frecuencia_horas > 0
           AND p.disparo_horas % pm.frecuencia_horas = 0
           AND COALESCE(pm.ultima_ejecucion_horas, 0) < NEW.horometro;
    ELSIF p.disparo_km IS NOT NULL AND NEW.kilometraje > 0 THEN
        UPDATE public.planes_mantenimiento pm
           SET ultima_ejecucion_km = NEW.kilometraje,
               ultima_ejecucion_horas = COALESCE(NULLIF(NEW.horometro, 0), pm.ultima_ejecucion_horas),
               ultima_ejecucion_fecha = NEW.fecha,
               updated_at = NOW()
         WHERE pm.activo_id = NEW.activo_id AND pm.frecuencia_km > 0
           AND p.disparo_km % pm.frecuencia_km = 0
           AND COALESCE(pm.ultima_ejecucion_km, 0) < NEW.kilometraje;
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_faena_ejecucion_avanza_plan ON public.faena_pauta_ejecucion;
CREATE TRIGGER trg_faena_ejecucion_avanza_plan
    AFTER INSERT OR UPDATE OF estado ON public.faena_pauta_ejecucion
    FOR EACH ROW EXECUTE FUNCTION public.fn_faena_ejecucion_avanza_plan();
""")

# ---- 4. view (from MIG717 + días)
v = open(MIG717, encoding="utf-8").read()
v = v[v.index("CREATE OR REPLACE VIEW"):v.index("-- Resultado para Franke")].rstrip()
old_v = """            WHEN p.disparo_horas IS NOT NULL AND (u.horometro + p.disparo_horas) <= COALESCE(a.horas_uso_actual, 0::numeric)
              OR p.disparo_km IS NOT NULL AND (u.kilometraje + p.disparo_km) <= COALESCE(a.kilometraje_actual, 0::numeric) THEN 'vencida'::text"""
new_v = """            WHEN p.disparo_horas IS NOT NULL AND (u.horometro + p.disparo_horas) <= COALESCE(a.horas_uso_actual, 0::numeric)
              OR p.disparo_km IS NOT NULL AND (u.kilometraje + p.disparo_km) <= COALESCE(a.kilometraje_actual, 0::numeric)
              OR p.disparo_dias IS NOT NULL AND u.fecha IS NOT NULL AND (u.fecha::date + p.disparo_dias) <= CURRENT_DATE THEN 'vencida'::text"""
assert old_v in v
v = v.replace(old_v, new_v)
old_p = """              OR p.disparo_km IS NOT NULL AND (u.kilometraje + p.disparo_km - COALESCE(a.kilometraje_actual, 0::numeric)) <= p.aviso_km THEN 'por_vencer'::text"""
new_p = """              OR p.disparo_km IS NOT NULL AND (u.kilometraje + p.disparo_km - COALESCE(a.kilometraje_actual, 0::numeric)) <= p.aviso_km
              OR p.disparo_dias IS NOT NULL AND u.fecha IS NOT NULL AND (u.fecha::date + p.disparo_dias) - CURRENT_DATE <= 7 THEN 'por_vencer'::text"""
assert old_p in v
v = v.replace(old_p, new_p)
old_end = """    hoy.ejecutado_por_nombre AS ejecucion_hoy_por
   FROM activos a"""
new_end = """    hoy.ejecutado_por_nombre AS ejecucion_hoy_por,
        CASE
            WHEN p.disparo_dias IS NOT NULL AND u.fecha IS NOT NULL THEN (u.fecha::date + p.disparo_dias) - CURRENT_DATE
            ELSE NULL::integer
        END AS faltan_dias
   FROM activos a"""
assert old_end in v
v = v.replace(old_end, new_end)
w("-- 4. Agenda de faena: también por días ------------------------------------------")
w(v + "\n")

# ---- 5. Franke programadas
w("-- 5. Franke: SL…SM4 en la app del mecánico ---------------------------------------")


def critico(v):
    n, sis, tarea, tipo, aplica, esp, ori, porq = v
    return tipo in ("Reemplazo", "Ensayo", "Ajuste") or sis in ("Frenos", "Válvulas", "Puesta a tierra", "Cumplimiento")


def fila_items(nivel_max, h):
    rows = [("Lecturas", "Horómetro al iniciar el servicio", "numero", "h", False, None, None),
            ("Lecturas", "Kilometraje al iniciar el servicio", "numero", "km", False, None, None)]
    orden_niveles = [n for n, _, _ in NIVELES]
    for nv in orden_niveles[:orden_niveles.index(nivel_max) + 1]:
        for v in T:
            if v[0] != nv:
                continue
            n, sis, tarea, tipo, aplica, esp, ori, porq = v
            if sis == "Cierre":
                tarea = "Prueba de ruta y del sistema de despacho"
            if sis == "Lecturas":
                tarea = "Códigos de falla activos (motor, transmisión, ABS, postratamiento) leídos con lector y registrados"
            ay = "; ".join(x for x in [("Especificación: " + esp) if esp and esp != "—" else "", ("Por qué: " + porq) if porq else ""] if x) or None
            rep = esp if (tipo in ("Reemplazo", "Lubricación", "Servicio") and esp and esp != "—") else None
            bloque = ("%s · %s" % (nv, sis)) if nivel_max != "SL" else sis
            rows.append((bloque, tarea, "ok_nok", None, critico(v), rep, ay))
    rows.append(("Cierre", "Horómetro de la próxima mantención en el sticker", "numero", "h", False, "Sticker de mantención",
                 "El horómetro de hoy más %d h." % h))
    return rows


PAUTAS_FRK = [("SL", "FRK-PM-300", "Servicio SL 300 h · Mack GU 813 (severo)"),
              ("SM1", "FRK-SM1-600", "Servicio SM1 600 h · Mack GU 813 (severo)"),
              ("SM2", "FRK-SM2-1200", "Servicio SM2 1.200 h · Mack GU 813 (severo)"),
              ("SM3", "FRK-SM3-2400", "Servicio SM3 2.400 h · Mack GU 813 (severo)"),
              ("SM4", "FRK-SM4-4800", "Servicio SM4 4.800 h · Mack GU 813 (severo)")]
HD = {n: (h, d) for n, h, d in NIVELES}
w("""DO $$
DECLARE v_faena UUID := (SELECT id FROM public.faenas WHERE codigo = 'FAE-FRANCKE');
        v_modelo UUID := (SELECT modelo_id FROM public.faena_pauta WHERE codigo = 'FRK-PM-300');
        v_pid UUID; v_ej INT;
BEGIN
  SELECT count(*) INTO v_ej FROM public.faena_pauta_ejecucion e JOIN public.faena_pauta p ON p.id = e.pauta_id WHERE p.codigo = 'FRK-PM-300';
  IF v_ej > 0 THEN RAISE EXCEPTION 'FRK-PM-300 ya tiene % ejecuciones: no se reemplazan sus ítems', v_ej; END IF;""")
for nivel, cod, nombre in PAUTAS_FRK:
    h, d = HD[nivel]
    if cod == "FRK-PM-300":
        w(f"  UPDATE public.faena_pauta SET nombre = {q(nombre)}, disparo_horas = {h}, disparo_dias = {d}, activo = TRUE,")
        w("         observacion = 'MIG720: escalera severa (SL de la escalera; absorción por SM1…SM4)', updated_at = NOW()")
        w(f"   WHERE codigo = '{cod}' RETURNING id INTO v_pid;")
        w("  DELETE FROM public.faena_pauta_item WHERE pauta_id = v_pid;")
    else:
        w(f"  SELECT id INTO v_pid FROM public.faena_pauta WHERE faena_id = v_faena AND codigo = '{cod}';")
        w("  IF v_pid IS NULL THEN")
        w("    INSERT INTO public.faena_pauta (faena_id, codigo, nombre, tipo, modelo_id, disparo_horas, disparo_dias, aviso_horas, activo, observacion)")
        w(f"    VALUES (v_faena, '{cod}', {q(nombre)}, 'programada', v_modelo, {h}, {d}, 50, TRUE, 'MIG720: incluye completos los niveles menores')")
        w("    RETURNING id INTO v_pid;")
        w("  ELSE DELETE FROM public.faena_pauta_item WHERE pauta_id = v_pid; END IF;")
    vals = []
    for i, (b, t_, tr, un, cr, rep, ay) in enumerate(fila_items(nivel, h), 1):
        vals.append("(v_pid, %d, %s, %s, '%s', %s, TRUE, %s, %s, %s, %s)" % (
            i * 10, q(b), q(t_), tr, q(un) if un else "NULL", "FALSE" if tr == "numero" else "TRUE",
            "TRUE" if cr else "FALSE", q(rep) if rep else "NULL", q(ay) if ay else "NULL"))
    w("  INSERT INTO public.faena_pauta_item (pauta_id, orden, bloque, texto, tipo_respuesta, unidad, obligatorio, foto_si_nok, critico, repuesto, ayuda) VALUES")
    w("    " + ",\n    ".join(vals) + ";")
w("END $$;\n")

# ---- 6. Diaria
w("-- 6. Diaria FRK-DIA-CP v2 (en su lugar + 15 nuevos) -------------------------------")
UPD = {210: ("Neumáticos: presión, cortes, tuercas (marcas) y piedras entre duales", True),
       230: ("Purga de estanques de aire; presión de corte normal; sin alarma", True),
       410: ("Manguera y pistola: sin cortes ni goteo; cierre automático; carrete retrae", True),
       620: ("Documentación a bordo vigente (hermeticidad, SEC, revisión técnica, SOAP)", True)}
NUEVOS = [  # orden, bloque, texto, critico
    (50, "Tablero", "Luces testigo y códigos de falla activos (motor, transmisión, ABS)", True),
    (60, "Tablero", "Temperatura de transmisión visible y en rango", False),
    (122, "Motor y fluidos", "Nivel de fluido de transmisión (indicador)", False),
    (124, "Motor y fluidos", "Nivel de DEF", False),
    (152, "Motor y fluidos", "Drenar separador de agua del combustible del motor", False),
    (154, "Motor y fluidos", "Indicador de restricción del filtro de aire", False),
    (225, "Rodado y frenos", "Prueba de freno de servicio, estacionamiento y freno motor", True),
    (245, "Rodado y frenos", "Dirección: juego libre normal, sin ruidos ni dureza", True),
    (350, "Luces y señalización", "Alarma de retroceso, bocina, espejos, limpiaparabrisas", False),
    (360, "Luces y señalización", "Tacógrafo operativo y radio con cobertura", False),
    (442, "Sistema de despacho", "Válvula de emergencia: accionamiento y cierre; mando remoto accesible", True),
    (444, "Sistema de despacho", "Puesta a tierra: cable y pinza íntegros, carrete funciona", True),
    (446, "Sistema de despacho", "Filtro de despacho: ΔP en rango, sumidero drenado", False),
    (505, "Emergencia", "Paradas de emergencia (cabina y despacho) operativas", True),
    (506, "Emergencia", "Arrestallamas de escape instalado; escape sin fugas", True),
]
assert len(NUEVOS) == sum(1 for x in D if x[3] == "nuevo")
w("DO $$\nDECLARE v_pid UUID := (SELECT id FROM public.faena_pauta WHERE codigo = 'FRK-DIA-CP'); v_n INT;\nBEGIN")
for o, (t_, cr) in UPD.items():
    w(f"  UPDATE public.faena_pauta_item SET texto = {q(t_)}, critico = {'TRUE' if cr else 'FALSE'} WHERE pauta_id = v_pid AND orden = {o};")
    w("  GET DIAGNOSTICS v_n = ROW_COUNT;")
    w(f"  IF v_n <> 1 THEN RAISE EXCEPTION 'FRK-DIA-CP: no está el ítem de orden {o}'; END IF;")
vals = ["(v_pid, %d, %s, %s, 'ok_nok', NULL, TRUE, TRUE, %s)" % (o, q(b), q(t_), "TRUE" if cr else "FALSE") for o, b, t_, cr in NUEVOS]
w("  INSERT INTO public.faena_pauta_item (pauta_id, orden, bloque, texto, tipo_respuesta, unidad, obligatorio, foto_si_nok, critico)")
w("  SELECT * FROM (VALUES\n    " + ",\n    ".join(vals) + "\n  ) n(pauta_id, orden, bloque, texto, tipo_respuesta, unidad, obligatorio, foto_si_nok, critico)")
w("  WHERE NOT EXISTS (SELECT 1 FROM public.faena_pauta_item i WHERE i.pauta_id = v_pid AND i.orden = n.orden);")
w("  UPDATE public.faena_pauta SET nombre = 'Revisión diaria · camión abastecedor Mack GU 813 (v2 severo)', updated_at = NOW() WHERE id = v_pid;")
w("END $$;\n")

# ---- Resultado
w("""-- Resultado
SELECT p.codigo, p.nombre, p.disparo_horas, p.disparo_dias, (SELECT count(*) FROM public.faena_pauta_item i WHERE i.pauta_id = p.id) AS items
  FROM public.faena_pauta p JOIN public.faenas f ON f.id = p.faena_id
 WHERE f.codigo = 'FAE-FRANCKE' ORDER BY p.tipo, p.disparo_horas NULLS FIRST, p.codigo;""")
open(OUT_SQL, "w", encoding="utf-8").write("\n".join(L) + "\n")
print("ok", OUT_SQL, sum(len(x) for x in L), "chars")
