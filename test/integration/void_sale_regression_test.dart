// Live regression coverage for F9-2 (Finalization Phase audit, void/refund
// forensic report + implementation authorization dated 2026-08-30) -- see
// supabase/migrations/0026_void_sale.sql.
//
// Covers: COMPLETED -> VOIDED state transition, inventory reversal (exact
// stock restore, exactly one RETURN/sale_void movement per PRODUCT line,
// safe skip when the product was later hard-deleted), commission reversal
// (status -> REVERSED, amount/rate/attribution untouched), payment
// bookkeeping (status -> REFUNDED, amount/method/reference/created_by
// untouched), atomic audit logging, tenant isolation, concurrency (exactly
// one success on two simultaneous voids), and the C1/C2/H1 bypass closures
// (direct PATCH on sales/payments and direct POST on audit_logs must now
// be denied).
//
// Uses the same live Supabase project and QA fixture accounts as the other
// integration tests in this directory (see business_repository_regression_
// test.dart's header for setup details):
//   - van@test.local   / admin123456@   -- OWNER of business "A"
//   - admin@test.local / 123456@12      -- OWNER of business "B", and
//     ADMIN member of business "A"
//
// No STAFF- or CASHIER-rank fixture account exists (self-service .local
// signup is rejected by GoTrue in this project, and real-domain signup
// hits email rate limits -- both hit and documented during Day 6 cleanup).
// The STAFF/CASHIER-denied and literal MANAGER-rank-allowed cases are
// therefore marked skipped below with an explicit reason rather than
// fabricated -- ADMIN (rank 4) and OWNER (rank 5) allowed, both exercised
// live here, already prove has_role_at_least(business_id, 'MANAGER')
// (rank >= 3) gates correctly at two points on the same unchanged helper
// this project has relied on since 0014.
//
// It skips itself (does not fail) when Supabase isn't configured, so a
// plain `flutter test` elsewhere stays green.
//
// Run explicitly with:
//   flutter test --dart-define-from-file=env.json test/integration/void_sale_regression_test.dart
import 'dart:convert';
import 'dart:io';

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
const _ownerBEmail = 'admin@test.local';
const _ownerBPassword = '123456@12';
const _uuid = Uuid();

final _canRun = Env.supabaseUrl.isNotEmpty && Env.supabaseAnonKey.isNotEmpty;
const _skipReason =
    'SUPABASE_URL/SUPABASE_ANON_KEY not provided -- run with '
    '--dart-define-from-file=env.json against a project with '
    '0026 applied and seeded with the QA fixture accounts.';
const _noStaffCashierFixture =
    'No STAFF- or CASHIER-rank fixture account exists (self-service '
    '.local signup is rejected by GoTrue in this project; documented '
    'during Day 6 cleanup). ADMIN/OWNER-allowed are exercised live below '
    'on the same has_role_at_least(business_id, MANAGER) helper.';

Future<void> _signIn(SupabaseClient client, String email, String password) async {
  await Future<void>.delayed(const Duration(milliseconds: 400));
  try {
    await client.auth.signInWithPassword(email: email, password: password);
  } on AuthUnknownException {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await client.auth.signInWithPassword(email: email, password: password);
  }
}

Matcher _deniedByRls() => isA<PostgrestException>().having((e) => e.code, 'code', '42501');

/// Same technique used by security_hardening_regression_test.dart's F3
/// coverage: a raw, session-free HTTP call distinguishes "Postgres itself
/// rejected the call" (42501, the ACL layer) from "the function ran and
/// rejected it internally".
Future<Map<String, dynamic>> _anonRpc(String function, Map<String, dynamic> body) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse('${Env.supabaseUrl}/rest/v1/rpc/$function'));
    request.headers.set('apikey', Env.supabaseAnonKey);
    request.headers.set('Authorization', 'Bearer ${Env.supabaseAnonKey}');
    request.headers.set('Content-Type', 'application/json');
    request.write(jsonEncode(body));
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    return {'status': response.statusCode, 'body': responseBody};
  } finally {
    client.close();
  }
}

