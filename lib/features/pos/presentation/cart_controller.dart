import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/models/customer.dart';
import '../../../shared/models/payment_method.dart';
import '../../auth/presentation/business_context_provider.dart';
import '../domain/cart_line.dart';
import '../domain/cart_state.dart';

const _uuid = Uuid();

class CartController extends StateNotifier<CartState> {
  CartController({required bool taxEnabled, required Decimal taxRate})
      : super(CartState(
          discountAmount: Decimal.zero,
          taxEnabled: taxEnabled,
          taxRate: taxRate,
          paymentMethod: PaymentMethod.cash,
          paidAmount: Decimal.zero,
          idempotencyKey: _uuid.v4(),
        ));

  void addLine(CartLine line) {
    // Merge with an identical existing line (same item + same staff
    // attribution) instead of adding a duplicate row.
    final existingIndex = state.lines.indexWhere(
      (l) => l.refId == line.refId && l.kind == line.kind && l.staffId == line.staffId,
    );
    if (existingIndex != -1) {
      final updated = [...state.lines];
      updated[existingIndex] =
          updated[existingIndex].copyWith(quantity: updated[existingIndex].quantity + line.quantity);
      state = state.copyWith(lines: updated);
    } else {
      state = state.copyWith(lines: [...state.lines, line]);
    }
  }

  void removeLine(String key) {
    state = state.copyWith(lines: state.lines.where((l) => l.key != key).toList());
  }

  void setQuantity(String key, int quantity) {
    if (quantity <= 0) {
      removeLine(key);
      return;
    }
    state = state.copyWith(
      lines: [
        for (final l in state.lines) l.key == key ? l.copyWith(quantity: quantity) : l,
      ],
    );
  }

  void setLineStaff(String key, String? staffId, String? staffName) {
    state = state.copyWith(
      lines: [
        for (final l in state.lines)
          l.key == key ? l.copyWith(staffId: staffId, staffName: staffName) : l,
      ],
    );
  }

  void setCustomer(Customer? customer) {
    state = state.copyWith(customer: customer, clearCustomer: customer == null);
  }

  void setDiscount(Decimal amount) {
    state = state.copyWith(discountAmount: amount < Decimal.zero ? Decimal.zero : amount);
  }

  void setPaymentMethod(PaymentMethod method) {
    state = state.copyWith(paymentMethod: method);
  }

  void setPaidAmount(Decimal amount) {
    state = state.copyWith(paidAmount: amount < Decimal.zero ? Decimal.zero : amount);
  }

  /// Resets to a brand-new empty cart with a fresh idempotency key —
  /// called after a completed sale or when the cashier explicitly clears.
  void reset() {
    state = CartState(
      discountAmount: Decimal.zero,
      taxEnabled: state.taxEnabled,
      taxRate: state.taxRate,
      paymentMethod: PaymentMethod.cash,
      paidAmount: Decimal.zero,
      idempotencyKey: _uuid.v4(),
    );
  }
}

final cartControllerProvider = StateNotifierProvider.autoDispose<CartController, CartState>((ref) {
  final business = ref.watch(currentMembershipProvider)?.business;
  return CartController(
    taxEnabled: business?.taxEnabled ?? false,
    taxRate: Decimal.parse((business?.taxRate ?? 0).toString()),
  );
});
