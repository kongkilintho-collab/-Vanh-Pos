import 'package:decimal/decimal.dart';

import '../../../shared/models/customer.dart';
import '../../../shared/models/payment_method.dart';
import 'cart_line.dart';

class CartState {
  final List<CartLine> lines;
  final Customer? customer;
  final Decimal discountAmount;
  final bool taxEnabled;
  final Decimal taxRate;
  final PaymentMethod paymentMethod;
  final Decimal paidAmount;

  /// Regenerated whenever the cart is cleared (after a completed sale, or
  /// manually) so a duplicate network retry of the same submit can't ever
  /// create two sales, while starting a genuinely new sale gets a fresh key.
  final String idempotencyKey;

  const CartState({
    this.lines = const [],
    this.customer,
    required this.discountAmount,
    required this.taxEnabled,
    required this.taxRate,
    required this.paymentMethod,
    required this.paidAmount,
    required this.idempotencyKey,
  });

  Decimal get subtotal =>
      lines.fold(Decimal.zero, (sum, l) => sum + l.subtotal);

  Decimal get taxAmount {
    if (!taxEnabled || taxRate <= Decimal.zero) return Decimal.zero;
    final taxable = subtotal - discountAmount;
    if (taxable <= Decimal.zero) return Decimal.zero;
    return (taxable * taxRate / Decimal.fromInt(100)).toDecimal(scaleOnInfinitePrecision: 2);
  }

  Decimal get total {
    final t = subtotal - discountAmount + taxAmount;
    return t < Decimal.zero ? Decimal.zero : t;
  }

  Decimal get change {
    final c = paidAmount - total;
    return c < Decimal.zero ? Decimal.zero : c;
  }

  bool get isEmpty => lines.isEmpty;

  CartState copyWith({
    List<CartLine>? lines,
    Customer? customer,
    bool clearCustomer = false,
    Decimal? discountAmount,
    PaymentMethod? paymentMethod,
    Decimal? paidAmount,
    String? idempotencyKey,
  }) {
    return CartState(
      lines: lines ?? this.lines,
      customer: clearCustomer ? null : (customer ?? this.customer),
      discountAmount: discountAmount ?? this.discountAmount,
      taxEnabled: taxEnabled,
      taxRate: taxRate,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paidAmount: paidAmount ?? this.paidAmount,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
    );
  }
}
