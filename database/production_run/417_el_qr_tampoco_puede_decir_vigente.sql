-- ============================================================================
-- MIG417 · El QR tampoco puede decir «vigente»
-- ----------------------------------------------------------------------------
-- MIG416 marcó doce certificados de hermeticidad como no sostenibles y arregló
-- `v_certificacion_actual` para que dejaran de leerse en verde. Al verificarlo
-- apareció que el QR público NO usa esa vista: `rpc_documentos_activo_publico`
-- repite su propia lógica de estados sobre la tabla.
--
-- O sea que el arreglo llegaba a las pantallas de adentro y no a la única que
-- ve el cliente parado frente al camión. Es la misma grieta de MIG410 — cuando
-- el estado se calcula en dos lugares, uno de los dos se queda atrás — y esta
-- vez del lado que más importa: adentro el papel se ve naranja y el cliente que
-- escanea el QR lo sigue viendo verde.
--
-- Se agrega la misma condición, primera en el CASE, y se anula el contador de
-- días: «faltan 307 días» sobre una vigencia que no se sostiene es exactamente
-- la afirmación que no se puede hacer.
--
-- Queda pendiente lo de fondo: unificar los dos cálculos en uno. Mientras
-- existan dos, esto vuelve a pasar.
--
-- Ojo con la firma: la columna de salida se llama `entidad`, no
-- `entidad_certificadora`. Renombrarla al redefinir la función rompe el QR
-- entero, que la lee por nombre.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_documentos_activo_publico(p_activo_id uuid)
RETURNS TABLE(
    tipo text, numero_certificado text, entidad text,
    fecha_emision date, fecha_vencimiento date, dias_restantes integer,
    estado text, archivo_url text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT DISTINCT ON (c.tipo)
         c.tipo::text, c.numero_certificado::text, c.entidad_certificadora::text,
         c.fecha_emision,
         -- Un 2099 no es una fecha: es el marcador de «sin dato». Devolverlo
         -- hacía que la pantalla mostrara «vence el 31-12-2099».
         CASE WHEN c.vigencia_dudosa OR c.fecha_vencimiento >= DATE '2099-01-01' THEN NULL
              ELSE c.fecha_vencimiento END,
         CASE WHEN c.vigencia_dudosa OR c.fecha_vencimiento >= DATE '2099-01-01' THEN NULL
              ELSE (c.fecha_vencimiento - CURRENT_DATE)::int END,
         CASE
           -- [MIG417] Una vigencia que no se sostiene vale lo mismo que no
           -- tener fecha, y el cliente frente al camión es quien más necesita
           -- saberlo: va primera en el CASE para que gane sobre el verde.
           WHEN c.vigencia_dudosa THEN 'sin_fecha'
           -- [MIG410] Mismo criterio que adentro (MIG407/408): papel cargado, de
           -- un tipo que caduca, sin fecha anotada. Decirle «permanente» al
           -- cliente es afirmar que no vence nunca algo que puede estar vencido.
           WHEN (c.fecha_vencimiento IS NULL OR c.fecha_vencimiento >= DATE '2099-01-01')
                AND c.archivo_url IS NOT NULL
                AND NOT fn_certificado_tipo_permanente(c.tipo::text)
             THEN 'sin_fecha'
           WHEN c.fecha_vencimiento IS NULL OR c.fecha_vencimiento >= DATE '2099-01-01' THEN 'permanente'
           WHEN c.fecha_vencimiento < CURRENT_DATE THEN 'vencido'
           WHEN c.fecha_vencimiento <= CURRENT_DATE + 45 THEN 'por_vencer'
           ELSE 'vigente'
         END,
         c.archivo_url
    FROM certificaciones c
   WHERE c.activo_id = p_activo_id
   ORDER BY c.tipo, c.fecha_vencimiento DESC NULLS LAST, c.created_at DESC
$function$;

COMMENT ON FUNCTION public.rpc_documentos_activo_publico(uuid) IS
  'MIG417: el QR público respeta vigencia_dudosa. El estado sigue calculandose en dos lugares (aca y v_certificacion_actual): unificarlos es deuda pendiente.';

DO $r$
DECLARE v RECORD; v_verde INT := 0; v_naranja INT := 0;
BEGIN
    FOR v IN SELECT DISTINCT c.activo_id FROM certificaciones c WHERE c.vigencia_dudosa
    LOOP
        SELECT count(*) FILTER (WHERE estado = 'vigente'),
               count(*) FILTER (WHERE estado = 'sin_fecha')
          INTO v_verde, v_naranja
          FROM rpc_documentos_activo_publico(v.activo_id) WHERE tipo = 'hermeticidad';
        EXIT;
    END LOOP;
    RAISE NOTICE 'Muestra del QR para un equipo dudoso -> vigente: %, sin_fecha: %', v_verde, v_naranja;
END
$r$;

COMMIT;
