-- Extensions
create extension if not exists pgcrypto;

-- Enums
create type business_role as enum ('OWNER', 'ADMIN', 'MANAGER', 'CASHIER', 'STAFF');
create type commission_kind as enum ('PERCENTAGE', 'FIXED');
create type sale_item_kind as enum ('SERVICE', 'PRODUCT');
create type sale_status as enum ('COMPLETED', 'VOIDED', 'REFUNDED');
create type payment_status_enum as enum ('PENDING', 'COMPLETED', 'FAILED', 'REFUNDED');
create type payment_method_enum as enum ('CASH', 'BANK_TRANSFER', 'CARD', 'OTHER');
create type inventory_movement_type as enum ('PURCHASE', 'SALE', 'RETURN', 'ADJUSTMENT', 'DAMAGE', 'EXPIRED');
create type commission_status as enum ('PENDING', 'APPROVED', 'REVERSED', 'PAID');
create type audit_action as enum (
  'LOGIN', 'LOGOUT', 'CREATE', 'UPDATE', 'DELETE', 'VOID', 'REFUND',
  'PAYMENT', 'STOCK_ADJUSTMENT', 'PERMISSION_CHANGE', 'SETTINGS_CHANGE'
);

-- Shared trigger: keep updated_at current on every row update.
create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
