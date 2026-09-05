import 'package:intl/intl.dart';

import '../../../core/utils/currency_formatter.dart';
import '../../../features/pos/domain/cart_line.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/models/business.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/models/payment_method.dart';
import '../../../shared/models/sale.dart';
import 'receipt_document.dart';

/// Converts already-authoritative POS data into a printer-independent
/// [ReceiptDocument]. This never recomputes subtotal/discount/tax/total/paid
/// amounts -- it only formats the values [Sale] already carries, exactly as
/// `ReceiptSheet` does on screen, so the printed receipt and the on-screen
/// confirmation can never disagree.
class ReceiptFormatter {
  /// Character columns available on the target printer. 32 is the common
  /// width for 58mm thermal printers; 42-48 is typical for 80mm. This is a
  /// presentation constant only, not a protocol requirement.
  final int charWidth;

  const ReceiptFormatter({this.charWidth = 32});

  ReceiptDocument format({
    required Sale sale,
    required Business business,
    required List<CartLine> lines,
    required Customer? customer,
    required PaymentMethod paymentMethod,
    required String cashierName,
    required AppLocalizations l10n,
  }) {
    final out = <ReceiptLine>[
      ReceiptLine.text(business.name, align: ReceiptAlign.center, bold: true),
      if (business.phone != null) ReceiptLine.text(business.phone!, align: ReceiptAlign.center),
      const ReceiptLine.separator(),
      ReceiptLine.text(_row(l10n.posReceiptReceipt, sale.receiptNumber)),
      ReceiptLine.text(
        _row(l10n.posReceiptDate, DateFormat('yMMMd · h:mm a').format(sale.createdAt.toLocal())),
      ),
      ReceiptLine.text(_row(l10n.posReceiptCashier, cashierName)),
      ReceiptLine.text(_row(l10n.posReceiptCustomer, customer?.name ?? l10n.posReceiptWalkIn)),
      const ReceiptLine.separator(),
    ];

    for (final line in lines) {
      final label = '${line.name}${line.quantity > 1 ? '  x${line.quantity}' : ''}';
      out.add(ReceiptLine.text(_row(label, formatMoney(line.subtotal))));
    }

    out.add(const ReceiptLine.separator());
    out.add(ReceiptLine.text(_row(l10n.posSubtotal, formatMoney(sale.subtotal))));
    if (sale.discountAmount.toDouble() > 0) {
      out.add(ReceiptLine.text(_row(l10n.posDiscount, '-${formatMoney(sale.discountAmount)}')));
    }
    if (sale.taxAmount.toDouble() > 0) {
      out.add(ReceiptLine.text(_row(l10n.posTax, formatMoney(sale.taxAmount))));
    }
    out.add(ReceiptLine.text(_row(l10n.posTotal, formatMoney(sale.totalAmount)), bold: true));
    out.add(
      ReceiptLine.text(_row(l10n.posReceiptPaidVia(paymentMethod.label(l10n)), formatMoney(sale.paidAmount))),
    );
    out.add(ReceiptLine.text(_row(l10n.posChange, formatMoney(sale.changeAmount))));
    out.add(const ReceiptLine.feed());
    out.add(ReceiptLine.text(l10n.posReceiptThankYou, align: ReceiptAlign.center));
    out.add(const ReceiptLine.feed());
    out.add(const ReceiptLine.feed());
    out.add(const ReceiptLine.cut());

    return ReceiptDocument(out);
  }

  /// Lays a label/value pair out as one fixed-width line: label left, value
  /// right, truncating the label if the pair doesn't fit [charWidth].
  String _row(String label, String value) {
    final maxLabelLen = charWidth - value.length - 1;
    final clippedLabel = maxLabelLen > 0 && label.length > maxLabelLen
        ? label.substring(0, maxLabelLen)
        : label;
    final padding = charWidth - clippedLabel.length - value.length;
    return padding > 0 ? '$clippedLabel${' ' * padding}$value' : '$clippedLabel $value';
  }
}
