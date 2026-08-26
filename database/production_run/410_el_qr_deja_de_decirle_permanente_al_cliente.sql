-- ============================================================================
-- MIG410 · El QR del equipo deja de decirle «permanente» a un papel sin fecha
-- ----------------------------------------------------------------------------
-- LO QUE ADVIRTIÓ MANUEL
-- 26-08-2026: «obviamente ese panel debe hablar con el QR de los documentos del
-- equipo».
--
-- Y era urgente, porque el QR tenía EL MISMO PUNTO CIEGO que el panel interno,
-- con un agravante: el QR lo escanea el cliente.
--
-- `rpc_documentos_activo_publico` traducía cualquier fecha ≥ 2099 a
-- «permanente». O sea: un arrendatario que escanea el QR del TGGF-57 y busca el
-- certificado de láminas de seguridad lee «permanente» —no vence nunca— cuando
-- en realidad venció el 26 de marzo. Lo mismo con la hermeticidad del estanque,
-- vencida desde mayo de 2025.
--
-- El problema no era que el dato faltara: era que el sistema afirmaba algo
-- tranquilizador en lugar de admitir el hueco. Y lo afirmaba hacia afuera.
--
-- ── LA MISMA REGLA EN LOS DOS LADOS ────────────────────────────────────────
-- MIG407 y MIG408 ya definieron el criterio para adentro: si hay archivo
-- cargado y el tipo caduca, el estado es «sin fecha», no «permanente». El QR
-- pasa a usar exactamente ese criterio, con las mismas funciones —no una copia
-- que mañana se desincronice—.
--
-- ── LO QUE VE EL CLIENTE AHORA ─────────────────────────────────────────────
--     vigente      el papel está al día
--     por_vencer   vence dentro de 45 días
--     vencido      caducó
--     sin_fecha    hay documento cargado, pero su vigencia no está registrada
--     permanente   sólo factura, ficha técnica, padrón, RNVM y homologación
--
-- «Sin fecha» no es bonito de mostrarle a un cliente. Pero es lo que hay, y es
-- mucho mejor que decirle que un certificado vencido no vence nunca.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_documentos_activo_publico(p_activo_id uuid)
RETURNS TABLE(
    tipo text, numero_certificado text, entidad text,
    fecha_emision date, fecha_vencimiento date, dias_restantes integer,
    estado text, archivo_url text)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT DISTINCT ON (c.tipo)
         c.tipo::text, c.numero_certificado::text, c.entidad_certificadora::text,
         c.fecha_emision,
         -- Un 2099 no es una fecha: es el marcador de «sin dato». Devolverlo
         -- hacía que la pantalla mostrara «vence el 31-12-2099».
         CASE WHEN c.fecha_vencimiento >= DATE '2099-01-01' THEN NULL
              ELSE c.fecha_vencimiento END,
         CASE WHEN c.fecha_vencimiento >= DATE '2099-01-01' THEN NULL
              ELSE (c.fecha_vencimiento - CURRENT_DATE)::int END,
         CASE
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
  'MIG410: los documentos que ve el cliente al escanear el QR. Usa el mismo criterio que el panel interno: «sin_fecha» cuando hay papel cargado de un tipo que caduca sin vigencia registrada.';

-- ── Qué cambia para el que escanea ────────────────────────────────────────
DO $r$
DECLARE r RECORD; v_act UUID;
BEGIN
    SELECT id INTO v_act FROM activos WHERE patente = 'TGGF-57';
    RAISE NOTICE 'QR del TGGF-57 después del cambio:';
    FOR r IN
        SELECT tipo, estado FROM rpc_documentos_activo_publico(v_act)
         WHERE estado IN ('sin_fecha','vencido') ORDER BY estado, tipo
    LOOP RAISE NOTICE '   % → %', rpad(r.tipo, 22), r.estado; END LOOP;

    SELECT count(*) AS n INTO r
      FROM activos a, LATERAL rpc_documentos_activo_publico(a.id) d
     WHERE a.estado <> 'dado_baja' AND d.estado = 'sin_fecha';
    RAISE NOTICE 'Papeles que el QR mostraba como «permanente» y ahora piden revisión: %', r.n;
END
$r$;

COMMIT;
