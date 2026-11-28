-- Return only the current administrator's delegation capability.
create or replace function public.current_user_can_manage_admins()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
 select exists (
  select 1 from public.profiles p
  where p.id = (select auth.uid())
    and p.is_active = true
    and p.role = 'admin'
    and p.can_manage_admins = true
 );
$$;
revoke all on function public.current_user_can_manage_admins() from public, anon;
grant execute on function public.current_user_can_manage_admins() to authenticated;
