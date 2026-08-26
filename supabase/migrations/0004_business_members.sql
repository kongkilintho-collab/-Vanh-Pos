-- Membership + role of a user within a business. This is the multi-tenant
-- join table every RLS policy in the system keys off of.
create table business_members (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  role business_role not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, user_id)
);

create index business_members_business_id_idx on business_members(business_id);
create index business_members_user_id_idx on business_members(user_id);

create trigger business_members_set_updated_at
  before update on business_members
  for each row execute function set_updated_at();
