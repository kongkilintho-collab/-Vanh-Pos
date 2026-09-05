/// Printer-independent description of a receipt. Any printer adapter
/// (ESC/POS today; ZPL/TSPL label adapters later) consumes this instead of
/// POS presentation types, so ESC/POS byte encoding never leaks into the UI
/// and a future protocol adapter never needs Sale/CartLine/Business types.
enum ReceiptAlign { left, center, right }

enum ReceiptLineKind { text, separator, feed, cut }

class ReceiptLine {
  final ReceiptLineKind kind;
  final String text;
  final ReceiptAlign align;
  final bool bold;

  const ReceiptLine.text(
    this.text, {
    this.align = ReceiptAlign.left,
    this.bold = false,
  }) : kind = ReceiptLineKind.text;

  const ReceiptLine.separator()
      : kind = ReceiptLineKind.separator,
        text = '',
        align = ReceiptAlign.left,
        bold = false;

  /// A blank line feed (not a printer cut).
  const ReceiptLine.feed()
      : kind = ReceiptLineKind.feed,
        text = '',
        align = ReceiptAlign.left,
        bold = false;

  /// Paper cut. An adapter/printer that doesn't support cutting must ignore
  /// this rather than fail the whole print (see escpos_encoder.dart).
  const ReceiptLine.cut()
      : kind = ReceiptLineKind.cut,
        text = '',
        align = ReceiptAlign.left,
        bold = false;
}

class ReceiptDocument {
  final List<ReceiptLine> lines;
  const ReceiptDocument(this.lines);
}
