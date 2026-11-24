# Prestige Landscaping & Cleaning — Portal

Portal interno en español para el equipo Prestige.

## Estado del proyecto

La rama main contiene la primera interfaz demostrativa y la estructura PWA. La rama tech-foundation añade la primera base de arquitectura para backend y seguridad:

- Esquema PostgreSQL inicial para Supabase.
- Políticas Row Level Security (RLS) para aislar departamentos.
- Roles de Administración, Gerencia, Supervisión y Empleado.
- Asignaciones departamentales explícitas; una asignación doble requiere autorización administrativa y deja constancia.
- Tablas separadas para comunicados oficiales y conversaciones.
- Equipos, turnos e incidencias.
- Edge Function para iniciar sesión con número de empleado y contraseña.
- Límite de solicitudes previo a la búsqueda del número de empleado, con contador atómico en PostgreSQL y huella HMAC de la IP de origen.
- Índices adicionales para las claves foráneas detectadas por el asesor de rendimiento.

## Seguridad

Los perfiles de demostración del frontend no son autenticación real. No introducir información personal ni operativa en esta versión. La función de acceso y el esquema SQL requieren un proyecto Supabase configurado, secretos del servidor, creación segura de la primera cuenta administrativa y pruebas RLS antes de producción. Las migraciones 008–014 y las Edge Functions siguen en la rama de desarrollo; no están desplegadas en el proyecto activo.

Nunca colocar la clave service_role en el navegador o en este repositorio.

Consulta docs/ARQUITECTURA-SEGURIDAD.md para los pasos de configuración y validación.

## Publicación

El frontend puede alojarse en GitHub Pages. La base de datos, autenticación y funciones se ejecutan en Supabase, no en GitHub Pages.
