-- ============================================================================
-- MIG328 · Orpak entra a SICOM
-- ----------------------------------------------------------------------------
-- Hasta hoy el sistema medía el volumen (cuánto combustible se movió) pero no
-- sabía imputarlo (a quién). Esa mitad vivía en un Excel que un chico procesa
-- a mano con una aplicación aparte. Esto la trae adentro.
--
-- QUÉ TRAE EL ARCHIVO DE ORPAK, Y POR QUÉ IMPORTA
-- El export tiene una hoja por estación (BIMODAL, MINA, CAMIONES, CASA FUERZA)
-- y una fila por transacción. La columna que resuelve la imputación es
-- «Department», que trae el CECO adentro del texto:
--     115207
--     115037 Empresa Santa Elvira
--     79588870-5 ESMAX
--     115039 Enaex Servicios 76041871-4
-- El código va al principio; el resto es el nombre de la empresa. Se extrae el
-- código y se amarra al maestro de CECO de la faena.
--
-- CÓMO SE REPARTE EL TRABAJO CON LA APP DE TERRENO
-- Las estaciones fijas las controla Orpak: ahí el archivo es la fuente de
-- verdad y esta ingesta la trae. Los camiones aljibe NO: hoy alguien teclea a
-- mano la hoja CAMIONES desde papeles del operador — eso es exactamente la
-- doble digitación que detectamos. Esa hoja la reemplaza /m/romeral. Cuando la
-- ingesta ve filas de una estación que ya tiene despachos propios del día, no
-- las duplica: las marca como redundantes y avisa.
--
-- IDEMPOTENCIA
-- El mismo archivo se va a subir dos veces. Cada fila lleva una huella de su
-- clave natural; subir de nuevo no duplica nada y el resumen dice cuántas
-- entraron y cuántas ya estaban.
-- ============================================================================

BEGIN;

