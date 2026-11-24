const profiles = {
  admin:{name:"Administración",role:"Administrador",department:"Administración",initials:"AD",views:["inicio","comunicados","conversaciones","turnos","equipos","incidencias","personal","ajustes"],departments:["Landscaping","Cleaning"],admin:true},
  "manager-land":{name:"Gerencia",role:"Gerencia",department:"Landscaping",initials:"GE",views:["inicio","comunicados","conversaciones","turnos","equipos","incidencias"],departments:["Landscaping"]},
  "manager-clean":{name:"Gerencia",role:"Gerencia",department:"Cleaning",initials:"GE",views:["inicio","comunicados","conversaciones","turnos","equipos","incidencias"],departments:["Cleaning"]},
  "super-land":{name:"Supervisor",role:"Supervisor",department:"Landscaping",initials:"SU",views:["inicio","comunicados","conversaciones","turnos","equipos","incidencias"],departments:["Landscaping"]},
  "super-clean":{name:"Supervisor",role:"Supervisor",department:"Cleaning",initials:"SU",views:["inicio","comunicados","conversaciones","turnos","equipos","incidencias"],departments:["Cleaning"]},
  "employee-land":{name:"Empleado",role:"Empleado",department:"Landscaping",initials:"EM",views:["inicio","comunicados","conversaciones","turnos","equipos"],departments:["Landscaping"]},
  "employee-clean":{name:"Empleado",role:"Empleado",department:"Cleaning",initials:"EM",views:["inicio","comunicados","conversaciones","turnos","equipos"],departments:["Cleaning"]},
  hybrid:{name:"Empleado autorizado",role:"Empleado",department:"Landscaping + Cleaning",initials:"EA",views:["inicio","comunicados","conversaciones","turnos","equipos"],departments:["Landscaping","Cleaning"],hybrid:true}
};
let activeProfile = profiles.admin;
let currentView = "inicio";
const $ = (id)=>document.getElementById(id);
const labels = {inicio:"Resumen de actividad",comunicados:"Comunicados oficiales",conversaciones:"Conversaciones del personal",turnos:"Turnos y horarios",equipos:"Equipos de trabajo",incidencias:"Incidencias",personal:"Administración de personal",ajustes:"Configuración del portal"};
const today = new Intl.DateTimeFormat("es-US",{weekday:"long",month:"long",day:"numeric"}).format(new Date());
$("today-label").textContent=today.toLocaleUpperCase("es-US");
function setProfile(key){
  activeProfile=profiles[key]||profiles.admin;
  currentView="inicio";
  $("user-name").textContent=activeProfile.name;
  $("user-role").textContent=activeProfile.role;
  $("user-avatar").textContent=activeProfile.initials;
  $("profile-button").textContent=activeProfile.initials;
  $("department-label").textContent=activeProfile.department;
  $("mobile-department").textContent=activeProfile.department;
  $("mobile-role").textContent=activeProfile.role;
  $("greeting").textContent="Bienvenido, "+activeProfile.name;
  $("welcome-copy").textContent=activeProfile.admin?"Administra las operaciones y mantén todo Prestige organizado.":"Este es el espacio de trabajo de "+activeProfile.department+".";
  document.querySelectorAll(".admin-only").forEach(el=>el.hidden=!activeProfile.admin);
  document.querySelectorAll(".nav-link").forEach(el=>el.hidden=!activeProfile.views.includes(el.dataset.view));
  render();
}
function nav(view){
  if(!activeProfile.views.includes(view))return;
  currentView=view;
  document.querySelectorAll(".nav-link").forEach(el=>el.classList.toggle("active",el.dataset.view===view));
  render();
}
function header(title,desc,action=""){return `<div class="section-head"><div><h2>${title}</h2><p class="muted">${desc}</p></div>${action}</div>`;}
function render(){
  document.querySelectorAll(".nav-link").forEach(el=>el.classList.toggle("active",el.dataset.view===currentView));
  const d=activeProfile.department;
  let html="";
  if(currentView==="inicio"){
    html=header("Resumen de actividad","Información correspondiente a "+d+".")+
    `<div class="stats"><div class="stat-card"><small>Personal asignado</small><strong>—</strong><span>Datos por conectar</span></div><div class="stat-card"><small>Turnos de hoy</small><strong>—</strong><span>Datos por conectar</span></div><div class="stat-card"><small>Incidencias abiertas</small><strong>—</strong><span>Datos por conectar</span></div></div>
    <div class="dashboard-grid"><div class="panel"><h3>Actividad reciente</h3><div class="empty-state">Aquí aparecerán las actualizaciones de tu departamento.</div></div><div class="panel"><h3>Accesos rápidos</h3><div class="list-row"><span>Comunicados oficiales<small>Información publicada por Administración</small></span><span class="tag">Abrir</span></div><div class="list-row"><span>Turnos y horarios<small>Consulta tu jornada</small></span><span class="tag">Abrir</span></div><div class="list-row"><span>Incidencias<small>Reportes del equipo</small></span><span class="tag">Abrir</span></div></div></div>
    <div class="notice"><strong>Separación de departamentos:</strong> tu panel muestra únicamente la información de ${d}. El acceso a ambos departamentos se reserva a las asignaciones dobles autorizadas por Administración.</div>`;
  } else if(currentView==="comunicados"){
    html=header("Comunicados oficiales","Avisos formales publicados por Administración.",activeProfile.admin?'<button class="primary-button" data-action="new-announcement">+ Nuevo comunicado</button>':"")+
    '<div class="panel"><h3>Comunicados de '+d+'</h3><div class="empty-state">Todavía no hay comunicados publicados. Los avisos oficiales aparecerán aquí, separados de las conversaciones del personal.</div></div>';
  } else if(currentView==="conversaciones"){
    html=header("Conversaciones","Espacio de participación del personal de "+d+".",'<button class="primary-button" data-action="new-conversation">+ Nueva conversación</button>')+
    '<div class="panel"><h3>Conversaciones del departamento</h3><div class="empty-state">Aún no hay conversaciones. Este espacio será independiente de los comunicados oficiales.</div></div>';
  } else if(currentView==="turnos"){
    html=header("Turnos y horarios","Consulta y administra los horarios de "+d+".")+
    '<div class="panel"><h3>Programación</h3><div class="empty-state">Los turnos y sus identificadores únicos aparecerán aquí cuando conectemos la base de datos.</div></div>';
  } else if(currentView==="equipos"){
    html=header("Equipos de trabajo","Organización de los equipos de "+d+".")+
    '<div class="panel"><h3>Equipos activos</h3><div class="empty-state">Todavía no hay equipos registrados.</div></div>';
  } else if(currentView==="incidencias"){
    html=header("Incidencias","Registro e historial de situaciones durante los servicios.",'<button class="primary-button" data-action="new-incident">+ Registrar incidencia</button>')+
    '<div class="panel"><h3>Historial de incidencias · '+d+'</h3><div class="empty-state">No hay incidencias registradas. Los reportes deberán notificar a Gerencia y Administración.</div></div>';
  } else if(currentView==="personal"){
    html=header("Administración de personal","Gestiona empleados, roles y departamentos.")+
    '<div class="notice">Solo Administración puede asignar departamentos y autorizar una asignación doble. Cada autorización quedará registrada y definirá los accesos del empleado.</div><div class="panel" style="margin-top:15px"><h3>Directorio de empleados</h3><div class="empty-state">El directorio estará disponible al conectar el servicio seguro de autenticación y datos.</div></div>';
  } else if(currentView==="ajustes"){
    html=header("Configuración","Preferencias generales del portal Prestige.")+
    '<div class="feature-grid"><article class="feature-card"><div class="feature-icon">◈</div><h3>Identidad de Prestige</h3><p>Logotipo tipográfico inicial. Administración podrá incorporar o cambiar el logotipo gráfico en el futuro.</p></article><article class="feature-card"><div class="feature-icon">⌘</div><h3>Accesos y permisos</h3><p>Roles, departamentos y autorizaciones administrados de forma centralizada.</p></article><article class="feature-card"><div class="feature-icon">⇧</div><h3>Aplicación instalable</h3><p>Preparada como aplicación web progresiva (PWA).</p></article><article class="feature-card"><div class="feature-icon">◌</div><h3>Modo sin conexión</h3><p>La estructura de la aplicación podrá abrirse sin internet. La sincronización de datos requiere un servidor.</p></article></div>';
  }
  $("view-container").innerHTML=html;
}
document.addEventListener("click",e=>{
  const navButton=e.target.closest("[data-view]");
  if(navButton){nav(navButton.dataset.view);return;}
  const action=e.target.closest("[data-action]");
  if(action){alert("Esta función se habilitará al conectar el backend seguro. Esta versión es una demostración de interfaz.");}
});
$("profile-button").addEventListener("click",()=>$("demo-dialog").showModal());
$("switch-department").addEventListener("click",()=>$("demo-dialog").showModal());
$("apply-profile").addEventListener("click",()=>setProfile($("demo-profile").value));
function updateConnection(){
  const online=navigator.onLine;
  $("connection-status").classList.toggle("offline",!online);
  $("connection-status").innerHTML='<i></i> '+(online?"En línea":"Sin conexión");
}
window.addEventListener("online",updateConnection);
window.addEventListener("offline",updateConnection);
updateConnection();
setProfile("admin");
if("serviceWorker" in navigator && location.protocol!=="file:"){
  window.addEventListener("load",()=>navigator.serviceWorker.register("./sw.js").catch(err=>console.warn("PWA no disponible:",err)));
}
