-- Services -----------------------------------------------------------------

create table service_categories (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  name text not null check (char_length(trim(name)) > 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, name)
);

create trigger service_categories_set_updated_at
  before update on service_categories
  for each row execute function set_updated_at();

create table services (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  category_id uuid references service_categories(id) on delete set null,
  name text not null check (char_length(trim(name)) > 0),
  description text,
  price numeric(14,2) not null check (price >= 0),
  duration_minutes integer not null default 30 check (duration_minutes > 0),
  commission_type commission_kind not null default 'PERCENTAGE',
  commission_value numeric(14,2) not null default 0 check (commission_value >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index services_business_id_idx on services(business_id);
create index services_category_id_idx on services(category_id);

create trigger services_set_updated_at
  before update on services
  for each row execute function set_updated_at();

-- Products & suppliers -------------------------------------------------------

create table suppliers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  name text not null check (char_length(trim(name)) > 0),
  phone text,
  email text,
  address text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger suppliers_set_updated_at
  before update on suppliers
  for each row execute function set_updated_at();

create table product_categories (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  name text not null check (char_length(trim(name)) > 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, name)
);

create trigger product_categories_set_updated_at
  before update on product_categories
  for each row execute function set_updated_at();

create table products (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  category_id uuid references product_categories(id) on delete set null,
  supplier_id uuid references suppliers(id) on delete set null,
  name text not null check (char_length(trim(name)) > 0),
  sku text,
  barcode text,
  description text,
  cost_price numeric(14,2) not null default 0 check (cost_price >= 0),
  selling_price numeric(14,2) not null check (selling_price >= 0),
  stock_quantity integer not null default 0 check (stock_quantity >= 0),
  minimum_stock integer not null default 0 check (minimum_stock >= 0),
  expiry_date date,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, sku)
);

create index products_business_id_idx on products(business_id);
create index products_category_id_idx on products(category_id);
create index products_barcode_idx on products(business_id, barcode);
create index products_name_idx on products using gin (to_tsvector('simple', name));

create trigger products_set_updated_at
  before update on products
  for each row execute function set_updated_at();
