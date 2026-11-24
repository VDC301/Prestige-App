const SUPABASE_URL = "https://kscrpzpxczeaodpvqibu.supabase.co";
const SUPABASE_PUBLIC_KEY = "sb_publishable_ZdIpq_JrIxj8MgoyM7w_2g_IeqsnNE2";
const supabase = window.supabase?.createClient(SUPABASE_URL, SUPABASE_PUBLIC_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
});

const $ = (id) => document.getElementById(id);
const labels = {
  inicio:"Resumen de actividad", comunicados:"Comunicados oficiales",
  conversaciones:"Conversaciones del personal", turnos:"Turnos y horarios",
  equipos:"Equipos de trabajo", incidencias:"Incidencias",
  personal:"Administración de personal", ajustes:"Configuración del portal"
};
const roleNames = {admin:"Administración",manager:"Gerencia",supervisor:"Supervisor",employee:"Empleado"};
let currentUser = null;
let activeProfile = null;
let currentView = "inicio";
let directory = [];

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, ch => ({
    "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"
  })[ch]);
}
function initials(name) {
  return String(name || "P").trim().split(/\s+/).slice(0,2).map(x=>x[0]).join("").toUpperCase();
}
function departmentsLabel(departments) {
  return departments?.length ? departments.map(d=>d.name).join(" + ") : "Administración";
}
function allowedViews(profile) {
  if(profile.role==="admin") return ["inicio","comunicados","conversaciones","turnos","equipos","incidencias","personal","ajustes"];
  if(profile.role==="manager") return ["inicio","comunicados","conversaciones","turnos","equipos","incidencias"];
  if(profile.role==="supervisor") return ["inicio","comunicados","conversaciones","turnos","equipos","incidencias"];
  return ["inicio","comunicados","conversaciones","turnos","equipos"];
}

async function loadProfile() {
  const {data,error} = await supabase.rpc("get_my_profile");
  if(error || !data || !data.is_active) throw new Error("No se pudo verificar tu perfil. Contacta a Administración.");
  currentUser = data;
  activeProfile = {
    ...data,
    name:data.display_name,
    roleLabel:roleNames[data.role] || "Usuario",
    department:departmentsLabel(data.departments),
    initials:initials(data.display_name),
    admin:data.role==="admin",
    views:allowedViews(data),
    departments:data.departments || []
  };
  if(!activeProfile.admin && activeProfile.departments.length===0) {
    await supabase.auth.signOut();
    throw new Error("Tu cuenta todavía no tiene un departamento asignado. Contacta a Administración.");
  }
  $("login-screen").hidden=true;
  $("app-shell").hidden=false;
  $("user-name").textContent=activeProfile.name;
  $("user-role").textContent=activeProfile.roleLabel+" · "+data.employee_number;
  $("user-avatar").textContent=activeProfile.initials;
  $("profile-button").textContent=activeProfile.initials;
  $("department-label").textContent=activeProfile.department;
  $("mobile-department").textContent=activeProfile.department;
  $("mobile-role").textContent=activeProfile.roleLabel;
  $("greeting").textContent="Bienvenido, "+activeProfile.name;
  $("welcome-copy").textContent=activeProfile.admin
    ?"Administra las operaciones y mantén todo Prestige organizado."
    :"Este es tu espacio de trabajo de "+activeProfile.department+".";
  $("session-pill").textContent="Sesión segura · "+data.employee_number;
  document.querySelectorAll(".nav-link").forEach(el=>{
    el.hidden=!activeProfile.views.includes(el.dataset.view);
  });
  currentView="inicio";
  render();
  updateConnection();
}

