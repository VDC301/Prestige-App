-- Explicit delegation: only ADM-000 starts with authority to create or empower admins.
alter table public.profiles
 add column if not exists can_manage_admins boolean not null default false;

update public.profiles
 set can_manage_admins = true
 where employee_number = 'ADM-000' and role = 'admin';

insert into public.audit_log(actor_id, action, entity_type, entity_id, details)
select p.id, 'initial_admin_management_permission_granted', 'profile', p.id::text,
       jsonb_build_object('employee_number', p.employee_number, 'can_manage_admins', true)
from public.profiles p
where p.employee_number = 'ADM-000' and p.role = 'admin'
and not exists (
 select 1 from public.audit_log a
 where a.action = 'initial_admin_management_permission_granted'
   and a.entity_id = p.id::text
);

create table if not exists public.employee_number_counters (
 prefix text primary key check (prefix in ('ADM','GER','SUP','EMP')),
 last_value integer not null check (last_value >= 0)
);
revoke all on public.employee_number_counters from anon, authenticated;

create or replace function public.next_employee_number(target_role public.app_role)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
 target_prefix text;
 next_value integer;
begin
 target_prefix := case target_role
  when 'admin' then 'ADM'
  when 'manager' then 'GER'
  when 'supervisor' then 'SUP'
  when 'employee' then 'EMP'
 end;

 insert into public.employee_number_counters(prefix, last_value)
 values (
  target_prefix,
  greatest(
   case when target_prefix = 'ADM' then 0 else 1 end,
   coalesce((
    select max(split_part(p.employee_number, '-', 2)::integer) + 1
    from public.profiles p
    where split_part(p.employee_number, '-', 1) = target_prefix
      and split_part(p.employee_number, '-', 2) ~ '^[0-9]{3,}$'
   ), case when target_prefix = 'ADM' then 0 else 1 end)
  )
 )
 on conflict (prefix) do update
 set last_value = greatest(
  public.employee_number_counters.last_value + 1,
  coalesce((
   select max(split_part(p.employee_number, '-', 2)::integer) + 1
   from public.profiles p
   where split_part(p.employee_number, '-', 1) = target_prefix
     and split_part(p.employee_number, '-', 2) ~ '^[0-9]{3,}$'
  ), case when target_prefix = 'ADM' then 0 else 1 end)
 )
 returning last_value into next_value;

 return target_prefix || '-' || lpad(next_value::text, 3, '0');
end;
$$;

revoke all on function public.next_employee_number(public.app_role) from public, anon, authenticated;
grant execute on function public.next_employee_number(public.app_role) to service_role;

-- Prevent browser clients from changing roles, activation state or delegated admin authority.
revoke update on public.profiles from authenticated;
grant update (display_name) on public.profiles to authenticated;
