-- Phase 2: lets a commission originate from a package-session redemption
-- instead of a sale_item -- approved design (see Phase 2 architecture
-- review): commission is earned by whoever performs the redeemed service,
-- not at package purchase time, so redemption-driven commissions have no
-- sale/sale_item at all.
--
-- sale_id and sale_item_id both become nullable; the new CHECK constraint
-- enforces the two allowed shapes exactly (never a commission with neither
-- source, or with both):
--   sale-driven:      sale_id NOT NULL, sale_item_id NOT NULL, redemption NULL
--   redemption-driven: sale_id NULL,     sale_item_id NULL,     redemption NOT NULL
--
-- customer_package_redemption_id uses ON DELETE RESTRICT (not CASCADE):
-- redemptions are financial/attribution history and must never silently
-- disappear out from under a commission row, the same reasoning already
-- applied to sales.cashier_id/payments.created_by/appointments.staff_id
-- (all `on delete restrict`) elsewhere in this schema.
--
-- No existing repository, screen, or report query is touched here --
-- CommissionRepository.updateStatus only ever writes `status`, and
-- reports_repository's commission query only selects commission_amount;
-- neither depends on sale_id/sale_item_id shape. The one real Flutter
-- dependency (Commission.fromJson's non-nullable saleId/saleItemId casts)
-- is fixed in the same Phase 2 change set, not here.

alter table commissions alter column sale_id drop not null;
alter table commissions alter column sale_item_id drop not null;

alter table commissions
  add column customer_package_redemption_id uuid references customer_package_redemptions(id) on delete restrict;

create unique index commissions_redemption_unique on commissions(customer_package_redemption_id)
  where customer_package_redemption_id is not null;

alter table commissions add constraint commissions_source_chk check (
  (sale_id is not null and sale_item_id is not null and customer_package_redemption_id is null)
  or
  (sale_id is null and sale_item_id is null and customer_package_redemption_id is not null)
);
