-- 620 — El panel completo de costos (gráficos + Pareto en cadena) se abre desde
-- el correo sin iniciar sesión. Manuel 2026-10-19 eligió esta opción («opción 2»)
-- sabiendo que quien tenga el link ve el detalle completo de Softland.
--
-- En vez de duplicar cada RPC con un parámetro p_token, la página pública manda
-- el token del link en el encabezado `x-reporte-token` y la única puerta de los
-- costos (fn_costos_operacion_puede_ver) lo acepta si está vigente en
-- reporte_tokens (reporte='costos', MIG617). Todas las RPC del panel ya pasan
-- por esa puerta, así que basta abrirles EXECUTE a anon: sin token válido,
-- siguen respondiendo 42501. Revocar el token (activo=false) corta todo.
CREATE OR REPLACE FUNCTION public.fn_costos_operacion_puede_ver()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT EXISTS (
               SELECT 1 FROM reporte_tokens t
                WHERE t.reporte = 'costos' AND t.activo
                  AND (t.expira_at IS NULL OR t.expira_at > NOW())
                  AND t.token = nullif(current_setting('request.headers', true), '')::json ->> 'x-reporte-token')
        OR fn_tiene_permiso_modulo('gerencia', 'view', ARRAY[
               'administrador','gerencia','subgerente_operaciones',
               'jefe_operaciones','jefe_mantenimiento'
           ]);
$function$;

GRANT EXECUTE ON FUNCTION rpc_costos_operacion_panel(date, date, text[])              TO anon;
GRANT EXECUTE ON FUNCTION rpc_costos_operacion_detalle(date, date, text, text, integer) TO anon;
GRANT EXECUTE ON FUNCTION rpc_costos_pareto(date, date, jsonb, text, boolean)          TO anon;
GRANT EXECUTE ON FUNCTION rpc_costos_por_faena(date, date)                             TO anon;
GRANT EXECUTE ON FUNCTION rpc_costos_faena_equipos(date, date, text, text)             TO anon;

SELECT fn_costos_operacion_puede_ver() AS postgres_sin_header_ve;
