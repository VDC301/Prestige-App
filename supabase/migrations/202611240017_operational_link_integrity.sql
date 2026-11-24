-- Serialize operational writes against department-assignment changes and validate
-- every cross-table relationship even when a caller uses privileged database paths.

create or replace function public.validate_team_member_department_link()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'DELETE' then
    perform 1 from public.profiles p
    where p.id = old.employee_id
    for update;
    return old;
  end if;

  -- Profile rows serialize roster/shift/incident creation with assignment removal.
  perform 1
  from public.profiles p
  where p.id in (
    case when tg_op = 'UPDATE' then old.employee_id else new.employee_id end,
    new.employee_id
  )
  order by p.id
  for update;

  if not exists (
    select 1 from public.profiles p
    join public.employee_departments ed on ed.employee_id = p.id
    where p.id = new.employee_id
      and p.is_active = true
      and ed.department_id = (
        select t.department_id from public.teams t
        where t.id = new.team_id and t.is_active = true
        for key share
      )
  ) then
    raise exception 'Team members must be active employees assigned to the active team department.';
  end if;

  return new;
end;
$$;

revoke all on function public.validate_team_member_department_link() from public, anon, authenticated;

create trigger validate_team_member_department_link
before insert or update or delete on public.team_members
for each row execute function public.validate_team_member_department_link();


create or replace function public.validate_shift_department_links()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  team_department uuid;
begin
  if new.employee_id is not null then
    perform 1
    from public.profiles p
    where p.id in (
      case when tg_op = 'UPDATE' then old.employee_id else new.employee_id end,
      new.employee_id
    )
    order by p.id
    for update;

    if not exists (
      select 1
      from public.profiles p
      join public.employee_departments ed on ed.employee_id = p.id
      where p.id = new.employee_id
        and p.is_active = true
        and ed.department_id = new.department_id
    ) then
      raise exception 'The shift employee must be active and assigned to the shift department.';
    end if;
  end if;

  if new.team_id is not null then
    select t.department_id into team_department
    from public.teams t
    where t.id = new.team_id and t.is_active = true
    for key share;

    if not found or team_department <> new.department_id then
      raise exception 'The selected active team does not belong to the shift department.';
    end if;

    if new.employee_id is not null and not exists (
      select 1 from public.team_members tm
      where tm.team_id = new.team_id
        and tm.employee_id = new.employee_id
    ) then
      raise exception 'An employee assigned to a team shift must be a member of that team.';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.validate_shift_department_links() from public, anon, authenticated;


create or replace function public.validate_incident_department_links()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  linked_shift_team uuid;
begin
  -- Lock reporter and assignee in deterministic order. This serializes an
  -- incident write against removal of either person's department assignment.
  perform 1
  from public.profiles p
  where p.id in (
    new.reported_by,
    new.assigned_to,
    case when tg_op = 'UPDATE' then old.assigned_to else new.assigned_to end
  )
  order by p.id
  for update;

  if not exists (
    select 1 from public.profiles p
    where p.id = new.reported_by
      and p.is_active = true
      and (
        p.role = 'admin'
        or exists (
          select 1 from public.employee_departments ed
          where ed.employee_id = p.id
            and ed.department_id = new.department_id
        )
      )
  ) then
    raise exception 'The incident reporter must be active and authorized for the incident department.';
  end if;

  if new.team_id is not null and not exists (
    select 1 from public.teams t
    where t.id = new.team_id
      and t.department_id = new.department_id
      and t.is_active = true
    for key share
  ) then
    raise exception 'The selected active team does not belong to the incident department.';
  end if;

  if new.shift_id is not null then
    select s.team_id into linked_shift_team
    from public.shifts s
    where s.id = new.shift_id
      and s.department_id = new.department_id
    for key share;

    if not found then
      raise exception 'The selected shift does not belong to the incident department.';
    end if;

    if new.team_id is not null and linked_shift_team is distinct from new.team_id then
      raise exception 'The incident team must match the team linked to its shift.';
    end if;
  end if;

  if new.assigned_to is not null and not exists (
    select 1
    from public.profiles p
    join public.employee_departments ed on ed.employee_id = p.id
    where p.id = new.assigned_to
      and p.is_active = true
      and ed.department_id = new.department_id
  ) then
    raise exception 'The assigned employee must be active and assigned to the incident department.';
  end if;

  return new;
end;
$$;

revoke all on function public.validate_incident_department_links() from public, anon, authenticated;


-- Keep assignment deletion mutually exclusive with roster, shift, incident,
-- and supervisor writes that lock the same employee profile row.
create or replace function public.prevent_department_assignment_in_use()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  perform 1 from public.profiles p
  where p.id = old.employee_id
  for update;

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


-- Serialize supervisor changes with department-assignment deletion.
create or replace function public.validate_team_department_links()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.supervisor_id is not null then
    perform 1 from public.profiles p
    where p.id = new.supervisor_id
    for update;

    if not exists (
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

    if exists (
      select 1 from public.shifts s
      where s.team_id = old.id and s.department_id <> new.department_id
    ) or exists (
      select 1 from public.incidents i
      where i.team_id = old.id and i.department_id <> new.department_id
    ) then
      raise exception 'The team cannot change departments while it has shifts or incidents in its current department.';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.validate_team_department_links() from public, anon, authenticated;

-- Existing triggers from migrations 003 and 016 are retained and now execute
-- the hardened function bodies above.
