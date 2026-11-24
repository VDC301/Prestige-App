# Prestige Landscaping & Cleaning — Portal

Portal interno en español, desarrollado inicialmente como una aplicación web progresiva (PWA) estática.

## Estado actual

Esta primera entrega contiene:
- Interfaz adaptable a móviles y escritorio.
- Navegación en español.
- Vistas de demostración para Administración, Gerencia, Supervisión y Empleados.
- Separación visual de Landscaping y Cleaning.
- Perfil híbrido de ejemplo para representar una asignación doble autorizada.
- Módulos iniciales: comunicados oficiales, conversaciones, turnos, equipos, incidencias, personal y configuración.
- Manifiesto PWA y caché inicial para abrir la interfaz sin conexión.

## Importante: seguridad y datos reales

Los perfiles actuales son únicamente demostrativos y se cambian desde la interfaz. No constituyen autenticación ni control de acceso seguro. No introducir datos personales, contraseñas, información de empleados ni datos operativos reales en esta versión.

GitHub Pages puede alojar la interfaz pública, pero no debe utilizarse como base de datos ni como mecanismo de autorización. Antes de usar el portal en operaciones reales se debe integrar un backend con autenticación, base de datos, permisos aplicados en el servidor, auditoría y sincronización segura sin conexión.

## Publicación

El sitio puede publicarse desde GitHub Pages seleccionando la rama `main` y la carpeta `/(root)` en Settings → Pages. La publicación requiere activar Pages en la configuración del repositorio.

## Próximas etapas

1. Revisar la interfaz y completar los flujos de cada módulo.
2. Diseñar el modelo de datos y los permisos por departamento.
3. Integrar autenticación individual mediante número de empleado y contraseña.
4. Implementar almacenamiento y sincronización segura para uso sin conexión.
5. Probar roles, aislamiento de departamentos, auditoría y notificaciones antes del lanzamiento.
