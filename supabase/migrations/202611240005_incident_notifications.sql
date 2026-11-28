-- Restrict incident reporting to operational leadership and notify management.
create table public.notifications (
 id uuid primary key default gen_random_uuid(),
 recipient_id uuid not null references public.profiles(id) on delete cascade,
 incident_id uuid references public.incidents(id) on delete cascade,
 title text not null check(length(trim(title)) between 1 and 180),
 body text not null check(length(trim(body)) between 1 and 2000),
 read_at timestamptz,
 created_at timestamptz not null default now()
);

create index notifications_recipient_date_idx
 on public.notifications(recipient_id, created_at desc);

alter table public.notifications enable row level security;

create policy "users read own notifications" on public.notifications
 for select to authenticated
 using (public.is_active_user() and recipient_id=(select auth.uid()));

create policy "users mark own notifications read" on public.notifications
 for update to authenticated
 using (public.is_active_user() and recipient_id=(select auth.uid()))
 with check (public.is_active_user() and recipient_id=(select auth.uid()));

grant select, update (read_at) on public.notifications to authenticated;

drop policy if exists "department members report incidents" on public.incidents;
create policy "department supervisors report incidents" on public.incidents
 for insert to authenticated
 with check (
  public.is_active_user()
  and public.has_department_access(department_id)
  and reported_by=(select auth.uid())
  and exists (
   select 1 from public.profiles p
   where p.id=(select auth.uid())
     and p.is_active=true
     and p.role in ('admin','manager','supervisor')
  )
 );

create or replace function public.notify_management_of_incident()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
 insert into public.notifications(recipient_id, incident_id, title, body)
 select p.id, new.id, 'Nueva incidencia reportada',
        'Se reportó una incidencia: ' || new.title
 from public.profiles p
 where p.is_active=true
   and (
    p.role='admin'
    or (
     p.role='manager'
     and exists (
      select 1 from public.employee_departments ed
      where ed.employee_id=p.id
        and ed.department_id=new.department_id
     )
    )
   );

 return new;
end;
$$;

create trigger notify_management_after_incident
 after insert on public.incidents
 for each row execute function public.notify_management_of_incident();

revoke all on function public.notify_management_of_incident() from public;
