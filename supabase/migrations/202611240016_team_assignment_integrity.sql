-- Keep team supervisors and roster/shift/incident links consistent with
-- department assignments throughout the lifetime of operational records.

create or replace function public.validate_team_department_links()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.supervisor_id is not null and not exists (
    select 1
    from public.profiles p
    join public.employee_departments ed on ed.employee_id = p.id
    where p.id = new.supervisor_id
      and p.is_active = true
      and p.role = 'supervisor'
      and ed.department_id = new.department_id
  ) then
    raise exception 'The team supervisor must be an active supervisor assigned to the team department.';
  end if;

  if tg_op = 'UPDATE' and new.department_id <> old.department_id then
    if exists (
      select 1 from public.team_members tm
      where tm.team_id = old.id
        and not exists (
          select 1 from public.employee_departments ed
          where ed.employee_id = tm.employee_id
            and ed.department_id = new.department_id
        )
    ) then
      raise exception 'The team cannot change departments while a member lacks an assignment to the new department.';
    end if;

    if exists (select 1 from public.shifts s where s.team_id = old.id and s.department_id <> new.department_id)
       or exists (select 1 from public.incidents i where i.team_id = old.id and i.department_id <> new.department_id) then
      raise exception 'The team cannot change departments while it has shifts or incidents in its current department.';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.validate_team_department_links() from public, anon, authenticated;

create trigger validate_team_department_links
before insert or update on public.teams
for each row execute function public.validate_team_department_links();

create or replace function public.prevent_department_assignment_in_use()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if exists (
    select 1 from public.team_members tm
    join public.teams t on t.id = tm.team_id
    where tm.employee_id = old.employee_id
      and t.department_id = old.department_id
  ) then
    raise exception 'Remove the employee from department teams before removing this department assignment.';
  end if;

  if exists (
    select 1 from public.shifts s
    where s.employee_id = old.employee_id
      and s.department_id = old.department_id
      and s.status in ('scheduled', 'in_progress')
  ) then
    raise exception 'Reassign or cancel the employee''s active shifts before removing this department assignment.';
  end if;

  if exists (
    select 1 from public.teams t
    where t.supervisor_id = old.employee_id
      and t.department_id = old.department_id
  ) then
    raise exception 'Assign another supervisor to the team before removing this department assignment.';
  end if;

  if exists (
    select 1 from public.incidents i
    where i.assigned_to = old.employee_id
      and i.department_id = old.department_id
      and i.status in ('open', 'under_review')
  ) then
    raise exception 'Reassign open incidents before removing this department assignment.';
  end if;

  return old;
end;
$$;

revoke all on function public.prevent_department_assignment_in_use() from public, anon, authenticated;

create trigger prevent_department_assignment_in_use
before delete on public.employee_departments
for each row execute function public.prevent_department_assignment_in_use();