function header(title,desc,action="") {
  return `<div class="section-head"><div><h2>${title}</h2><p class="muted">${desc}</p></div>${action}</div>`;
}
function panel(title,body) {
  return `<div class="panel"><h3>${title}</h3>${body}</div>`;
}
function render() {
  if(!activeProfile) return;
  document.querySelectorAll(".nav-link").forEach(el=>el.classList.toggle("active",el.dataset.view===currentView));
  const d=escapeHtml(activeProfile.department);
  let html="";
  if(currentView==="inicio") {
    html=header("Resumen de actividad","Información correspondiente a "+d+".")+
    `<div class="stats"><div class="stat-card"><small>Personal asignado</small><strong>—</strong><span>Conexión de datos en preparación</span></div><div class="stat-card"><small>Turnos de hoy</small><strong>—</strong><span>Conexión de datos en preparación</span></div><div class="stat-card"><small>Incidencias abiertas</small><strong>—</strong><span>Conexión de datos en preparación</span></div></div>
    <div class="dashboard-grid">${panel("Actividad reciente",'<div class="empty-state">Aquí aparecerán las actualizaciones de tu departamento.</div>')}${panel("Accesos rápidos",'<div class="list-row">Comunicados oficiales</div><div class="list-row">Turnos y horarios</div><div class="list-row">Incidencias</div>')}</div>
    <div class="notice"><strong>Separación de departamentos:</strong> tu panel muestra únicamente la información de ${d}. El acceso a ambos departamentos requiere autorización de Administración.</div>`;
  } else if(currentView==="comunicados") {
    html=header("Comunicados oficiales","Avisos formales publicados por Administración.")+
      panel("Comunicados de "+d,'<div class="empty-state">Los comunicados oficiales aparecerán aquí, separados de las conversaciones del personal.</div>');
  } else if(currentView==="conversaciones") {
    html=header("Conversaciones","Espacio de participación del personal de "+d,'<button class="primary-button" data-action="new-conversation">+ Nueva conversación</button>')+
      panel("Conversaciones del departamento",'<div class="empty-state">Las conversaciones del equipo aparecerán aquí.</div>');
  } else if(currentView==="turnos") {
    html=header("Turnos y horarios","Consulta y administra los horarios de "+d)+
      panel("Programación",'<div class="empty-state">Los turnos y sus identificadores únicos aparecerán aquí.</div>');
  } else if(currentView==="equipos") {
    html=header("Equipos de trabajo","Organización de los equipos de "+d)+
      panel("Equipos activos",'<div class="empty-state">Los equipos registrados aparecerán aquí.</div>');
  } else if(currentView==="incidencias") {
    html=header("Incidencias","Registro e historial de situaciones durante los servicios.",'<button class="primary-button" data-action="new-incident">+ Registrar incidencia</button>')+
      panel("Historial de incidencias · "+d,'<div class="empty-state">Los reportes de trabajo aparecerán aquí.</div>');
  } else if(currentView==="personal" && activeProfile.admin) {
    html=renderPersonal();
  } else if(currentView==="ajustes" && activeProfile.admin) {
    html=header("Configuración","Preferencias generales del portal Prestige.")+
      '<div class="feature-grid"><article class="feature-card"><h3>Identidad de Prestige</h3><p>Logotipo tipográfico inicial. Administración podrá incorporar un logotipo gráfico en el futuro.</p></article><article class="feature-card"><h3>Accesos y permisos</h3><p>Roles, departamentos y autorizaciones administrados de forma centralizada.</p></article><article class="feature-card"><h3>Aplicación instalable</h3><p>Portal preparado como aplicación web progresiva.</p></article><article class="feature-card"><h3>Modo sin conexión</h3><p>La apertura básica puede almacenarse; las operaciones requieren conexión para sincronizarse.</p></article></div>';
  }
  $("view-container").innerHTML=html;
  if(currentView==="personal") loadDirectory();
}

