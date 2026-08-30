-- Day 8 audit (F8-1 CRITICAL, F8-2 HIGH, F8-3 HIGH, F8-4 MEDIUM, F8-5
-- MEDIUM): sales_insert, sale_items_insert, payments_insert,
-- commissions_insert, and inventory_movements_insert (0015_rls_policies.sql)
-- were all role-gated only ("has_role_at_least(business_id, X)"), with no
-- validation of the values being inserted or their relationship to other
-- rows. That let an authenticated CASHIER+/ADMIN+/MANAGER+ session bypass
-- complete_sale/adjust_stock entirely via a direct REST INSERT --
-- fabricating an arbitrary sale with no items, injecting a retroactive
-- line item into an existing (even closed) sale with a forged price,
-- fabricating a commission payout unconnected to any real sale, inserting
-- a phantom payment, or fabricating an inventory ledger entry that never
-- moved real stock. This defeated every integrity control Day 7 built
-- into complete_sale, since that function is only one path into these
-- tables -- the tables themselves remained directly writable.
--
-- Fix: remove the client-facing INSERT policy on all five tables
-- entirely, so no role satisfies any INSERT policy on them and Postgres's
-- default-deny applies. This is the same, already-proven-safe pattern
-- this project already uses for `businesses` (see 0015_rls_policies.sql:
-- "No INSERT policy: businesses are only created via the
-- create_business_with_owner() SECURITY DEFINER function") and for the
-- initial `business_members` OWNER row -- complete_sale and adjust_stock
-- are SECURITY DEFINER functions owned by a role that bypasses RLS for
-- its own writes (the same reason create_business_with_owner has always
-- been able to insert into `businesses` despite no policy ever existing
-- there), so removing these policies does not require touching either
-- function and does not change their behavior for a legitimate caller in
-- any way.
--
-- SELECT/UPDATE/DELETE policies on all five tables are completely
-- untouched: sales_select/sales_update, sale_items_select (no
-- UPDATE/DELETE policy existed or exists), payments_select/
-- payments_update, commissions_select/commissions_update,
-- inventory_movements_select (no UPDATE/DELETE policy existed or exists)
-- all remain exactly as they were. The Day 6 column-protection triggers
-- on sales/payments/commissions (0022_protect_financial_snapshot_columns.sql)
-- are BEFORE UPDATE triggers and are unaffected either way.
--
-- Intended end state:
--   direct authenticated REST INSERT -> sales/sale_items/payments/
--     commissions/inventory_movements: DENIED for every role
--   complete_sale() -> still succeeds (inserts all five tables internally)
--   adjust_stock() -> still succeeds (inserts inventory_movements internally)
drop policy sales_insert on sales;
drop policy sale_items_insert on sale_items;
drop policy payments_insert on payments;
drop policy inventory_movements_insert on inventory_movements;
drop policy commissions_insert on commissions;
