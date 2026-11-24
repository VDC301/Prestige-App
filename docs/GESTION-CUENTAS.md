# Gestión segura de cuentas — Prestige

## Alta de empleados
El panel administrativo utilizará la Edge Function `create-employee-invitation`. El cliente envía nombre, correo, rol y departamentos; la función valida la sesión Supabase, consulta el perfil del administrador y aplica las reglas antes de invitar.

- La invitación de Auth se envía con `auth.admin.inviteUserByEmail`.
- El perfil se enlaza al UUID Auth generado; no se escriben filas en `auth.users` desde SQL.
- El número de empleado se asigna en servidor y bajo bloqueo de fila para evitar duplicados.
- Prefijos: ADM, GER, SUP y EMP. La cuenta inicial ADM-000 conserva su número; las siguientes cuentas administrativas comienzan en ADM-001. Los demás roles comienzan en 001.
- Los empleados no administrativos deben tener al menos un departamento. La segunda asignación requiere justificación y se registra mediante la auditoría existente.
- Las cuentas administrativas no reciben asignaciones departamentales.
- Cada alta genera un evento de auditoría con actor, número, rol y departamentos.

## Delegación administrativa
La columna `profiles.can_manage_admins` controla quién puede crear otras cuentas administrativas y conceder esa misma facultad. La migración inicial concede el permiso a ADM-000. Las nuevas cuentas administrativas no lo reciben por defecto.

Los clientes autenticados solo pueden actualizar su nombre visible. No pueden cambiar su rol, estado activo ni permiso de delegación. Esos cambios se reservan a operaciones de servidor autorizadas.

## Seguridad antes de producción
- Configurar `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` y `APP_ORIGIN` como secretos de Edge Functions.
- Mantener `verify_jwt = true` para `create-employee-invitation`.
- No desplegar hasta revisar CORS, límites de invitaciones, recuperación de cuenta, plantillas de correo y pruebas negativas de autorización.
- La función no se despliega con este commit; el código queda preparado para revisión.

## Permisos administrativos delegados
La RPC `current_user_can_manage_admins()` devuelve únicamente si la sesión actual puede delegar permisos administrativos. La Edge Function `manage-admin-delegation` permite a ese administrador habilitar o retirar esa facultad a otra cuenta ADM. No permite cambiar el permiso propio y cada cambio queda en auditoría.
