import { createClient } from "npm:@supabase/supabase-js@2";

type AppRole = "admin" | "manager" | "supervisor" | "employee";
const jsonHeaders = { "Content-Type": "application/json", "Vary": "Origin" };

function response(body: unknown, status = 200, origin = "") {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...jsonHeaders, ...(origin ? { "Access-Control-Allow-Origin": origin } : {}) },
  });
}

Deno.serve(async (request: Request) => {
  const allowedOrigin = Deno.env.get("APP_ORIGIN");
  const origin = request.headers.get("Origin") ?? "";
  if (!allowedOrigin) return response({ error: "El servicio no está configurado." }, 503);
  if (origin && origin !== allowedOrigin) return response({ error: "Origen no autorizado." }, 403);

  const cors = {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (request.method !== "POST") return response({ error: "Método no permitido." }, 405, allowedOrigin);

  const authorization = request.headers.get("Authorization") ?? "";
  const token = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
  if (!token) return response({ error: "Sesión requerida." }, 401, allowedOrigin);

  let input: {
    email?: unknown;
    displayName?: unknown;
    role?: unknown;
    departmentCodes?: unknown;
    secondDepartmentReason?: unknown;
    canManageAdmins?: unknown;
  };
  try { input = await request.json(); }
  catch { return response({ error: "Solicitud no válida." }, 400, allowedOrigin); }

  const email = typeof input.email === "string" ? input.email.trim().toLowerCase() : "";
  const displayName = typeof input.displayName === "string" ? input.displayName.trim() : "";
  const roleValue = typeof input.role === "string" ? input.role : "";
  const allowedRoles: AppRole[] = ["admin", "manager", "supervisor", "employee"];
  if (!allowedRoles.includes(roleValue as AppRole)) {
    return response({ error: "El rol seleccionado no es válido." }, 400, allowedOrigin);
  }
  const role = roleValue as AppRole;
  const departmentCodes = Array.isArray(input.departmentCodes)
    ? [...new Set(input.departmentCodes.filter((v): v is string => typeof v === "string"))]
    : [];
  const secondDepartmentReason = typeof input.secondDepartmentReason === "string"
    ? input.secondDepartmentReason.trim() : "";
  const canManageAdmins = input.canManageAdmins === true;

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254 ||
      displayName.length < 1 || displayName.length > 100) {
    return response({ error: "Revisa el nombre y el correo electrónico." }, 400, allowedOrigin);
  }
  if (departmentCodes.length > 2 ||
      departmentCodes.some((code) => !["landscaping", "cleaning"].includes(code))) {
    return response({ error: "La selección de departamentos no es válida." }, 400, allowedOrigin);
  }
  if (role === "admin" && departmentCodes.length !== 0) {
    return response({ error: "Las cuentas de Administración no requieren departamento." }, 400, allowedOrigin);
  }
  if (role !== "admin" && departmentCodes.length === 0) {
    return response({ error: "Selecciona al menos un departamento." }, 400, allowedOrigin);
  }
  if (departmentCodes.length === 2 && secondDepartmentReason.length < 8) {
    return response({ error: "La segunda asignación requiere una justificación administrativa." }, 400, allowedOrigin);
  }
  if (secondDepartmentReason.length > 1000) {
    return response({ error: "La justificación es demasiado larga." }, 400, allowedOrigin);
  }
  if (role !== "admin" && canManageAdmins) {
    return response({ error: "Ese permiso solo corresponde a una cuenta administrativa." }, 400, allowedOrigin);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) {
    return response({ error: "El servicio de invitaciones no está configurado." }, 503, allowedOrigin);
  }

  const authClient = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const adminClient = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

  const { data: actorData, error: actorError } = await authClient.auth.getUser(token);
  if (actorError || !actorData.user) return response({ error: "La sesión no es válida." }, 401, allowedOrigin);
  const actorId = actorData.user.id;

  const { data: actor, error: actorProfileError } = await adminClient
    .from("profiles")
    .select("id,role,is_active,can_manage_admins,employee_number")
    .eq("id", actorId).maybeSingle();
  if (actorProfileError || !actor || !actor.is_active || actor.role !== "admin") {
    return response({ error: "No tienes permiso para crear cuentas." }, 403, allowedOrigin);
  }
  if (role === "admin" && actor.can_manage_admins !== true) {
    return response({ error: "Solo un administrador autorizado puede crear cuentas administrativas." }, 403, allowedOrigin);
  }
  if (role === "admin" && canManageAdmins && actor.can_manage_admins !== true) {
    return response({ error: "No puedes conceder este permiso." }, 403, allowedOrigin);
  }

  const { data: numberData, error: numberError } = await adminClient.rpc("next_employee_number", { target_role: role });
  if (numberError || typeof numberData !== "string") {
    return response({ error: "No se pudo generar el número de empleado." }, 500, allowedOrigin);
  }
  const employeeNumber = numberData;

  const { data: invitation, error: invitationError } = await adminClient.auth.admin
    .inviteUserByEmail(email, { data: { display_name: displayName, employee_number: employeeNumber } });
  if (invitationError || !invitation.user) {
    return response({ error: "No se pudo enviar la invitación. Verifica si el correo ya tiene una cuenta." }, 400, allowedOrigin);
  }

  const newUserId = invitation.user.id;
  const { error: profileError } = await adminClient.from("profiles").insert({
    id: newUserId,
    employee_number: employeeNumber,
    display_name: displayName,
    role,
    is_active: true,
    can_manage_admins: role === "admin" && canManageAdmins,
  });
  if (profileError) {
    await adminClient.auth.admin.deleteUser(newUserId);
    return response({ error: "No se pudo completar el perfil; la invitación se revirtió." }, 500, allowedOrigin);
  }

  if (departmentCodes.length) {
    const { data: departments, error: departmentError } = await adminClient.from("departments")
      .select("id,code").in("code", departmentCodes);
    if (departmentError || !departments || departments.length !== departmentCodes.length) {
      await adminClient.from("profiles").delete().eq("id", newUserId);
      await adminClient.auth.admin.deleteUser(newUserId);
      return response({ error: "No se pudieron validar los departamentos; la invitación se revirtió." }, 500, allowedOrigin);
    }
    const assignments = departmentCodes.map((code, index) => ({
      employee_id: newUserId,
      department_id: departments.find((d) => d.code === code)!.id,
      is_primary: index === 0,
      assigned_by: actorId,
      ...(index === 1 ? { authorization_note: secondDepartmentReason } : {}),
    }));
    const { error: assignmentError } = await adminClient.from("employee_departments").insert(assignments);
    if (assignmentError) {
      await adminClient.from("employee_departments").delete().eq("employee_id", newUserId);
      await adminClient.from("profiles").delete().eq("id", newUserId);
      await adminClient.auth.admin.deleteUser(newUserId);
      return response({ error: "No se pudieron guardar las asignaciones; la invitación se revirtió." }, 500, allowedOrigin);
    }
  }

  const { error: auditError } = await adminClient.from("audit_log").insert({
    actor_id: actorId,
    action: "employee_invitation_created",
    entity_type: "profile",
    entity_id: newUserId,
    details: {
      employee_number: employeeNumber,
      role,
      department_codes: departmentCodes,
      can_manage_admins: role === "admin" && canManageAdmins,
      invited_email: email,
    },
  });
  if (auditError) {
    await adminClient.from("employee_departments").delete().eq("employee_id", newUserId);
    await adminClient.from("profiles").delete().eq("id", newUserId);
    await adminClient.auth.admin.deleteUser(newUserId);
    return response({ error: "No se pudo registrar la auditoría; la invitación se revirtió." }, 500, allowedOrigin);
  }

  return response({
    message: "Invitación enviada.",
    employeeNumber,
    displayName,
    role,
    departmentCodes,
    invitationSent: true,
  }, 201, allowedOrigin);
});
