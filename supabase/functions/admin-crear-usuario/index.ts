// ============================================================================
// supabase/functions/admin-crear-usuario/index.ts
// ----------------------------------------------------------------------------
// Crea un usuario de la plataforma desde la sesion del ADMINISTRADOR
// (/dashboard/admin/perfiles-roles). Pensado para dar de alta a los perfiles
// de taller (jefe_mantenimiento / operador_taller) sin salir de la app.
//
// Flujo:
//   1. Valida que el caller (JWT del header Authorization) tenga rol
//      'administrador' en usuarios_perfil.
//   2. Crea el usuario en auth (email confirmado, password inicial) con
//      user_metadata.rol — asi fn_user_rol() resuelve el rol desde el JWT.
//   3. Inserta el perfil en usuarios_perfil (id, email, nombre, rol, cargo).
//   4. (Opcional) Vincula la cuenta a un tecnico del catalogo taller_tecnicos
//      (usuario_perfil_id) para que el operador vea las OTs de su cuadrilla.
//   Si (3) falla se elimina el usuario auth creado (sin usuarios huerfanos).
//
// Variables de entorno (Supabase las setea automaticamente):
//   - SUPABASE_URL
//   - SUPABASE_SERVICE_ROLE_KEY
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

const ROLES_VALIDOS = [
  "administrador", "gerencia", "subgerente_operaciones", "supervisor",
  "planificador", "tecnico_mantenimiento", "bodeguero", "operador_abastecimiento",
  "auditor", "rrhh_incentivos", "jefe_operaciones", "jefe_mantenimiento",
  "comercial", "prevencionista", "colaborador", "auditor_calidad",
  "operador_taller",
];

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json(405, { error: "Solo POST" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    return json(500, { error: "Faltan SUPABASE_URL / SERVICE_ROLE_KEY" });
  }
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // ── 1. Autenticar y autorizar al caller ────────────────────────────────────
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return json(401, { error: "No autenticado" });

  const { data: caller, error: callerErr } = await admin.auth.getUser(jwt);
  if (callerErr || !caller?.user) return json(401, { error: "Sesión inválida" });

  const { data: perfilCaller } = await admin
    .from("usuarios_perfil")
    .select("rol, activo")
    .eq("id", caller.user.id)
    .maybeSingle();
  if (perfilCaller?.rol !== "administrador" || perfilCaller?.activo === false) {
    return json(403, { error: "Solo el administrador puede crear usuarios" });
  }

  // ── 2. Validar payload ──────────────────────────────────────────────────────
  let body: {
    email?: string; password?: string; nombre_completo?: string;
    rol?: string; cargo?: string | null; tecnico_id?: string | null;
  };
  try { body = await req.json(); } catch { return json(400, { error: "Body JSON inválido" }); }

  const email = (body.email ?? "").trim().toLowerCase();
  const password = body.password ?? "";
  const nombre = (body.nombre_completo ?? "").trim();
  const rol = (body.rol ?? "").trim();

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json(400, { error: "Correo inválido" });
  if (password.length < 6) return json(400, { error: "La contraseña debe tener al menos 6 caracteres" });
  if (!nombre) return json(400, { error: "El nombre completo es obligatorio" });
  if (!ROLES_VALIDOS.includes(rol)) return json(400, { error: `Rol inválido: ${rol}` });

  // ── 3. Crear usuario auth (email confirmado, sin correo de invitación) ─────
  const { data: created, error: createErr } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { nombre_completo: nombre, rol },
  });
  if (createErr || !created?.user) {
    const msg = createErr?.message ?? "No se pudo crear el usuario";
    const dup = /already|registered|exists/i.test(msg);
    return json(dup ? 409 : 500, { error: dup ? `Ya existe un usuario con el correo ${email}` : msg });
  }
  const userId = created.user.id;

  // ── 4. Perfil de la plataforma ──────────────────────────────────────────────
  const { error: perfilErr } = await admin.from("usuarios_perfil").insert({
    id: userId,
    email,
    nombre_completo: nombre,
    rol,
    cargo: body.cargo?.trim() || null,
    activo: true,
  });
  if (perfilErr) {
    // rollback: no dejar usuario auth sin perfil
    await admin.auth.admin.deleteUser(userId).catch(() => undefined);
    return json(500, { error: `No se pudo crear el perfil: ${perfilErr.message}` });
  }

  // ── 5. Vincular al catálogo de técnicos de taller (opcional) ────────────────
  let tecnicoVinculado: string | null = null;
  if (body.tecnico_id) {
    const { data: tec, error: tecErr } = await admin
      .from("taller_tecnicos")
      .update({ usuario_perfil_id: userId, updated_at: new Date().toISOString() })
      .eq("id", body.tecnico_id)
      .is("usuario_perfil_id", null)
      .select("nombre")
      .maybeSingle();
    if (tecErr || !tec) {
      // No es fatal: el usuario queda creado; se informa el problema del vínculo.
      return json(201, {
        ok: true, user_id: userId,
        warning: "Usuario creado, pero el técnico no se pudo vincular (¿ya tiene cuenta vinculada?)",
      });
    }
    tecnicoVinculado = tec.nombre;
  }

  return json(201, { ok: true, user_id: userId, tecnico_vinculado: tecnicoVinculado });
});
