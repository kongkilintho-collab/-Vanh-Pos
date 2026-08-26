-- Every stock change is traced here. Nothing should mutate
-- products.stock_quantity without a corresponding row in this table
-- (enforced in application/RPC logic, not by trigger, so adjustments can
-- carry context such as reference_type/reference_id).
create table inventory_movements (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses(id) on delete cascade,
  branch_id uuid references branches(id) on delete set null,
  product_id uuid not null references products(id) on delete cascade,
  movement_type inventory_movement_type not null,
  quantity integer not null check (quantity <> 0),
  reference_type text,
  reference_id uuid,
  note text,
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index inventory_movements_business_id_idx on inventory_movements(business_id);
create index inventory_movements_product_id_idx on inventory_movements(product_id);
create index inventory_movements_reference_idx on inventory_movements(reference_type, reference_id);
create index inventory_movements_created_at_idx on inventory_movements(business_id, created_at);
