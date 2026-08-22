-- ============================================================================
-- MIG317 · Cierre físico del turno en terreno + CECO anotado por quien despacha
-- ----------------------------------------------------------------------------
-- DE DÓNDE SALE ESTE MODELO
--   No lo inventé. Sale de tres fuentes que ya funcionan:
--     · El "Registro de Cierre Diario" del libro Cierre Romeral (hoja por día):
--       bloque de mediciones físicas por estanque + bloque de numerales
--       mecánicos por cuentalitros, y abajo las tres diferencias.
--     · La aplicación que ya se construyó para el mundo Orpak, cuyo estado
--       guarda exactamente mi/rfp/rt/mf/cli/clf y calcula vFis, vMec, var1 y
--       var2. Esa aritmética está probada con 9 días de junio; se conserva tal
--       cual, con los mismos nombres, para que los números se puedan comparar
--       uno a uno entre los dos sistemas.
--     · El FORM AC 066, que necesita capacidad nominal y máxima de llenado por
--       punto para calcular el KPI de llenado.
--
-- LOS CECO QUE NO ESTÁN EN LA BASE
--   Hoy el 65 % de las transacciones del tag maestro llega sin CECO y alguien
--   lo completa después, de memoria, en oficina. La regla acá es la contraria:
--   quien despacha puede ANOTAR un CECO que no está en el catálogo, en el
--   momento, y queda registrado como propuesto. No se pierde, no se inventa
--   después y no bloquea el despacho. Prevención de errores por diseño: el
--   dato lo pone quien sabe, cuando sabe.
--
--   Un CECO propuesto NO entra al catálogo oficial hasta que alguien con
--   permiso lo confirma. Mientras tanto el despacho queda imputado a un texto
--   trazable en vez de a nada.
-- ============================================================================

BEGIN;

-- ── 1. Los puntos de medición reales de Romeral ────────────────────────────
-- El catálogo tenía sólo los dos camiones, con capacidad 25.000 (son 15.000).
-- Faltaban las cuatro estaciones fijas y el tercer camión.
ALTER TABLE public.combustible_estanques
    ADD COLUMN IF NOT EXISTS capacidad_llenado_lt NUMERIC,
    ADD COLUMN IF NOT EXISTS orden_cierre         INTEGER,
    ADD COLUMN IF NOT EXISTS clave_cierre         TEXT;

COMMENT ON COLUMN public.combustible_estanques.capacidad_llenado_lt IS
  'Capacidad maxima de llenado (menor que la nominal). Es la que usa el KPI del FORM AC 066. MIG317.';
COMMENT ON COLUMN public.combustible_estanques.clave_cierre IS
  'Clave corta del punto en el cierre diario (mina1, mina2, bimodal, casaf, djkl18...). Permite comparar 1 a 1 con la app Orpak. MIG317.';

INSERT INTO public.combustible_estanques
    (codigo, nombre, tipo, faena_id, capacidad_lt, capacidad_llenado_lt,
     patente, clave_cierre, orden_cierre, activo)
SELECT v.codigo, v.nombre, v.tipo::text,
       (SELECT id FROM faenas WHERE codigo = 'FAE-CMP-ROMERAL'),
       v.cap, v.cap_llenado, v.patente, v.clave, v.orden, true
FROM (VALUES
    ('ROM-MINA-1',  'Estación Isla Mina — Tanque 1', 'fijo',  75000, 67500, NULL,      'mina1',  10),
    ('ROM-MINA-2',  'Estación Isla Mina — Tanque 2', 'fijo',  30000, 29000, NULL,      'mina2',  20),
    ('ROM-BIMODAL', 'Estación Bimodal',              'fijo',  51000, 50000, NULL,      'bimodal',30),
    ('ROM-CASAF',   'Casa Fuerza',                   'fijo',  30000, 29000, NULL,      'casaf',  40),
    ('ROM-LCSX-78', 'Camión cisterna LCSX-78',       'movil', 15000, 14500, 'LCSX-78', 'lcsx78', 70)
) AS v(codigo, nombre, tipo, cap, cap_llenado, patente, clave, orden)
WHERE NOT EXISTS (
    SELECT 1 FROM combustible_estanques e WHERE e.codigo = v.codigo
);

