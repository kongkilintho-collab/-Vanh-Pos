-- Phase 2: lets a booked appointment_item declare, up front, which
-- customer_package_item it's meant to be covered by. Nullable and purely
-- additive -- every existing Phase 1 row/RPC call is unaffected (defaults
-- null). The actual session redemption still only happens at completion
-- (0036_package_rpcs.sql extends set_appointment_status), never at
-- booking -- this column only records intent, so it must not be trusted as
-- proof of redemption on its own.

alter table appointment_items
  add column customer_package_item_id uuid references customer_package_items(id) on delete set null;

create index appointment_items_customer_package_item_id_idx
  on appointment_items(customer_package_item_id)
  where customer_package_item_id is not null;
