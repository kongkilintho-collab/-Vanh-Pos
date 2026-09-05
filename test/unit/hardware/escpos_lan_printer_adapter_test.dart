// Uses dart:io directly (ServerSocket) to stand up a real loopback TCP
// listener -- this proves the adapter's TCP/ESC-POS wiring end-to-end
// without a physical printer. Safe here because `flutter test` runs on the
// Dart VM; this file is never compiled for Web.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:beauty_clinic_pos/core/hardware/adapters/escpos_encoder.dart';
import 'package:beauty_clinic_pos/core/hardware/adapters/escpos_lan_printer_adapter.dart';
import 'package:beauty_clinic_pos/core/hardware/contracts/printer_adapter.dart';
import 'package:beauty_clinic_pos/core/hardware/formatting/receipt_document.dart';
import 'package:beauty_clinic_pos/core/hardware/models/hardware_result.dart';

void main() {
  group('EscPosLanPrinterAdapter against a loopback TCP listener', () {
    test('connects and writes exactly the encoded ESC/POS bytes', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final receivedBytes = <int>[];
      final receivedAllData = Completer<void>();
      server.listen((socket) {
        socket.listen(
          receivedBytes.addAll,
          onDone: () => receivedAllData.complete(),
        );
      });

      const document = ReceiptDocument([
        ReceiptLine.text('Beauty Clinic', align: ReceiptAlign.center, bold: true),
        ReceiptLine.cut(),
      ]);

      final adapter = EscPosLanPrinterAdapter();
      await adapter.connect(PrinterDeviceConfig(
        host: 'localhost',
        port: server.port,
        connectTimeout: const Duration(seconds: 2),
        writeTimeout: const Duration(seconds: 2),
      ));
      expect(adapter.status, HardwareConnectionStatus.connected);

      final result = await adapter.print(document);
      expect(result.isConfirmed, isTrue);

      await adapter.disconnect();
      expect(adapter.status, HardwareConnectionStatus.disconnected);

      await receivedAllData.future.timeout(const Duration(seconds: 2));
      expect(receivedBytes, encodeReceipt(document));

      await server.close();
    });

    test(
      'reports a typed HardwareFailure, never a raw platform exception, when nothing is listening',
      () async {
        // Bind then immediately close to get a port with nothing listening.
        // Whether the OS/sandbox network stack answers with an immediate
        // refusal (-> CONNECTION_FAILED) or never answers at all within the
        // configured window (-> TIMEOUT) is environment-dependent; either
        // is a correct, honest classification of what actually happened.
        // What must never happen is a raw SocketException escaping this
        // adapter, which this test's `throwsA(isA<HardwareFailure>...)`
        // enforces regardless of which of the two it is.
        final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final unusedPort = probe.port;
        await probe.close();

        final adapter = EscPosLanPrinterAdapter();
        await expectLater(
          () => adapter.connect(PrinterDeviceConfig(
            host: 'localhost',
            port: unusedPort,
            connectTimeout: const Duration(seconds: 2),
          )),
          throwsA(
            isA<HardwareFailure>().having(
              (f) => f.code,
              'code',
              anyOf(HardwareErrorCode.connectionFailed, HardwareErrorCode.timeout),
            ),
          ),
        );
        expect(adapter.status, anyOf(HardwareConnectionStatus.error, HardwareConnectionStatus.timeout));
      },
    );

    test('reports TIMEOUT when the connect attempt exceeds the configured timeout', () async {
      // 10.255.255.1 is a non-routable address commonly used in tests to
      // force a connect attempt that never resolves within a short window.
      final adapter = EscPosLanPrinterAdapter();
      await expectLater(
        () => adapter.connect(const PrinterDeviceConfig(
          host: '10.255.255.1',
          port: 9100,
          connectTimeout: Duration(milliseconds: 200),
        )),
        throwsA(
          isA<HardwareFailure>().having(
            (f) => f.code,
            'code',
            anyOf(HardwareErrorCode.timeout, HardwareErrorCode.connectionFailed),
          ),
        ),
      );
    }, skip: 'Network reachability of the probe address is environment-dependent; run manually when validating against real network conditions.');

    test('print() fails safely when called before connect()', () async {
      final adapter = EscPosLanPrinterAdapter();
      const document = ReceiptDocument([ReceiptLine.text('hi')]);

      final result = await adapter.print(document);

      expect(result.outcome, PrintOutcome.failed);
      expect(result.failure?.code, HardwareErrorCode.connectionFailed);
    });
  });
}
