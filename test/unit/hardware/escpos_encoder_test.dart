import 'package:flutter_test/flutter_test.dart';

import 'package:beauty_clinic_pos/core/hardware/adapters/escpos_encoder.dart';
import 'package:beauty_clinic_pos/core/hardware/formatting/receipt_document.dart';

void main() {
  group('encodeReceipt', () {
    test('always starts with the ESC @ initialize sequence', () {
      final bytes = encodeReceipt(const ReceiptDocument([ReceiptLine.text('hi')]));
      expect(bytes.sublist(0, 2), [0x1B, 0x40]);
    });

    test('is deterministic for the same document', () {
      const doc = ReceiptDocument([
        ReceiptLine.text('Beauty Clinic', align: ReceiptAlign.center, bold: true),
        ReceiptLine.separator(),
        ReceiptLine.text('Total   10,000 LAK'),
        ReceiptLine.feed(),
        ReceiptLine.cut(),
      ]);

      expect(encodeReceipt(doc), encodeReceipt(doc));
    });

    test('emits an alignment command only when alignment changes', () {
      const doc = ReceiptDocument([
        ReceiptLine.text('a', align: ReceiptAlign.center),
        ReceiptLine.text('b', align: ReceiptAlign.center),
        ReceiptLine.text('c', align: ReceiptAlign.left),
      ]);

      final bytes = encodeReceipt(doc);
      final alignCommandCount = _countOccurrences(bytes, [0x1B, 0x61]);
      // One for the initial switch to center, one for the switch back to
      // left -- not one per line.
      expect(alignCommandCount, 2);
    });

    test('wraps bold text with ESC E 1 / ESC E 0', () {
      const doc = ReceiptDocument([ReceiptLine.text('Total', bold: true)]);
      final bytes = encodeReceipt(doc);

      expect(_countOccurrences(bytes, [0x1B, 0x45, 0x01]), 1);
    });

    test('a cut line appends the GS V partial-cut command', () {
      const doc = ReceiptDocument([ReceiptLine.cut()]);
      final bytes = encodeReceipt(doc);

      expect(bytes.sublist(bytes.length - 4), [0x1D, 0x56, 0x42, 0x00]);
    });

    test('a separator line encodes as a run of 32 dashes', () {
      const doc = ReceiptDocument([ReceiptLine.separator()]);
      final bytes = encodeReceipt(doc);

      expect(String.fromCharCodes(bytes), contains('-' * 32));
    });
  });
}

int _countOccurrences(List<int> haystack, List<int> needle) {
  var count = 0;
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    var matches = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        matches = false;
        break;
      }
    }
    if (matches) count++;
  }
  return count;
}
