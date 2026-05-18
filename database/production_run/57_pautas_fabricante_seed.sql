-- ============================================================================
-- 57_pautas_fabricante_seed.sql
-- ----------------------------------------------------------------------------
-- Carga 41 pautas oficiales del fabricante en `pautas_fabricante`, extraidas
-- del Excel "Pautas Mantencion Maestro.xlsx" (Pillado, Mayo 2026).
--
-- Cubre 8 familias de modelos con detalle de fabricante:
--   - Mercedes Actros (Kaufmann)   : SI/SL/SM1-6     (8 pautas)
--   - Mercedes Atego               : SL/SM1-4         (5)
--   - Mercedes Axor                : SL/SM1-4         (5)
--   - Mack GU813E (Granite)        : SL/SM1/SM2/SM3  (4)
--   - Volvo VM 350 (D8C VAS)       : L1/S/M/L/Eje/Caja (6)
--   - Volvo FMX 420 (D13C VAS)     : L1/S/M/L/Eje/Caja (6)
--   - Renault C440 (SALFA)         : 500/1000/2500/6000/8000h (5)
--   - Nissan NP300 Diesel 2.3      : 10K/20K/40K     (3)
--
-- Pattern matching por nombre del modelo en BD para que TODAS las variantes
-- de cada familia hereden las pautas (ej. Actros 3336 K + Actros 3341 -> ambas
-- reciben SI/SL/SM1-6).
--
-- Modelos QUE NO RECIBEN PAUTAS automaticamente (Manuel los carga despues):
--   - Volvo FMX 540 (motor distinto al 420 — capacidades difieren)
--   - Mercedes Accelo 1016/44, Canter 7.5, Hilux, Berlingo, Maxus, Yale, etc.
--   - Camionetas y grua horquilla
--
-- ADITIVA, IDEMPOTENTE. ON CONFLICT requiere UNIQUE (modelo_id, nombre)
-- que esta migracion crea si no existe.
-- ============================================================================

-- ── Precheck ───────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='pautas_fabricante') THEN
        RAISE EXCEPTION 'STOP - tabla pautas_fabricante no existe (correr mig 02_tablas_core).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='tipo_plan_pm_enum') THEN
        RAISE EXCEPTION 'STOP - tipo_plan_pm_enum no existe.';
    END IF;
END $$;


-- ============================================================================
-- 1. UNIQUE constraint (modelo_id, nombre) para idempotencia del INSERT
-- ============================================================================
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'public.pautas_fabricante'::regclass
           AND contype  = 'u'
           AND pg_get_constraintdef(oid) LIKE '%modelo_id, nombre%'
    ) THEN
        ALTER TABLE pautas_fabricante
            ADD CONSTRAINT uq_pautas_fabricante_modelo_nombre UNIQUE (modelo_id, nombre);
    END IF;
END $$;


