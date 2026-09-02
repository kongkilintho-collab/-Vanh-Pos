-- Phase 2 forensic fix: sale_items.package_id was added in
-- 0035_sale_items_package_column.sql as an inline column reference with no
-- explicit constraint name, so Postgres auto-named it
-- sale_items_package_id_fkey (confirmed by inspection, not assumed) --
-- `on delete set null`.
--
-- Defect (confirmed live during Phase 2 E2E regression): deleting a
-- `packages` row that has ever been purchased cascades that SET NULL onto
-- its sale_items row, which then immediately violates
-- sale_items_item_reference_chk (0035) -- that constraint requires
-- package_id IS NOT NULL whenever item_type = 'PACKAGE'. The DELETE fails
-- with a confusing 23514 check_violation instead of a clear, standard
-- foreign-key rejection.
--
-- Fix: package_id becomes `on delete restrict`, matching every other FK in
-- this schema that backs financial/attribution history a row must never
-- silently lose (sales.cashier_id, payments.created_by,
-- appointments.staff_id, customer_packages.customer_id,
-- customer_package_redemptions.customer_package_item_id -- all already
-- `on delete restrict` for the same reason). This does not change behavior
-- for any existing row: it only affects a future DELETE attempt against a
-- packages row that already has purchase history, which now fails
-- immediately and cleanly (23503 foreign_key_violation) instead of via the
-- CHECK constraint. A never-purchased package is completely unaffected --
-- RESTRICT only blocks deletion when a referencing sale_items row exists.
--
-- Nothing else changes: sale_items_item_reference_chk, the services/
-- products FKs (which have the identical latent SET NULL + CHECK pattern,
-- confirmed by inspection but explicitly out of scope for this migration
-- per the approved fix), package RLS, and every Phase 2 RPC are untouched.
-- No data migration is required -- every existing package_id value is
-- already valid against packages(id) (it could not have violated the prior
-- constraint), so validating the new constraint is instant.
alter table sale_items
  drop constraint sale_items_package_id_fkey;

alter table sale_items
  add constraint sale_items_package_id_fkey
  foreign key (package_id)
  references packages(id)
  on delete restrict;
