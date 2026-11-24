# Arquitectura y seguridad — Prestige

## Decisiones técnicas
- Frontend: aplicación web progresiva estática, alojable en GitHub Pages.
- Backend previsto: Supabase (PostgreSQL, Auth y Edge Functions).
- Inicio de sesión: cada persona usa su número de empleado y contraseña. El número se resuelve en el servidor a la identidad de Supabase Auth.
- Autorización: Row Level Security (RLS) en PostgreSQL. Ocultar botones en la interfaz no es seguridad.
- Roles: admin, manager, supervisor y employee.
- Departamentos: landscaping y cleaning.
- Una persona tiene un departamento principal. La segunda asignación solo la puede registrar Administración; se conserva quién la autorizó, cuándo y la justificación.
- Comunicados oficiales y conversaciones se guardan en tablas separadas.

## Antes de conectar Supabase
1. Crear el proyecto Supabase de Prestige.
2. Configurar SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY y APP_ORIGIN como secretos de la Edge Function. La clave service-role nunca se publica ni se incluye en el frontend.
3. Revisar y aplicar las migraciones SQL en un proyecto nuevo.
4. Crear la cuenta inicial de Administración por un canal seguro y registrar su perfil con rol admin. Nunca crear una cuenta administrativa desde el navegador público.
5. Crear las cuentas de empleados mediante un proceso administrativo confiable, enlazar cada perfil con auth.users y registrar sus asignaciones.
6. Desplegar la función employee-login.
7. Configurar límites de frecuencia y protección contra abuso, políticas de contraseñas, recuperación segura y monitoreo de Auth antes de uso real.
8. Probar cada política RLS con usuarios de prueba de ambos departamentos y todos los roles.

## Reglas de acceso previstas
- Administración puede administrar todos los departamentos y asignaciones.
- Gerencia y Supervisión ven solamente los departamentos que tienen asignados.
- Empleados ven solamente su departamento asignado.
- Una persona con asignación doble aprobada por Administración puede acceder a ambos departamentos.
- El rol no concede acceso a un departamento por sí solo: también se exige una asignación explícita.
- Los comunicados oficiales solo los publica Administración.
- Las conversaciones y sus comentarios son independientes de los comunicados.
- Los incidentes son visibles dentro del departamento autorizado; su estado solo lo actualizan Administración, Gerencia y Supervisión.
- Los miembros que se agreguen a un equipo deben estar asignados a ese departamento.

## Límites de esta etapa
Estas migraciones y Edge Function son una base de implementación, no una instalación ya conectada. El repositorio no contiene credenciales ni un proyecto Supabase. La interfaz actual todavía es demostrativa; no debe usarse con información real hasta completar despliegue, pruebas de seguridad e integración.

El modo offline de producción requiere almacenamiento local protegido, cola de operaciones, resolución de conflictos y sincronización autorizada. No se almacenarán contraseñas ni tokens de larga duración en cachés del service worker.


## Gestión automatizada de cuentas
- Las altas se procesan en la Edge Function `create-employee-invitation`, que exige JWT y valida que el actor sea un administrador activo.
- Los números de empleado se generan en servidor con contadores bloqueados por prefijo para evitar duplicados concurrentes.
- La invitación de correo usa Supabase Auth Admin; el perfil se enlaza al UUID de Auth. Nunca se insertan usuarios directamente en `auth.users`.
- `can_manage_admins` separa el rol de Administración de la facultad de crear o delegar otras cuentas administrativas. ADM-000 recibe inicialmente esa facultad; los demás administradores no la reciben automáticamente.
- La Edge Function `manage-admin-delegation` permite cambiar la delegación de otro administrador únicamente a quien tenga esa facultad. El cambio y su auditoría se ejecutan dentro de una misma transacción SQL.
- Los clientes autenticados no pueden modificar el rol, el estado activo, el número de empleado ni la delegación administrativa de un perfil.

Estas migraciones y funciones están en la rama de desarrollo. No se han aplicado las migraciones 008–014 al proyecto Supabase ni se han desplegado las funciones nuevas.

## Funciones internas de políticas RLS (migración 012)

Los helpers `is_active_user`, `is_admin`, `has_department_access`,
`can_view_employee` y `can_manage_department` se trasladan al esquema
`private`. Conservan `SECURITY DEFINER` porque consultan perfiles y
asignaciones protegidos por RLS; convertirlos a `SECURITY INVOKER` causaría
recursión o pérdida de visibilidad en las políticas.

El esquema `private` no debe añadirse a los esquemas expuestos por la API
(PostgREST). Se concede únicamente el uso y la ejecución necesarios para que
las políticas RLS puedan evaluar esos helpers. Las funciones dejan de estar
disponibles como RPC dentro del esquema público.

## Configuración pendiente en Supabase Auth

Antes de habilitar el acceso real, activar **Leaked password protection** en
Authentication → Settings → Password Security. La protección comprueba
contraseñas comprometidas y reduce el riesgo de credenciales reutilizadas.

