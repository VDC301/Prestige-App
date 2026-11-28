-- Security hardening before first installation.
-- Draft announcements are visible only to administrators.
drop policy if exists "department members read announcements" on public.announcements;
create policy "members read published announcements" on public.announcements
for select to authenticated
using (
  public.is_active_user()
  and (
    public.is_admin()
    or (published_at is not null and public.has_department_access(department_id))
  )
);

-- Authors may edit/delete their discussions only while they remain active
-- members of that discussion's department. Administrators retain oversight.
drop policy if exists "authors or admins update discussions" on public.discussions;
create policy "authors or admins update discussions" on public.discussions
for update to authenticated
using (
  public.is_admin()
  or (
    public.is_active_user()
    and created_by=(select auth.uid())
    and public.has_department_access(department_id)
  )
)
with check (
  public.is_admin()
  or (
    public.is_active_user()
    and created_by=(select auth.uid())
    and public.has_department_access(department_id)
  )
);

drop policy if exists "authors or admins delete discussions" on public.discussions;
create policy "authors or admins delete discussions" on public.discussions
for delete to authenticated
using (
  public.is_admin()
  or (
    public.is_active_user()
    and created_by=(select auth.uid())
    and public.has_department_access(department_id)
  )
);

-- Comment authors may edit/delete only while they retain department access.
drop policy if exists "authors or admins edit comments" on public.discussion_comments;
create policy "authors or admins edit comments" on public.discussion_comments
for update to authenticated
using (
  public.is_admin()
  or (
    public.is_active_user()
    and author_id=(select auth.uid())
    and exists (
      select 1 from public.discussions d
      where d.id=discussion_id and public.has_department_access(d.department_id)
    )
  )
)
with check (
  public.is_admin()
  or (
    public.is_active_user()
    and author_id=(select auth.uid())
    and exists (
      select 1 from public.discussions d
      where d.id=discussion_id and public.has_department_access(d.department_id)
    )
  )
);

drop policy if exists "authors or admins delete comments" on public.discussion_comments;
create policy "authors or admins delete comments" on public.discussion_comments
for delete to authenticated
using (
  public.is_admin()
  or (
    public.is_active_user()
    and author_id=(select auth.uid())
    and exists (
      select 1 from public.discussions d
      where d.id=discussion_id and public.has_department_access(d.department_id)
    )
  )
);
