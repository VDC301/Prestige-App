-- Prestige portal database foundation
create extension if not exists pgcrypto;
create type public.app_role as enum ('admin','manager','supervisor','employee');
create table public.departments (
 id uuid primary key default gen_random_uuid(),
 code text not null unique check (code in ('landscaping','cleaning')),
 name text not null unique
);
insert into public.departments(code,name) values
 ('landscaping','Landscaping'),('cleaning','Cleaning')
on conflict(code) do nothing;
create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 employee_number text not null unique check(employee_number=upper(trim(employee_number)) and length(employee_number) between 2 and 32),
 display_name text not null check(length(trim(display_name)) between 1 and 100),
 role public.app_role not null default 'employee',
 is_active boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table public.employee_departments (
 employee_id uuid not null references public.profiles(id) on delete cascade,
 department_id uuid not null references public.departments(id),
 is_primary boolean not null default false,
 assigned_by uuid not null references public.profiles(id),
 assigned_at timestamptz not null default now(),
 authorization_note text,
 primary key(employee_id,department_id)
);
create unique index one_primary_department_per_employee on public.employee_departments(employee_id) where is_primary;
create table public.announcements (
 id uuid primary key default gen_random_uuid(),
 department_id uuid not null references public.departments(id),
 title text not null check(length(trim(title)) between 1 and 180),
 body text not null check(length(trim(body)) between 1 and 12000),
 published_at timestamptz,
 created_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table public.discussions (
 id uuid primary key default gen_random_uuid(),
 department_id uuid not null references public.departments(id),
 title text not null check(length(trim(title)) between 1 and 180),
 created_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table public.discussion_comments (
 id uuid primary key default gen_random_uuid(),
 discussion_id uuid not null references public.discussions(id) on delete cascade,
 author_id uuid not null references public.profiles(id),
 body text not null check(length(trim(body)) between 1 and 8000),
 created_at timestamptz not null default now(),
 edited_at timestamptz
);
create table public.teams (
 id uuid primary key default gen_random_uuid(),
 department_id uuid not null references public.departments(id),
 name text not null check(length(trim(name)) between 1 and 120),
 supervisor_id uuid references public.profiles(id),
 is_active boolean not null default true,
 created_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now()
);
create table public.team_members (
 team_id uuid not null references public.teams(id) on delete cascade,
 employee_id uuid not null references public.profiles(id) on delete cascade,
 assigned_at timestamptz not null default now(),
 primary key(team_id,employee_id)
);
create table public.shifts (
 id uuid primary key default gen_random_uuid(),
 department_id uuid not null references public.departments(id),
 team_id uuid references public.teams(id),
 employee_id uuid references public.profiles(id),
 starts_at timestamptz not null,
 ends_at timestamptz not null,
 status text not null default 'scheduled' check(status in ('scheduled','in_progress','completed','cancelled')),
 created_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(),
 check(ends_at>starts_at),
 check(team_id is not null or employee_id is not null)
);
create table public.incidents (
 id uuid primary key default gen_random_uuid(),
 department_id uuid not null references public.departments(id),
 team_id uuid references public.teams(id),
 shift_id uuid references public.shifts(id),
 category text not null check(category in ('property_damage','missing_tools','employee_issue','service_difficulty','safety','other')),
 title text not null check(length(trim(title)) between 1 and 180),
 description text not null check(length(trim(description)) between 1 and 10000),
 status text not null default 'open' check(status in ('open','under_review','resolved','closed')),
 reported_by uuid not null references public.profiles(id),
 assigned_to uuid references public.profiles(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table public.audit_log (
 id bigint generated always as identity primary key,
 actor_id uuid references public.profiles(id),
 action text not null,
 entity_type text not null,
 entity_id text,
 details jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
create index employee_departments_department_idx on public.employee_departments(department_id,employee_id);
create index announcements_department_date_idx on public.announcements(department_id,published_at desc);
create index discussions_department_date_idx on public.discussions(department_id,created_at desc);
create index comments_discussion_date_idx on public.discussion_comments(discussion_id,created_at);
create index shifts_department_start_idx on public.shifts(department_id,starts_at);
create index incidents_department_status_idx on public.incidents(department_id,status,created_at desc);
create index audit_log_created_idx on public.audit_log(created_at desc);

create or replace function public.is_active_user()
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.is_active=true); $$;
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.is_active=true and p.role='admin'); $$;
create or replace function public.has_department_access(target_department uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select public.is_admin() or exists(
 select 1 from public.employee_departments ed join public.profiles p on p.id=ed.employee_id
 where ed.employee_id=(select auth.uid()) and ed.department_id=target_department and p.is_active=true
); $$;
create or replace function public.can_view_employee(target_employee uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select public.is_admin() or target_employee=(select auth.uid()) or exists(
 select 1 from public.employee_departments mine
 join public.employee_departments theirs on theirs.department_id=mine.department_id
 join public.profiles target_profile on target_profile.id=theirs.employee_id
 where mine.employee_id=(select auth.uid()) and theirs.employee_id=target_employee and target_profile.is_active=true
); $$;
create or replace function public.can_manage_department(target_department uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select public.is_admin() or (
 public.has_department_access(target_department) and exists(
  select 1 from public.profiles p where p.id=(select auth.uid()) and p.is_active=true and p.role in ('manager','supervisor')
 )
); $$;
create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path=public
as $$ begin new.updated_at=now(); return new; end; $$;
create trigger profiles_updated_at before update on public.profiles for each row execute function public.set_updated_at();
create trigger announcements_updated_at before update on public.announcements for each row execute function public.set_updated_at();
create trigger discussions_updated_at before update on public.discussions for each row execute function public.set_updated_at();
create trigger incidents_updated_at before update on public.incidents for each row execute function public.set_updated_at();

alter table public.departments enable row level security;
alter table public.profiles enable row level security;
alter table public.employee_departments enable row level security;
alter table public.announcements enable row level security;
alter table public.discussions enable row level security;
alter table public.discussion_comments enable row level security;
alter table public.teams enable row level security;
alter table public.team_members enable row level security;
alter table public.shifts enable row level security;
alter table public.incidents enable row level security;
alter table public.audit_log enable row level security;

create policy "active users read departments" on public.departments for select to authenticated using(public.is_active_user());
create policy "users view permitted profiles" on public.profiles for select to authenticated using(public.is_active_user() and public.can_view_employee(id));
create policy "admins manage profiles" on public.profiles for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "users view permitted assignments" on public.employee_departments for select to authenticated using(public.is_active_user() and public.can_view_employee(employee_id));
create policy "admins manage department assignments" on public.employee_departments for all to authenticated using(public.is_admin()) with check(public.is_admin() and assigned_by=(select auth.uid()));

create policy "department members read announcements" on public.announcements for select to authenticated using(public.is_active_user() and public.has_department_access(department_id));
create policy "admins publish announcements" on public.announcements for insert to authenticated with check(public.is_admin() and created_by=(select auth.uid()));
create policy "admins update announcements" on public.announcements for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "admins delete announcements" on public.announcements for delete to authenticated using(public.is_admin());

create policy "department members read discussions" on public.discussions for select to authenticated using(public.is_active_user() and public.has_department_access(department_id));
create policy "department members start discussions" on public.discussions for insert to authenticated with check(public.is_active_user() and public.has_department_access(department_id) and created_by=(select auth.uid()));
create policy "authors or admins update discussions" on public.discussions for update to authenticated using(public.is_admin() or created_by=(select auth.uid())) with check(public.is_admin() or (created_by=(select auth.uid()) and public.has_department_access(department_id)));
create policy "authors or admins delete discussions" on public.discussions for delete to authenticated using(public.is_admin() or created_by=(select auth.uid()));

create policy "members read discussion comments" on public.discussion_comments for select to authenticated using(public.is_active_user() and exists(select 1 from public.discussions d where d.id=discussion_id and public.has_department_access(d.department_id)));
create policy "members add discussion comments" on public.discussion_comments for insert to authenticated with check(public.is_active_user() and author_id=(select auth.uid()) and exists(select 1 from public.discussions d where d.id=discussion_id and public.has_department_access(d.department_id)));
create policy "authors or admins edit comments" on public.discussion_comments for update to authenticated using(public.is_admin() or author_id=(select auth.uid())) with check(public.is_admin() or (author_id=(select auth.uid()) and exists(select 1 from public.discussions d where d.id=discussion_id and public.has_department_access(d.department_id))));
create policy "authors or admins delete comments" on public.discussion_comments for delete to authenticated using(public.is_admin() or author_id=(select auth.uid()));

create policy "department members read teams" on public.teams for select to authenticated using(public.is_active_user() and public.has_department_access(department_id));
create policy "department managers manage teams" on public.teams for all to authenticated using(public.can_manage_department(department_id)) with check(public.can_manage_department(department_id) and created_by=(select auth.uid()));
create policy "members read team rosters" on public.team_members for select to authenticated using(exists(select 1 from public.teams t where t.id=team_id and public.has_department_access(t.department_id)));
create policy "department managers manage rosters" on public.team_members for all to authenticated using(exists(select 1 from public.teams t where t.id=team_id and public.can_manage_department(t.department_id))) with check(exists(select 1 from public.teams t where t.id=team_id and public.can_manage_department(t.department_id)));

create policy "department members read shifts" on public.shifts for select to authenticated using(public.is_active_user() and public.has_department_access(department_id));
create policy "department managers create shifts" on public.shifts for insert to authenticated with check(public.can_manage_department(department_id) and created_by=(select auth.uid()));
create policy "department managers update shifts" on public.shifts for update to authenticated using(public.can_manage_department(department_id)) with check(public.can_manage_department(department_id));
create policy "department managers delete shifts" on public.shifts for delete to authenticated using(public.can_manage_department(department_id));

create policy "department members read incidents" on public.incidents for select to authenticated using(public.is_active_user() and public.has_department_access(department_id));
create policy "department members report incidents" on public.incidents for insert to authenticated with check(public.is_active_user() and public.has_department_access(department_id) and reported_by=(select auth.uid()));
create policy "department managers update incidents" on public.incidents for update to authenticated using(public.can_manage_department(department_id)) with check(public.can_manage_department(department_id));
create policy "admins read audit log" on public.audit_log for select to authenticated using(public.is_admin());

revoke all on function public.is_active_user() from public;
revoke all on function public.is_admin() from public;
revoke all on function public.has_department_access(uuid) from public;
revoke all on function public.can_view_employee(uuid) from public;
revoke all on function public.can_manage_department(uuid) from public;
grant execute on function public.is_active_user() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.has_department_access(uuid) to authenticated;
grant execute on function public.can_view_employee(uuid) to authenticated;
grant execute on function public.can_manage_department(uuid) to authenticated;
grant usage on schema public to authenticated;
grant select on public.departments to authenticated;
grant select,update on public.profiles to authenticated;
grant select,insert,update,delete on public.employee_departments,public.announcements,public.discussions,public.discussion_comments,public.teams,public.team_members,public.shifts,public.incidents to authenticated;
grant select on public.audit_log to authenticated;
-- Bootstrap the first admin only through a trusted server-side process.
-- Never expose the service-role key in the browser.