La función `employee-login` aplica un límite adicional de **300 solicitudes
por dirección IP en 15 minutos** antes de consultar el número de empleado.
Usa únicamente el encabezado de IP de origen `CF-Connecting-IP` que añade
Cloudflare; no confía en `X-Forwarded-For` enviado por el cliente. El valor
se transforma mediante HMAC usando la clave service-role, por lo que la tabla
privada conserva una huella y no la dirección IP original. La tabla y su RPC
no son accesibles a los roles públicos; el endpoint público solo expone una
función invoker concedida a service_role.

Si el encabezado de IP no está disponible o falla el control de frecuencia,
el login falla de forma cerrada con HTTP 503; al exceder el límite responde
HTTP 429 con `Retry-After`. Supabase Auth mantiene además sus propios límites
para intentos de contraseña. El umbral IP es compartido por personas que
utilicen la misma conexión de salida, por lo que debe revisarse con tráfico
real antes de producción. La limpieza de huellas vencidas se realiza de forma
oportunista dentro de la función SQL.

## Protección de operaciones administrativas

Las funciones de invitación y delegación limitan el tamaño del cuerpo de cada
solicitud antes de procesar JSON. La creación de invitaciones aplica cuotas
independientes mediante el limitador privado: hasta 30 solicitudes por
administrador cada 15 minutos y hasta 5 invitaciones por dirección de correo
cada 24 horas. La modificación de delegaciones administrativas se limita a
60 solicitudes por administrador cada 15 minutos. Las claves son huellas
HMAC; la tabla privada no almacena directamente identificadores de usuario ni
direcciones de correo. Si el control no está disponible, estas operaciones
fallan de forma cerrada. Los límites deben revisarse con el uso real para
evitar fricción operativa.

## Estado de despliegue

Las migraciones 008–014 y las Edge Functions están en la rama de desarrollo.
Las pruebas SQL se ejecutaron dentro de transacciones revertidas.

La migración 014 agrega índices para las 17 claves foráneas señaladas por el
asesor de rendimiento de Supabase en la base activa. La advertencia de política
duplicada de perfiles y las cinco funciones SECURITY DEFINER en `public`
corresponden al estado anterior a las migraciones 011 y 012, todavía pendientes
de aplicar.
No se han aplicado estas migraciones al proyecto activo ni se han desplegado
las funciones.


## Integridad de asignaciones concurrentes (migración 015)

La validación del máximo de dos departamentos se serializa por empleado
bloqueando su fila de perfil durante cada alta de asignación. Esto evita que
dos operaciones simultáneas lean el mismo conteo y creen una tercera
asignación. La regla de una asignación principal y la justificación escrita
para la segunda se mantienen. La migración 015 aún requiere prueba en el
entorno de desarrollo antes de aplicarse al proyecto activo.


## Integridad de equipos y asignaciones (migración 016)

- El supervisor asignado a un equipo debe tener perfil activo, rol de
  Supervisión y una asignación vigente al mismo departamento. Los triggers
  validan estas relaciones con funciones SECURITY DEFINER de búsqueda
  controlada para que RLS no oculte registros relacionados al comprobarlas.
- Un equipo no puede cambiar de departamento si conserva miembros sin
  asignación al departamento nuevo o si tiene turnos/incidencias vinculados
  al departamento anterior.
- No se puede retirar una asignación departamental mientras el empleado siga
  en equipos de ese departamento, tenga turnos programados/en curso, sea
  supervisor de un equipo o tenga incidencias abiertas/en revisión asignadas.
- El historial de incidencias cerradas y turnos completados/cancelados se
  conserva sin bloquear innecesariamente la limpieza de asignaciones.

La migración 016 está preparada en la rama de desarrollo y requiere pruebas
en un entorno aislado antes de su aplicación.


## Integridad operativa y concurrencia (migración 017)

La migración 017 refuerza las relaciones entre asignaciones departamentales,
equipos, miembros, turnos e incidencias:

- Cada miembro de un equipo debe tener un perfil activo y una asignación al
  departamento del equipo. La regla se aplica también al modificar o retirar
  miembros.
- Un turno con empleado y equipo exige que ese empleado forme parte del equipo.
  El equipo debe estar activo y pertenecer al departamento del turno.
- El reportante de una incidencia debe estar activo y tener acceso por
  asignación al departamento, salvo Administración. La persona asignada debe
  estar activa y pertenecer al mismo departamento.
- Si una incidencia vincula equipo y turno, ambos deben referirse al mismo
  equipo y departamento.
- Los triggers bloquean las filas de perfil implicadas para serializar altas
  operativas con la retirada de asignaciones departamentales. También bloquean
  las filas de equipos/turnos relacionadas para impedir cambios simultáneos
  que invaliden los vínculos.
- Las funciones de trigger usan SECURITY DEFINER con search_path controlado y
  ejecución directa revocada a los roles de API; las políticas RLS siguen
  siendo responsables de autorizar quién puede iniciar cada operación.

La migración 017 está preparada en la rama de desarrollo. El CI comprueba su
presencia y reglas esenciales, pero esas comprobaciones estáticas no sustituyen
pruebas reales de PostgreSQL. Antes de aplicarla se deben ejecutar pruebas
transaccionales en un proyecto aislado que cubran altas válidas e inválidas,
actualizaciones, eliminaciones y operaciones concurrentes. No se ha aplicado
al proyecto Supabase activo.
