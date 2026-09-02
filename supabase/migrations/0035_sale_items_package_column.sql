-- Phase 2: sale_items gains a PACKAGE line-item shape, one row per package
-- purchase (created by purchase_package, 0037_package_rpcs.sql). Applied
-- after 0034 has committed the PACKAGE enum value -- see that file's header
-- for why this must be a separate transaction.
--
-- package_id is nullable and `on delete set null`, same treatment as
-- customer_packages.package_id (0032): the sale_items row already carries
-- its own name_snapshot/unit_price, so it stays fully meaningful even if
-- the package definition is later deleted.

alter table sale_items
  add column package_id uuid references packages(id) on delete set null;

create index sale_items_package_id_idx on sale_items(package_id);

alter table sale_items drop constraint sale_items_item_reference_chk;

alter table sale_items add constraint sale_items_item_reference_chk check (
  (item_type = 'SERVICE' and service_id is not null and product_id is null and package_id is null) or
  (item_type = 'PRODUCT' and product_id is not null and service_id is null and package_id is null) or
  (item_type = 'PACKAGE' and package_id is not null and service_id is null and product_id is null)
);
