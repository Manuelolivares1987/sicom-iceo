"""MIG721: registro (foto del tablero, foto de lo realizado, firma) en Franke + foto en las OT Mack de Coquimbo.

Lee las MISMAS tareas que MIG720 (build_pauta.py) para que lo que pide foto
sea idéntico en la app de faena y en la OT del taller.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_SQL, RPC_DEF, TPL_DEF = sys.argv[1], sys.argv[2], sys.argv[3]
sys.argv = [sys.argv[0], os.path.join(HERE, "_tmp_pauta.xlsx")]
sys.path.insert(0, HERE)
import build_pauta as bp  # noqa: E402

T = bp.T
AC = "Aljibe combustible"
TRABAJO = ("Reemplazo", "Lubricación", "Servicio", "Ajuste")
PREV = {"SM1": "SL", "SM2": "SM1", "SM3": "SM2", "SM4": "SM3"}
NOMBRE_PF = {"SL": "Mack GU813E - Servicio SL (300h)", "SM1": "Mack GU813E - Servicio SM1 (600h)",
             "SM2": "Mack GU813E - Servicio SM2 (1200h)", "SM3": "Mack GU813E - Servicio SM3 (2400h)",
             "SM4": "Mack GU813E - Servicio SM4 (4800h)"}


def q(s):
    return "'" + s.replace("'", "''") + "'"


def texto_pf(v):  # idéntico a MIG720
    n, sis, tarea, tipo, aplica, esp, ori, porq = v
    s = tarea + (" — " + esp if esp and esp != "—" else "")
    return ("[Solo aljibe de combustible] " + s) if aplica == AC else s


def es_trabajo(v):
    n, sis, tarea, tipo, *_ = v
    return tipo in TRABAJO or tarea.startswith("Tomar muestra")


def items_pf(nivel):
    own = []
    for v in T:
        if v[0] != nivel:
            continue
        own.append({"descripcion": texto_pf(v), "requiere_foto": True} if es_trabajo(v) else texto_pf(v))
    return ([PREV[nivel] + " completo"] if nivel in PREV else []) + own


# Textos de faena (los mismos que fila_items de MIG720: la tarea sin especificación).
trabajos_faena = sorted({v[2] for v in T if es_trabajo(v)})
trabajos_faena += ["Cambio de aceite de motor y filtro", "Cambio de filtro de aire", "Cambio de filtro de combustible",
                   "Cambio de filtro de aire acondicionado", "Rotación y presión de neumáticos", "Niveles y engrase"]  # Hilux 10K

L = []
w = L.append
w("""-- ============================================================================
-- MIG721 — Registro en faena igual que en el taller (19-11-2026)
-- ----------------------------------------------------------------------------
-- Manuel (19-11): «en el taller de Coquimbo siempre pide un registro; aquí se
-- debe pedir lo mismo para el mantenimiento diario y cuando se ejecuta una
-- pauta» y «que saque fotos de lo realizado».
--
-- En TODAS las pautas de Franke (diarias y servicios, camión y camioneta):
--   · foto del tablero (horómetro/km) en la primera lectura,
--   · firma de quien ejecuta al cerrar (nuevo tipo de respuesta 'firma'; viaja
--     como foto: funciona sin señal con la cola de siempre).
-- En los servicios: foto de lo realizado en cada trabajo ejecutado (cambios,
-- reemplazos, engrases, muestras, ajustes, servicios). Las inspecciones siguen
-- con foto solo si salen NO OK.
-- rpc_faena_pauta_guardar lo exige también en el servidor.
-- Coquimbo: la OT de los Mack pide foto en esos mismos trabajos
-- (items_checklist con requiere_foto, que fn_pauta_a_template ahora respeta).
-- ============================================================================

-- 1. Columna y tipo de respuesta ---------------------------------------------
ALTER TABLE public.faena_pauta_item ADD COLUMN IF NOT EXISTS foto_obligatoria BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.faena_pauta_item DROP CONSTRAINT IF EXISTS faena_pauta_item_tipo_respuesta_check;
ALTER TABLE public.faena_pauta_item ADD CONSTRAINT faena_pauta_item_tipo_respuesta_check
    CHECK (tipo_respuesta = ANY (ARRAY['ok_nok', 'numero', 'texto', 'firma']));
