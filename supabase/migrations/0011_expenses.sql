create table expense_categories (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  name text not null check (char_length(trim(name)) > 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, name)
);

create trigger expense_categories_set_updated_at
  before update on expense_categories
  for each row execute function set_updated_at();

create table expenses (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  branch_id uuid references branches(id) on delete set null,
  category_id uuid references expense_categories(id) on delete set null,
  amount numeric(14,2) not null check (amount > 0),
  payment_method payment_method_enum not null default 'CASH',
  description text,
  expense_date date not null default current_date,
  created_by uuid not null references profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index expenses_business_id_idx on expenses(business_id);
create index expenses_category_id_idx on expenses(category_id);
create index expenses_date_idx on expenses(business_id, expense_date);

create trigger expenses_set_updated_at
  before update on expenses
  for each row execute function set_updated_at();
