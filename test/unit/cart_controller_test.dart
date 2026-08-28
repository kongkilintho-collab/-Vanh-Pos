import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beauty_clinic_pos/features/pos/domain/cart_line.dart';
import 'package:beauty_clinic_pos/features/pos/presentation/cart_controller.dart';
import 'package:beauty_clinic_pos/shared/models/sale_item_kind.dart';

CartLine _line({required String key, required String refId, int quantity = 1, String? staffId}) {
  return CartLine(
    key: key,
    kind: SaleItemKind.service,
    refId: refId,
    name: 'Facial',
    unitPrice: Decimal.parse('500000'),
    quantity: quantity,
    staffId: staffId,
  );
}

void main() {
  group('CartController', () {
    test('adding an identical line (same item + same staff) merges quantity instead of duplicating', () {
      final controller = CartController(taxEnabled: false, taxRate: Decimal.zero);
      controller.addLine(_line(key: 'a', refId: 'svc-1'));
      controller.addLine(_line(key: 'b', refId: 'svc-1'));

      expect(controller.state.lines.length, 1);
      expect(controller.state.lines.first.quantity, 2);
    });

    test('the same service assigned to different staff stays as separate lines', () {
      final controller = CartController(taxEnabled: false, taxRate: Decimal.zero);
      controller.addLine(_line(key: 'a', refId: 'svc-1', staffId: 'staff-1'));
      controller.addLine(_line(key: 'b', refId: 'svc-1', staffId: 'staff-2'));

      expect(controller.state.lines.length, 2);
    });

    test('setQuantity to zero or below removes the line', () {
      final controller = CartController(taxEnabled: false, taxRate: Decimal.zero);
      controller.addLine(_line(key: 'a', refId: 'svc-1'));
      controller.setQuantity('a', 0);

      expect(controller.state.lines, isEmpty);
    });

    test('removeLine only removes the targeted line', () {
      final controller = CartController(taxEnabled: false, taxRate: Decimal.zero);
      controller.addLine(_line(key: 'a', refId: 'svc-1'));
      controller.addLine(_line(key: 'b', refId: 'svc-2'));
      controller.removeLine('a');

      expect(controller.state.lines.map((l) => l.key), ['b']);
    });

    test('reset clears lines and issues a fresh idempotency key', () {
      final controller = CartController(taxEnabled: false, taxRate: Decimal.zero);
      final firstKey = controller.state.idempotencyKey;
      controller.addLine(_line(key: 'a', refId: 'svc-1'));
      controller.setDiscount(Decimal.parse('10000'));

      controller.reset();

      expect(controller.state.lines, isEmpty);
      expect(controller.state.discountAmount, Decimal.zero);
      expect(controller.state.idempotencyKey, isNot(firstKey));
    });

    test('setDiscount clamps negative input to zero', () {
      final controller = CartController(taxEnabled: false, taxRate: Decimal.zero);
      controller.setDiscount(Decimal.parse('-500'));
      expect(controller.state.discountAmount, Decimal.zero);
    });
  });

  test('cartControllerProvider derives tax settings from the current business', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // With no membership resolved yet, the cart defaults to no tax rather
    // than throwing.
    final cart = container.read(cartControllerProvider);
    expect(cart.taxEnabled, isFalse);
  });
}
