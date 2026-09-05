import 'dart:async';

import '../contracts/printer_adapter.dart';
import '../formatting/receipt_document.dart';
import '../models/hardware_result.dart';
import 'escpos_encoder.dart';
import 'transport/printer_socket_transport.dart';

/// Protocol-based printer adapter: plain ESC/POS over a raw TCP socket
/// (the standard port-9100 "raw print" convention supported by effectively
/// every ESC/POS-compatible receipt printer, regardless of manufacturer).
/// Deliberately has no manufacturer-specific behavior -- there is no
/// EpsonPrinter/XPrinter/etc. subclass; any printer that speaks ESC/POS
/// over TCP on the configured host/port works with this one adapter.
class EscPosLanPrinterAdapter implements PrinterAdapter {
  PrinterSocketTransport? _transport;
  PrinterDeviceConfig? _config;
  HardwareConnectionStatus _status = HardwareConnectionStatus.disconnected;

  @override
  HardwareConnectionStatus get status => _status;

  @override
  Future<void> connect(PrinterDeviceConfig config) async {
    _status = HardwareConnectionStatus.connecting;
    final transport = createPrinterSocketTransport();
    try {
      await transport.connect(config.host, config.port, config.connectTimeout);
      _transport = transport;
      _config = config;
      _status = HardwareConnectionStatus.connected;
    } on PrinterTransportTimeoutException {
      _status = HardwareConnectionStatus.timeout;
      throw HardwareFailure(
        HardwareErrorCode.timeout,
        'Connection to ${config.host}:${config.port} timed out',
      );
    } on TimeoutException {
      _status = HardwareConnectionStatus.timeout;
      throw HardwareFailure(
        HardwareErrorCode.timeout,
        'Connection to ${config.host}:${config.port} timed out',
      );
    } on PrinterTransportConnectionException {
      _status = HardwareConnectionStatus.error;
      throw HardwareFailure(
        HardwareErrorCode.connectionFailed,
        'Could not connect to ${config.host}:${config.port}',
      );
    } on UnsupportedError catch (e) {
      _status = HardwareConnectionStatus.error;
      throw HardwareFailure(
        HardwareErrorCode.unsupportedOperation,
        e.message?.toString() ?? 'Not supported on this platform',
      );
    } catch (_) {
      _status = HardwareConnectionStatus.error;
      throw HardwareFailure(
        HardwareErrorCode.connectionFailed,
        'Could not connect to ${config.host}:${config.port}',
      );
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _transport?.close();
    } catch (_) {
      // disconnect() must never throw -- callers rely on this in `finally`.
    }
    _transport = null;
    _config = null;
    _status = HardwareConnectionStatus.disconnected;
  }

  @override
  Future<HardwareConnectionStatus> healthCheck() async => _status;

  @override
  Future<PrintResult> print(ReceiptDocument document) async {
    final transport = _transport;
    final config = _config;
    if (transport == null || config == null || _status != HardwareConnectionStatus.connected) {
      return const PrintResult.failed(
        HardwareFailure(HardwareErrorCode.connectionFailed, 'Printer is not connected'),
      );
    }

    final bytes = encodeReceipt(document);
    try {
      // Raw ESC/POS-over-TCP has no protocol acknowledgement, so a write
      // timeout here does not prove the printer received nothing -- it may
      // have received a partial or complete receipt. Report that honestly
      // as uncertain rather than as a definite failure.
      await transport.write(bytes, config.writeTimeout);
      return const PrintResult.confirmed();
    } on TimeoutException {
      return const PrintResult.uncertain(
        HardwareFailure(HardwareErrorCode.timeout, 'Write timed out; printer status unknown'),
      );
    } catch (_) {
      return const PrintResult.failed(
        HardwareFailure(HardwareErrorCode.writeFailed, 'Failed to send data to the printer'),
      );
    }
  }
}
