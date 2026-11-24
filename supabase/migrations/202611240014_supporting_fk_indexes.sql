-- Add indexes for foreign-key columns identified by Supabase's performance advisor.
-- These indexes support joins and prevent table scans during referenced-row updates/deletes.
create index if not exists announcements_created_by_idx
  on public.announcements(created_by);
create index if not exists audit_log_actor_id_idx
  on public.audit_log(actor_id);
create index if not exists discussion_comments_author_id_idx
  on public.discussion_comments(author_id);
create index if not exists discussions_created_by_idx
  on public.discussions(created_by);
create index if not exists employee_departments_assigned_by_idx
  on public.employee_departments(assigned_by);
create index if not exists incidents_assigned_to_idx
  on public.incidents(assigned_to);
create index if not exists incidents_reported_by_idx
  on public.incidents(reported_by);
create index if not exists incidents_shift_id_idx
  on public.incidents(shift_id);
create index if not exists incidents_team_id_idx
  on public.incidents(team_id);
create index if not exists notifications_incident_id_idx
  on public.notifications(incident_id);
create index if not exists shifts_created_by_idx
  on public.shifts(created_by);
create index if not exists shifts_employee_id_idx
  on public.shifts(employee_id);
create index if not exists shifts_team_id_idx
  on public.shifts(team_id);
create index if not exists team_members_employee_id_idx
  on public.team_members(employee_id);
create index if not exists teams_created_by_idx
  on public.teams(created_by);
create index if not exists teams_department_id_idx
  on public.teams(department_id);
create index if not exists teams_supervisor_id_idx
  on public.teams(supervisor_id);
