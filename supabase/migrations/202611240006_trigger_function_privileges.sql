-- Lock down trigger-only SECURITY DEFINER functions.
-- Trigger invocation does not require callers to have EXECUTE privileges.
revoke all on function public.audit_department_assignment_change() from public, anon, authenticated;
revoke all on function public.enforce_department_assignment_rules() from public, anon, authenticated;

-- This view intentionally runs with its owner privileges so it can expose only
-- the approved directory columns while profiles.employee_number remains private.
comment on view public.employee_directory is
'Intentional owner-privileged directory view: exposes only id, display_name, role, is_active to users sharing a department; does not expose employee_number. Review before changing security mode.';
