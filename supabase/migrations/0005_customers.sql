create table customers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  branch_id uuid references branches(id) on delete set null,
  name text not null check (char_length(trim(name)) > 0),
  phone text,
  gender text check (gender in ('MALE', 'FEMALE', 'OTHER')),
  birthday date,
  notes text,
  total_spent numeric(14,2) not null default 0,
  visit_count integer not null default 0,
  last_visit_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index customers_business_id_idx on customers(business_id);
create index customers_phone_idx on customers(business_id, phone);
create index customers_name_idx on customers using gin (to_tsvector('simple', name));

create trigger customers_set_updated_at
  before update on customers
  for each row execute function set_updated_at();

create table customer_notes (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  customer_id uuid not null references customers(id) on delete cascade,
  note text not null check (char_length(trim(note)) > 0),
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index customer_notes_customer_id_idx on customer_notes(customer_id);
