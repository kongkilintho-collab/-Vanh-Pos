create table commissions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  sale_id uuid not null references sales(id) on delete cascade,
  sale_item_id uuid not null references sale_items(id) on delete cascade,
  staff_id uuid not null references profiles(id) on delete restrict,
  commission_type commission_kind not null,
  commission_rate numeric(14,2) not null default 0 check (commission_rate >= 0),
  commission_amount numeric(14,2) not null check (commission_amount >= 0),
  status commission_status not null default 'PENDING',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (sale_item_id)
);

create index commissions_business_id_idx on commissions(business_id);
create index commissions_staff_id_idx on commissions(staff_id);
create index commissions_sale_id_idx on commissions(sale_id);
create index commissions_status_idx on commissions(business_id, status);

create trigger commissions_set_updated_at
  before update on commissions
  for each row execute function set_updated_at();