-- ============================================================================
-- 2. SEED 41 pautas con pattern matching a modelos
-- ============================================================================
WITH spec(marca_grafia, pattern_modelo, nombre, tipo_plan, frec_h, frec_km, frec_d, dur_hrs, descripcion, items, materiales) AS (
    VALUES
        -- ───── Mercedes Actros (Kaufmann WDB 930/932/934) — 8 pautas ─────
        ('Mercedes-Benz', '^Actros',
         'Actros - Servicio inicial SI (100h)',
         'por_horas', 100, 5000, NULL, 1.2,
         'Servicio inicial Kaufmann tras los primeros 100h.',
         '["Servicio inicial post primeras 100h", "Reapriete pernos y conexiones generales", "Chequeo de niveles (motor, refrigerante, transmision, diferenciales)"]'::jsonb,
         NULL::jsonb),

        ('Mercedes-Benz', '^Actros',
         'Actros - Servicio lubricacion SL (200h)',
         'por_horas', 200, 10000, NULL, 2.7,
         'Lubricacion menor (no aplica con aceite sintetico).',
         '["Servicio lubricacion motor (aceite mineral)", "Engrase puntos de articulacion", "Chequeo de niveles generales"]'::jsonb,
         NULL),

        ('Mercedes-Benz', '^Actros',
         'Actros - Servicio SM1 (400h)',
         'por_horas', 400, 20000, NULL, 4.2,
         'Mantenimiento 1: cambio aceite motor + filtros principales.',
         '["Cambio aceite motor + filtro aceite", "Cambio filtros petroleo y racor", "Chequeo niveles transmision/diferencial/direccion"]'::jsonb,
         NULL),

        ('Mercedes-Benz', '^Actros',
         'Actros - Servicio SM2 (800h)',
         'por_horas', 800, 40000, NULL, 6.4,
         'Mantenimiento 2: SM1 + cambio aceite diferenciales y filtros adicionales.',
         '["SM1 completo", "Cambio aceite diferenciales delantero y trasero", "Cambio filtros adicionales (aire, racor)"]'::jsonb,
         NULL),

        ('Mercedes-Benz', '^Actros',
         'Actros - Servicio SM3 (1600h)',
         'por_horas', 1600, 80000, NULL, 10.8,
         'Servicio mayor: SM1+SM2 + cambio caja, refrigerante anual y correas.',
         '["SM2 completo", "Cambio aceite caja de cambios y direccion", "Cambio refrigerante (anual/3000h)", "Cambio correas y tensores"]'::jsonb,
         NULL),

        ('Mercedes-Benz', '^Actros',
         'Actros - Servicio SM4 (3200h)',
         'por_horas', 3200, 160000, NULL, 12.6,
         'Servicio mantenimiento 4 — cierre del ciclo SM1-SM2-SM1-SM3-SM1-SM2-SM1-SM4.',
         '["SM3 completo", "Revision profunda transmision y embrague", "Juego de valvulas e inspeccion turbocompresor"]'::jsonb,
         NULL),

        ('Mercedes-Benz', '^Actros',
         'Actros - Servicio SM5 (4800h)',
         'por_horas', 4800, 240000, NULL, 13.2,
         'Overhaul intermedio: cambios profundos chasis/transmision.',
         '["SM4 completo", "Recambio piezas de desgaste mayor (frenos, bujes)", "Inspeccion estructural chasis"]'::jsonb,
         NULL),

        ('Mercedes-Benz', '^Actros',
         'Actros - Servicio SM6 (9600h)',
         'por_horas', 9600, 480000, NULL, 15.0,
         'Overhaul mayor maximo. Cambios profundos motor y caja.',
         '["SM5 completo", "Inspeccion y recambio mayor motor", "Inspeccion y recambio mayor caja Telligent"]'::jsonb,
         NULL),

        -- ───── Mercedes Atego — 5 pautas ─────
        ('Mercedes-Benz', '^Atego',
         'Atego - Servicio SL (200h)',
         'por_horas', 200, NULL, NULL, 2.7,
         'Lubricacion menor Atego (mismo patron ciclico Actros).',
         '["Servicio lubricacion motor (mineral)", "Engrase general y chequeos"]'::jsonb,
         NULL),

        ('Mercedes-Benz', '^Atego',
         'Atego - Servicio SM1 (400h)',
         'por_horas', 400, NULL, NULL, 4.2,
         'Cambio aceite motor + filtros principales (regimen severo 400h).',
         '["Cambio aceite motor + filtro aceite", "Cambio filtros petroleo y racor"]'::jsonb,
         NULL),

        ('Mercedes-Benz', '^Atego',
         'Atego - Servicio SM2 (800h)',
         'por_horas', 800, NULL, NULL, 6.4,
         'SM1 + cambio aceite diferenciales y filtros adicionales.',
         '["SM1 completo", "Cambio aceite diferenciales", "Filtros adicionales"]'::jsonb,
         NULL),

        ('Mercedes-Benz', '^Atego',
         'Atego - Servicio SM3 (1600h)',
         'por_horas', 1600, NULL, NULL, 10.8,
         'Servicio mayor: caja, refrigerante anual y correas.',
         '["SM2 completo", "Cambio aceite caja y direccion", "Cambio refrigerante", "Correas y tensores"]'::jsonb,
         NULL),

        ('Mercedes-Benz', '^Atego',
         'Atego - Servicio SM4 (3200h)',
         'por_horas', 3200, NULL, NULL, 12.6,
         'Servicio mantenimiento 4 cierre ciclo Atego.',
         '["SM3 completo", "Revision profunda transmision", "Juego de valvulas + turbo"]'::jsonb,
         NULL),

        -- ───── Mercedes Axor — 5 pautas ─────
        ('Mercedes-Benz', '^Axor',
         'Axor - Servicio SL (200h)',
         'por_horas', 200, NULL, NULL, 2.7,
         'Lubricacion menor Axor (mismo patron Actros).',
         '["Servicio lubricacion motor (mineral)", "Engrase general y chequeos"]'::jsonb,
         NULL),

        ('Mercedes-Benz', '^Axor',
         'Axor - Servicio SM1 (400h)',
         'por_horas', 400, NULL, NULL, 4.2,
         'Cambio aceite motor + filtros principales (400h regimen severo).',
         '["Cambio aceite motor + filtro aceite", "Cambio filtros petroleo y racor"]'::jsonb,
         NULL),

        ('Mercedes-Benz', '^Axor',
         'Axor - Servicio SM2 (800h)',
         'por_horas', 800, NULL, NULL, 6.4,
         'SM1 + cambio aceite diferenciales y filtros adicionales.',
         '["SM1 completo", "Cambio aceite diferenciales", "Filtros adicionales"]'::jsonb,
         NULL),

        ('Mercedes-Benz', '^Axor',
         'Axor - Servicio SM3 (1600h)',
         'por_horas', 1600, NULL, NULL, 10.8,
         'Servicio mayor: caja, refrigerante anual y correas.',
         '["SM2 completo", "Cambio aceite caja y direccion", "Cambio refrigerante", "Correas y tensores"]'::jsonb,
         NULL),

        ('Mercedes-Benz', '^Axor',
         'Axor - Servicio SM4 (3200h)',
         'por_horas', 3200, NULL, NULL, 12.6,
         'Servicio mantenimiento 4 cierre ciclo Axor.',
         '["SM3 completo", "Revision profunda transmision", "Juego de valvulas + turbo"]'::jsonb,
         NULL),

        -- ───── Mack GU813E (Granite 6x4) — 4 pautas ─────
        ('Mack', '^GU.?813',
         'Mack GU813E - Servicio SL (250h / 5.000km)',
         'mixto', 250, 5000, NULL, NULL,
         'Lubricacion menor (lo que ocurra primero: 250h o 5.000km).',
         '["Cambio aceite motor 15W40 (38 L)", "Reemplazo filtro aceite motor (2 un)", "Reemplazo filtro aceite motor adicional (1 un)", "Reemplazo filtro aire si necesario", "Revision niveles aceite motor/refrigerante/diferenciales/caja/hidraulico/direccion", "Pruebas testeo encendido/voltimetro/temperatura/tacometro/turbo", "Revision caja cambios automatica/ejes propulsores/cardan"]'::jsonb,
         '{"aceite_motor_15w40_L": 38, "filtro_aceite_motor_qty": 2, "filtro_aceite_motor_adic_qty": 1, "filtro_aire_qty": 1}'::jsonb),

        ('Mack', '^GU.?813',
         'Mack GU813E - Servicio SM1 (500h / 10.000km)',
         'mixto', 500, 10000, NULL, NULL,
         'SL + cambio aceite diferenciales y filtros combustible.',
         '["Cambio aceite motor 15W40 (38 L)", "Reemplazo filtros aceite motor (2 + 1 adic)", "Cambio aceite diferencial delantero + divisor 80W90 (18 L)", "Cambio aceite diferencial trasero 80W90 (15 L)", "Reemplazo filtro petroleo (1)", "Reemplazo filtro racor (1)", "Reemplazo filtro aire si necesario", "Revision niveles + pruebas testeo + revision caja/ejes/cardan"]'::jsonb,
         '{"aceite_motor_15w40_L": 38, "filtro_aceite_motor_qty": 2, "filtro_aceite_motor_adic_qty": 1, "aceite_dif_delantero_80w90_L": 18, "aceite_dif_trasero_80w90_L": 15, "filtro_petroleo_qty": 1, "filtro_racor_qty": 1}'::jsonb),

        ('Mack', '^GU.?813',
         'Mack GU813E - Servicio SM2 (1000h / 20.000km)',
         'mixto', 1000, 20000, NULL, NULL,
         'SM1 (sin difs) + filtros respiradero/direccion + revision turbo anual.',
         '["Cambio aceite motor 15W40 (38 L)", "Reemplazo filtros aceite motor (2 + 1 adic)", "Reemplazo filtro petroleo (1)", "Reemplazo filtro racor (1)", "Limpieza filtro respiradero diferenciales", "Reemplazo filtro direccion hidraulica", "Chequeo de tensores correas", "Revision turbocompresor (anual / 3000h)", "Revision niveles + pruebas testeo + revision caja/ejes/cardan"]'::jsonb,
         '{"aceite_motor_15w40_L": 38, "filtro_aceite_motor_qty": 2, "filtro_aceite_motor_adic_qty": 1, "filtro_petroleo_qty": 1, "filtro_racor_qty": 1, "filtro_direccion_qty": 1}'::jsonb),

        ('Mack', '^GU.?813',
         'Mack GU813E - Servicio SM3 (3000h / 60.000km / anual)',
         'mixto', 3000, 60000, 365, NULL,
         'Servicio mayor anual: caja Allison, refrigerante, correas, valvulas y rotadores.',
         '["Cambio aceite motor 15W40 (38 L)", "Cambio refrigerante 50/50 (57 L) - anual", "Cambio aceite diferencial delantero + divisor 80W90 (18 L)", "Cambio aceite diferencial trasero 80W90 (15 L)", "Cambio aceite caja Allison TES295/ATF 3000S (48 L) + filtros", "Cambio aceite direccion ATF220 (3.8 L)", "Filtros aceite motor (2 + 1 adic)", "Filtros petroleo/racor/aire/respiradero dif./direccion/transmision kit", "Cambio correa alternador-A/C", "Cambio correa ventilador-bomba agua", "Juego de valvulas + rotadores", "Limpieza estanque combustible", "Revision niveles + pruebas testeo"]'::jsonb,
         '{"aceite_motor_15w40_L": 38, "refrigerante_50_50_L": 57, "aceite_dif_delantero_80w90_L": 18, "aceite_dif_trasero_80w90_L": 15, "aceite_caja_allison_tes295_L": 48, "aceite_direccion_atf220_L": 3.8, "filtro_aceite_motor_qty": 2, "filtro_aceite_motor_adic_qty": 1, "filtro_petroleo_qty": 1, "filtro_racor_qty": 1, "filtro_direccion_qty": 1, "filtro_transmision_kit_qty": 1, "correa_alternador_ac_qty": 1, "correa_ventilador_bomba_qty": 1}'::jsonb),

        -- ───── Volvo VM 350 (D8C) — VAS — 6 pautas ─────
        ('Volvo', '^VM 350$',
         'Volvo VM 350 - L1 lubricacion (250h / 30 dias)',
         'mixto', 250, 12500, 30, 1.5,
         'Engrase + chequeos. Aceite NO se cambia. Pre-op y articulaciones.',
         '["Chequeo + relleno aceite motor", "Chequeo filtros aire/petroleo", "Chequeo nivel y fugas transmision/diferencial", "Engrase puntos de articulacion"]'::jsonb,
         NULL),

        ('Volvo', '^VM 350$',
         'Volvo VM 350 - S pequeno (500h / 60 dias)',
         'mixto', 500, 25000, 60, 3.0,
         'Cambio aceite motor (~30L D8C) + filtro aceite.',
         '["Cambio aceite motor D8C (~30 L)", "Cambio filtro aceite motor (2 un)", "Chequeo nivel transmision y diferencial", "Chequeo nivel refrigerante"]'::jsonb,
         '{"aceite_motor_L": 30, "filtro_aceite_motor_qty": 2}'::jsonb),

        ('Volvo', '^VM 350$',
         'Volvo VM 350 - M mediano (1000h / 120 dias)',
         'mixto', 1000, 50000, 120, 4.5,
         'Cambio aceite motor + 4 filtros + muestra aceite obligatoria.',
         '["Cambio aceite motor + filtro aceite", "Cambio filtro petroleo", "Cambio filtro racor", "Cambio filtro aire si saturado", "Chequeo nivel transmision + muestra aceite", "Chequeo nivel refrigerante"]'::jsonb,
         '{"aceite_motor_L": 30, "filtro_aceite_motor_qty": 2, "filtro_petroleo_qty": 1, "filtro_racor_qty": 1}'::jsonb),

        ('Volvo', '^VM 350$',
         'Volvo VM 350 - L mayor (1500h / 180 dias)',
         'mixto', 1500, 75000, 180, 7.5,
         'Todos los filtros + muestra aceites + inspeccion EGR/SCR/AdBlue. Cambio caja+dif cada 3000h.',
         '["Cambio aceite motor + filtro aceite", "Cambio todos los filtros (motor/petroleo/racor/aire primario/secundario)", "Cambio aceite caja I-Shift + diferenciales (D8C c/2 L = 3000h)", "Inspeccion sistema EGR/SCR/AdBlue", "Muestras de aceite obligatorias"]'::jsonb,
         '{"aceite_motor_L": 30, "filtro_aceite_motor_qty": 2, "filtro_petroleo_qty": 1, "filtro_racor_qty": 1, "filtro_aire_primario_qty": 1, "filtro_aire_secundario_qty": 1}'::jsonb),

        ('Volvo', '^VM 350$',
         'Volvo VM 350 - Servicio Eje (3000h / anual)',
         'mixto', 3000, 150000, 365, 6.0,
         'Cambio aceite diferencial tandem (RTH3210) + inspeccion rodamientos. Refrigerante anual ~45L.',
         '["Cambio aceite ejes RTH3210", "Inspeccion rodamientos", "Cambio refrigerante (~45 L D8C, anual o 3000h)"]'::jsonb,
         '{"refrigerante_L": 45}'::jsonb),

        ('Volvo', '^VM 350$',
         'Volvo VM 350 - Servicio Caja I-Shift (4800h / 2 anios)',
         'mixto', 4800, 240000, 730, 8.0,
         'Cambio aceite + filtro caja I-Shift (AT2612). Inspeccion embrague.',
         '["Cambio aceite I-Shift (AT2612)", "Cambio filtro caja I-Shift", "Inspeccion embrague"]'::jsonb,
         NULL),

        -- ───── Volvo FMX 420 (D13C) — VAS — 6 pautas ─────
        ('Volvo', '^FMX 420$',
         'Volvo FMX 420 - L1 lubricacion (250h / 30 dias)',
         'mixto', 250, 12500, 30, 1.5,
         'Engrase + chequeos D13C 420. Aceite NO se cambia.',
         '["Chequeo + relleno aceite motor", "Chequeo filtros aire/petroleo", "Chequeo nivel y fugas transmision/diferencial", "Engrase puntos de articulacion"]'::jsonb,
         NULL),

        ('Volvo', '^FMX 420$',
         'Volvo FMX 420 - S pequeno (500h / 60 dias)',
         'mixto', 500, 25000, 60, 3.0,
         'Cambio aceite motor D13C (~40L) + filtro aceite.',
         '["Cambio aceite motor D13C (~40 L)", "Cambio filtro aceite motor (2 un)", "Chequeo nivel transmision y diferencial", "Chequeo nivel refrigerante"]'::jsonb,
         '{"aceite_motor_L": 40, "filtro_aceite_motor_qty": 2}'::jsonb),

        ('Volvo', '^FMX 420$',
         'Volvo FMX 420 - M mediano (1000h / 120 dias)',
         'mixto', 1000, 50000, 120, 4.5,
         'Cambio aceite + 4 filtros + muestra aceite obligatoria.',
         '["Cambio aceite motor + filtro aceite", "Cambio filtro petroleo", "Cambio filtro racor", "Cambio filtro aire si saturado", "Chequeo nivel transmision + muestra aceite"]'::jsonb,
         '{"aceite_motor_L": 40, "filtro_aceite_motor_qty": 2, "filtro_petroleo_qty": 1, "filtro_racor_qty": 1}'::jsonb),

        ('Volvo', '^FMX 420$',
         'Volvo FMX 420 - L mayor (1500h / 180 dias)',
         'mixto', 1500, 75000, 180, 7.5,
         'Todos los filtros + muestra aceites + inspeccion EGR/SCR/AdBlue + cambio caja+dif.',
         '["Cambio aceite motor + filtro aceite", "Cambio todos los filtros (motor/petroleo/racor/aire primario/secundario)", "Cambio aceite caja I-Shift + diferenciales", "Inspeccion sistema EGR/SCR/AdBlue", "Muestras de aceite obligatorias"]'::jsonb,
         '{"aceite_motor_L": 40, "filtro_aceite_motor_qty": 2, "filtro_petroleo_qty": 1, "filtro_racor_qty": 1, "filtro_aire_primario_qty": 1, "filtro_aire_secundario_qty": 1}'::jsonb),

        ('Volvo', '^FMX 420$',
         'Volvo FMX 420 - Servicio Eje (3000h / anual)',
         'mixto', 3000, 150000, 365, 6.0,
         'Cambio aceite diferencial tandem (RTH/RTS) + refrigerante anual (~55L D13C).',
         '["Cambio aceite ejes tandem (RTH/RTS)", "Inspeccion rodamientos", "Cambio refrigerante Krynex Glycoultra G40 (~55 L)"]'::jsonb,
         '{"refrigerante_L": 55}'::jsonb),

        ('Volvo', '^FMX 420$',
         'Volvo FMX 420 - Servicio Caja I-Shift (4800h / 2 anios)',
         'mixto', 4800, 240000, 730, 8.0,
         'Cambio aceite + filtro caja I-Shift (AT2612) + inspeccion embrague.',
         '["Cambio aceite I-Shift (AT2612)", "Cambio filtro caja I-Shift", "Inspeccion embrague"]'::jsonb,
         NULL),

        -- ───── Renault C440 6x4 Optidrive (SALFA) — 5 pautas ─────
        ('Renault', '^C440$',
         'Renault C440 - Servicio basico cada 500h',
         'por_horas', 500, NULL, NULL, NULL,
         'Plan SALFA recurrente: aceite + filtros principales + engrase + analisis aceite motor.',
         '["Cambio aceite motor", "Cambio filtro aceite motor", "Cambio filtro aceite turbo motor", "Cambio filtro petroleo", "Cambio filtro prefiltro petroleo", "Cambio golilla tapon carter", "Cambio filtro aire principal", "Engrase general", "Analisis aceite motor (obligatorio garantia SALFA)"]'::jsonb,
         NULL),

        ('Renault', '^C440$',
         'Renault C440 - Servicio intermedio cada 1000h',
         'por_horas', 1000, NULL, NULL, NULL,
         'Servicio 500h + cambio filtro aire secundario.',
         '["Servicio basico 500h completo", "Cambio filtro aire secundario", "Analisis aceite motor"]'::jsonb,
         NULL),

        ('Renault', '^C440$',
         'Renault C440 - Servicio mayor cada 2500h',
         'por_horas', 2500, NULL, NULL, NULL,
         'Servicio intermedio + caja Optidriver + puente + AD Blue + A/C + analisis transmision/dif.',
         '["Servicio intermedio 1000h completo", "Cambio filtro depurador APM2", "Cambio filtro caja Optidriver", "Cambio filtro AD Blue", "Cambio filtro A/C cabina", "Cambio aceite caja de cambios", "Cambio aceite puente trasero", "Cambio aceite direccion hidraulica", "Cambio aceite bomba cabina hidraulica", "Analisis transmision caja y diferencial"]'::jsonb,
         NULL),

        ('Renault', '^C440$',
         'Renault C440 - Servicio overhaul cada 6000h',
         'por_horas', 6000, NULL, NULL, NULL,
         'Servicio mayor + correas, tensores, retardador Voith, empaque tapa valvulas.',
         '["Servicio mayor 2500h completo", "Cambio rodillo tensor alternador", "Cambio correa ventilador", "Cambio rodillo tensor ventilador", "Cambio polea ruptura ventilador", "Cambio empaque tapa de valvulas", "Cambio golilla tapon puente", "Cambio aceite retardador Voith type C", "Cambio filtro estanque combustible"]'::jsonb,
         NULL),

        ('Renault', '^C440$',
         'Renault C440 - Cambio refrigerante a 8000h',
         'por_horas', 8000, NULL, NULL, NULL,
         'Cambio liquido refrigerante motor + analisis refrigerante.',
         '["Cambio liquido refrigerante motor", "Analisis de refrigerante", "Cambio filtro estanque combustible"]'::jsonb,
         NULL),

        -- ───── Nissan NP300 Diesel 2.3 — 3 pautas ─────
        ('Nissan', '^NP300',
         'NP300 - Inspeccion cada 10K (10/30/50/70/90K)',
         'por_kilometraje', NULL, 10000, NULL, 2.36,
         'Pauta de inspeccion (I) por kilometraje. Cambio aceite motor + filtro aire.',
         '["Cambio aceite motor + filtro + revisar fugas", "Cambio filtro aire", "Inspeccion puertas/capo/cinturones/vidrios/plumillas/faros", "Funcionamiento electrico (luces/cierre/alza vidrios/A-C/radio)", "Diagnostico CONSULT III", "Inspeccion embrague (T/M)", "Inspeccion correas accesorios + tensor", "Inspeccion ductos vacio (A/C, PCV, EVAP, servofreno)", "Direccion servo asistida (nivel y ductos)", "Inspeccion aceite transmision/transferencia/diferencial", "Inspeccion flexibles combustible/frenos/cardanes", "Inspeccion bateria (apriete + Midtronics)", "Inspeccion filtro combustible y separador agua (drenar)", "Inspeccion filtro polen", "Inspeccion nivel y fuga refrigerante", "Limpieza freno + inspeccion freno mano y liquido", "Alineacion + inspeccion rotulas y amortiguadores", "Inspeccion multiples + tubos escape", "Inspeccion reapriete pernos motor/transmision/suspension", "Prueba ruta + analisis gases (CO/HC/CO+CO2)", "Reprogramar siguiente mantencion", "Lavado"]'::jsonb,
         NULL),

        ('Nissan', '^NP300',
         'NP300 - Inspeccion cada 20K (20/60/100K)',
         'por_kilometraje', NULL, 20000, NULL, 2.31,
         'Inspeccion 10K + cambio filtro separador agua. A 100K cambio aceite transmision.',
         '["Servicio inspeccion 10K completo", "Cambio filtro separador agua", "Inspeccion + alineacion direccion/suspension (R/R/I)", "Inspeccion aceite transmision (cambio en 100K)"]'::jsonb,
         NULL),

        ('Nissan', '^NP300',
         'NP300 - Cambio cada 40K (40/80K)',
         'por_kilometraje', NULL, 40000, NULL, 2.51,
         'Cambio filtros combustible/polen/freno. A 80K cambio refrigerante. Distribucion c/240K.',
         '["Cambio aceite motor + filtro + revisar fugas", "Cambio filtro combustible", "Cambio filtro separador agua", "Cambio filtro aire", "Cambio filtro polen", "Cambio liquido frenos", "Limpieza freno + inspeccion freno mano", "Cambio refrigerante a 80K", "Prueba ruta + analisis gases", "Reprogramar siguiente mantencion", "Lavado"]'::jsonb,
         NULL)
)
INSERT INTO pautas_fabricante (
    modelo_id, nombre, tipo_plan,
    frecuencia_horas, frecuencia_km, frecuencia_dias,
    duracion_estimada_hrs, descripcion, items_checklist, materiales_estimados
)
SELECT
    m.id,
    s.nombre,
    s.tipo_plan::tipo_plan_pm_enum,
    s.frec_h, s.frec_km, s.frec_d,
    s.dur_hrs, s.descripcion, s.items, s.materiales
  FROM spec s
  JOIN marcas  ma ON ma.nombre = s.marca_grafia
  JOIN modelos m  ON m.marca_id = ma.id AND m.nombre ~ s.pattern_modelo
