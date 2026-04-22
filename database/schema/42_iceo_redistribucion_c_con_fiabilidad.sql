-- ============================================================================
-- SICOM-ICEO | Migracion 42 — ICEO: redistribucion area C + C8 OEE-Fiabilidad
-- ============================================================================
-- Agrega el KPI C8 "OEE-Fiabilidad Flota Movil" al area C y redistribuye los
-- pesos dentro del 30% asignado al area. Actualiza C2 y C3 para reflejar su
-- nueva metodologia (mig 40 + 41). No toca los pesos globales A=35, B=35,
-- C=30 del ICEO.
--
-- Distribucion final del 30% (area C):
--   C1 Cumplimiento PM Moviles ............ 5%
--   C2 Disponibilidad Inherente ........... 5%   <- era "horas operativas"
--   C3 MTTR (dias) ........................ 3%   <- era "horas"
--   C4 Certificaciones Vehiculares ........ 5%
--   C5 Eficiencia Combustible Flota ....... 2%
--   C6 Exactitud Inventario Repuestos ..... 2%
--   C7 Backlog OT Correctivas ............. 2%
--   C8 OEE-Fiabilidad (NUEVO) ............. 6%
--   TOTAL ................................ 30%
-- ============================================================================

-- ============================================================================
-- 1. Actualizar pesos y metadata de C1-C7
-- ============================================================================

-- C1: peso 6% -> 5%
UPDATE kpi_definiciones
   SET peso = 0.0500
 WHERE codigo = 'C1';

-- C2: peso 6% -> 5%, renombrar y redefinir formula (mig 40+41).
UPDATE kpi_definiciones
   SET peso              = 0.0500,
       nombre            = 'Disponibilidad Inherente Flota Movil',
       descripcion       = 'Promedio de Disponibilidad Inherente (MTBF/(MTBF+MTTR)) '
                           'de la flota movil, calculado sobre corridas de dias en '
                           'estados DOWN (M/T/F) en estado_diario_flota. '
                           'Metodologia Analisis de Fiabilidad.',
       formula           = 'AVG( MTBF_i / (MTBF_i + MTTR_i) ) sobre activos moviles',
       meta_valor        = 90.0000,
       umbral_bloqueante = 80.0000
 WHERE codigo = 'C2';

-- C3: peso 4% -> 3%, cambiar unidad a dias, meta a 3 dias.
UPDATE kpi_definiciones
   SET peso        = 0.0300,
       nombre      = 'Tiempo Medio de Reparacion Flota Movil (MTTR, dias)',
       descripcion = 'Tiempo medio (dias) que dura un evento de falla en la flota '
                     'movil, calculado como promedio de (Dias DOWN / N eventos) por '
                     'activo con al menos un evento. Meta: maximo 3 dias.',
       formula     = 'AVG( Dias DOWN_i / N_eventos_i )  (solo activos con eventos)',
       unidad      = 'dias',
       meta_valor  = 3.0000
 WHERE codigo = 'C3';

-- C4: sin cambio de peso
-- C5: peso 3% -> 2%
UPDATE kpi_definiciones SET peso = 0.0200 WHERE codigo = 'C5';
-- C6: peso 3% -> 2%
UPDATE kpi_definiciones SET peso = 0.0200 WHERE codigo = 'C6';
-- C7: peso 3% -> 2%
UPDATE kpi_definiciones SET peso = 0.0200 WHERE codigo = 'C7';


-- ============================================================================
-- 2. Insertar C8 — OEE-Fiabilidad Flota Movil
-- ============================================================================
-- Verifica si no existe ya, para que la migracion sea idempotente.

INSERT INTO kpi_definiciones (
    id, codigo, nombre, area, descripcion, formula, funcion_calculo,
    unidad, meta_valor, meta_direccion, peso,
    es_bloqueante, umbral_bloqueante, efecto_bloqueante,
    frecuencia, activo
)
SELECT
    gen_random_uuid(),
    'C8',
    'OEE-Fiabilidad Flota Movil',
    'mantenimiento_moviles',
    'OEE de la flota movil con metodologia del Analisis de Fiabilidad '
    '(vista comercial): A=Disponibilidad, P=(Dias A + Dias L)/(A+D+V+H+R+L) '
    'que captura utilizacion comercial, Q=1-(Dias F/Total). OEE = A*P*Q. '
    'Excluye equipos 100% en Uso Interno (P indefinido). Referencia world '
    'class industria pesada: OEE >= 85%.',
    'OEE = A * P * Q  (promedio sobre activos moviles)',
    'fn_kpi_oee_fiabilidad_moviles',
    '%',
    85.0000,              -- meta world class industria pesada
    'mayor_igual',
    0.0600,               -- peso 6%
    true,                 -- es bloqueante
    60.0000,              -- umbral bloqueante: OEE < 60% penaliza
    'penalizar',
    'mensual',
    true
WHERE NOT EXISTS (
    SELECT 1 FROM kpi_definiciones WHERE codigo = 'C8'
);


-- ============================================================================
-- 3. Verificacion: la suma de pesos del area C debe dar exactamente 0.30
-- ============================================================================

DO $$
DECLARE
    v_suma NUMERIC;
    v_c8_existe BOOLEAN;
BEGIN
    SELECT COALESCE(SUM(peso), 0)
      INTO v_suma
      FROM kpi_definiciones
     WHERE area = 'mantenimiento_moviles'
       AND activo = true;

    SELECT EXISTS (SELECT 1 FROM kpi_definiciones WHERE codigo = 'C8')
      INTO v_c8_existe;

    RAISE NOTICE '== Migracion 42 ==';
    RAISE NOTICE 'C8 OEE-Fiabilidad insertado ... %', v_c8_existe;
    RAISE NOTICE 'Suma pesos area C (debe=0.30) . %', v_suma;

    IF NOT v_c8_existe THEN
        RAISE EXCEPTION 'C8 no fue insertado.';
    END IF;

    IF ABS(v_suma - 0.30) > 0.0001 THEN
        RAISE EXCEPTION 'Suma de pesos area C = % (esperado 0.30)', v_suma;
    END IF;
END $$;


-- ============================================================================
-- 4. (Opcional) Regenerar tramos C2 y C3 si su meta cambio
-- ============================================================================
-- El sistema de tramos (kpi_tramos) genera los puntajes por rango de
-- cumplimiento. Si C2 y C3 cambiaron su meta, los tramos existentes
-- pueden estar calibrados contra la meta vieja. Este UPDATE mantiene
-- la estructura de tramos (porcentajes 100/95/90/85/80 de la meta)
-- usando la nueva meta.
--
-- Si kpi_tramos no se usa para C2/C3 (porque eran NULL en la version
-- anterior), este UPDATE es no-op. No tumba nada.
-- ============================================================================

-- Nada que hacer aqui: kpi_tramos referencia a kpi_definiciones por FK y los
-- tramos se generan como porcentaje relativo a kd.meta_valor en tiempo de
-- evaluacion, no como valores absolutos. Los pesos de tramo siguen validos.
