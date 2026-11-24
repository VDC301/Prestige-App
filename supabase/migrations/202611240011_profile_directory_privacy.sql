-- Restrict the profile table to safe directory columns. Sensitive self-only
-- fields are returned by a SECURITY DEFINER function scoped to auth.uid().
drop policy if exists "users view own profile" on public.profiles;
drop policy if exists "users view permitted profiles" on public.profiles;
create policy "users view permitted profiles" on public.profiles
 for select to authenticated
 using (public.is_active_user() and public.can_view_employee(id));

revoke select on public.profiles from authenticated;
grant select (id, display_name, role, is_active) on public.profiles to authenticated;

create or replace function public.get_my_profile()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
 select jsonb_build_object(
  'id', p.id,
  'employee_number', p.employee_number,
  'display_name', p.display_name,
  'role', p.role,
  'is_active', p.is_active,
  'can_manage_admins', p.can_manage_admins,
  'departments', coalesce((
   select jsonb_agg(jsonb_build_object(
    'id', d.id, 'code', d.code, 'name', d.name, 'is_primary', ed.is_primary
   ) order by ed.is_primary desc, d.name)
   from public.employee_departments ed
   join public.departments d on d.id = ed.department_id
   where ed.employee_id = p.id
  ), '[]'::jsonb)
 )
 from public.profiles p
 where p.id = (select auth.uid()) and p.is_active = true;
$$;
revoke all on function public.get_my_profile() from public, anon;
grant execute on function public.get_my_profile() to authenticated;
