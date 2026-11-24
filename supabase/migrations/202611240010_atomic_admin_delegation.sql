-- Apply a delegated-admin permission change and its audit record atomically.
create or replace function public.set_admin_delegation_permission(
 actor_id uuid,
 target_employee_number text,
 grant_permission boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
 actor_record public.profiles%rowtype;
 target_record public.profiles%rowtype;
begin
 select * into actor_record
 from public.profiles
 where id = actor_id and is_active = true and role = 'admin'
   and can_manage_admins = true;
 if not found then
  raise exception 'Not authorized to manage administrator delegation.';
 end if;

 select * into target_record
 from public.profiles
 where employee_number = upper(trim(target_employee_number)) and role = 'admin'
 for update;
 if not found then
  raise exception 'Administrator account not found.';
 end if;
 if target_record.id = actor_id then
  raise exception 'Administrators cannot change their own delegation permission.';
 end if;

 if target_record.can_manage_admins = grant_permission then
  return jsonb_build_object(
   'changed', false,
   'employee_number', target_record.employee_number,
   'can_manage_admins', target_record.can_manage_admins
  );
 end if;

 update public.profiles
 set can_manage_admins = grant_permission
 where id = target_record.id;

 insert into public.audit_log(actor_id, action, entity_type, entity_id, details)
 values (
  actor_id,
  'admin_delegation_permission_changed',
  'profile',
  target_record.id::text,
  jsonb_build_object(
   'employee_number', target_record.employee_number,
   'previous_value', target_record.can_manage_admins,
   'new_value', grant_permission
  )
 );

 return jsonb_build_object(
  'changed', true,
  'employee_number', target_record.employee_number,
  'can_manage_admins', grant_permission
 );
end;
$$;

revoke all on function public.set_admin_delegation_permission(uuid, text, boolean) from public, anon, authenticated;
grant execute on function public.set_admin_delegation_permission(uuid, text, boolean) to service_role;
