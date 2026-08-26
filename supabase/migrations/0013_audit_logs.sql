-- Audit trail. Insert-only from the application's perspective: RLS grants
-- SELECT to business admins and INSERT to any active member, but never
-- grants UPDATE or DELETE to anyone (see 0015_rls_policies.sql).
create table audit_logs (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  user_id uuid references profiles(id) on delete set null,
  action audit_action not null,
  entity_type text not null,
  entity_id uuid,
  old_data jsonb,
  new_data jsonb,
  metadata jsonb,
  created_at timestamptz not null default now()
);

create index audit_logs_business_id_idx on audit_logs(business_id);
create index audit_logs_entity_idx on audit_logs(entity_type, entity_id);
create index audit_logs_created_at_idx on audit_logs(business_id, created_at);