-- ── Normalizador: mismo criterio que usa la app (sin tildes, mayúsculas) ────
CREATE OR REPLACE FUNCTION public.fn_orpak_norm(p_txt text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $f$
    SELECT upper(trim(translate(COALESCE(p_txt,''),
        'áéíóúÁÉÍÓÚñÑüÜ', 'aeiouAEIOUnNuU')));
$f$;

-- ── Clasificación de la transacción ────────────────────────────────────────
-- Las reglas son las que ya venían aplicando en el Excel y en la app. Se
-- guardan como datos, no como código, para que se puedan corregir sin migrar.
CREATE TABLE IF NOT EXISTS public.combustible_orpak_clasificacion (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_id   UUID NOT NULL REFERENCES public.faenas(id) ON DELETE CASCADE,
    prioridad  INTEGER NOT NULL,
    etiqueta   TEXT NOT NULL,
    patron     TEXT NOT NULL,
    -- 'contiene' busca el patrón dentro de flota o vehículo (sirve para
    -- TRASVASIJE, que aparece embebido en «TRASVASIJE CAMION FSLZ67»).
    -- 'flota_exacta' exige que la flota sea idéntica.
    modo       TEXT NOT NULL DEFAULT 'contiene'
               CHECK (modo IN ('contiene','flota_exacta')),
    activo     BOOLEAN NOT NULL DEFAULT true,
    UNIQUE (faena_id, prioridad, patron)
);

COMMENT ON TABLE public.combustible_orpak_clasificacion IS
  'Reglas para clasificar cada transaccion de Orpak. El orden importa: gana la de menor prioridad. MIG328.';

CREATE OR REPLACE FUNCTION public.fn_orpak_clasificar(
    p_faena_id uuid, p_flota text, p_vehiculo text
)
RETURNS text
LANGUAGE sql STABLE
AS $f$
    SELECT COALESCE((
        SELECT c.etiqueta
          FROM combustible_orpak_clasificacion c
         WHERE c.faena_id = p_faena_id AND c.activo
           AND CASE c.modo
                 WHEN 'flota_exacta' THEN public.fn_orpak_norm(p_flota) = c.patron
                 ELSE public.fn_orpak_norm(p_vehiculo) LIKE '%' || c.patron || '%'
                   OR public.fn_orpak_norm(p_flota)   LIKE '%' || c.patron || '%'
               END
         ORDER BY c.prioridad
         LIMIT 1
    ), 'CMP');
$f$;

-- ── Mapeo estación del archivo → estanque del sistema ──────────────────────
CREATE TABLE IF NOT EXISTS public.combustible_orpak_estacion_map (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_id      UUID NOT NULL REFERENCES public.faenas(id) ON DELETE CASCADE,
    prioridad     INTEGER NOT NULL,
    patron_estacion TEXT,          -- se busca dentro del «Station Name»
    patron_vehiculo TEXT,          -- alternativa: se busca en el vehículo
    bomba_igual   TEXT,            -- si viene, la regla sólo aplica a esa bomba
    patron_excluye TEXT,           -- si la estación contiene esto, la regla no aplica
    estanque_id   UUID NOT NULL REFERENCES public.combustible_estanques(id),
    bomba_forzada TEXT,            -- corrige la bomba cuando el Excel la omite
    excluye_cisterna BOOLEAN NOT NULL DEFAULT false,
    activo        BOOLEAN NOT NULL DEFAULT true
);

COMMENT ON COLUMN public.combustible_orpak_estacion_map.excluye_cisterna IS
  'La regla no aplica si el vehiculo es un camion aljibe. Un camion que carga una locomotora en terreno descarga de su propio estanque, no del Bimodal. MIG328.';

CREATE INDEX IF NOT EXISTS idx_orpak_map_faena
    ON public.combustible_orpak_estacion_map(faena_id, prioridad);

CREATE OR REPLACE FUNCTION public.fn_orpak_estanque(
    p_faena_id uuid, p_estacion text, p_vehiculo text, p_bomba text
)
RETURNS TABLE (estanque_id uuid, bomba text)
LANGUAGE sql STABLE
AS $f$
    WITH ctx AS (
        SELECT public.fn_orpak_norm(p_estacion) AS est,
               public.fn_orpak_norm(p_vehiculo) AS veh,
               NULLIF(trim(COALESCE(p_bomba,'')),'') AS bmb
    ), es_cisterna AS (
        SELECT EXISTS (
            SELECT 1 FROM combustible_estanques e, ctx
             WHERE e.faena_id = p_faena_id AND e.tipo = 'movil'
               AND e.patente IS NOT NULL
               AND ctx.veh LIKE '%' || replace(public.fn_orpak_norm(e.patente),'-','') || '%'
        ) AS v
    )
    SELECT m.estanque_id, COALESCE(m.bomba_forzada, ctx.bmb)
      FROM combustible_orpak_estacion_map m, ctx, es_cisterna
     WHERE m.faena_id = p_faena_id AND m.activo
       AND (m.patron_estacion IS NULL OR ctx.est LIKE '%' || m.patron_estacion || '%')
       AND (m.patron_vehiculo IS NULL OR ctx.veh LIKE '%' || m.patron_vehiculo || '%')
       AND (m.bomba_igual   IS NULL OR ctx.bmb = m.bomba_igual)
       AND (m.patron_excluye IS NULL OR ctx.est NOT LIKE '%' || m.patron_excluye || '%')
       AND (NOT m.excluye_cisterna OR NOT es_cisterna.v)
     ORDER BY m.prioridad
     LIMIT 1;
$f$;

-- ── El CECO viene dentro del texto de Department ───────────────────────────
CREATE OR REPLACE FUNCTION public.fn_orpak_ceco_codigo(p_departamento text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $f$
    -- El codigo va al principio: «115037 Empresa Santa Elvira» → 115037.
    -- Tambien cubre el caso RUT-DV: «79588870-5 ESMAX» → 79588870-5.
    SELECT NULLIF((regexp_match(trim(COALESCE(p_departamento,'')),
                                '^([0-9]{4,}(?:-[0-9kK])?)'))[1], '');
$f$;

-- ── Las transacciones ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.combustible_orpak_carga (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_id      UUID NOT NULL REFERENCES public.faenas(id) ON DELETE CASCADE,
    archivo       TEXT NOT NULL,
    periodo_desde DATE,
    periodo_hasta DATE,
    filas_leidas  INTEGER NOT NULL DEFAULT 0,
    filas_nuevas  INTEGER NOT NULL DEFAULT 0,
    filas_repetidas INTEGER NOT NULL DEFAULT 0,
    filas_rechazadas INTEGER NOT NULL DEFAULT 0,
    rechazos      JSONB NOT NULL DEFAULT '[]'::jsonb,
    cargado_por   UUID,
    cargado_nombre TEXT,
    cargado_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.combustible_orpak_transaccion (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    carga_id      UUID NOT NULL REFERENCES public.combustible_orpak_carga(id) ON DELETE CASCADE,
    faena_id      UUID NOT NULL REFERENCES public.faenas(id) ON DELETE CASCADE,
    hoja          TEXT,
    serie         TEXT,
    fecha         DATE NOT NULL,
    hora          TEXT,
    flota         TEXT,
    vehiculo      TEXT,
    producto      TEXT,
    litros        NUMERIC NOT NULL,
    estacion_texto TEXT,
    estanque_id   UUID REFERENCES public.combustible_estanques(id),
    bomba         TEXT,
    departamento  TEXT,
    ceco_codigo   TEXT,
    ceco_id       UUID REFERENCES public.combustible_faena_cecos(id),
    tarjeta       TEXT,
    autorizado_por TEXT,
    clasificacion TEXT NOT NULL,
    dia_cierre    DATE,
    hash_fila     TEXT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_orpak_hash UNIQUE (faena_id, hash_fila)
);

CREATE INDEX IF NOT EXISTS idx_orpak_tx_faena_fecha
    ON public.combustible_orpak_transaccion(faena_id, dia_cierre);
CREATE INDEX IF NOT EXISTS idx_orpak_tx_estanque
    ON public.combustible_orpak_transaccion(estanque_id, dia_cierre);
CREATE INDEX IF NOT EXISTS idx_orpak_tx_ceco
    ON public.combustible_orpak_transaccion(ceco_codigo);

ALTER TABLE public.combustible_orpak_carga        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.combustible_orpak_transaccion  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.combustible_orpak_clasificacion ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.combustible_orpak_estacion_map ENABLE ROW LEVEL SECURITY;

DO $pol$
DECLARE t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['combustible_orpak_carga','combustible_orpak_transaccion',
                             'combustible_orpak_clasificacion','combustible_orpak_estacion_map']
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS pol_%s_lectura ON public.%I', t, t);
        EXECUTE format($p$CREATE POLICY pol_%s_lectura ON public.%I
                          FOR SELECT TO authenticated
                          USING (public.fn_tiene_permiso_modulo('inventario','view',
                                 ARRAY['administrador','gerencia','subgerente_operaciones',
                                       'jefe_operaciones','supervisor','planificador',
                                       'operador_combustible','bodeguero']))$p$, t, t);
        EXECUTE format('GRANT SELECT ON public.%I TO authenticated', t);
    END LOOP;
END $pol$;

-- ── La carga ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_comb_orpak_cargar(
    p_faena_id uuid,
    p_archivo  text,
    p_filas    jsonb
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_carga    UUID;
    v_r        JSONB;
    v_est      UUID;
    v_bomba    TEXT;
    v_hash     TEXT;
    v_ceco_cod TEXT;
    v_ceco     UUID;
    v_clase    TEXT;
    v_fecha    DATE;
    v_dia      DATE;
    v_litros   NUMERIC;
    v_nuevas   INT := 0;
    v_rep      INT := 0;
    v_rech     INT := 0;
    v_rechazos JSONB := '[]'::jsonb;
    v_ins      INT;
BEGIN
    IF NOT public.fn_comb_puede_cerrar() THEN
        RAISE EXCEPTION 'No autorizado para cargar el archivo de Orpak.' USING ERRCODE = '42501';
    END IF;

    INSERT INTO combustible_orpak_carga (faena_id, archivo, cargado_por, cargado_nombre)
    VALUES (p_faena_id, p_archivo, auth.uid(),
            (SELECT u.nombre_completo FROM usuarios_perfil u WHERE u.id = auth.uid()))
    RETURNING id INTO v_carga;

    FOR v_r IN SELECT * FROM jsonb_array_elements(COALESCE(p_filas, '[]'::jsonb))
    LOOP
        v_fecha  := NULLIF(v_r->>'fecha','')::date;
        v_litros := NULLIF(v_r->>'litros','')::numeric;

        -- Una fila sin fecha o sin litros no es un dato incompleto: es basura
        -- de la hoja (totales, filas en blanco). Se cuenta y se sigue.
        IF v_fecha IS NULL OR v_litros IS NULL OR v_litros = 0 THEN
            v_rech := v_rech + 1;
            IF jsonb_array_length(v_rechazos) < 50 THEN
                v_rechazos := v_rechazos || jsonb_build_object(
                    'hoja', v_r->>'hoja', 'fila', v_r->>'serie',
                    'motivo', 'sin fecha o sin litros');
            END IF;
            CONTINUE;
        END IF;

        -- «Día de Cierre» manda sobre la fecha: una carga de las 23:50 puede
        -- pertenecer al cierre del día siguiente según la hora de corte.
        v_dia := COALESCE(NULLIF(v_r->>'dia_cierre','')::date, v_fecha);

        SELECT f.estanque_id, f.bomba INTO v_est, v_bomba
          FROM fn_orpak_estanque(p_faena_id, v_r->>'estacion', v_r->>'vehiculo', v_r->>'bomba') f;

        IF v_est IS NULL THEN
            v_rech := v_rech + 1;
            IF jsonb_array_length(v_rechazos) < 50 THEN
                v_rechazos := v_rechazos || jsonb_build_object(
                    'hoja', v_r->>'hoja', 'fila', v_r->>'serie',
                    'motivo', 'estacion no reconocida: ' || COALESCE(v_r->>'estacion','(vacia)'));
            END IF;
            CONTINUE;
        END IF;

        v_clase    := fn_orpak_clasificar(p_faena_id, v_r->>'flota', v_r->>'vehiculo');
        v_ceco_cod := fn_orpak_ceco_codigo(v_r->>'departamento');

        SELECT c.id INTO v_ceco FROM combustible_faena_cecos c
         WHERE c.faena_id = p_faena_id AND c.codigo = v_ceco_cod AND c.activo;

        -- Huella de la clave natural. El mismo archivo subido dos veces no
        -- duplica; dos cargas distintas del mismo segundo tampoco (la bomba y
        -- la tarjeta las separan).
        v_hash := md5(concat_ws('|', v_dia::text, COALESCE(v_r->>'hora',''),
                                fn_orpak_norm(v_r->>'vehiculo'), v_litros::text,
                                v_est::text, COALESCE(v_bomba,''),
                                COALESCE(v_r->>'tarjeta',''), COALESCE(v_r->>'serie','')));

        INSERT INTO combustible_orpak_transaccion
            (carga_id, faena_id, hoja, serie, fecha, hora, flota, vehiculo, producto,
             litros, estacion_texto, estanque_id, bomba, departamento, ceco_codigo,
             ceco_id, tarjeta, autorizado_por, clasificacion, dia_cierre, hash_fila)
        VALUES (v_carga, p_faena_id, v_r->>'hoja', v_r->>'serie', v_fecha, v_r->>'hora',
                v_r->>'flota', v_r->>'vehiculo', v_r->>'producto', v_litros,
                v_r->>'estacion', v_est, v_bomba, v_r->>'departamento', v_ceco_cod,
                v_ceco, v_r->>'tarjeta', v_r->>'autorizado_por', v_clase, v_dia, v_hash)
        ON CONFLICT (faena_id, hash_fila) DO NOTHING;

        GET DIAGNOSTICS v_ins = ROW_COUNT;
        IF v_ins = 1 THEN v_nuevas := v_nuevas + 1; ELSE v_rep := v_rep + 1; END IF;
    END LOOP;

    UPDATE combustible_orpak_carga
       SET filas_leidas = jsonb_array_length(COALESCE(p_filas,'[]'::jsonb)),
           filas_nuevas = v_nuevas, filas_repetidas = v_rep,
           filas_rechazadas = v_rech, rechazos = v_rechazos,
           periodo_desde = (SELECT min(dia_cierre) FROM combustible_orpak_transaccion WHERE carga_id = v_carga),
           periodo_hasta = (SELECT max(dia_cierre) FROM combustible_orpak_transaccion WHERE carga_id = v_carga)
     WHERE id = v_carga;

    RETURN jsonb_build_object(
        'carga_id', v_carga, 'nuevas', v_nuevas, 'repetidas', v_rep,
        'rechazadas', v_rech, 'rechazos', v_rechazos,
        'desde', (SELECT periodo_desde FROM combustible_orpak_carga WHERE id = v_carga),
        'hasta', (SELECT periodo_hasta FROM combustible_orpak_carga WHERE id = v_carga));
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_comb_orpak_cargar(uuid, text, jsonb) TO authenticated;

-- ── Lo que Orpak dice de cada día, por estanque ────────────────────────────
CREATE OR REPLACE VIEW public.v_comb_orpak_dia AS
SELECT t.faena_id, t.dia_cierre AS fecha, t.estanque_id, e.nombre AS estanque,
       e.grupo_cuadre,
       count(*) FILTER (WHERE t.clasificacion NOT IN ('TRASVASIJE','RECIRCULACION')) AS transacciones,
       COALESCE(sum(t.litros) FILTER (WHERE t.clasificacion NOT IN ('TRASVASIJE','RECIRCULACION')), 0) AS litros_venta,
       COALESCE(sum(t.litros) FILTER (WHERE t.clasificacion = 'TRASVASIJE'), 0)     AS litros_trasvasije,
       COALESCE(sum(t.litros) FILTER (WHERE t.clasificacion = 'RECIRCULACION'), 0)  AS litros_recirculacion,
       COALESCE(sum(t.litros) FILTER (WHERE t.clasificacion = 'CALIBRACION'), 0)    AS litros_calibracion,
       COALESCE(sum(t.litros), 0) AS litros_total,
       count(*) FILTER (WHERE t.ceco_id IS NULL
                          AND t.clasificacion NOT IN ('TRASVASIJE','RECIRCULACION','CALIBRACION')) AS sin_ceco
FROM combustible_orpak_transaccion t
JOIN combustible_estanques e ON e.id = t.estanque_id
GROUP BY t.faena_id, t.dia_cierre, t.estanque_id, e.nombre, e.grupo_cuadre;

GRANT SELECT ON public.v_comb_orpak_dia TO authenticated;

-- ── CECO que aparece en Orpak y no está en el maestro ──────────────────────
CREATE OR REPLACE VIEW public.v_comb_orpak_ceco_desconocido AS
SELECT t.faena_id, t.ceco_codigo,
       min(t.departamento) AS departamento,
       count(*) AS transacciones,
       sum(t.litros) AS litros,
       min(t.dia_cierre) AS desde, max(t.dia_cierre) AS hasta
FROM combustible_orpak_transaccion t
WHERE t.ceco_id IS NULL AND t.ceco_codigo IS NOT NULL
GROUP BY t.faena_id, t.ceco_codigo;

GRANT SELECT ON public.v_comb_orpak_ceco_desconocido TO authenticated;

-- ── Reglas de Romeral ──────────────────────────────────────────────────────
DO $seed$
DECLARE
    f UUID := (SELECT id FROM faenas WHERE codigo = 'FAE-CMP-ROMERAL');
    bim UUID; casaf UUID; m1 UUID; m2 UUID; c18 UUID; c67 UUID; c78 UUID;
BEGIN
    IF f IS NULL THEN RAISE NOTICE 'Romeral no existe, no se siembran reglas.'; RETURN; END IF;

    SELECT id INTO bim   FROM combustible_estanques WHERE codigo='ROM-BIMODAL';
    SELECT id INTO casaf FROM combustible_estanques WHERE codigo='ROM-CASAF';
    SELECT id INTO m1    FROM combustible_estanques WHERE codigo='ROM-MINA-1';
    SELECT id INTO m2    FROM combustible_estanques WHERE codigo='ROM-MINA-2';
    SELECT id INTO c18   FROM combustible_estanques WHERE codigo='ROM-DJKL-18';
    SELECT id INTO c67   FROM combustible_estanques WHERE codigo='ROM-FSLZ-67';
    SELECT id INTO c78   FROM combustible_estanques WHERE codigo='ROM-LCSX-78';

    DELETE FROM combustible_orpak_clasificacion WHERE faena_id = f;
    INSERT INTO combustible_orpak_clasificacion (faena_id, prioridad, etiqueta, patron, modo) VALUES
      (f, 10, 'RECIRCULACION', 'RECIRCULACION',                    'contiene'),
      (f, 20, 'TRASVASIJE',    'TRASVASIJE',                       'contiene'),
      (f, 30, 'CALIBRACION',   'TAG CALIBRACION',                  'contiene'),
      (f, 31, 'CALIBRACION',   'CALIBRACION MINA ROMERAL',         'contiene'),
      (f, 40, 'ORPAK',         'ANILLO DE PRUEBA ORPAK',           'contiene'),
      (f, 41, 'ORPAK',         'TAG PRUEBA',                       'contiene'),
      (f, 50, 'TRANSPORTISTAS','FLOTA TRANSPORTISTAS HUASCO',      'flota_exacta'),
      (f, 60, 'CONTRATISTA',   'FLOTA CONTRATISTAS ESMAX ROMERAL', 'flota_exacta'),
      (f, 70, 'ORPAK',         'COPEC',                            'flota_exacta');
    -- Todo lo demás cae en CMP, que es el default de la función.

    DELETE FROM combustible_orpak_estacion_map WHERE faena_id = f;
    INSERT INTO combustible_orpak_estacion_map
        (faena_id, prioridad, patron_estacion, patron_vehiculo, bomba_igual,
         estanque_id, bomba_forzada, excluye_cisterna, patron_excluye) VALUES
      -- Los camiones aljibe primero: «Camion Romeral Aljibe DJKL18» contiene
      -- ROMERAL y se lo llevaría el catch-all del Bimodal.
      (f,  5, 'DJKL',            NULL,     NULL, c18,   NULL, false, NULL),
      (f,  6, NULL,              'DJKL18', NULL, c18,   NULL, false, NULL),
      (f,  7, 'CAMION 18',       NULL,     NULL, c18,   NULL, false, NULL),
      (f,  8, 'FSLZ',            NULL,     NULL, c67,   NULL, false, NULL),
      (f,  9, NULL,              'FSLZ67', NULL, c67,   NULL, false, NULL),
      (f, 10, 'CAMION 67',       NULL,     NULL, c67,   NULL, false, NULL),
      (f, 11, 'LCSX',            NULL,     NULL, c78,   NULL, false, NULL),
      (f, 12, NULL,              'LCSX78', NULL, c78,   NULL, false, NULL),
      (f, 13, 'CAMION 78',       NULL,     NULL, c78,   NULL, false, NULL),
      -- La locomotora carga en la bomba 5 del Bimodal. Cuando el Excel viene
      -- sin bomba se corrige sola — salvo que la haya cargado un aljibe en
      -- terreno, que descarga de su propio estanque.
      (f, 20, 'LOCOMOTORA',      NULL,     NULL, bim,   '5',  true,  NULL),
      (f, 30, 'LIVIANOS ROMERAL',NULL,     NULL, bim,   NULL, false, NULL),
      (f, 31, 'LIVIANOS ROM',    NULL,     NULL, bim,   NULL, false, NULL),
      (f, 40, 'BIMODAL',         NULL,     NULL, bim,   NULL, false, NULL),
      -- Mina: la bomba 2 es el estanque 2. Sin bomba, se asume el 1.
      (f, 50, 'ROM MINA',        NULL,     '2',  m2,    '2',  false, NULL),
      (f, 51, 'ISLA MINA',       NULL,     '2',  m2,    '2',  false, NULL),
      (f, 52, 'ROM MINA',        NULL,     NULL, m1,    '1',  false, NULL),
      (f, 53, 'ISLA MINA',       NULL,     NULL, m1,    '1',  false, NULL),
      (f, 54, 'MINA',            NULL,     '2',  m2,    '2',  false, NULL),
      (f, 55, 'MINA',            NULL,     NULL, m1,    '1',  false, NULL),
      (f, 60, 'CASA',            NULL,     NULL, casaf, NULL, false, NULL),
      (f, 61, 'FUERZA',          NULL,     NULL, casaf, NULL, false, NULL),
      -- Catch-all al final, ya sin las excepciones de arriba. «Camionetas
      -- Romeral» es una flota, no una estación: no debe caer aquí.
      (f, 90, 'ROMERAL',         NULL,     NULL, bim,   NULL, false, 'CAMIONETAS');

    RAISE NOTICE 'Romeral: % reglas de clasificacion, % de estacion.',
      (SELECT count(*) FROM combustible_orpak_clasificacion WHERE faena_id=f),
      (SELECT count(*) FROM combustible_orpak_estacion_map  WHERE faena_id=f);
END $seed$;

COMMIT;
