-- ============================================================================
-- 611_qr_publico_sin_factura.sql
-- ----------------------------------------------------------------------------
-- Manuel 2026-10-19: ocultar la factura de compra también en el QR público del
-- equipo (/equipo/[id]/documentos). Una sola lista de tipos ocultos al cliente
-- para QR y portal de flota (fn_portal_flota_tipo_oculto, MIG610).
-- Sólo se agrega un filtro: mismas columnas y misma lógica de estados
-- (ver gotcha_qr_calcula_estados_aparte).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.rpc_documentos_activo_publico(p_activo_id uuid)
 RETURNS TABLE(tipo text, numero_certificado text, entidad text, fecha_emision date, fecha_vencimiento date, dias_restantes integer, estado text, archivo_url text, etiqueta text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT DISTINCT ON (fn_certificado_clave(c.tipo::text, c.tipo_otro))
         c.tipo::text, c.numero_certificado::text, c.entidad_certificadora::text,
         c.fecha_emision,
         CASE WHEN c.horometro_vence IS NOT NULL
                OR c.vigencia_dudosa OR c.fecha_vencimiento >= DATE '2099-01-01' THEN NULL
              ELSE c.fecha_vencimiento END,
         CASE WHEN c.horometro_vence IS NOT NULL
                OR c.vigencia_dudosa OR c.fecha_vencimiento >= DATE '2099-01-01' THEN NULL
              ELSE (c.fecha_vencimiento - CURRENT_DATE)::int END,
         CASE
           -- [MIG514/516] Vigencia por horas: manda el horómetro del equipo.
           WHEN c.horometro_vence IS NOT NULL THEN
             CASE WHEN COALESCE(a.horas_uso_actual, 0) >= c.horometro_vence THEN 'vencido'
                  WHEN COALESCE(a.horas_uso_actual, 0) >= c.horometro_vence - 50 THEN 'por_vencer'
                  ELSE 'vigente' END
           WHEN c.fecha_origen = 'documento_sin_vencimiento' THEN 'permanente'
           WHEN c.vigencia_dudosa THEN 'sin_fecha'
           WHEN (c.fecha_vencimiento IS NULL OR c.fecha_vencimiento >= DATE '2099-01-01')
                AND c.archivo_url IS NOT NULL
                AND NOT fn_certificado_tipo_permanente(c.tipo::text)
             THEN 'sin_fecha'
           WHEN c.fecha_vencimiento IS NULL OR c.fecha_vencimiento >= DATE '2099-01-01' THEN 'permanente'
           WHEN c.fecha_vencimiento < CURRENT_DATE THEN 'vencido'
           WHEN c.fecha_vencimiento <= CURRENT_DATE + 45 THEN 'por_vencer'
           ELSE 'vigente'
         END,
         c.archivo_url,
         fn_certificado_etiqueta(c.tipo::text, c.tipo_otro)
    FROM certificaciones c
    LEFT JOIN activos a ON a.id = c.activo_id
   WHERE c.activo_id = p_activo_id
     AND c.anulado_at IS NULL          -- [MIG486]
     -- [MIG611] La factura de compra no se muestra al cliente (precio, banco del
     -- leasing). Misma lista que el portal de flota: fn_portal_flota_tipo_oculto.
     AND NOT fn_portal_flota_tipo_oculto(c.tipo::text)
   ORDER BY fn_certificado_clave(c.tipo::text, c.tipo_otro),
            c.created_at DESC, c.fecha_vencimiento DESC NULLS LAST
$function$;

SELECT count(*) AS facturas_visibles_en_qr FROM activos a, rpc_documentos_activo_publico(a.id) x WHERE x.tipo = 'factura_compra';
