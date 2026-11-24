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

  const { data: target, error: targetError } = await admin.from("profiles")
    .select("id,employee_number,role,can_manage_admins")
    .eq("employee_number", employeeNumber).maybeSingle();
  if (targetError || !target || target.role !== "admin") {
    return reply({ error: "No se encontró esa cuenta administrativa." }, 404, allowedOrigin);
  }
  if (target.id === actor.id) {
    return reply({ error: "Por seguridad, no puedes modificar tu propio permiso de delegación." }, 400, allowedOrigin);
  }
  if (target.can_manage_admins === input.canManageAdmins) {
    return reply({ message: "El permiso ya tenía ese valor.", employeeNumber }, 200, allowedOrigin);
  }

  const { error: updateError } = await admin.from("profiles")
    .update({ can_manage_admins: input.canManageAdmins }).eq("id", target.id);
  if (updateError) return reply({ error: "No se pudo actualizar el permiso." }, 500, allowedOrigin);

  const { error: auditError } = await admin.from("audit_log").insert({
    actor_id: actor.id,
    action: "admin_delegation_permission_changed",
    entity_type: "profile",
    entity_id: target.id,
    details: {
      employee_number: target.employee_number,
      previous_value: target.can_manage_admins,
      new_value: input.canManageAdmins,
    },
  });
  if (auditError) return reply({ error: "El permiso cambió, pero no se pudo completar la auditoría. Requiere revisión administrativa." }, 500, allowedOrigin);

  return reply({ message: "Permiso administrativo actualizado.", employeeNumber, canManageAdmins: input.canManageAdmins }, 200, allowedOrigin);
});