function renderPersonal() {
  const canDelegate=activeProfile.can_manage_admins===true;
  return header("Administración de personal","Crea cuentas, asigna departamentos y administra los accesos.")+
  `<div class="invite-layout">
    <form id="invite-form" class="panel invite-form">
      <h3>Invitar a un empleado</h3>
      <label for="invite-name">Nombre completo</label>
      <input id="invite-name" name="displayName" required maxlength="100" placeholder="Nombre del empleado">
      <label for="invite-email">Correo electrónico</label>
      <input id="invite-email" name="email" type="email" required maxlength="254" placeholder="empleado@correo.com">
      <label for="invite-role">Rol</label>
      <select id="invite-role" name="role" required>
        <option value="employee">Empleado</option><option value="supervisor">Supervisor</option>
        <option value="manager">Gerencia</option><option value="admin" ${canDelegate ? "" : "disabled"}>Administración</option>
      </select>
      <div id="department-fields">
        <label>Departamento principal</label>
        <div class="department-options">
          <label><input type="checkbox" name="department" value="landscaping"> Landscaping</label>
          <label><input type="checkbox" name="department" value="cleaning"> Cleaning</label>
        </div>
        <p class="field-help">Selecciona uno. El segundo departamento solo puede asignarse con autorización y justificación.</p>
        <div id="second-department-reason" hidden>
          <label for="invite-reason">Justificación de la segunda asignación</label>
          <textarea id="invite-reason" maxlength="1000" placeholder="Explica por qué necesita acceso a ambos departamentos."></textarea>
        </div>
      </div>
      ${canDelegate ? '<div id="admin-delegation-option" hidden><label class="department-options"><input id="invite-can-manage-admins" type="checkbox"> Autorizar a esta cuenta para crear y administrar otras cuentas administrativas</label><p class="field-help">Esta facultad es independiente del rol de Administración.</p></div>' : ''}
      <p id="invite-feedback" role="status" hidden></p>
      <button class="primary-button full" type="submit" id="invite-submit">Enviar invitación</button>
    </form>
    <div class="panel">
      <h3>Reglas de acceso</h3>
      <div class="list-row"><span>Empleado<small>Acceso a su departamento asignado.</small></span></div>
      <div class="list-row"><span>Supervisor<small>Herramientas operativas e incidencias de su departamento.</small></span></div>
      <div class="list-row"><span>Gerencia<small>Supervisión limitada a sus departamentos.</small></span></div>
      <div class="list-row"><span>Administración<small>Acceso global; delegación administrativa controlada.</small></span></div>
      <div class="notice" style="margin-top:14px">Cada invitación genera un número automático y un registro de auditoría.</div>
    </div>
  </div>
  ${canDelegate ? `<div class="panel" style="margin-top:16px">
    <h3>Permisos de Administración</h3>
    <p class="muted">Concede o retira la facultad de crear y administrar otras cuentas administrativas. No cambia el rol de la persona.</p>
    <form id="admin-delegation-form" class="inline-form">
      <label for="admin-target-number">Número de empleado administrativo</label>
      <input id="admin-target-number" name="employeeNumber" required maxlength="32" pattern="ADM-[0-9]{3,}" placeholder="ADM-001">
      <label class="department-options"><input id="admin-target-permission" type="checkbox"> Autorizar administración de otras cuentas</label>
      <p id="admin-delegation-feedback" role="status" hidden></p>
      <button class="primary-button" type="submit" id="admin-delegation-submit">Guardar permiso</button>
    </form>
  </div>` : ""}
  <div class="panel" style="margin-top:16px"><h3>Directorio de empleados</h3><div id="directory-list"><div class="empty-state">Cargando directorio…</div></div></div>`;
}

async function loadDirectory() {
  const target=$("directory-list");
  if(!target) return;
  const {data,error}=await supabase.from("employee_directory")
    .select("id,display_name,role,is_active").order("display_name");
  if(error) {
    target.innerHTML='<div class="empty-state">No se pudo cargar el directorio con los permisos actuales.</div>';
    return;
  }
  directory=data||[];
  if(!directory.length) {
    target.innerHTML='<div class="empty-state">Todavía no hay empleados registrados.</div>';
    return;
  }
  target.innerHTML=directory.map(person=>`<div class="employee-row"><span><strong>${escapeHtml(person.display_name)}</strong><small>${escapeHtml(roleNames[person.role]||person.role)}</small></span><span class="tag">${person.is_active?"Activo":"Inactivo"}</span></div>`).join("");
}

function showFeedback(id,message,type="error") {
  const el=$(id);
  if(!el)return;
  el.textContent=message;
  el.className=type==="success"?"form-success":"form-error";
  el.hidden=false;
}
function nav(view) {
  if(!activeProfile?.views.includes(view)) return;
  currentView=view;
  render();
}
document.addEventListener("click",event=>{
  const navButton=event.target.closest("[data-view]");
  if(navButton){nav(navButton.dataset.view);return;}
  const action=event.target.closest("[data-action]");
  if(action) {
    alert("Este módulo se conectará a la base de datos en la siguiente etapa.");
  }
});

$("login-form").addEventListener("submit",async event=>{
  event.preventDefault();
  const button=$("login-submit");
  const error=$("login-error");
  error.hidden=true;
  button.disabled=true;
  button.textContent="Verificando…";
  const employeeNumber=$("employee-number").value.trim().toUpperCase();
  const password=$("employee-password").value;
  try {
    const {data,error:loginError}=await supabase.functions.invoke("employee-login",{
      body:{employeeNumber,password}
    });
    if(loginError || !data?.access_token || !data?.refresh_token) {
      throw new Error("Número de empleado o contraseña incorrectos, o servicio de acceso no disponible.");
    }
    const {error:sessionError}=await supabase.auth.setSession({
      access_token:data.access_token,refresh_token:data.refresh_token
    });
    if(sessionError) throw sessionError;
    await loadProfile();
  } catch(err) {
    error.textContent=err.message==="Failed to fetch"
      ?"No se pudo conectar. Comprueba tu conexión e inténtalo de nuevo."
      :(err.message||"No se pudo iniciar sesión.");
    error.hidden=false;
    await supabase.auth.signOut();
  } finally {
    button.disabled=false;
    button.textContent="Iniciar sesión";
  }
});

