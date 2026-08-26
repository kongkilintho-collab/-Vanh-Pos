create table businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) > 0),
  logo_url text,
  phone text,
  email text,
  address text,
  currency text not null default 'LAK' check (char_length(currency) = 3),
  timezone text not null default 'Asia/Vientiane',
  tax_enabled boolean not null default false,
  tax_rate numeric(5,2) not null default 0 check (tax_rate >= 0 and tax_rate <= 100),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger businesses_set_updated_at
  before update on businesses
  for each row execute function set_updated_at();

create table branches (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  name text not null check (char_length(trim(name)) > 0),
  phone text,
  address text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index branches_business_id_idx on branches(business_id);

create trigger branches_set_updated_at
  before update on branches
  for each row execute function set_updated_at();
