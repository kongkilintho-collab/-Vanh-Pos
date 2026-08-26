create sequence sales_receipt_seq;

create table sales (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  branch_id uuid references branches(id) on delete set null,
  customer_id uuid references customers(id) on delete set null,
  cashier_id uuid not null references profiles(id) on delete restrict,
  receipt_number text not null default ('R-' || to_char(now(), 'YYYYMMDD') || '-' || lpad(nextval('sales_receipt_seq')::text, 6, '0')),
  subtotal numeric(14,2) not null check (subtotal >= 0),
  discount_amount numeric(14,2) not null default 0 check (discount_amount >= 0),
  tax_amount numeric(14,2) not null default 0 check (tax_amount >= 0),
  total_amount numeric(14,2) not null check (total_amount >= 0),
  paid_amount numeric(14,2) not null default 0 check (paid_amount >= 0),
  change_amount numeric(14,2) not null default 0 check (change_amount >= 0),
  status sale_status not null default 'COMPLETED',
  payment_status payment_status_enum not null default 'PENDING',
  idempotency_key text,
  void_reason text,
  voided_by uuid references profiles(id) on delete set null,
  voided_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, receipt_number),
  unique (business_id, idempotency_key)
);

create index sales_business_id_idx on sales(business_id);
create index sales_branch_id_idx on sales(branch_id);
create index sales_customer_id_idx on sales(customer_id);
create index sales_cashier_id_idx on sales(cashier_id);
create index sales_created_at_idx on sales(business_id, created_at);
create index sales_status_idx on sales(business_id, status);

create trigger sales_set_updated_at
  before update on sales
  for each row execute function set_updated_at();

create table sale_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  sale_id uuid not null references sales(id) on delete cascade,
  item_type sale_item_kind not null,
  service_id uuid references services(id) on delete set null,
  product_id uuid references products(id) on delete set null,
  staff_id uuid references profiles(id) on delete set null,
  name_snapshot text not null,
  quantity integer not null default 1 check (quantity > 0),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  discount_amount numeric(14,2) not null default 0 check (discount_amount >= 0),
  subtotal numeric(14,2) not null check (subtotal >= 0),
  commission_amount numeric(14,2) not null default 0 check (commission_amount >= 0),
  created_at timestamptz not null default now(),
  constraint sale_items_item_reference_chk check (
    (item_type = 'SERVICE' and service_id is not null and product_id is null) or
    (item_type = 'PRODUCT' and product_id is not null and service_id is null)
  )
);

create index sale_items_sale_id_idx on sale_items(sale_id);
create index sale_items_business_id_idx on sale_items(business_id);
create index sale_items_staff_id_idx on sale_items(staff_id);
create index sale_items_service_id_idx on sale_items(service_id);
create index sale_items_product_id_idx on sale_items(product_id);
