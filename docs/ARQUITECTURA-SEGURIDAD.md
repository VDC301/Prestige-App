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
