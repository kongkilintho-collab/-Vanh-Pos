-- Enable RLS everywhere. No table is ever trusted to filter by business_id
-- supplied from the client — every check below re-derives membership from
-- business_members using auth.uid(), server-side.

alter table businesses enable row level security;
alter table branches enable row level security;
alter table profiles enable row level security;
alter table business_members enable row level security;
alter table customers enable row level security;
alter table customer_notes enable row level security;
alter table service_categories enable row level security;
alter table services enable row level security;
alter table product_categories enable row level security;
alter table products enable row level security;
alter table suppliers enable row level security;
alter table sales enable row level security;
alter table sale_items enable row level security;
alter table payments enable row level security;
alter table inventory_movements enable row level security;
alter table commissions enable row level security;
alter table expense_categories enable row level security;
alter table expenses enable row level security;
alter table settings enable row level security;
alter table audit_logs enable row level security;

-- businesses ------------------------------------------------------------
-- No INSERT policy: businesses are only created via the
-- create_business_with_owner() SECURITY DEFINER function so the owner
-- membership is created atomically with the business.

create policy businesses_select on businesses
  for select using (is_member(id));

create policy businesses_update on businesses
  for update using (has_role_at_least(id, 'ADMIN'))
  with check (has_role_at_least(id, 'ADMIN'));

-- branches ----------------------------------------------------------------

create policy branches_select on branches
  for select using (is_member(business_id));

create policy branches_insert on branches
  for insert with check (has_role_at_least(business_id, 'ADMIN'));

create policy branches_update on branches
  for update using (has_role_at_least(business_id, 'ADMIN'))
  with check (has_role_at_least(business_id, 'ADMIN'));

create policy branches_delete on branches
  for delete using (has_role_at_least(business_id, 'ADMIN'));

-- profiles ------------------------------------------------------------------
-- No INSERT policy: rows are created by the handle_new_auth_user() trigger.
-- No DELETE policy: profiles are removed by cascading from auth.users.

create policy profiles_select on profiles
  for select using (
    id = auth.uid()
    or exists (
      select 1 from business_members mine
      join business_members theirs on theirs.business_id = mine.business_id
      where mine.user_id = auth.uid() and mine.active
        and theirs.user_id = profiles.id and theirs.active
    )
  );

create policy profiles_update on profiles
  for update using (id = auth.uid())
  with check (id = auth.uid());

-- business_members ----------------------------------------------------------
-- No INSERT policy for the initial OWNER row: that happens inside
-- create_business_with_owner(). Later invites go through the
-- invite_business_member() function so role-escalation rules are enforced
-- in one place instead of duplicated in RLS.

create policy business_members_select on business_members
  for select using (is_member(business_id));

-- An ADMIN may manage MANAGER/CASHIER/STAFF rows, but only an OWNER may
-- touch a row that is (or would become) OWNER/ADMIN — otherwise an ADMIN
-- could self-escalate or demote/remove an owner via a raw UPDATE.

create policy business_members_update on business_members
  for update using (
    has_role_at_least(business_id, 'ADMIN')
    and (role <> 'OWNER' or member_role(business_id) = 'OWNER')
  )
  with check (
    has_role_at_least(business_id, 'ADMIN')
    and (role not in ('OWNER', 'ADMIN') or member_role(business_id) = 'OWNER')
  );

create policy business_members_delete on business_members
  for delete using (
    has_role_at_least(business_id, 'ADMIN')
    and (role <> 'OWNER' or member_role(business_id) = 'OWNER')
  );

-- customers / customer_notes -------------------------------------------------

create policy customers_select on customers
  for select using (is_member(business_id));

create policy customers_insert on customers
  for insert with check (has_role_at_least(business_id, 'CASHIER'));

create policy customers_update on customers
  for update using (has_role_at_least(business_id, 'CASHIER'))
  with check (has_role_at_least(business_id, 'CASHIER'));

create policy customers_delete on customers
  for delete using (has_role_at_least(business_id, 'ADMIN'));

create policy customer_notes_select on customer_notes
  for select using (is_member(business_id));

create policy customer_notes_insert on customer_notes
  for insert with check (has_role_at_least(business_id, 'CASHIER'));

-- service_categories / services ----------------------------------------------

create policy service_categories_select on service_categories
  for select using (is_member(business_id));

create policy service_categories_write on service_categories
  for insert with check (has_role_at_least(business_id, 'MANAGER'));

create policy service_categories_update on service_categories
  for update using (has_role_at_least(business_id, 'MANAGER'))
  with check (has_role_at_least(business_id, 'MANAGER'));

create policy service_categories_delete on service_categories
  for delete using (has_role_at_least(business_id, 'MANAGER'));

create policy services_select on services
  for select using (is_member(business_id));

create policy services_insert on services
  for insert with check (has_role_at_least(business_id, 'MANAGER'));

create policy services_update on services
  for update using (has_role_at_least(business_id, 'MANAGER'))
  with check (has_role_at_least(business_id, 'MANAGER'));

create policy services_delete on services
  for delete using (has_role_at_least(business_id, 'MANAGER'));

-- product_categories / products / suppliers ----------------------------------

