-- Prestige backend repair: profile bootstrap, employee numbering, rate limits and admin delegation.
-- This migration is prepared in GitHub only; it is not applied to the live Supabase project.

alter table public.profiles
  add column if not exists can_manage_admins boolean not null default false;

comment on column public.profiles.can_manage_admins is
  'Explicit delegation flag: permits an active administrator to create and manage other administrator accounts.';

-- Preserve the first bootstrap administrator's ability to delegate administration.
update public.profiles
set can_manage_admins = true
where role = 'admin'
  and employee_number = 'ADM-000'
  and not exists (
    select 1 from public.profiles p
    where p.role = 'admin' and p.is_active = true and p.can_manage_admins = true
  );

-- Private counters. No client role receives direct table access.
create table if not exists public.employee_number_counters (
  role public.app_role primary key,
  last_value bigint not null check (last_value >= -1),
  updated_at timestamptz not null default now()
);

insert into public.employee_number_counters(role, last_value)
select
  p.role,
  coalesce(
    max(nullif(substring(p.employee_number from '[0-9]+$'), '')::bigint),
    case when p.role = 'admin' then -1 else 0 end
  )
from public.profiles p
group by p.role
on conflict (role) do update
set last_value = greatest(public.employee_number_counters.last_value, excluded.last_value),
    updated_at = now();

alter table public.employee_number_counters enable row level security;
revoke all on public.employee_number_counters from public, anon, authenticated, service_role;

create or replace function public.next_employee_number(target_role public.app_role)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  next_value bigint;
  prefix text;
begin
  prefix := case target_role
    when 'admin' then 'ADM'
    when 'manager' then 'GER'
    when 'supervisor' then 'SUP'
    when 'employee' then 'EMP'
  end;

  if prefix is null then
    raise exception 'Unsupported employee role.';
  end if;

  insert into public.employee_number_counters(role, last_value)
  values (target_role, case when target_role = 'admin' then -1 else 0 end)
  on conflict (role) do nothing;

  update public.employee_number_counters
  set last_value = last_value + 1,
      updated_at = now()
  where role = target_role
  returning last_value into next_value;

  return prefix || '-' || lpad(next_value::text, 3, '0');
end;
$$;

revoke all on function public.next_employee_number(public.app_role) from public, anon, authenticated;
grant execute on function public.next_employee_number(public.app_role) to service_role;

-- The rate-limit buckets contain only keyed HMAC digests, never raw IPs or emails.
create table if not exists public.edge_rate_limits (
  bucket_key text primary key check (bucket_key ~ '^[a-f0-9]{64}$'),
  window_started_at timestamptz not null,
  attempts integer not null check (attempts >= 1),
  updated_at timestamptz not null default now()
);

alter table public.edge_rate_limits enable row level security;
revoke all on public.edge_rate_limits from public, anon, authenticated, service_role;

