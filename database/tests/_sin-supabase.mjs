// Sustituto de '@/lib/supabase' para las pruebas fuera del navegador.
// El módulo que lo importa usa globalThis.__supaShim cuando existe, así que
// este objeto nunca se llega a consultar: está para que el import resuelva.
export const supabase = null