""")

w("""-- 2. Franke: foto del tablero, foto de lo realizado y firma ------------------------
DO $$
DECLARE v_faena UUID := (SELECT id FROM public.faenas WHERE codigo = 'FAE-FRANCKE');
        r RECORD; v_n INT;
BEGIN
  -- Foto del tablero: la primera lectura de cada pauta.
  UPDATE public.faena_pauta_item i
     SET foto_obligatoria = TRUE,
         ayuda = 'Foto del tablero con el horómetro y el kilometraje a la vista: es el respaldo de la lectura.'
   WHERE i.id IN (SELECT DISTINCT ON (x.pauta_id) x.id
                    FROM public.faena_pauta_item x JOIN public.faena_pauta p ON p.id = x.pauta_id
                   WHERE p.faena_id = v_faena AND x.tipo_respuesta = 'numero' AND x.bloque = 'Lecturas'
                   ORDER BY x.pauta_id, x.orden);
  GET DIAGNOSTICS v_n = ROW_COUNT; RAISE NOTICE 'Foto del tablero: % pautas', v_n;
""")
w("  -- Foto de lo realizado: los trabajos ejecutados de los servicios.")
w("  UPDATE public.faena_pauta_item i SET foto_obligatoria = TRUE")
w("    FROM public.faena_pauta p")
w("   WHERE p.id = i.pauta_id AND p.faena_id = v_faena AND p.tipo = 'programada'")
w("     AND i.texto = ANY (ARRAY[\n      " + ",\n      ".join(q(t) for t in trabajos_faena) + "\n     ]);")
w("""  GET DIAGNOSTICS v_n = ROW_COUNT; RAISE NOTICE 'Foto de lo realizado: % ítems', v_n;

  -- Firma de quien ejecuta, al final de cada pauta.
  FOR r IN SELECT p.id, (SELECT max(orden) FROM public.faena_pauta_item WHERE pauta_id = p.id) AS mx
             FROM public.faena_pauta p WHERE p.faena_id = v_faena AND p.activo LOOP
    IF NOT EXISTS (SELECT 1 FROM public.faena_pauta_item WHERE pauta_id = r.id AND tipo_respuesta = 'firma') THEN
      INSERT INTO public.faena_pauta_item (pauta_id, orden, bloque, texto, ayuda, tipo_respuesta, obligatorio,
                                           foto_si_nok, critico, foto_obligatoria)
      VALUES (r.id, COALESCE(r.mx, 0) + 10, 'Cierre', 'Firma de quien ejecuta',
              'Firma con el dedo: confirma que lo marcado se hizo y se revisó.', 'firma', TRUE, FALSE, FALSE, TRUE);
    END IF;
  END LOOP;
