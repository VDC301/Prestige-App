-- Remove table-level privileges that bypass or sit outside row-level security.
-- TRUNCATE is not governed by RLS, so authenticated/anon must never receive it.
-- REFERENCES and TRIGGER are not required by browser clients either.

REVOKE TRUNCATE, REFERENCES, TRIGGER
ON ALL TABLES IN SCHEMA public
FROM anon, authenticated;

-- Keep the same least-privilege baseline for tables created by either
-- database role used for Supabase migrations/project administration.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLES
FROM anon, authenticated;

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLES
FROM anon, authenticated;

COMMENT ON SCHEMA public IS
  'Browser roles must not have TRUNCATE, REFERENCES, or TRIGGER table privileges; row-level security does not protect TRUNCATE.';
