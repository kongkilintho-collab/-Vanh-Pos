-- Free-form per-business settings (receipt footer text, POS behavior
-- toggles, etc.) as key/value so new settings don't require a migration.
create table settings (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  key text not null,
  value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  unique (business_id, key)
);

create trigger settings_set_updated_at
  before update on settings
  for each row execute function set_updated_at();