create or replace function public.consume_login_rate_limit(
  p_bucket_key text,
  p_limit integer,
  p_window_seconds integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_started_at timestamptz;
  v_attempts integer;
  v_now timestamptz := clock_timestamp();
  v_retry_after integer;
begin
  if p_bucket_key is null or p_bucket_key !~ '^[a-f0-9]{64}$'
     or p_limit < 1 or p_window_seconds < 1 or p_window_seconds > 604800 then
    raise exception 'Invalid rate-limit parameters.';
  end if;

  insert into public.edge_rate_limits(bucket_key, window_started_at, attempts, updated_at)
  values (p_bucket_key, v_now, 1, v_now)
  on conflict (bucket_key) do update
  set window_started_at = case
        when public.edge_rate_limits.window_started_at
             + make_interval(secs => p_window_seconds::double precision) <= v_now
        then v_now
        else public.edge_rate_limits.window_started_at
      end,
      attempts = case
        when public.edge_rate_limits.window_started_at
             + make_interval(secs => p_window_seconds::double precision) <= v_now
        then 1
        else public.edge_rate_limits.attempts + 1
      end,
      updated_at = v_now
  returning window_started_at, attempts
  into v_started_at, v_attempts;

  v_retry_after := greatest(
    1,
    ceil(extract(epoch from (
      v_started_at + make_interval(secs => p_window_seconds::double precision) - clock_timestamp()
    )))::integer
  );

  return jsonb_build_object(
    'allowed', v_attempts <= p_limit,
    'retry_after_seconds', case when v_attempts > p_limit then v_retry_after else 0 end
  );
end;
$$;

revoke all on function public.consume_login_rate_limit(text, integer, integer) from public, anon, authenticated;
grant execute on function public.consume_login_rate_limit(text, integer, integer) to service_role;

-- The browser receives only its own profile and authorized department assignments.
create or replace function public.get_my_profile()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  if auth.uid() is null then
    return null;
  end if;

  select jsonb_build_object(
    'id', p.id,
    'employee_number', p.employee_number,
    'display_name', p.display_name,
    'role', p.role,
    'is_active', p.is_active,
    'can_manage_admins', p.can_manage_admins,
    'departments', coalesce((
      select jsonb_agg(
        jsonb_build_object('id', d.id, 'code', d.code, 'name', d.name)
        order by ed.is_primary desc, d.name
      )
      from public.employee_departments ed
      join public.departments d on d.id = ed.department_id
      where ed.employee_id = p.id
    ), '[]'::jsonb)
  )
  into result
  from public.profiles p
  where p.id = auth.uid()
    and p.is_active = true;

  return result;
end;
$$;

revoke all on function public.get_my_profile() from public, anon;
grant execute on function public.get_my_profile() to authenticated;

-- Only a verified server-side service-role call may change administrative delegation.
create or replace function public.set_admin_delegation_permission(
  p_actor_id uuid,
  p_target_employee_number text,
  p_grant_permission boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.profiles%rowtype;
  v_target public.profiles%rowtype;
  v_changed boolean;
  v_authorized_admin_count integer;
begin
  if p_actor_id is null or p_target_employee_number is null or p_grant_permission is null then
    raise exception 'Invalid delegation request.';
  end if;

  select * into v_actor
  from public.profiles
  where id = p_actor_id
    and is_active = true
    and role = 'admin'
    and can_manage_admins = true
  for update;

  if not found then
    raise exception 'Actor is not authorized to manage administrative delegation.';
  end if;

  select * into v_target
  from public.profiles
  where employee_number = upper(trim(p_target_employee_number))
    and role = 'admin'
  for update;

  if not found then
    raise exception 'Target administrator not found.';
  end if;

  if v_actor.id = v_target.id then
    raise exception 'An administrator cannot change their own delegation.';
  end if;

  if p_grant_permission = false and v_target.can_manage_admins = true then
    select count(*) into v_authorized_admin_count
    from public.profiles
    where role = 'admin' and is_active = true and can_manage_admins = true;

    if v_authorized_admin_count <= 1 then
      raise exception 'Cannot revoke the last active administrator delegation.';
    end if;
  end if;

  v_changed := v_target.can_manage_admins is distinct from p_grant_permission;

  if v_changed then
    update public.profiles
    set can_manage_admins = p_grant_permission
    where id = v_target.id;

    insert into public.audit_log(actor_id, action, entity_type, entity_id, details)
    values (
      v_actor.id,
      'admin_delegation_permission_changed',
      'profile',
      v_target.id::text,
      jsonb_build_object(
        'employee_number', v_target.employee_number,
        'previous_can_manage_admins', v_target.can_manage_admins,
        'can_manage_admins', p_grant_permission
      )
    );
  end if;

  return jsonb_build_object(
    'changed', v_changed,
    'can_manage_admins', p_grant_permission
  );
end;
$$;

revoke all on function public.set_admin_delegation_permission(uuid, text, boolean) from public, anon, authenticated;
grant execute on function public.set_admin_delegation_permission(uuid, text, boolean) to service_role;
