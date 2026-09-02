-- Phase 2: purchase_package (new) and set_appointment_status (extended).
--
-- purchase_package follows complete_sale's exact proven shape: auth.uid()
-- guard, has_role_at_least(p_business_id, 'CASHIER'), idempotency
-- short-circuit, tenant-scoped lookups for every referenced id, and
-- server-authoritative pricing -- packages.price is read here and used for
-- every downstream calculation; the client never supplies a price. Tax is
-- derived the same way 0029 fixed complete_sale to derive it (from the
-- business's own tax_enabled/tax_rate, never a client-supplied amount) --
-- there is no legacy p_tax_amount parameter to keep for wire compatibility
-- since this RPC is new. A customer is required (not optional, unlike
-- complete_sale) per the approved UX requirement that package purchases
-- always have an owner.
--
-- No sale_items.staff_id/commission on the PACKAGE line -- approved
-- design: no service-performance commission is earned merely by selling a
-- package (see 0036's header). Commission is created only at redemption,
-- inside set_appointment_status below.
create or replace function purchase_package(
  p_business_id uuid,
  p_branch_id uuid,
  p_customer_id uuid,
  p_package_id uuid,
  p_discount_amount numeric,
  p_payment_method payment_method_enum,
  p_paid_amount numeric,
  p_idempotency_key text
)
returns customer_packages
language plpgsql
security definer
set search_path = public
as $$
declare
  v_package packages;
  v_customer_package customer_packages;
  v_existing_sale sales;
  v_sale sales;
  v_business businesses;
  v_item record;
  v_subtotal numeric(14,2);
  v_taxable_base numeric(14,2);
  v_tax numeric(14,2);
  v_total numeric(14,2);
  v_change numeric(14,2);
  v_payment_status payment_status_enum;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to purchase a package';
  end if;

  if p_customer_id is null then
    raise exception 'A customer is required to purchase a package';
  end if;

  if p_idempotency_key is null then
    raise exception 'Idempotency key is required';
  end if;

  select * into v_existing_sale from sales
    where business_id = p_business_id and idempotency_key = p_idempotency_key;
  if found then
    select * into v_customer_package from customer_packages where sale_id = v_existing_sale.id;
    return v_customer_package;
  end if;

  if not exists (
    select 1 from customers where id = p_customer_id and business_id = p_business_id
  ) then
    raise exception 'Customer not found in this business';
  end if;

  select * into v_package from packages
    where id = p_package_id and business_id = p_business_id and active = true;

  if v_package.id is null then
    raise exception 'Package not found or inactive in this business';
  end if;

  if not exists (select 1 from package_items where package_id = p_package_id) then
    raise exception 'Package has no included services';
  end if;

  select * into v_business from businesses where id = p_business_id;

  v_subtotal := v_package.price;
  v_taxable_base := v_subtotal - coalesce(p_discount_amount, 0);
  if v_taxable_base < 0 then
    raise exception 'Discount cannot exceed the package price';
  end if;

  if v_business.tax_enabled and v_business.tax_rate > 0 and v_taxable_base > 0 then
    v_tax := round(v_taxable_base * v_business.tax_rate / 100, 2);
  else
    v_tax := 0;
  end if;

  v_total := v_taxable_base + v_tax;

  if p_paid_amount is null then
    raise exception 'Payment amount is required';
  elsif p_paid_amount < 0 then
    raise exception 'Payment amount cannot be negative';
  elsif p_paid_amount < v_total then
    raise exception 'Payment amount cannot be less than the package total';
  end if;

  v_payment_status := 'COMPLETED';
  v_change := p_paid_amount - v_total;

  insert into sales (
    business_id, branch_id, customer_id, cashier_id,
    subtotal, discount_amount, tax_amount, total_amount,
    paid_amount, change_amount, status, payment_status, idempotency_key
  ) values (
    p_business_id, p_branch_id, p_customer_id, auth.uid(),
    v_subtotal, coalesce(p_discount_amount, 0), v_tax, v_total,
    p_paid_amount, v_change, 'COMPLETED', v_payment_status, p_idempotency_key
  ) returning * into v_sale;

  insert into sale_items (
    business_id, sale_id, item_type, package_id,
    name_snapshot, quantity, unit_price, discount_amount, subtotal, commission_amount
  ) values (
    p_business_id, v_sale.id, 'PACKAGE', p_package_id,
    v_package.name, 1, v_package.price, coalesce(p_discount_amount, 0), v_taxable_base, 0
  );

  insert into payments (business_id, sale_id, payment_method, amount, status, created_by)
  values (p_business_id, v_sale.id, p_payment_method, p_paid_amount, v_payment_status, auth.uid());

  insert into customer_packages (
    business_id, customer_id, package_id, sale_id, name_snapshot, price_paid_snapshot, expires_at, status
  ) values (
    p_business_id, p_customer_id, p_package_id, v_sale.id, v_package.name, v_total,
    case when v_package.validity_days is not null then now() + (v_package.validity_days || ' days')::interval else null end,
    'ACTIVE'
  ) returning * into v_customer_package;

  for v_item in select * from package_items where package_id = p_package_id
  loop
    insert into customer_package_items (
      business_id, customer_package_id, service_id, name_snapshot, total_sessions, used_sessions
    )
    select p_business_id, v_customer_package.id, v_item.service_id, s.name, v_item.session_count, 0
    from services s where s.id = v_item.service_id;
  end loop;

  perform set_config('app.trusted_customer_stats_update', 'true', true);
  update customers set
    total_spent = total_spent + v_total,
    visit_count = visit_count + 1,
    last_visit_at = now()
  where id = p_customer_id and business_id = p_business_id;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
  values (p_business_id, auth.uid(), 'CREATE', 'customer_package', v_customer_package.id, to_jsonb(v_customer_package));

  return v_customer_package;
end;
$$;

revoke execute on function purchase_package(
  uuid, uuid, uuid, uuid, numeric, payment_method_enum, numeric, text
) from public;
revoke execute on function purchase_package(
  uuid, uuid, uuid, uuid, numeric, payment_method_enum, numeric, text
) from anon;
grant execute on function purchase_package(
  uuid, uuid, uuid, uuid, numeric, payment_method_enum, numeric, text
) to authenticated;

-- set_appointment_status: every line above the "-- Phase 2:" marker below
-- is verbatim from 0031_appointment_rpcs.sql -- same signature, same
-- guards, same state machine, same original audit_logs insert. The only
-- change is the new block appended before RETURN, which only executes when
-- p_status = 'COMPLETED' and only touches appointment_items that were
-- explicitly linked to a package entitlement at booking time
-- (customer_package_item_id is not null) -- every other transition, and
-- every appointment with no package-linked items, is byte-for-byte
-- unchanged from Phase 1.
--
-- Redemption re-validates everything server-side at completion time (never
-- trusting that booking-time eligibility still holds): the entitlement's
-- customer must match the appointment's customer (the cross-check flagged
-- in the Phase 2 audit as the one risk with no existing precedent to copy),
-- its service must match the booked service, the package must still be
-- ACTIVE and not expired, and it must have a remaining session -- each
-- customer_package_items row is locked FOR UPDATE before any of this is
-- checked, so two appointments racing for the same entitlement's last
-- session resolve to exactly one success (the second blocks on the lock,
-- then observes used_sessions = total_sessions once it resumes and
-- raises). The partial unique index from 0032 is the second, DB-level
-- layer against double redemption, not the only one.
--
-- Commission is created only here, at redemption, per the approved design
-- (0036) -- never at package purchase. Staff validity is re-checked against
-- business_members at redemption time, the same defensive re-check
-- complete_sale already performs for its own commission attribution.
create or replace function set_appointment_status(
  p_business_id uuid,
  p_appointment_id uuid,
  p_status appointment_status,
  p_cancel_reason text
)
returns appointments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_appointment appointments;
  v_old_data jsonb;
  v_allowed appointment_status[];
  v_appt_item appointment_items;
  v_cpi customer_package_items;
  v_cp customer_packages;
  v_redemption customer_package_redemptions;
  v_staff_id uuid;
  v_staff_valid boolean;
  v_commission_type commission_kind;
  v_commission_value numeric(14,2);
  v_commission_amount numeric(14,2);
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not has_role_at_least(p_business_id, 'CASHIER') then
    raise exception 'Insufficient permission to change appointment status';
  end if;

  select * into v_appointment from appointments
    where id = p_appointment_id and business_id = p_business_id
    for update;

  if v_appointment.id is null then
    raise exception 'Appointment not found in this business';
  end if;

  v_allowed := case v_appointment.status
    when 'SCHEDULED' then array['CONFIRMED', 'CANCELLED', 'NO_SHOW']::appointment_status[]
    when 'CONFIRMED' then array['CHECKED_IN', 'CANCELLED', 'NO_SHOW']::appointment_status[]
    when 'CHECKED_IN' then array['COMPLETED', 'CANCELLED']::appointment_status[]
    else array[]::appointment_status[]
  end;

  if not (p_status = any(v_allowed)) then
    raise exception 'Cannot move an appointment from % to %', v_appointment.status, p_status;
  end if;

  v_old_data := to_jsonb(v_appointment);

  update appointments set
    status = p_status,
    cancel_reason = case when p_status = 'CANCELLED' then p_cancel_reason else cancel_reason end
  where id = p_appointment_id
  returning * into v_appointment;

  insert into audit_logs (business_id, user_id, action, entity_type, entity_id, old_data, new_data)
  values (p_business_id, auth.uid(), 'UPDATE', 'appointment', v_appointment.id, v_old_data, to_jsonb(v_appointment));

  -- Phase 2: completion-time package redemption.
  if p_status = 'COMPLETED' then
    for v_appt_item in
      select * from appointment_items
      where appointment_id = p_appointment_id and customer_package_item_id is not null
    loop
      select * into v_cpi from customer_package_items
        where id = v_appt_item.customer_package_item_id and business_id = p_business_id
        for update;

      if v_cpi.id is null then
        raise exception 'Package entitlement not found in this business';
      end if;

      select * into v_cp from customer_packages where id = v_cpi.customer_package_id;

      if v_cp.customer_id is distinct from v_appointment.customer_id then
        raise exception 'This package entitlement does not belong to the appointment''s customer';
      end if;

      if v_cpi.service_id is distinct from v_appt_item.service_id then
        raise exception 'This package entitlement does not cover the booked service';
      end if;

      if v_cp.status <> 'ACTIVE' then
        raise exception 'This package is not active';
      end if;

      if v_cp.expires_at is not null and v_cp.expires_at < now() then
        raise exception 'This package has expired';
      end if;

      if v_cpi.used_sessions >= v_cpi.total_sessions then
        raise exception 'No remaining sessions on this package entitlement';
      end if;

      if exists (
        select 1 from customer_package_redemptions
        where appointment_item_id = v_appt_item.id and not reversed
      ) then
        raise exception 'This service has already been redeemed against a package';
      end if;

      update customer_package_items set used_sessions = used_sessions + 1
        where id = v_cpi.id
        returning * into v_cpi;

      v_staff_id := coalesce(v_appt_item.staff_id, v_appointment.staff_id);

      insert into customer_package_redemptions (
        business_id, customer_package_item_id, appointment_id, appointment_item_id, staff_id
      ) values (
        p_business_id, v_cpi.id, p_appointment_id, v_appt_item.id, v_staff_id
      ) returning * into v_redemption;

      insert into audit_logs (business_id, user_id, action, entity_type, entity_id, new_data)
      values (p_business_id, auth.uid(), 'CREATE', 'customer_package_redemption', v_redemption.id, to_jsonb(v_redemption));

      v_staff_valid := exists (
        select 1 from business_members
        where business_id = p_business_id and user_id = v_staff_id and active = true
      );

      select commission_type, commission_value into v_commission_type, v_commission_value
        from services where id = v_appt_item.service_id and business_id = p_business_id;

      v_commission_amount := 0;
      if v_staff_valid and v_commission_type is not null then
        if v_commission_type = 'PERCENTAGE' then
          v_commission_amount := round(v_appt_item.price_snapshot * coalesce(v_commission_value, 0) / 100, 2);
        else
          v_commission_amount := coalesce(v_commission_value, 0);
        end if;
      end if;

      if v_commission_amount > 0 then
        insert into commissions (
          business_id, customer_package_redemption_id, staff_id, commission_type,
          commission_rate, commission_amount, status
        ) values (
          p_business_id, v_redemption.id, v_staff_id,
          v_commission_type, coalesce(v_commission_value, 0), v_commission_amount, 'PENDING'
        );
      end if;
    end loop;
  end if;

  return v_appointment;
end;
$$;

revoke execute on function set_appointment_status(uuid, uuid, appointment_status, text) from public;
revoke execute on function set_appointment_status(uuid, uuid, appointment_status, text) from anon;
grant execute on function set_appointment_status(uuid, uuid, appointment_status, text) to authenticated;
