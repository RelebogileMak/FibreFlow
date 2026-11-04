-- FibreFlow tenant isolation.
-- Apply as the table owner, then run the API as a different role that is not
-- a superuser and does not have BYPASSRLS. Owners bypass RLS unless FORCE is
-- set, which keeps migrations and seeds working. The API role must not own
-- these tables.

CREATE TABLE tenants (
  id text PRIMARY KEY CHECK (id ~ '^[A-Za-z0-9_-]{1,64}$'),
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id text NOT NULL REFERENCES tenants (id),
  email text NOT NULL,
  roles text[] NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, email)
);

CREATE TABLE customers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id text NOT NULL REFERENCES tenants (id),
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE leads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id text NOT NULL REFERENCES tenants (id),
  customer_id uuid REFERENCES customers (id),
  name text NOT NULL,
  stage text NOT NULL DEFAULT 'new',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE quotes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id text NOT NULL REFERENCES tenants (id),
  customer_id uuid NOT NULL REFERENCES customers (id),
  title text NOT NULL,
  status text NOT NULL DEFAULT 'draft',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id text NOT NULL REFERENCES tenants (id),
  customer_id uuid NOT NULL REFERENCES customers (id),
  quote_id uuid REFERENCES quotes (id),
  technician_id uuid REFERENCES users (id),
  title text NOT NULL,
  status text NOT NULL DEFAULT 'scheduled',
  technician_note text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE activity_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id text NOT NULL REFERENCES tenants (id),
  actor_id uuid REFERENCES users (id),
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX users_tenant_id_idx ON users (tenant_id);
CREATE INDEX customers_tenant_id_idx ON customers (tenant_id);
CREATE INDEX leads_tenant_id_idx ON leads (tenant_id);
CREATE INDEX quotes_tenant_id_idx ON quotes (tenant_id);
CREATE INDEX jobs_tenant_id_idx ON jobs (tenant_id);
CREATE INDEX activity_events_tenant_id_idx ON activity_events (tenant_id, created_at DESC);

-- Matches DatabaseService: SELECT set_config('app.tenant_id', $1, true)
CREATE OR REPLACE FUNCTION app_current_tenant() RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT current_setting('app.tenant_id', true)
$$;

DO $$
DECLARE
  target regclass;
BEGIN
  FOREACH target IN ARRAY ARRAY[
    'users'::regclass,
    'customers'::regclass,
    'leads'::regclass,
    'quotes'::regclass,
    'jobs'::regclass,
    'activity_events'::regclass
  ]
  LOOP
    EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', target);
    EXECUTE format('DROP POLICY IF EXISTS tenant_isolation ON %s', target);
    EXECUTE format(
      'CREATE POLICY tenant_isolation ON %s USING (tenant_id = app_current_tenant()) WITH CHECK (tenant_id = app_current_tenant())',
      target
    );
  END LOOP;
END;
$$;

ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON tenants;
CREATE POLICY tenant_isolation ON tenants
  USING (id = app_current_tenant())
  WITH CHECK (id = app_current_tenant());