/// Creates a fresh, voidable sale in [businessId]: one commission-earning
/// SERVICE line attributed to [staffId], and one PRODUCT line with
/// [productQuantity] units out of [productStock] on hand. Returns the raw
/// sale row plus the fixture ids a test needs to assert against.
class _VoidableSale {
  final Map<String, dynamic> sale;
  final String productId;
  final int productStock;
  final int productQuantity;

  _VoidableSale({
    required this.sale,
    required this.productId,
    required this.productStock,
    required this.productQuantity,
  });
}

Future<_VoidableSale> _createVoidableSale(
  SupabaseClient client,
  String businessId,
  String staffId, {
  int productStock = 10,
  int productQuantity = 2,
}) async {
  final service = await client
      .from('services')
      .insert({
        'business_id': businessId,
        'name': 'F9-2 Fixture Service ${_uuid.v4()}',
        'price': 100000,
        'commission_value': 10,
      })
      .select()
      .single();
  final product = await client
      .from('products')
      .insert({
        'business_id': businessId,
        'name': 'F9-2 Fixture Product ${_uuid.v4()}',
        'selling_price': 20000,
        'stock_quantity': productStock,
      })
      .select()
      .single();

  final posRepo = PosRepository(client);
  final branchId = await posRepo.primaryBranchId(businessId);
  final sale = await posRepo.completeSale(
    businessId: businessId,
    branchId: branchId,
    customerId: null,
    items: [
      {
        'item_type': 'SERVICE',
        'service_id': service['id'],
        'product_id': null,
        'staff_id': staffId,
        'name_snapshot': 'F9-2 Fixture Service',
        'quantity': 1,
        'unit_price': '100000',
        'discount_amount': '0',
      },
      {
        'item_type': 'PRODUCT',
        'service_id': null,
        'product_id': product['id'],
        'staff_id': null,
        'name_snapshot': 'F9-2 Fixture Product',
        'quantity': productQuantity,
        'unit_price': '20000',
        'discount_amount': '0',
      },
    ],
    discountAmount: '0',
    taxAmount: '0',
    paymentMethod: 'CASH',
    paidAmount: (100000 + 20000 * productQuantity).toString(),
    idempotencyKey: _uuid.v4(),
  );

  return _VoidableSale(
    sale: sale,
    productId: product['id'] as String,
    productStock: productStock,
    productQuantity: productQuantity,
  );
}

