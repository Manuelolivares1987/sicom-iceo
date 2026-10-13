-- ============================================================================
-- SICOM-ICEO | 584b — Lomas 2 microfiltrado 23/09: quitar un cuadro velado
-- ============================================================================
-- El cuadro registro/003.jpg (sacado del video) salió sobreexpuesto y en el
-- PDF se ve como una foto en blanco. Se deja solo el 001 como registro
-- complementario y se invalida el PDF para regenerarlo.
-- ============================================================================
BEGIN;
UPDATE enex_ejecuciones
   SET evidencia_urls = ARRAY['https://gvmaucxgjnrxvgleyklf.supabase.co/storage/v1/object/public/evidencias-verificacion/enex/2026-09/23-lomas2-microfiltrado/registro/001.jpg'],
       informe_pdf_url = NULL
 WHERE id = '718a2882-4c07-43c8-885d-32110899886e'
   AND fecha_ejecucion = DATE '2026-09-23';
SELECT fecha_ejecucion, array_length(evidencia_urls, 1) AS fotos, informe_pdf_url
  FROM enex_ejecuciones WHERE id = '718a2882-4c07-43c8-885d-32110899886e';
COMMIT;
