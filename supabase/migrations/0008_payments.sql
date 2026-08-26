create table payments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  sale_id uuid not null references sales(id) on delete cascade,
  payment_method payment_method_enum not null,
  amount numeric(14,2) not null check (amount > 0),
  reference text,
  status payment_status_enum not null default 'COMPLETED',
  created_by uuid not null references profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create index payments_business_id_idx on payments(business_id);
create index payments_sale_id_idx on payments(sale_id);