create policy product_categories_select on product_categories
  for select using (is_member(business_id));

create policy product_categories_insert on product_categories
  for insert with check (has_role_at_least(business_id, 'MANAGER'));

create policy product_categories_update on product_categories
  for update using (has_role_at_least(business_id, 'MANAGER'))
  with check (has_role_at_least(business_id, 'MANAGER'));

create policy product_categories_delete on product_categories
  for delete using (has_role_at_least(business_id, 'MANAGER'));

create policy products_select on products
  for select using (is_member(business_id));

create policy products_insert on products
  for insert with check (has_role_at_least(business_id, 'MANAGER'));

create policy products_update on products
  for update using (has_role_at_least(business_id, 'MANAGER'))
  with check (has_role_at_least(business_id, 'MANAGER'));

create policy products_delete on products
  for delete using (has_role_at_least(business_id, 'MANAGER'));

create policy suppliers_select on suppliers
  for select using (is_member(business_id));

create policy suppliers_insert on suppliers
  for insert with check (has_role_at_least(business_id, 'MANAGER'));

create policy suppliers_update on suppliers
  for update using (has_role_at_least(business_id, 'MANAGER'))
  with check (has_role_at_least(business_id, 'MANAGER'));

create policy suppliers_delete on suppliers
  for delete using (has_role_at_least(business_id, 'MANAGER'));

-- sales / sale_items ----------------------------------------------------------
-- No DELETE policy on either table, ever: sales are never hard-deleted
-- (see spec section 18/38) — void/refund is a status UPDATE instead.

create policy sales_select on sales
  for select using (is_member(business_id));

create policy sales_insert on sales
  for insert with check (has_role_at_least(business_id, 'CASHIER'));

create policy sales_update on sales
  for update using (has_role_at_least(business_id, 'MANAGER'))
  with check (has_role_at_least(business_id, 'MANAGER'));

create policy sale_items_select on sale_items
  for select using (is_member(business_id));

create policy sale_items_insert on sale_items
  for insert with check (has_role_at_least(business_id, 'CASHIER'));

-- payments --------------------------------------------------------------------
-- No DELETE policy: payments are corrected via status updates, not removal.

create policy payments_select on payments
  for select using (is_member(business_id));

create policy payments_insert on payments
  for insert with check (has_role_at_least(business_id, 'CASHIER'));

create policy payments_update on payments
  for update using (has_role_at_least(business_id, 'MANAGER'))
  with check (has_role_at_least(business_id, 'MANAGER'));

-- inventory_movements -----------------------------------------------------------
-- No UPDATE/DELETE policy: it is an append-only ledger. Corrections are new
-- offsetting movements (ADJUSTMENT), not edits to history.

create policy inventory_movements_select on inventory_movements
  for select using (is_member(business_id));

create policy inventory_movements_insert on inventory_movements
  for insert with check (has_role_at_least(business_id, 'MANAGER'));

-- commissions -------------------------------------------------------------------

create policy commissions_select on commissions
  for select using (is_member(business_id));

create policy commissions_insert on commissions
  for insert with check (has_role_at_least(business_id, 'ADMIN'));

create policy commissions_update on commissions
  for update using (has_role_at_least(business_id, 'ADMIN'))
  with check (has_role_at_least(business_id, 'ADMIN'));

-- expense_categories / expenses ---------------------------------------------------

create policy expense_categories_select on expense_categories
  for select using (is_member(business_id));

create policy expense_categories_insert on expense_categories
  for insert with check (has_role_at_least(business_id, 'ADMIN'));

create policy expense_categories_update on expense_categories
  for update using (has_role_at_least(business_id, 'ADMIN'))
  with check (has_role_at_least(business_id, 'ADMIN'));

create policy expense_categories_delete on expense_categories
  for delete using (has_role_at_least(business_id, 'ADMIN'));

create policy expenses_select on expenses
  for select using (is_member(business_id));

create policy expenses_insert on expenses
  for insert with check (has_role_at_least(business_id, 'ADMIN'));

create policy expenses_update on expenses
  for update using (has_role_at_least(business_id, 'ADMIN'))
  with check (has_role_at_least(business_id, 'ADMIN'));

create policy expenses_delete on expenses
  for delete using (has_role_at_least(business_id, 'ADMIN'));

-- settings ------------------------------------------------------------------------

create policy settings_select on settings
  for select using (is_member(business_id));

create policy settings_insert on settings
  for insert with check (has_role_at_least(business_id, 'ADMIN'));

create policy settings_update on settings
  for update using (has_role_at_least(business_id, 'ADMIN'))
  with check (has_role_at_least(business_id, 'ADMIN'));

create policy settings_delete on settings
  for delete using (has_role_at_least(business_id, 'ADMIN'));

-- audit_logs ------------------------------------------------------------------------
-- No UPDATE/DELETE policy for anyone: the log is immutable from the client.

create policy audit_logs_select on audit_logs
  for select using (has_role_at_least(business_id, 'ADMIN'));

create policy audit_logs_insert on audit_logs
  for insert with check (
    is_member(business_id)
    and (user_id = auth.uid() or user_id is null)
  );
