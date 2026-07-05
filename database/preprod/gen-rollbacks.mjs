// Genera scripts de rollback ESPECÍFICOS (no reaplica migraciones históricas)
// a partir de las definiciones exactas pre-migración extraídas de prod.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
const funcs = readFileSync('./preprod_funcs_prod.sql', 'utf8')

// Extrae el bloque CREATE ... $function$ ... $function$; de una función por nombre.
function extractFn(name) {
  const re = new RegExp(`CREATE OR REPLACE FUNCTION public\\.${name}\\([\\s\\S]*?\\$function\\$\\s*;`, 'g')
  const m = funcs.match(re)
  if (!m) throw new Error('no encontrada: ' + name)
  return m.join('\n\n')
}

const OUT = 'C:/Users/Manuel Olivares/sicom-iceo/database/rollback'
mkdirSync(OUT, { recursive: true })

// ── ROLLBACK 185 ────────────────────────────────────────────────────────────
writeFileSync(OUT + '/rollback_185_seguridad_cierre_diario.sql', `-- ============================================================================
-- ROLLBACK MIG185 — rollback técnico de EMERGENCIA
-- ----------------------------------------------------------------------------
-- ⚠️ REABRE la vulnerabilidad CRÍTICA C1: deja rpc_confirmar_cierre_diario y
--    fn_propuesta_cierre_diario ejecutables por anon SIN validación, y quita la
--    RLS de estado_diario_flota (anon vuelve a poder escribir la matriz).
--    Usar SOLO si el cierre diario queda inoperante para usuarios legítimos y no
--    se resuelve otorgando el permiso 'approve' del módulo flota en Admin.
-- Restaura la definición y grants EXACTOS previos a MIG185 (extraídos de prod).
-- ============================================================================
BEGIN;

-- 1. Restaurar rpc_confirmar_cierre_diario a su definición pre-185.
${extractFn('rpc_confirmar_cierre_diario')}

-- 2. Restaurar grants previos (anon + authenticated) de las 2 funciones.
GRANT EXECUTE ON FUNCTION public.rpc_confirmar_cierre_diario(date, jsonb) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_propuesta_cierre_diario(date)        TO anon, authenticated;

-- 3. Quitar RLS y policy de estado_diario_flota; restaurar grants de tabla a anon.
DROP POLICY IF EXISTS pol_edf_select_authenticated ON public.estado_diario_flota;
ALTER TABLE public.estado_diario_flota DISABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.estado_diario_flota TO anon, authenticated;

-- 4. Eliminar el helper introducido por MIG185.
DROP FUNCTION IF EXISTS public.fn_tiene_permiso_modulo(text, text, text[]);

-- 5. Validación posterior del rollback.
DO $$
BEGIN
    IF NOT has_function_privilege('anon','public.rpc_confirmar_cierre_diario(date, jsonb)','EXECUTE') THEN
        RAISE EXCEPTION 'ROLLBACK185 incompleto: anon no recuperó EXECUTE';
    END IF;
    IF (SELECT rowsecurity FROM pg_tables WHERE tablename='estado_diario_flota') THEN
        RAISE EXCEPTION 'ROLLBACK185 incompleto: RLS sigue activa';
    END IF;
    RAISE NOTICE 'ROLLBACK185 aplicado (VULNERABILIDAD C1 REABIERTA).';
END $$;
COMMIT;
`)

// ── ROLLBACK 186 ────────────────────────────────────────────────────────────
writeFileSync(OUT + '/rollback_186_reporte_fiabilidad.sql', `-- ============================================================================
-- ROLLBACK MIG186 — rollback técnico de EMERGENCIA
-- ----------------------------------------------------------------------------
-- ⚠️ REABRE C3 (reporte de fiabilidad accesible por anon con VIN/motor/clientes)
--    y vuelve a PERDER la sección 'combustible' del informe. Usar solo si el
--    reporte queda inoperante para usuarios internos.
-- Restaura la definición EXACTA previa (MIG169) + grant anon.
-- ============================================================================
BEGIN;

${extractFn('fn_reporte_fiabilidad_publico')}

GRANT EXECUTE ON FUNCTION public.fn_reporte_fiabilidad_publico(date, date) TO anon, authenticated;

DO $$
BEGIN
    IF NOT has_function_privilege('anon','public.fn_reporte_fiabilidad_publico(date, date)','EXECUTE') THEN
        RAISE EXCEPTION 'ROLLBACK186 incompleto';
    END IF;
    RAISE NOTICE 'ROLLBACK186 aplicado (C3 REABIERTA; combustible perdido de nuevo).';
END $$;
COMMIT;
`)

// ── ROLLBACK 187 ────────────────────────────────────────────────────────────
writeFileSync(OUT + '/rollback_187_combustible_valor.sql', `-- ============================================================================
-- ROLLBACK MIG187 — rollback técnico de EMERGENCIA
-- ----------------------------------------------------------------------------
-- ⚠️ REABRE C5: las salidas y traspasos de combustible dejan de actualizar
--    valor_total_stock (el valor del estanque vuelve a inflarse). Usar solo si
--    el flujo de despacho queda inoperante.
-- Restaura definiciones EXACTAS previas de la salida y el traspaso + grants.
-- NOTA: rpc_registrar_despacho_combustible_con_sellos NO se tocó en lógica por
--    MIG187 (solo grants); no requiere restauración de cuerpo.
-- ============================================================================
BEGIN;

${extractFn('rpc_registrar_salida_combustible_valorizada')}

${extractFn('rpc_registrar_traspaso_combustible')}

-- Grants previos (en prod estas RPC tenían EXECUTE para anon+authenticated).
GRANT EXECUTE ON FUNCTION public.rpc_registrar_salida_combustible_valorizada(
    UUID, NUMERIC, VARCHAR, TEXT, UUID, UUID, UUID, UUID, VARCHAR, TIMESTAMPTZ,
    TEXT, TEXT, UUID, TEXT, TEXT, TEXT, TEXT, VARCHAR, VARCHAR,
    NUMERIC, NUMERIC, TIMESTAMPTZ, NUMERIC, NUMERIC, TIMESTAMPTZ,
    NUMERIC, NUMERIC, TIMESTAMPTZ, NUMERIC, NUMERIC, NUMERIC) TO anon, authenticated;

DO $$
DECLARE v_def TEXT;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname='rpc_registrar_salida_combustible_valorizada';
    IF v_def LIKE '%valor_total_stock = v_valor_post%' THEN
        RAISE EXCEPTION 'ROLLBACK187 incompleto: la salida aún actualiza valor';
    END IF;
    RAISE NOTICE 'ROLLBACK187 aplicado (C5 REABIERTA: valor deja de actualizarse).';
END $$;
COMMIT;
`)

console.log('rollbacks generados en database/rollback/')
