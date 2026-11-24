import { createClient } from "npm:@supabase/supabase-js@2";

const reply = (body: unknown, status: number, origin: string) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Vary": "Origin",
    },
  });

Deno.serve(async (request: Request) => {
  const allowedOrigin = Deno.env.get("APP_ORIGIN");
  const origin = request.headers.get("Origin") ?? "";
  if (!allowedOrigin) return new Response("Service unavailable", { status: 503 });
  if (origin && origin !== allowedOrigin) return new Response("Forbidden", { status: 403 });
  if (request.method === "OPTIONS") return new Response("ok", {
    headers: {
      "Access-Control-Allow-Origin": allowedOrigin,
      "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Vary": "Origin",
    },
  });
  if (request.method !== "POST") return reply({ error: "Método no permitido." }, 405, allowedOrigin);

  const bearer = request.headers.get("Authorization") ?? "";
  const token = bearer.startsWith("Bearer ") ? bearer.slice(7) : "";
  if (!token) return reply({ error: "Sesión requerida." }, 401, allowedOrigin);

  let input: { employeeNumber?: unknown; canManageAdmins?: unknown };
  try { input = await request.json(); }
  catch { return reply({ error: "Solicitud no válida." }, 400, allowedOrigin); }
  const employeeNumber = typeof input.employeeNumber === "string"
    ? input.employeeNumber.trim().toUpperCase() : "";
  if (!/^ADM-[0-9]{3,}$/.test(employeeNumber) || typeof input.canManageAdmins !== "boolean") {
    return reply({ error: "Indica una cuenta ADM válida y el permiso que deseas establecer." }, 400, allowedOrigin);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) return reply({ error: "El servicio no está configurado." }, 503, allowedOrigin);

  const auth = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authData, error: authError } = await auth.auth.getUser(token);
  if (authError || !authData.user) return reply({ error: "La sesión no es válida." }, 401, allowedOrigin);

  const { data: actor, error: actorError } = await admin.from("profiles")
    .select("id,role,is_active,can_manage_admins,employee_number")
    .eq("id", authData.user.id).maybeSingle();
  if (actorError || !actor || actor.role !== "admin" || !actor.is_active || actor.can_manage_admins !== true) {
    return reply({ error: "No tienes autorización para modificar permisos administrativos." }, 403, allowedOrigin);
  }

  const { data: result, error: permissionError } = await admin.rpc("set_admin_delegation_permission", {
    p_actor_id: actor.id,
    p_target_employee_number: employeeNumber,
    p_grant_permission: input.canManageAdmins,
  });
  if (permissionError) {
    const message = permissionError.message.includes("not found")
      ? "No se encontró esa cuenta administrativa."
      : permissionError.message.includes("own delegation")
        ? "Por seguridad, no puedes modificar tu propio permiso."
        : "No se pudo validar o actualizar el permiso administrativo.";
    return reply({ error: message }, 400, allowedOrigin);
  }

  return reply({
    message: result?.changed ? "Permiso administrativo actualizado." : "El permiso ya tenía ese valor.",
    employeeNumber,
    canManageAdmins: result?.can_manage_admins,
  }, 200, allowedOrigin);
});