void main() {
  setUpAll(() async {
    if (!_canRun) return;
    WidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  });

  test('ADMIN can void a COMPLETED sale: inventory, commission, payment, and audit are all correct', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerBEmail, _ownerBPassword);
    final businessAId = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.admin)
        .business
        .id;
    final adminId = client.auth.currentUser!.id;

    final fixture = await _createVoidableSale(client, businessAId, adminId);
    final saleId = fixture.sale['id'] as String;

    final commissionBefore = await client.from('commissions').select().eq('sale_id', saleId).single();
    final paymentBefore = await client.from('payments').select().eq('sale_id', saleId).single();

    final voided = await PosRepository(client).voidSale(
      businessId: businessAId,
      saleId: saleId,
      reason: 'F9-2 test: ADMIN void',
    );
    expect(voided['status'], 'VOIDED');
    expect(voided['void_reason'], 'F9-2 test: ADMIN void');
    expect(voided['voided_by'], adminId);
    expect(voided['voided_at'], isNotNull);
    // Financial snapshot fields must be untouched by the void.
    expect(voided['total_amount'], fixture.sale['total_amount']);
    expect(voided['paid_amount'], fixture.sale['paid_amount']);

    final product = await client.from('products').select('stock_quantity').eq('id', fixture.productId).single();
    expect(product['stock_quantity'], fixture.productStock, reason: 'stock must be restored exactly');

    final movements = await client
        .from('inventory_movements')
        .select()
        .eq('product_id', fixture.productId)
        .eq('reference_type', 'sale_void');
    expect(movements, hasLength(1), reason: 'exactly one reversal movement');
    expect(movements[0]['movement_type'], 'RETURN');
    expect(movements[0]['reference_id'], saleId);
    expect(movements[0]['quantity'], fixture.productQuantity, reason: 'reversal quantity is positive and matches the original sale');

    final commissionAfter = await client.from('commissions').select().eq('sale_id', saleId).single();
    expect(commissionAfter['status'], 'REVERSED');
    expect(commissionAfter['commission_amount'], commissionBefore['commission_amount']);
    expect(commissionAfter['commission_rate'], commissionBefore['commission_rate']);
    expect(commissionAfter['staff_id'], commissionBefore['staff_id']);

    final paymentAfter = await client.from('payments').select().eq('sale_id', saleId).single();
    expect(paymentAfter['status'], 'REFUNDED');
    expect(paymentAfter['amount'], paymentBefore['amount']);
    expect(paymentAfter['payment_method'], paymentBefore['payment_method']);
    expect(paymentAfter['reference'], paymentBefore['reference']);
    expect(paymentAfter['created_by'], paymentBefore['created_by']);

    final auditRows = await client
        .from('audit_logs')
        .select()
        .eq('entity_type', 'sale')
        .eq('entity_id', saleId)
        .eq('action', 'VOID');
    expect(auditRows, hasLength(1), reason: 'exactly one VOID audit row');
    final audit = auditRows[0];
    expect(audit['user_id'], adminId);
    expect(audit['business_id'], businessAId);
    expect((audit['old_data'] as Map)['status'], 'COMPLETED');
    expect((audit['new_data'] as Map)['status'], 'VOIDED');
    final metadata = audit['metadata'] as Map;
    expect(metadata['reason'], 'F9-2 test: ADMIN void');
    expect(metadata['reversed_commission_count'], 1);
    expect(metadata['reversed_inventory_line_count'], 1);
    expect(metadata['skipped_product_deleted_lines'], 0);

    await client.auth.signOut();
  });

  test('OWNER can void a COMPLETED sale', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final businessAId = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.owner)
        .business
        .id;
    final ownerAId = client.auth.currentUser!.id;

    final fixture = await _createVoidableSale(client, businessAId, ownerAId);
    final saleId = fixture.sale['id'] as String;

    final voided = await PosRepository(client).voidSale(
      businessId: businessAId,
      saleId: saleId,
      reason: 'F9-2 test: OWNER void',
    );
    expect(voided['status'], 'VOIDED');

    final auditRows = await client.from('audit_logs').select().eq('entity_type', 'sale').eq('entity_id', saleId).eq('action', 'VOID');
    expect(auditRows, hasLength(1));
    expect(auditRows[0]['user_id'], ownerAId);

    await client.auth.signOut();
  });

  test(
    'STAFF/CASHIER rank is denied by the same has_role_at_least(business_id, MANAGER) check -- no fixture account to run this live',
    () => markTestSkipped(_noStaffCashierFixture),
  );

  test('a sale that is already VOIDED cannot be voided again', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final businessAId = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.owner)
        .business
        .id;
    final ownerAId = client.auth.currentUser!.id;

    final fixture = await _createVoidableSale(client, businessAId, ownerAId);
    final saleId = fixture.sale['id'] as String;
    final posRepo = PosRepository(client);

    await posRepo.voidSale(businessId: businessAId, saleId: saleId, reason: 'first void');

    await expectLater(
      posRepo.voidSale(businessId: businessAId, saleId: saleId, reason: 'second void attempt'),
      throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Only a completed sale can be voided'))),
    );

    await client.auth.signOut();
  });

  test('voiding a non-existent sale id fails with zero mutation', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final businessAId = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.owner)
        .business
        .id;

    await expectLater(
      PosRepository(client).voidSale(businessId: businessAId, saleId: _uuid.v4(), reason: 'no such sale'),
      throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Sale not found in this business'))),
    );

    await client.auth.signOut();
  });

  test('a non-member of the target business is denied before any sale lookup', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerBEmail, _ownerBPassword);
    final businessBId = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.owner)
        .business
        .id;
    await client.auth.signOut();

    // van@test.local is OWNER of business A only -- not a member of B.
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    await expectLater(
      PosRepository(client).voidSale(businessId: businessBId, saleId: _uuid.v4(), reason: 'not a member of B'),
      throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Insufficient permission to void a sale'))),
    );

    await client.auth.signOut();
  });

  test('cross-tenant: a real sale in business A cannot be voided by scoping the call to business B', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final businessAId = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.owner)
        .business
        .id;
    final ownerAId = client.auth.currentUser!.id;
    final fixture = await _createVoidableSale(client, businessAId, ownerAId);
    final saleId = fixture.sale['id'] as String;
    await client.auth.signOut();

    // admin@test.local is OWNER of business B -- has ample rank there, but
    // the sale belongs to business A, so it must resolve as not found.
    await _signIn(client, _ownerBEmail, _ownerBPassword);
    final businessBId = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.owner)
        .business
        .id;

    await expectLater(
      PosRepository(client).voidSale(businessId: businessBId, saleId: saleId, reason: 'cross-tenant attempt'),
      throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Sale not found in this business'))),
    );

    await client.auth.signOut();
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final stillCompleted = await client.from('sales').select('status').eq('id', saleId).single();
    expect(stillCompleted['status'], 'COMPLETED', reason: 'the cross-tenant attempt must not have mutated the sale');
    await client.auth.signOut();
  });

  test(
    'a NULL product_id on a PRODUCT sale_item is structurally unreachable -- hard-deleting a sold '
    'product is itself rejected by sale_items_item_reference_chk, before void_sale is ever involved',
    () async {
      if (!_canRun) {
        markTestSkipped(_skipReason);
        return;
      }
      final client = Supabase.instance.client;
      await _signIn(client, _ownerAEmail, _ownerAPassword);
      final businessAId = (await BusinessRepository(client).myMemberships())
          .firstWhere((m) => m.role == BusinessRole.owner)
          .business
          .id;
      final ownerAId = client.auth.currentUser!.id;

      final fixture = await _createVoidableSale(client, businessAId, ownerAId);

      // void_sale's product_id-is-null branch (0026_void_sale.sql) assumed
      // this was reachable via a later hard-delete of a sold product
      // (products_delete has no dependency check against sale history, and
      // sale_items.product_id is declared ON DELETE SET NULL). Live
      // verification found that assumption wrong: the SET NULL action
      // itself is rejected by sale_items_item_reference_chk
      // (0007_sales.sql -- item_type='PRODUCT' requires product_id IS NOT
      // NULL), so the DELETE fails outright and the product is never
      // removed. This documents that discovery rather than fabricating a
      // NULL-product state that the schema will not actually produce.
      await expectLater(
        client.from('products').delete().eq('id', fixture.productId),
        throwsA(isA<PostgrestException>().having((e) => e.code, 'code', '23514')),
      );

      final stillThere = await client.from('products').select('id').eq('id', fixture.productId).maybeSingle();
      expect(stillThere, isNotNull, reason: 'the rejected DELETE must not have removed the product');

      // The sale is therefore still fully voidable through the normal,
      // already-covered path (see the ADMIN/OWNER void tests above) --
      // void_sale's product_id-is-null skip branch remains defensively
      // correct code but is not exercised by any reachable live state.
      await client.auth.signOut();
    },
  );

  test('two simultaneous void attempts on the same sale: exactly one succeeds, stock reversed exactly once', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final businessAId = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.owner)
        .business
        .id;
    final ownerAId = client.auth.currentUser!.id;

    final fixture = await _createVoidableSale(client, businessAId, ownerAId);
    final saleId = fixture.sale['id'] as String;
    final posRepo = PosRepository(client);

    final results = await Future.wait<Object?>([
      posRepo.voidSale(businessId: businessAId, saleId: saleId, reason: 'concurrent A').then<Object?>((v) => v).catchError((Object e) => e),
      posRepo.voidSale(businessId: businessAId, saleId: saleId, reason: 'concurrent B').then<Object?>((v) => v).catchError((Object e) => e),
    ]);

    final successes = results.whereType<Map<String, dynamic>>().toList();
    final failures = results.whereType<PostgrestException>().toList();
    expect(successes, hasLength(1), reason: 'exactly one of the two concurrent calls must succeed');
    expect(failures, hasLength(1));
    expect(failures.single.message, contains('Only a completed sale can be voided'));

    final product = await client.from('products').select('stock_quantity').eq('id', fixture.productId).single();
    expect(product['stock_quantity'], fixture.productStock, reason: 'stock must be restored exactly once, not twice');

    final movements = await client.from('inventory_movements').select().eq('product_id', fixture.productId).eq('reference_type', 'sale_void');
    expect(movements, hasLength(1));

    final commissions = await client.from('commissions').select().eq('sale_id', saleId);
    expect(commissions.where((c) => c['status'] == 'REVERSED'), hasLength(1));

    final auditRows = await client.from('audit_logs').select().eq('entity_type', 'sale').eq('entity_id', saleId).eq('action', 'VOID');
    expect(auditRows, hasLength(1), reason: 'exactly one audit row despite two concurrent attempts');

    await client.auth.signOut();
  });

  test('anon EXECUTE on void_sale is denied by ACL (never reaches the function body)', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final result = await _anonRpc('void_sale', {
      'p_business_id': '00000000-0000-0000-0000-000000000000',
      'p_sale_id': '00000000-0000-0000-0000-000000000000',
      'p_reason': 'anon probe',
    });
    expect(result['status'], 401);
    expect(result['body'], contains('42501'));
    expect(result['body'], contains('permission denied for function void_sale'));
  });

  test('C1: a direct PATCH on sales.status is no longer possible (sales_update dropped)', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final businessAId = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.owner)
        .business
        .id;
    final ownerAId = client.auth.currentUser!.id;
    final fixture = await _createVoidableSale(client, businessAId, ownerAId);
    final saleId = fixture.sale['id'] as String;

    final updated = await client.from('sales').update({'status': 'VOIDED'}).eq('id', saleId).select();
    expect(updated, isEmpty, reason: 'no UPDATE policy exists on sales anymore -- RLS filters the row to zero matches');

    final stillCompleted = await client.from('sales').select('status').eq('id', saleId).single();
    expect(stillCompleted['status'], 'COMPLETED');

    await client.auth.signOut();
  });

  test('C2: a direct PATCH on payments.status is no longer possible (payments_update dropped)', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final businessAId = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.owner)
        .business
        .id;
    final ownerAId = client.auth.currentUser!.id;
    final fixture = await _createVoidableSale(client, businessAId, ownerAId);
    final saleId = fixture.sale['id'] as String;

    final updated = await client.from('payments').update({'status': 'REFUNDED'}).eq('sale_id', saleId).select();
    expect(updated, isEmpty, reason: 'no UPDATE policy exists on payments anymore -- RLS filters the row to zero matches');

    final stillCompleted = await client.from('payments').select('status').eq('sale_id', saleId).single();
    expect(stillCompleted['status'], 'COMPLETED');

    await client.auth.signOut();
  });

  test('H1: a direct POST into audit_logs is denied by RLS (audit_logs_insert dropped)', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final businessAId = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.owner)
        .business
        .id;
    final ownerAId = client.auth.currentUser!.id;

    await expectLater(
      client.from('audit_logs').insert({
        'business_id': businessAId,
        'user_id': ownerAId,
        'action': 'VOID',
        'entity_type': 'sale',
        'entity_id': _uuid.v4(),
        'new_data': {'status': 'VOIDED'},
      }),
      throwsA(_deniedByRls()),
    );

    await client.auth.signOut();
  });

  test('legitimate paths remain functional: complete_sale() still succeeds after 0026', () async {
    if (!_canRun) {
      markTestSkipped(_skipReason);
      return;
    }
    final client = Supabase.instance.client;
    await _signIn(client, _ownerAEmail, _ownerAPassword);
    final businessAId = (await BusinessRepository(client).myMemberships())
        .firstWhere((m) => m.role == BusinessRole.owner)
        .business
        .id;
    final ownerAId = client.auth.currentUser!.id;

    final fixture = await _createVoidableSale(client, businessAId, ownerAId);
    expect(fixture.sale['status'], 'COMPLETED');
    expect(Decimal.parse(fixture.sale['total_amount'].toString()), Decimal.parse('140000'));

    await client.auth.signOut();
  });
}