END $$;
""")

# ---- 3. RPC
rpc = open(RPC_DEF, encoding="utf-8").read()
rpc = rpc[:rpc.index("#### callers")].rstrip()
old_f = "            OR (i.tipo_respuesta = 'texto'  AND COALESCE(r.texto,'') = ''));"
assert old_f in rpc
rpc = rpc.replace(old_f, "            OR (i.tipo_respuesta = 'texto'  AND COALESCE(r.texto,'') = '')\n"
                         "            OR (i.tipo_respuesta = 'firma'  AND COALESCE(r.foto_url,'') = ''));")
anchor = "    IF v_sin_foto IS NOT NULL AND array_length(v_sin_foto, 1) > 0 THEN\n        RAISE EXCEPTION 'Estos hallazgos necesitan foto: %',"
assert anchor in rpc
end_nok = rpc.index("END IF;", rpc.index(anchor)) + len("END IF;")
gate = """

    -- 2b) [MIG721] El registro: foto del tablero, foto de lo realizado y firma.
    --     Lo mismo que pide el taller de Coquimbo. Sin registro no se cierra.
    v_sin_foto := NULL;
    SELECT array_agg(i.texto ORDER BY i.orden) INTO v_sin_foto
      FROM public.faena_pauta_item i
      JOIN public.faena_pauta_ejecucion_item r ON r.item_id = i.id AND r.ejecucion_id = v_id
     WHERE i.pauta_id = p_pauta_id AND i.foto_obligatoria
       AND (r.resultado IS NOT NULL OR r.valor IS NOT NULL OR i.tipo_respuesta = 'firma')
       AND COALESCE(r.foto_url, '') = '';

    IF v_sin_foto IS NOT NULL AND array_length(v_sin_foto, 1) > 0 THEN
        RAISE EXCEPTION 'Falta el registro (foto o firma) de: %',
            array_to_string(v_sin_foto[1:5], ' · ')
            USING ERRCODE = 'check_violation';
    END IF;"""
rpc = rpc[:end_nok] + gate + rpc[end_nok:]
w("-- 3. El servidor exige el registro ------------------------------------------------")
w(rpc.rstrip().rstrip(";") + ";\n")

# ---- 4. Coquimbo
tpl = open(TPL_DEF, encoding="utf-8").read()
a = tpl.index("#### fn_pauta_a_template") + len("#### fn_pauta_a_template")
b = tpl.index("#### generar_ots_preventivas")
tpl = tpl[a:b].strip()
old_sel = "    SELECT p.id, p.nombre, p.descripcion, p.items_checklist, p.duracion_estimada_hrs,\n           p.tipo_plan, m.nombre AS modelo"
assert old_sel in tpl
tpl = tpl.replace(old_sel, "    SELECT p.id, p.nombre, p.descripcion, p.items_checklist, p.duracion_estimada_hrs,\n           p.tipo_plan, m.nombre AS modelo, p.modelo_id")
old_ins = "            v_tipos, TRUE, FALSE, 'ok_no_ok',"
assert old_ins in tpl
tpl = tpl.replace(old_ins, """            v_tipos, TRUE,
            -- [MIG721] El paso pide foto si así viene en la pauta (objeto con
            -- requiere_foto), también cuando llega heredado de un nivel menor.
            EXISTS (SELECT 1 FROM pautas_fabricante pf2, jsonb_array_elements(pf2.items_checklist) e
                     WHERE pf2.modelo_id IS NOT DISTINCT FROM v_p.modelo_id
                       AND jsonb_typeof(pf2.items_checklist) = 'array'
                       AND jsonb_typeof(e) = 'object'
                       AND COALESCE((e ->> 'requiere_foto')::BOOLEAN, FALSE)
                       AND btrim(e ->> 'descripcion') = it.descripcion),
            'ok_no_ok',""")
w("-- 4. Coquimbo: la OT de los Mack pide foto en los mismos trabajos -----------------")
w(tpl.rstrip().rstrip(";") + ";\n")
w("DO $$\nDECLARE m RECORD; v_n INT;\nBEGIN")
w("  FOR m IN SELECT id FROM public.modelos WHERE nombre IN ('GU 813 autom','GU813E Mec','GU813E Allison') LOOP")
for nivel in ["SL", "SM1", "SM2", "SM3", "SM4"]:
    js = q(json.dumps(items_pf(nivel), ensure_ascii=False)) + "::jsonb"
    w(f"    UPDATE public.pautas_fabricante SET items_checklist = {js}, updated_at = NOW()")
    w(f"     WHERE modelo_id = m.id AND nombre = {q(NOMBRE_PF[nivel])};")
    w("    GET DIAGNOSTICS v_n = ROW_COUNT;")
    w(f"    IF v_n <> 1 THEN RAISE EXCEPTION 'Falta la pauta {nivel} de un modelo Mack'; END IF;")
w("  END LOOP;")
w("""  PERFORM public.fn_pauta_a_template(pf.id)
     FROM public.pautas_fabricante pf JOIN public.modelos mo ON mo.id = pf.modelo_id
    WHERE mo.nombre IN ('GU 813 autom','GU813E Mec','GU813E Allison') AND pf.activo
      AND pf.nombre LIKE 'Mack GU813E - Servicio %';
END $$;

-- Resultado
SELECT p.codigo, count(*) AS items,
       count(*) FILTER (WHERE i.foto_obligatoria AND i.tipo_respuesta <> 'firma') AS con_foto,
       count(*) FILTER (WHERE i.tipo_respuesta = 'firma') AS firma
  FROM public.faena_pauta p JOIN public.faena_pauta_item i ON i.pauta_id = p.id
  JOIN public.faenas f ON f.id = p.faena_id
 WHERE f.codigo = 'FAE-FRANCKE' GROUP BY p.codigo ORDER BY p.codigo;""")
open(OUT_SQL, "w", encoding="utf-8").write("\n".join(L) + "\n")
print("ok", len(trabajos_faena), "textos de trabajo")