ON CONFLICT (modelo_id, nombre) DO NOTHING;


-- ============================================================================
-- VALIDACION + REPORTE
-- ============================================================================

-- 1. Conteo total de pautas insertadas + por familia
SELECT
    ma.nombre AS marca,
    m.nombre  AS modelo,
    COUNT(pf.id) AS pautas_asignadas,
    array_agg(pf.nombre ORDER BY pf.frecuencia_horas, pf.frecuencia_km) AS pautas
  FROM modelos m
  JOIN marcas ma ON ma.id = m.marca_id
  LEFT JOIN pautas_fabricante pf ON pf.modelo_id = m.id AND pf.activo = true
 WHERE ma.nombre IN ('Mercedes-Benz', 'Mack', 'Volvo', 'Renault', 'Nissan')
   AND (m.nombre ~ '^(Actros|Atego|Axor|GU.?813|VM 350|FMX 420|C440|NP300)')
 GROUP BY ma.nombre, m.nombre
 ORDER BY ma.nombre, m.nombre;

-- 2. Resumen ejecutivo
SELECT
    'Total pautas en BD' AS metrica,
    COUNT(*)::text AS valor
  FROM pautas_fabricante
 WHERE activo = true
UNION ALL
SELECT 'Familias cubiertas', COUNT(DISTINCT m.nombre)::text
  FROM pautas_fabricante pf
  JOIN modelos m ON m.id = pf.modelo_id
  JOIN marcas ma ON ma.id = m.marca_id
 WHERE ma.nombre IN ('Mercedes-Benz', 'Mack', 'Volvo', 'Renault', 'Nissan');

NOTIFY pgrst, 'reload schema';
