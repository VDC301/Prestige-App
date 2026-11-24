import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": Deno.env.get("APP_ORIGIN") ?? "https://vdc301.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};
function reply(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}
Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return reply({ error: "Solicitud no válida." }, 405);
  const allowedOrigin = Deno.env.get("APP_ORIGIN");
  const origin = request.headers.get("Origin");
  if (allowedOrigin && origin && origin !== allowedOrigin) return reply({ error: "No autorizado." }, 403);

  let input: { employeeNumber?: unknown; password?: unknown };
  try { input = await request.json(); } catch { return reply({ error: "Solicitud no válida." }, 400); }
  const employeeNumber = typeof input.employeeNumber === "string" ? input.employeeNumber.trim().toUpperCase() : "";
  const password = typeof input.password === "string" ? input.password : "";
  if (!/^[A-Z0-9-]{2,32}$/.test(employeeNumber) || password.length < 1 || password.length > 256) {
    return reply({ error: "Número de empleado o contraseña incorrectos." }, 400);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !serviceKey || !anonKey) return reply({ error: "El servicio de acceso no está configurado." }, 503);

  const admin = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const auth = createClient(url, anonKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const { data: profile, error: lookupError } = await admin.from("profiles")
    .select("id,is_active").eq("employee_number", employeeNumber).maybeSingle();
  if (lookupError || !profile || !profile.is_active) {
    return reply({ error: "Número de empleado o contraseña incorrectos." }, 401);
  }
  const { data: userData, error: userError } = await admin.auth.admin.getUserById(profile.id);
  const email = userData.user?.email;
  if (userError || !email) return reply({ error: "Número de empleado o contraseña incorrectos." }, 401);

  const { data, error } = await auth.auth.signInWithPassword({ email, password });
  if (error || !data.session) return reply({ error: "Número de empleado o contraseña incorrectos." }, 401);
  return reply({
    access_token: data.session.access_token,
    refresh_token: data.session.refresh_token,
    expires_at: data.session.expires_at,
    token_type: data.session.token_type,
    user: { id: data.user.id },
  });
});
