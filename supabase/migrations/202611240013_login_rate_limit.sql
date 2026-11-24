-- Atomic IP-based throttling for the pre-authentication employee lookup.
-- The caller stores only an HMAC of the trusted Cloudflare client IP.
create table private.login_rate_limits (
  bucket_key text primary key check (bucket_key ~ '^[a-f0-9]{64}$'),
  window_started_at timestamptz not null,
  attempts integer not null check (attempts >= 1)
);

revoke all on table private.login_rate_limits from public, anon, authenticated, service_role;

create or replace function private.consume_login_rate_limit(
  p_bucket_key text,
  p_limit integer,
  p_window_seconds integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, private
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_attempts integer;
  v_window_started_at timestamptz;
  v_retry_after integer;
begin
  if p_bucket_key is null or p_bucket_key !~ '^[a-f0-9]{64}$'
     or p_limit < 1 or p_limit > 5000
     or p_window_seconds < 1 or p_window_seconds > 86400 then
    raise exception 'Invalid rate-limit parameters.';
  end if;

  insert into private.login_rate_limits as existing (
    bucket_key, window_started_at, attempts
  ) values (
    p_bucket_key, v_now, 1
  )
  on conflict (bucket_key) do update
  set
    window_started_at = case
      when existing.window_started_at <= v_now - make_interval(secs => p_window_seconds)
        then v_now
      else existing.window_started_at
    end,
    attempts = case
      when existing.window_started_at <= v_now - make_interval(secs => p_window_seconds)
        then 1
      else existing.attempts + 1
    end
  returning attempts, window_started_at
  into v_attempts, v_window_started_at;

  v_retry_after := greatest(
    1,
    ceil(extract(epoch from (
      v_window_started_at + make_interval(secs => p_window_seconds) - v_now
    )))::integer
  );

  return jsonb_build_object(
    'allowed', v_attempts <= p_limit,
    'retry_after_seconds', case when v_attempts > p_limit then v_retry_after else 0 end
  );
end;
$$;

revoke all on function private.consume_login_rate_limit(text, integer, integer)
  from public, anon, authenticated;
grant execute on function private.consume_login_rate_limit(text, integer, integer)
  to service_role;
