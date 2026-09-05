import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beauty_clinic_pos/core/hardware/formatting/receipt_document.dart';
import 'package:beauty_clinic_pos/core/hardware/formatting/receipt_formatter.dart';
import 'package:beauty_clinic_pos/features/pos/domain/cart_line.dart';
import 'package:beauty_clinic_pos/l10n/generated/app_localizations_en.dart';
import 'package:beauty_clinic_pos/shared/models/business.dart';
import 'package:beauty_clinic_pos/shared/models/customer.dart';
import 'package:beauty_clinic_pos/shared/models/payment_method.dart';
import 'package:beauty_clinic_pos/shared/models/sale.dart';
import 'package:beauty_clinic_pos/shared/models/sale_item_kind.dart';

final _l10n = AppLocalizationsEn();

Sale _sale({String discount = '0', String tax = '0'}) {
  return Sale(
    id: 'sale-1',
    receiptNumber: 'R-0001',
    subtotal: Decimal.parse('100000'),
    discountAmount: Decimal.parse(discount),
    taxAmount: Decimal.parse(tax),
    totalAmount: Decimal.parse('100000'),
    paidAmount: Decimal.parse('100000'),
    changeAmount: Decimal.zero,
    status: 'COMPLETED',
    paymentStatus: 'PAID',
    createdAt: DateTime(2026, 1, 5, 14, 30),
  );
}

Business _business() {
  return const Business(
    id: 'biz-1',
    name: 'Beauty Clinic',
    phone: '020 1234 5678',
    currency: 'LAK',
    timezone: 'Asia/Vientiane',
    taxEnabled: false,
    taxRate: 0,
  );
}

List<CartLine> _lines() {
  return [
    CartLine(
      key: 'a',
      kind: SaleItemKind.service,
      refId: 'svc-1',
      name: 'Facial',
      unitPrice: Decimal.parse('100000'),
      quantity: 1,
    ),
  ];
}

void main() {
  group('ReceiptFormatter', () {
    test('formats authoritative sale values without recomputing them', () {
      const formatter = ReceiptFormatter();
      final document = formatter.format(
        sale: _sale(),
        business: _business(),
        lines: _lines(),
        customer: null,
        paymentMethod: PaymentMethod.cash,
        cashierName: 'Nok',
        l10n: _l10n,
      );

      final text = document.lines.map((l) => l.text).join('\n');

      expect(text, contains('R-0001'));
      expect(text, contains('Nok'));
      expect(text, contains('Facial'));
      expect(text, contains('100,000 LAK'));
      expect(text, contains(_l10n.posReceiptWalkIn));
    });

    test('includes a named customer instead of the walk-in label', () {
      const formatter = ReceiptFormatter();
      final customer = Customer(
        id: 'cust-1',
        businessId: 'biz-1',
        name: 'Somchai',
        totalSpent: Decimal.zero,
        visitCount: 1,
        active: true,
      );

      final document = formatter.format(
        sale: _sale(),
        business: _business(),
        lines: _lines(),
        customer: customer,
        paymentMethod: PaymentMethod.cash,
        cashierName: 'Nok',
        l10n: _l10n,
      );

      final text = document.lines.map((l) => l.text).join('\n');
      expect(text, contains('Somchai'));
      expect(text, isNot(contains(_l10n.posReceiptWalkIn)));
    });

    test('omits discount/tax rows when the sale has none, includes them when present', () {
      const formatter = ReceiptFormatter();

      final withoutExtras = formatter.format(
        sale: _sale(),
        business: _business(),
        lines: _lines(),
        customer: null,
        paymentMethod: PaymentMethod.cash,
        cashierName: 'Nok',
        l10n: _l10n,
      );
      expect(
        withoutExtras.lines.any((l) => l.text.contains(_l10n.posDiscount)),
        isFalse,
      );

      final withExtras = formatter.format(
        sale: _sale(discount: '5000', tax: '2000'),
        business: _business(),
        lines: _lines(),
        customer: null,
        paymentMethod: PaymentMethod.cash,
        cashierName: 'Nok',
        l10n: _l10n,
      );
      expect(withExtras.lines.any((l) => l.text.contains(_l10n.posDiscount)), isTrue);
      expect(withExtras.lines.any((l) => l.text.contains(_l10n.posTax)), isTrue);
    });

    test('ends with a blank feed followed by a cut', () {
      const formatter = ReceiptFormatter();
      final document = formatter.format(
        sale: _sale(),
        business: _business(),
        lines: _lines(),
        customer: null,
        paymentMethod: PaymentMethod.cash,
        cashierName: 'Nok',
        l10n: _l10n,
      );

      expect(document.lines.last.kind, ReceiptLineKind.cut);
    });
  });
}
