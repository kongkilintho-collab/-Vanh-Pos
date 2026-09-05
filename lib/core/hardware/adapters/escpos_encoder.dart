import 'dart:convert';
import 'dart:typed_data';

import '../formatting/receipt_document.dart';

/// Pure ESC/POS byte encoder: no sockets, no platform code, deterministic
/// output for a given [ReceiptDocument]. Kept separate from the LAN adapter
/// so it is testable without any network access, and so a future
/// non-TCP ESC/POS transport (USB/Bluetooth/Serial) can reuse it unchanged.
///
/// Only the minimum command set needed for a proof-of-pattern receipt is
/// implemented: initialize, alignment, bold/emphasis, line feed, and paper
/// cut. Unsupported/unknown ESC/POS bytes are safely ignored by essentially
/// every ESC/POS-compatible printer, so sending a cut command to a printer
/// without a cutter does not corrupt the receipt -- it is simply ignored.
///
/// Known limitation: text is encoded as UTF-8. Standard ESC/POS printers
/// use a single-byte code page and do not render non-Latin scripts (e.g.
/// Lao) without vendor-specific code-page selection, which this
/// proof-of-pattern encoder does not implement. ASCII/Latin receipt content
/// prints correctly; Lao text will not render correctly on unmodified
/// ESC/POS hardware. This is a documented limitation, not a silent failure.
Uint8List encodeReceipt(ReceiptDocument document) {
  final bytes = BytesBuilder();

  const esc = 0x1B;
  const gs = 0x1D;

  // ESC @ -- initialize printer.
  bytes.addByte(esc);
  bytes.addByte(0x40);

  ReceiptAlign? currentAlign;
  bool currentBold = false;

  void setAlign(ReceiptAlign align) {
    if (align == currentAlign) return;
    currentAlign = align;
    bytes.addByte(esc);
    bytes.addByte(0x61);
    bytes.addByte(switch (align) {
      ReceiptAlign.left => 0x00,
      ReceiptAlign.center => 0x01,
      ReceiptAlign.right => 0x02,
    });
  }

  void setBold(bool bold) {
    if (bold == currentBold) return;
    currentBold = bold;
    bytes.addByte(esc);
    bytes.addByte(0x45);
    bytes.addByte(bold ? 0x01 : 0x00);
  }

  for (final line in document.lines) {
    switch (line.kind) {
      case ReceiptLineKind.text:
        setAlign(line.align);
        setBold(line.bold);
        bytes.add(utf8.encode(line.text));
        bytes.addByte(0x0A);
      case ReceiptLineKind.separator:
        setAlign(ReceiptAlign.left);
        setBold(false);
        bytes.add(utf8.encode('-' * 32));
        bytes.addByte(0x0A);
      case ReceiptLineKind.feed:
        bytes.addByte(0x0A);
      case ReceiptLineKind.cut:
        // GS V 66 0 -- partial cut. Ignored by printers without a cutter.
        bytes.addByte(gs);
        bytes.addByte(0x56);
        bytes.addByte(0x42);
        bytes.addByte(0x00);
    }
  }

  return bytes.toBytes();
}