-- Corregir los dos camiones que ya estaban: son de 15.000, no de 25.000.
UPDATE public.combustible_estanques
   SET capacidad_lt = 15000, capacidad_llenado_lt = 14500,
       clave_cierre = CASE codigo WHEN 'ROM-DJKL-18' THEN 'djkl18' ELSE 'fslz67' END,
       orden_cierre = CASE codigo WHEN 'ROM-DJKL-18' THEN 50 ELSE 60 END,
       updated_at = NOW()
 WHERE codigo IN ('ROM-DJKL-18', 'ROM-FSLZ-67');

-- ── 2. Los cuentalitros ────────────────────────────────────────────────────
-- Un punto puede tener varios (Bimodal tiene cinco). El numeral es acumulado y
-- sólo sube: esa es la validación que hoy no existe y que dejó pasar un
-- -2.845.287 en agosto.
CREATE TABLE IF NOT EXISTS public.combustible_faena_medidores (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    estanque_id    UUID NOT NULL REFERENCES public.combustible_estanques(id) ON DELETE CASCADE,
    surtidor       TEXT NOT NULL,              -- 'S1', 'S2', 'S Trenes'
    numero         TEXT NOT NULL,              -- 'N° 1', 'N° 2', 'N° 3'
    etiqueta       TEXT,                       -- lo que dice el letrero en terreno
    orden          INTEGER NOT NULL DEFAULT 1,
    ultimo_numeral NUMERIC,                    -- para proponer el inicial del día siguiente
    activo         BOOLEAN NOT NULL DEFAULT true,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (estanque_id, surtidor, numero)
);

COMMENT ON TABLE public.combustible_faena_medidores IS
  'Cuentalitros por punto de medicion. El numeral es acumulado y monotono creciente. MIG317.';

-- Los 11 numerales que aparecen en la hoja del dia 01-08-2026, con su lectura
-- de ese dia como punto de partida.
INSERT INTO public.combustible_faena_medidores
    (estanque_id, surtidor, numero, etiqueta, orden, ultimo_numeral)
SELECT e.id, v.surtidor, v.numero, v.etiqueta, v.orden, v.numeral
FROM (VALUES
    ('ROM-BIMODAL', 'S1',        'N° 1', 'Bimodal S1 · contador 1',  1,  4578797),
    ('ROM-BIMODAL', 'S1',        'N° 2', 'Bimodal S1 · contador 2',  2,  3752835),
    ('ROM-BIMODAL', 'S2',        'N° 1', 'Bimodal S2 · contador 1',  3,    54834),
    ('ROM-BIMODAL', 'S2',        'N° 2', 'Bimodal S2 · contador 2',  4,    48282),
    ('ROM-BIMODAL', 'S Trenes',  'N° 1', 'Bimodal trenes',           5,  1099598),
    ('ROM-MINA-1',  'S1',        'N° 1', 'Mina S1 · contador 1',     1, 24400737),
    ('ROM-MINA-1',  'S1',        'N° 2', 'Mina S1 · contador 2',     2, 20100472),
    ('ROM-CASAF',   'S1',        'N° 1', 'Casa Fuerza',              1,   366632),
    ('ROM-DJKL-18', 'S1',        'N° 3', 'Camión 18',                1,  2794371),
    ('ROM-FSLZ-67', 'S1',        'N° 3', 'Camión 67',                1,  4294390),
    ('ROM-LCSX-78', 'S2',        'N° 1', 'Camión 78',                1,        0)
) AS v(codigo, surtidor, numero, etiqueta, orden, numeral)
JOIN combustible_estanques e ON e.codigo = v.codigo
WHERE NOT EXISTS (
    SELECT 1 FROM combustible_faena_medidores m
     WHERE m.estanque_id = e.id AND m.surtidor = v.surtidor AND m.numero = v.numero
);

