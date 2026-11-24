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

Estas migraciones y funciones están en la rama de desarrollo. No se han aplicado las migraciones 008–010 al proyecto Supabase ni se han desplegado las funciones nuevas.

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

La función `employee-login` devuelve HTTP 429 cuando Supabase Auth limita
intentos, e incluye `Retry-After`. Esto complementa —no sustituye— los
límites de solicitudes configurados en Auth y en la plataforma.

## Estado de despliegue

Las migraciones 008–012 y las Edge Functions están en la rama de desarrollo.
La prueba SQL combinada se ejecutó dentro de una transacción revertida.
No se han aplicado estas migraciones al proyecto activo ni se han desplegado
las funciones.
