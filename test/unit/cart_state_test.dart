import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beauty_clinic_pos/features/pos/domain/cart_line.dart';
import 'package:beauty_clinic_pos/features/pos/domain/cart_state.dart';
import 'package:beauty_clinic_pos/shared/models/payment_method.dart';
import 'package:beauty_clinic_pos/shared/models/sale_item_kind.dart';

CartState _emptyCart({bool taxEnabled = false, String taxRate = '0'}) {
  return CartState(
    discountAmount: Decimal.zero,
    taxEnabled: taxEnabled,
    taxRate: Decimal.parse(taxRate),
    paymentMethod: PaymentMethod.cash,
    paidAmount: Decimal.zero,
    idempotencyKey: 'test-key',
  );
}

CartLine _line({required String price, int quantity = 1, String key = 'a'}) {
  return CartLine(
    key: key,
    kind: SaleItemKind.service,
    refId: 'svc-1',
    name: 'Facial',
    unitPrice: Decimal.parse(price),
    quantity: quantity,
  );
}

void main() {
  group('CartState totals', () {
    test('subtotal sums line subtotals (unit price x quantity)', () {
      final cart = _emptyCart().copyWith(lines: [
        _line(price: '500000', quantity: 1, key: 'a'),
        _line(price: '300000', quantity: 2, key: 'b'),
      ]);
      expect(cart.subtotal, Decimal.parse('1100000'));
    });

    test('discount reduces total but never subtotal', () {
      final cart = _emptyCart()
          .copyWith(lines: [_line(price: '500000')], discountAmount: Decimal.parse('50000'));
      expect(cart.subtotal, Decimal.parse('500000'));
      expect(cart.total, Decimal.parse('450000'));
    });

    test('total never goes negative even if discount exceeds subtotal', () {
      final cart = _emptyCart()
          .copyWith(lines: [_line(price: '10000')], discountAmount: Decimal.parse('999999'));
      expect(cart.total, Decimal.zero);
    });

    test('tax is computed on (subtotal - discount) only when enabled', () {
      final withoutTax = _emptyCart(taxEnabled: false, taxRate: '10')
          .copyWith(lines: [_line(price: '1000000')]);
      expect(withoutTax.taxAmount, Decimal.zero);

      final withTax = _emptyCart(taxEnabled: true, taxRate: '10')
          .copyWith(lines: [_line(price: '1000000')], discountAmount: Decimal.parse('100000'));
      // (1,000,000 - 100,000) * 10% = 90,000
      expect(withTax.taxAmount, Decimal.parse('90000'));
      expect(withTax.total, Decimal.parse('990000')); // 900,000 + 90,000
    });

    test('change is paid minus total, never negative', () {
      final cart =
          _emptyCart().copyWith(lines: [_line(price: '500000')], paidAmount: Decimal.parse('600000'));
      expect(cart.change, Decimal.parse('100000'));

      final underpaid =
          _emptyCart().copyWith(lines: [_line(price: '500000')], paidAmount: Decimal.parse('100000'));
      expect(underpaid.change, Decimal.zero);
    });

    test('isEmpty reflects whether there are any lines', () {
      expect(_emptyCart().isEmpty, isTrue);
      expect(_emptyCart().copyWith(lines: [_line(price: '1')]).isEmpty, isFalse);
    });
  });
}