document.addEventListener("change",event=>{
  if(event.target.id==="invite-role") {
    const isAdmin=event.target.value==="admin";
    $("department-fields").hidden=isAdmin;
    const delegation=$("admin-delegation-option");
    if(delegation) delegation.hidden=!isAdmin;
  }
  if(event.target.matches('input[name="department"]')) {
    const selected=[...document.querySelectorAll('input[name="department"]:checked')];
    $("second-department-reason").hidden=selected.length<2;
  }
});

document.addEventListener("submit",async event=>{
  if(event.target.id==="admin-delegation-form") {
    event.preventDefault();
    const form=event.target;
    const button=$("admin-delegation-submit");
    button.disabled=true;
    button.textContent="Guardando…";
    $("admin-delegation-feedback").hidden=true;
    try {
      const {data,error}=await supabase.functions.invoke("manage-admin-delegation",{
        body:{
          employeeNumber:$("admin-target-number").value.trim().toUpperCase(),
          canManageAdmins:$("admin-target-permission").checked
        }
      });
      if(error) throw new Error(data?.error||"No se pudo actualizar el permiso.");
      showFeedback("admin-delegation-feedback",data.message||"Permiso actualizado.","success");
      form.reset();
    } catch(err) {
      showFeedback("admin-delegation-feedback",err.message||"No se pudo actualizar el permiso.");
    } finally {
      button.disabled=false;
      button.textContent="Guardar permiso";
    }
    return;
  }
  if(event.target.id!=="invite-form")return;
  event.preventDefault();
  const form=event.target;
  const button=$("invite-submit");
  button.disabled=true;
  button.textContent="Enviando…";
  $("invite-feedback").hidden=true;
  const role=$("invite-role").value;
  const departmentCodes=role==="admin"?[]:[...form.querySelectorAll('input[name="department"]:checked')].map(el=>el.value);
  const payload={
    displayName:$("invite-name").value.trim(),
    email:$("invite-email").value.trim(),
    role,
    departmentCodes,
    secondDepartmentReason:$("invite-reason")?.value.trim()||"",
    canManageAdmins:$("invite-can-manage-admins")?.checked===true
  };
  try {
    const {data,error}=await supabase.functions.invoke("create-employee-invitation",{body:payload});
    if(error) throw new Error(data?.error||"No se pudo enviar la invitación. Comprueba el servicio.");
    showFeedback("invite-feedback",`Invitación enviada. Número asignado: ${data.employeeNumber}. La persona recibirá un correo para activar su cuenta.`,"success");
    form.reset();
    $("department-fields").hidden=false;
    $("second-department-reason").hidden=true;
    if($("admin-delegation-option")) $("admin-delegation-option").hidden=true;
    await loadDirectory();
  } catch(err) {
    showFeedback("invite-feedback",err.message||"No se pudo completar la invitación.");
  } finally {
    button.disabled=false;
    button.textContent="Enviar invitación";
  }
});

$("profile-button").addEventListener("click",async()=>{
  if(confirm("¿Quieres cerrar tu sesión de Prestige?")) {
    await supabase.auth.signOut();
    activeProfile=null;
    currentUser=null;
    $("app-shell").hidden=true;
    $("login-screen").hidden=false;
    $("login-form").reset();
  }
});

function updateConnection() {
  const online=navigator.onLine;
  $("connection-status").classList.toggle("offline",!online);
  $("connection-status").innerHTML='<i></i> '+(online?"En línea":"Sin conexión");
}
window.addEventListener("online",updateConnection);
window.addEventListener("offline",updateConnection);
updateConnection();
$("today-label").textContent=new Intl.DateTimeFormat("es-US",{weekday:"long",month:"long",day:"numeric"}).format(new Date()).toLocaleUpperCase("es-US");

(async()=>{
  if(!window.supabase) {
    $("login-error").textContent="No se pudo cargar el servicio de acceso. Recarga la página.";
    $("login-error").hidden=false;
    return;
  }
  const {data}=await supabase.auth.getSession();
  if(data.session) {
    try { await loadProfile(); }
    catch(error) {
      $("app-shell").hidden=true;
      $("login-screen").hidden=false;
      $("login-error").textContent=error.message;
      $("login-error").hidden=false;
      await supabase.auth.signOut();
    }
  }
})();

if("serviceWorker" in navigator && location.protocol!=="file:") {
  window.addEventListener("load",()=>navigator.serviceWorker.register("./sw.js").catch(err=>console.warn("PWA no disponible:",err)));
}
