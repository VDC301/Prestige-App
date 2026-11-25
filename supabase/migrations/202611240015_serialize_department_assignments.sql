-- Serialize assignment writes per employee so concurrent requests cannot
-- bypass the two-department maximum checked by the trigger.
create or replace function public.enforce_department_assignment_rules()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  existing_count integer;
begin
  if tg_op = 'INSERT' then
    -- The profile row is the per-employee mutex. Concurrent assignment inserts
    -- for this employee wait here, then count the committed assignment rows.
    perform 1
    from public.profiles
    where id = new.employee_id
    for update;

    if not found then
      raise exception 'Employee profile not found.';
    end if;

    select count(*)
    into existing_count
    from public.employee_departments
    where employee_id = new.employee_id;

    if existing_count >= 2 then
      raise exception 'An employee may have at most two department assignments.';
    end if;

    if existing_count = 0 then
      new.is_primary := true;
    elsif coalesce(length(trim(new.authorization_note)), 0) < 8 then
      raise exception 'A written administrative reason is required for a second department assignment.';
    end if;
  elsif tg_op = 'UPDATE' then
    raise exception 'Department assignments cannot be edited; remove and re-create them with an audit trail.';
  end if;

  return new;
end;
$$;
