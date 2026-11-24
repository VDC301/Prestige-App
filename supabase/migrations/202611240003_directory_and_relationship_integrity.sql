-- Keep employee numbers private while providing a limited department-scoped directory.
drop policy if exists "users view permitted profiles" on public.profiles;
create policy "users view own profile" on public.profiles
for select to authenticated
using (public.is_active_user() and (id=(select auth.uid()) or public.is_admin()));

create view public.employee_directory
with (security_barrier=true)
as
select p.id, p.display_name, p.role, p.is_active
from public.profiles p
where p.is_active=true and public.can_view_employee(p.id);

grant select on public.employee_directory to authenticated;

-- Split team write policies so any authorized manager can update a team,
-- while the creator identity is fixed at insertion time.
drop policy if exists "department managers manage teams" on public.teams;
create policy "department managers create teams" on public.teams
for insert to authenticated
with check (public.can_manage_department(department_id) and created_by=(select auth.uid()));
create policy "department managers update teams" on public.teams
for update to authenticated
using (public.can_manage_department(department_id))
with check (public.can_manage_department(department_id));
create policy "department managers delete teams" on public.teams
for delete to authenticated
using (public.can_manage_department(department_id));

-- Validate all linked records against the same authorized department.
create or replace function public.validate_shift_department_links()
returns trigger language plpgsql set search_path=public
as $$
begin
 if new.team_id is not null and not exists(
  select 1 from public.teams t where t.id=new.team_id and t.department_id=new.department_id
 ) then
  raise exception 'The selected team does not belong to the shift department.';
 end if;
 if new.employee_id is not null and not exists(
  select 1 from public.employee_departments ed
  join public.profiles p on p.id=ed.employee_id
  where ed.employee_id=new.employee_id and ed.department_id=new.department_id and p.is_active=true
 ) then
  raise exception 'The selected employee is not assigned to the shift department.';
 end if;
 return new;
end;
$$;
create trigger validate_shift_department_links
before insert or update on public.shifts
for each row execute function public.validate_shift_department_links();

create or replace function public.validate_incident_department_links()
returns trigger language plpgsql set search_path=public
as $$
begin
 if new.team_id is not null and not exists(
  select 1 from public.teams t where t.id=new.team_id and t.department_id=new.department_id
 ) then
  raise exception 'The selected team does not belong to the incident department.';
 end if;
 if new.shift_id is not null and not exists(
  select 1 from public.shifts s where s.id=new.shift_id and s.department_id=new.department_id
 ) then
  raise exception 'The selected shift does not belong to the incident department.';
 end if;
 if new.assigned_to is not null and not exists(
  select 1 from public.employee_departments ed
  join public.profiles p on p.id=ed.employee_id
  where ed.employee_id=new.assigned_to and ed.department_id=new.department_id and p.is_active=true
 ) then
  raise exception 'The assigned employee is not a member of the incident department.';
 end if;
 return new;
end;
$$;
create trigger validate_incident_department_links
before insert or update on public.incidents
for each row execute function public.validate_incident_department_links();

-- Do not allow removal of a primary assignment while a secondary assignment remains.
create or replace function public.prevent_primary_assignment_orphan()
returns trigger language plpgsql set search_path=public
as $$
begin
 if old.is_primary and exists(
  select 1 from public.employee_departments ed
  where ed.employee_id=old.employee_id and ed.department_id<>old.department_id
 ) then
  raise exception 'Remove the secondary department assignment before removing the primary assignment.';
 end if;
 return old;
end;
$$;
create trigger prevent_primary_assignment_orphan
before delete on public.employee_departments
for each row execute function public.prevent_primary_assignment_orphan();
