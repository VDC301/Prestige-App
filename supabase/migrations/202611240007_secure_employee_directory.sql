-- Replace the owner-privileged employee directory with an invoker view.
-- Protect employee_number using column-level privileges while allowing
-- department-scoped directory rows through profiles RLS.
drop policy if exists "users view own profile" on public.profiles;
create policy "users view permitted profiles" on public.profiles
 for select to authenticated
 using (public.is_active_user() and public.can_view_employee(id));

revoke select, update on public.profiles from authenticated;
grant select (id, display_name, role, is_active) on public.profiles to authenticated;
grant update (employee_number, display_name, role, is_active) on public.profiles to authenticated;

create or replace view public.employee_directory
with (security_barrier=true, security_invoker=true)
as
select p.id, p.display_name, p.role, p.is_active
from public.profiles p
where p.is_active=true and public.can_view_employee(p.id);

comment on view public.employee_directory is
'Security-invoker directory view. Exposes only id, display_name, role, is_active; employee_number is protected by column-level privileges and profiles RLS.';
