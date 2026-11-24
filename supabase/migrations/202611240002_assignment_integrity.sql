-- Enforce the single-primary / optional admin-approved second department rule.
create or replace function public.enforce_department_assignment_rules()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_count integer;
begin
  if tg_op = 'INSERT' then
    select count(*) into existing_count
    from public.employee_departments
    where employee_id = new.employee_id;

    if existing_count >= 2 then
      raise exception 'An employee may have at most two department assignments.';
    end if;

    if existing_count = 0 then
      new.is_primary := true;
    elsif coalesce(length(trim(new.authorization_note)), 0) = 0 then
      raise exception 'A written administrative reason is required for a second department assignment.';
    end if;
  elsif tg_op = 'UPDATE' then
    raise exception 'Department assignments cannot be edited; remove and re-create them with an audit trail.';
  end if;

  return new;
end;
$$;

create trigger enforce_department_assignment_rules
before insert or update on public.employee_departments
for each row execute function public.enforce_department_assignment_rules();

create or replace function public.audit_department_assignment_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.audit_log(actor_id, action, entity_type, entity_id, details)
    values (
      coalesce((select auth.uid()), new.assigned_by),
      'department_assignment_created',
      'employee_department',
      new.employee_id::text,
      jsonb_build_object(
        'department_id', new.department_id,
        'is_primary', new.is_primary,
        'assigned_by', new.assigned_by,
        'authorization_note', new.authorization_note
      )
    );
    return new;
  elsif tg_op = 'DELETE' then
    insert into public.audit_log(actor_id, action, entity_type, entity_id, details)
    values (
      (select auth.uid()),
      'department_assignment_removed',
      'employee_department',
      old.employee_id::text,
      jsonb_build_object('department_id', old.department_id, 'was_primary', old.is_primary)
    );
    return old;
  end if;
  return null;
end;
$$;

create trigger audit_department_assignment_insert
after insert on public.employee_departments
for each row execute function public.audit_department_assignment_change();
create trigger audit_department_assignment_delete
after delete on public.employee_departments
for each row execute function public.audit_department_assignment_change();

-- Assignment changes are append/remove operations; no silent edits.
drop policy if exists "admins manage department assignments" on public.employee_departments;
create policy "admins create department assignments"
on public.employee_departments for insert to authenticated
with check (public.is_admin() and assigned_by = (select auth.uid()));
create policy "admins remove department assignments"
on public.employee_departments for delete to authenticated
using (public.is_admin());
revoke update on public.employee_departments from authenticated;

-- A manager may only add a person who is actually assigned to that team's department.
drop policy if exists "department managers manage rosters" on public.team_members;
create policy "department managers add assigned employees"
on public.team_members for insert to authenticated
with check (
  exists (
    select 1 from public.teams t
    where t.id = team_id
      and public.can_manage_department(t.department_id)
      and exists (
        select 1 from public.employee_departments ed
        join public.profiles p on p.id = ed.employee_id
        where ed.employee_id = employee_id
          and ed.department_id = t.department_id
          and p.is_active = true
      )
  )
);
create policy "department managers remove roster members"
on public.team_members for delete to authenticated
using (
  exists (
    select 1 from public.teams t
    where t.id = team_id and public.can_manage_department(t.department_id)
  )
);