-- ── 3. El cierre físico del turno ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.combustible_faena_cierre (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_id      UUID NOT NULL REFERENCES public.faenas(id),
    fecha         DATE NOT NULL,
    turno         TEXT,
    estado        TEXT NOT NULL DEFAULT 'borrador',   -- borrador | firmado
    -- Quien midió. En terreno la firma es el nombre, no una cuenta.
    medido_por    TEXT,
    firmado_at    TIMESTAMPTZ,
    observacion   TEXT,
    client_uuid   TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by    UUID,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (faena_id, fecha, turno)
);

CREATE TABLE IF NOT EXISTS public.combustible_faena_cierre_punto (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cierre_id     UUID NOT NULL REFERENCES public.combustible_faena_cierre(id) ON DELETE CASCADE,
    estanque_id   UUID NOT NULL REFERENCES public.combustible_estanques(id),
    -- Mismos nombres que la app Orpak, a propósito: así los números se
    -- comparan uno a uno entre los dos sistemas sin traducir nada.
    mi            NUMERIC,        -- medición inicial (varilla)
    rfp           NUMERIC,        -- recepción de flota primaria
    rt            NUMERIC,        -- recepción por trasvasije
    mf            NUMERIC,        -- medición final (varilla)
    agua_mm       NUMERIC,        -- H2O: la columna que el libro ya tiene
    temperatura_c NUMERIC,        -- para explicar la variación por dilatación
    sin_medicion  BOOLEAN NOT NULL DEFAULT false,
    motivo_sin_medicion TEXT,
    foto_url      TEXT,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (cierre_id, estanque_id)
);

CREATE TABLE IF NOT EXISTS public.combustible_faena_cierre_medidor (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cierre_id     UUID NOT NULL REFERENCES public.combustible_faena_cierre(id) ON DELETE CASCADE,
    medidor_id    UUID NOT NULL REFERENCES public.combustible_faena_medidores(id),
    numeral_ini   NUMERIC,
    numeral_fin   NUMERIC,
    calibracion   NUMERIC NOT NULL DEFAULT 0,   -- litros de calibración a descontar
    foto_url      TEXT,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (cierre_id, medidor_id),
    -- La validación que faltaba. Un numeral no retrocede.
    CONSTRAINT chk_numeral_no_retrocede
        CHECK (numeral_fin IS NULL OR numeral_ini IS NULL OR numeral_fin >= numeral_ini)
);

COMMENT ON CONSTRAINT chk_numeral_no_retrocede ON public.combustible_faena_cierre_medidor IS
  'El 10-08-2026 el numeral final del camion 18 quedo vacio y la resta dio -2.845.287 L. Esto lo impide en la base, no solo en la pantalla. MIG317.';

CREATE INDEX IF NOT EXISTS idx_comb_cierre_faena_fecha
    ON public.combustible_faena_cierre (faena_id, fecha DESC);

-- ── 4. CECO y equipo anotados en terreno ───────────────────────────────────
ALTER TABLE public.combustible_faena_cecos
    ADD COLUMN IF NOT EXISTS origen      TEXT NOT NULL DEFAULT 'maestro',  -- maestro | terreno
    ADD COLUMN IF NOT EXISTS confirmado  BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS anotado_por TEXT,
    ADD COLUMN IF NOT EXISTS anotado_at  TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS observacion TEXT;

COMMENT ON COLUMN public.combustible_faena_cecos.origen IS
  'maestro = venia del catalogo. terreno = lo anoto quien despacha porque no estaba. MIG317.';

ALTER TABLE public.combustible_faena_equipos
    ADD COLUMN IF NOT EXISTS origen      TEXT NOT NULL DEFAULT 'maestro',
    ADD COLUMN IF NOT EXISTS confirmado  BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS anotado_por TEXT,
    ADD COLUMN IF NOT EXISTS anotado_at  TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS alias       TEXT[] NOT NULL DEFAULT '{}';

COMMENT ON COLUMN public.combustible_faena_equipos.alias IS
  'Como aparece este equipo escrito en Orpak. Resuelve LUMI IP 208 vs LUM IP193 sin tocar el maestro. MIG317.';

