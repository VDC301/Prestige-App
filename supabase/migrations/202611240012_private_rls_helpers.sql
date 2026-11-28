-- Keep SECURITY DEFINER helpers outside PostgREST's exposed public schema.
-- RLS policies retain their function dependencies when these functions move.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated, service_role;

alter function public.is_active_user() set schema private;
alter function public.is_admin() set schema private;
alter function public.has_department_access(uuid) set schema private;
alter function public.can_view_employee(uuid) set schema private;
alter function public.can_manage_department(uuid) set schema private;

create or replace function private.is_active_user()
returns boolean
language sql stable security definer
set search_path = public, auth
as $$
 select exists(
  select 1 from public.profiles p
  where p.id = (select auth.uid()) and p.is_active = true
 );
$$;

create or replace function private.is_admin()
returns boolean
language sql stable security definer
set search_path = public, auth
as $$
 select exists(
  select 1 from public.profiles p
  where p.id = (select auth.uid())
    and p.is_active = true
    and p.role = 'admin'
 );
$$;

create or replace function private.has_department_access(target_department uuid)
returns boolean
language sql stable security definer
set search_path = public, auth, private
as $$
 select private.is_admin() or exists(
  select 1
  from public.employee_departments ed
  join public.profiles p on p.id = ed.employee_id
  where ed.employee_id = (select auth.uid())
    and ed.department_id = target_department
    and p.is_active = true
 );
$$;

create or replace function private.can_view_employee(target_employee uuid)
returns boolean
language sql stable security definer
set search_path = public, auth, private
as $$
 select private.is_admin()
   or target_employee = (select auth.uid())
   or exists(
    select 1
    from public.employee_departments mine
    join public.employee_departments theirs
      on theirs.department_id = mine.department_id
    join public.profiles target_profile
      on target_profile.id = theirs.employee_id
    where mine.employee_id = (select auth.uid())
      and theirs.employee_id = target_employee
      and target_profile.is_active = true
   );
$$;

create or replace function private.can_manage_department(target_department uuid)
returns boolean
language sql stable security definer
set search_path = public, auth, private
as $$
 select private.is_admin() or (
  private.has_department_access(target_department)
  and exists(
   select 1 from public.profiles p
   where p.id = (select auth.uid())
     and p.is_active = true
     and p.role in ('manager', 'supervisor')
  )
 );
$$;

revoke all on function private.is_active_user() from public, anon;
revoke all on function private.is_admin() from public, anon;
revoke all on function private.has_department_access(uuid) from public, anon;
revoke all on function private.can_view_employee(uuid) from public, anon;
revoke all on function private.can_manage_department(uuid) from public, anon;

grant execute on function private.is_active_user() to authenticated, service_role;
grant execute on function private.is_admin() to authenticated, service_role;
grant execute on function private.has_department_access(uuid) to authenticated, service_role;
grant execute on function private.can_view_employee(uuid) to authenticated, service_role;
grant execute on function private.can_manage_department(uuid) to authenticated, service_role;
