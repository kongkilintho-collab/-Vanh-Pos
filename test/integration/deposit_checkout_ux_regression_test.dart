// Live regression coverage for the Phase 3 deposit-checkout UX completion --
// specifically PosRepository.completeSale's new `allowPartialPayment`
// parameter (see lib/features/pos/data/pos_repository.dart and
// lib/features/pos/presentation/deposit_checkout_sheet.dart). Distinct from
// test/integration/phase3_deposit_settlement_regression_test.dart, which
// exercises the complete_sale/record_sale_payment RPCs directly via raw
// client.rpc() calls -- this file exercises the actual Flutter repository
// method the UI calls, to prove the wire-format contract:
//   - the normal checkout path (allowPartialPayment omitted/false) sends
//     no p_allow_partial_payment key at all, byte-for-byte the same
//     request the app has always sent -- verified here by confirming it
//     still behaves exactly as it did before Phase 3 (an underpayment is
//     rejected), against the currently-live complete_sale, with NO
//     dependency on migrations 0042-0045 being applied yet.
//   - the deposit path (allowPartialPayment: true) sends the key and the
//     deposit amount reaches the server unchanged -- this part DOES
//     require 0043 to be live, and is expected to fail with a clean
//     PGRST202 "function not found" until it is applied (see the Phase 3
//     backend implementation report).
//
// Run explicitly with:
//   flutter test --dart-define-from-file=env.json test/integration/deposit_checkout_ux_regression_test.dart
import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:beauty_clinic_pos/config/env.dart';
import 'package:beauty_clinic_pos/features/auth/data/business_repository.dart';
import 'package:beauty_clinic_pos/features/pos/data/pos_repository.dart';
import 'package:beauty_clinic_pos/shared/models/business_role.dart';

const _ownerAEmail = 'van@test.local';
const _ownerAPassword = 'admin123456@';
const _uuid = Uuid();

final _canRun = Env.supabaseUrl.isNotEmpty && Env.supabaseAnonKey.isNotEmpty;
const _skipReason =
    'SUPABASE_URL/SUPABASE_ANON_KEY not provided -- run with '
    '--dart-define-from-file=env.json.';

Future<void> _signIn(SupabaseClient client, String email, String password) async {
  await Future<void>.delayed(const Duration(milliseconds: 400));
  try {
    await client.auth.signInWithPassword(email: email, password: password);
  } on AuthUnknownException {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await client.auth.signInWithPassword(email: email, password: password);
  }
}

void main() {
  setUpAll(() async {
    if (!_canRun) return;
    WidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  });

  test('PosRepository.completeSale with allowPartialPayment omitted (normal checkout) '
      'still rejects an underpayment exactly as before -- no dependency on 0043', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final businessId = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.owner)
        .business
        .id;
    final service = await client
        .from('services')
        .insert({'business_id': businessId, 'name': 'Deposit UX Normal Checkout Service ${_uuid.v4()}', 'price': 120000})
        .select()
        .single();

    final repo = PosRepository(client);
    final branchId = await repo.primaryBranchId(businessId);

    // allowPartialPayment not passed -- defaults to false, and per the
    // repository's own contract, false means the key is omitted entirely
    // from the request body, matching the pre-Phase-3 wire format exactly.
    await expectLater(
      repo.completeSale(
        businessId: businessId,
        branchId: branchId,
        customerId: null,
        items: [
          {
            'item_type': 'SERVICE',
            'service_id': service['id'],
            'product_id': null,
            'staff_id': null,
            'name_snapshot': service['name'],
            'quantity': 1,
            'unit_price': service['price'].toString(),
            'discount_amount': '0',
          },
        ],
        discountAmount: '0',
        taxAmount: '0',
        paymentMethod: 'CASH',
        paidAmount: '50000',
        idempotencyKey: _uuid.v4(),
      ),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('PosRepository.completeSale with allowPartialPayment: true accepts a deposit '
      'and the amount reaches the server unchanged', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final businessId = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.owner)
        .business
        .id;
    final service = await client
        .from('services')
        .insert({'business_id': businessId, 'name': 'Deposit UX Deposit Service ${_uuid.v4()}', 'price': 600000})
        .select()
        .single();

    final repo = PosRepository(client);
    final branchId = await repo.primaryBranchId(businessId);

    final row = await repo.completeSale(
      businessId: businessId,
      branchId: branchId,
      customerId: null,
      items: [
        {
          'item_type': 'SERVICE',
          'service_id': service['id'],
          'product_id': null,
          'staff_id': null,
          'name_snapshot': service['name'],
          'quantity': 1,
          'unit_price': service['price'].toString(),
          'discount_amount': '0',
        },
      ],
      discountAmount: '0',
      taxAmount: '0',
      paymentMethod: 'CASH',
      paidAmount: '250000',
      idempotencyKey: _uuid.v4(),
      allowPartialPayment: true,
    );

    expect(row['payment_status'], 'PARTIAL');
    expect(Decimal.parse(row['paid_amount'].toString()), Decimal.parse('250000.00'));
    expect(Decimal.parse(row['total_amount'].toString()), Decimal.parse('600000.00'));
  });
}