-- Los que ya estaban quedan marcados como confirmados del maestro.
UPDATE public.combustible_faena_cecos   SET origen = 'maestro', confirmado = true WHERE origen IS NULL;
UPDATE public.combustible_faena_equipos SET origen = 'maestro', confirmado = true WHERE origen IS NULL;

-- ── 5. El despacho acepta lo que el catálogo todavía no tiene ──────────────
ALTER TABLE public.combustible_faena_despachos
    ADD COLUMN IF NOT EXISTS tipo_movimiento     TEXT NOT NULL DEFAULT 'venta',
    ADD COLUMN IF NOT EXISTS destino_estanque_id UUID REFERENCES public.combustible_estanques(id),
    ADD COLUMN IF NOT EXISTS ceco_texto          TEXT,
    ADD COLUMN IF NOT EXISTS flota               TEXT;

COMMENT ON COLUMN public.combustible_faena_despachos.tipo_movimiento IS
  'venta | trasvasije | recirculacion | calibracion. Es la clasificacion de la seccion 10 del instructivo, hecha en el origen y no en oficina. MIG317.';
COMMENT ON COLUMN public.combustible_faena_despachos.ceco_texto IS
  'CECO anotado en terreno cuando no esta en el catalogo. No bloquea el despacho y no se pierde. MIG317.';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_comb_tipo_movimiento') THEN
        ALTER TABLE public.combustible_faena_despachos
            ADD CONSTRAINT chk_comb_tipo_movimiento
            CHECK (tipo_movimiento IN ('venta','trasvasije','recirculacion','calibracion'));
    END IF;
END $$;

-- ── 6. Anotar un CECO desde terreno ────────────────────────────────────────
-- Devuelve el id, exista o no. Si ya existe con ese código no lo duplica: lo
-- devuelve. Así el operador no tiene que saber si "ya está" — sólo lo anota.
CREATE OR REPLACE FUNCTION public.rpc_comb_faena_anotar_ceco(
    p_faena_id   uuid,
    p_codigo     text,
    p_empresa    text DEFAULT NULL,
    p_anotado_por text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_codigo TEXT := upper(trim(COALESCE(p_codigo, '')));
    v_id     UUID;
    v_nuevo  BOOLEAN := false;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'No autenticado.' USING ERRCODE = '42501';
    END IF;
    IF length(v_codigo) < 2 THEN
        RAISE EXCEPTION 'Escriba el número de CECO.' USING ERRCODE = '22023';
    END IF;

    SELECT id INTO v_id FROM combustible_faena_cecos
     WHERE faena_id = p_faena_id AND upper(trim(codigo)) = v_codigo
     LIMIT 1;

    IF v_id IS NULL THEN
        INSERT INTO combustible_faena_cecos
            (faena_id, codigo, empresa, activo, origen, confirmado, anotado_por, anotado_at)
        VALUES (p_faena_id, v_codigo, NULLIF(trim(COALESCE(p_empresa,'')), ''),
                true, 'terreno', false, p_anotado_por, NOW())
        RETURNING id INTO v_id;
        v_nuevo := true;
    END IF;

    RETURN jsonb_build_object('ceco_id', v_id, 'codigo', v_codigo, 'nuevo', v_nuevo);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_comb_faena_anotar_ceco(uuid, text, text, text) TO authenticated;

-- ── 7. Guardar el cierre físico ────────────────────────────────────────────
-- Recibe el día completo de una vez: la app de terreno trabaja sin señal y
-- sincroniza el turno entero cuando aparece red. Se guarda como borrador
-- cuantas veces haga falta; firmar es una acción aparte y deliberada.
CREATE OR REPLACE FUNCTION public.rpc_comb_faena_guardar_cierre(
    p_faena_id  uuid,
    p_fecha     date,
    p_turno     text,
    p_medido_por text,
    p_puntos    jsonb,          -- [{estanque_id, mi, rfp, rt, mf, agua_mm, temperatura_c, sin_medicion, motivo_sin_medicion, foto_url}]
    p_medidores jsonb,          -- [{medidor_id, numeral_ini, numeral_fin, calibracion, foto_url}]
    p_observacion text DEFAULT NULL,
    p_firmar    boolean DEFAULT false,
    p_client_uuid text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_id   UUID;
    v_r    JSONB;
    v_ini  NUMERIC;
    v_fin  NUMERIC;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'No autenticado.' USING ERRCODE = '42501';
    END IF;

    INSERT INTO combustible_faena_cierre
        (faena_id, fecha, turno, medido_por, observacion, client_uuid, created_by)
    VALUES (p_faena_id, p_fecha, NULLIF(trim(COALESCE(p_turno,'')),''),
            p_medido_por, p_observacion, p_client_uuid, auth.uid())
    ON CONFLICT (faena_id, fecha, turno) DO UPDATE
        SET medido_por = EXCLUDED.medido_por,
            observacion = EXCLUDED.observacion,
            updated_at = NOW()
    RETURNING id INTO v_id;

    -- Un cierre firmado no se reescribe por accidente desde el teléfono.
    IF (SELECT estado FROM combustible_faena_cierre WHERE id = v_id) = 'firmado'
       AND NOT p_firmar THEN
        RAISE EXCEPTION 'Este cierre ya está firmado. Pida reapertura para corregirlo.'
            USING ERRCODE = '42501';
    END IF;

    FOR v_r IN SELECT * FROM jsonb_array_elements(COALESCE(p_puntos, '[]'::jsonb))
    LOOP
        INSERT INTO combustible_faena_cierre_punto
            (cierre_id, estanque_id, mi, rfp, rt, mf, agua_mm, temperatura_c,
             sin_medicion, motivo_sin_medicion, foto_url)
        VALUES (v_id, (v_r->>'estanque_id')::uuid,
                (v_r->>'mi')::numeric, (v_r->>'rfp')::numeric, (v_r->>'rt')::numeric,
                (v_r->>'mf')::numeric, (v_r->>'agua_mm')::numeric, (v_r->>'temperatura_c')::numeric,
                COALESCE((v_r->>'sin_medicion')::boolean, false),
                NULLIF(v_r->>'motivo_sin_medicion',''), NULLIF(v_r->>'foto_url',''))
        ON CONFLICT (cierre_id, estanque_id) DO UPDATE
            SET mi = EXCLUDED.mi, rfp = EXCLUDED.rfp, rt = EXCLUDED.rt, mf = EXCLUDED.mf,
                agua_mm = EXCLUDED.agua_mm, temperatura_c = EXCLUDED.temperatura_c,
                sin_medicion = EXCLUDED.sin_medicion,
                motivo_sin_medicion = EXCLUDED.motivo_sin_medicion,
                foto_url = COALESCE(EXCLUDED.foto_url, combustible_faena_cierre_punto.foto_url),
                updated_at = NOW();
    END LOOP;

    FOR v_r IN SELECT * FROM jsonb_array_elements(COALESCE(p_medidores, '[]'::jsonb))
    LOOP
        v_ini := (v_r->>'numeral_ini')::numeric;
        v_fin := (v_r->>'numeral_fin')::numeric;

        -- El mensaje tiene que servirle a quien está parado frente al contador.
        IF v_ini IS NOT NULL AND v_fin IS NOT NULL AND v_fin < v_ini THEN
            RAISE EXCEPTION 'El contador no puede bajar: anotó % y antes marcaba %. Revise el número.',
                v_fin, v_ini USING ERRCODE = '22023';
        END IF;

        INSERT INTO combustible_faena_cierre_medidor
            (cierre_id, medidor_id, numeral_ini, numeral_fin, calibracion, foto_url)
        VALUES (v_id, (v_r->>'medidor_id')::uuid, v_ini, v_fin,
                COALESCE((v_r->>'calibracion')::numeric, 0), NULLIF(v_r->>'foto_url',''))
        ON CONFLICT (cierre_id, medidor_id) DO UPDATE
            SET numeral_ini = EXCLUDED.numeral_ini, numeral_fin = EXCLUDED.numeral_fin,
                calibracion = EXCLUDED.calibracion,
                foto_url = COALESCE(EXCLUDED.foto_url, combustible_faena_cierre_medidor.foto_url),
                updated_at = NOW();

        -- El numeral final de hoy es el inicial que se le propone a mañana.
        IF v_fin IS NOT NULL THEN
            UPDATE combustible_faena_medidores
               SET ultimo_numeral = v_fin
             WHERE id = (v_r->>'medidor_id')::uuid
               AND (ultimo_numeral IS NULL OR v_fin >= ultimo_numeral);
        END IF;
    END LOOP;

    IF p_firmar THEN
        UPDATE combustible_faena_cierre
           SET estado = 'firmado', firmado_at = NOW(), updated_at = NOW()
         WHERE id = v_id;
    END IF;

    RETURN jsonb_build_object('cierre_id', v_id, 'firmado', p_firmar);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_comb_faena_guardar_cierre(uuid, date, text, text, jsonb, jsonb, text, boolean, text) TO authenticated;

-- ── 8. La aritmética del cierre, calculada donde no se puede editar ────────
-- vFis, vMec, var1 — los mismos nombres de la app Orpak. La imputación (var2,
-- contra Orpak) se calcula aparte porque llega días después.
CREATE OR REPLACE VIEW public.v_comb_faena_cierre_punto AS
SELECT
    c.id                AS cierre_id,
    c.faena_id,
    c.fecha,
    c.turno,
    c.estado,
    c.medido_por,
    e.id                AS estanque_id,
    e.codigo            AS estanque_codigo,
    e.nombre            AS estanque_nombre,
    e.clave_cierre,
    e.orden_cierre,
    e.tipo              AS estanque_tipo,
    e.capacidad_lt,
    e.capacidad_llenado_lt,
    p.mi, p.rfp, p.rt, p.mf, p.agua_mm, p.temperatura_c,
    p.sin_medicion, p.motivo_sin_medicion,
    -- Salida por varilla: lo que entró menos lo que quedó.
    (COALESCE(p.mi,0) + COALESCE(p.rfp,0) + COALESCE(p.rt,0) - COALESCE(p.mf,0)) AS v_fis,
    -- Salida por cuentalitros: la suma de todos los contadores del punto.
    COALESCE(m.v_mec, 0) AS v_mec,
    COALESCE(m.v_mec, 0)
      - (COALESCE(p.mi,0) + COALESCE(p.rfp,0) + COALESCE(p.rt,0) - COALESCE(p.mf,0)) AS var1,
    m.medidores_total,
    m.medidores_leidos,
    -- % de llenado para el FORM AC 066, sobre la capacidad de llenado real.
    CASE WHEN e.capacidad_llenado_lt > 0 AND p.mf IS NOT NULL
         THEN ROUND(p.mf / e.capacidad_llenado_lt, 4) END AS pct_llenado
FROM combustible_faena_cierre c
JOIN combustible_faena_cierre_punto p ON p.cierre_id = c.id
JOIN combustible_estanques e          ON e.id = p.estanque_id
LEFT JOIN LATERAL (
    SELECT SUM(COALESCE(cm.numeral_fin,0) - COALESCE(cm.numeral_ini,0) - COALESCE(cm.calibracion,0)) AS v_mec,
           COUNT(*)::int                                                        AS medidores_total,
           COUNT(*) FILTER (WHERE cm.numeral_fin IS NOT NULL)::int              AS medidores_leidos
      FROM combustible_faena_cierre_medidor cm
      JOIN combustible_faena_medidores md ON md.id = cm.medidor_id
     WHERE cm.cierre_id = c.id AND md.estanque_id = e.id
) m ON TRUE;

GRANT SELECT ON public.v_comb_faena_cierre_punto TO authenticated;

COMMENT ON VIEW public.v_comb_faena_cierre_punto IS
  'Cierre fisico por punto con la aritmetica calculada: v_fis (varilla), v_mec (cuentalitros) y var1 (la diferencia). Mismos nombres que la app Orpak para poder comparar. MIG317.';

COMMIT;
