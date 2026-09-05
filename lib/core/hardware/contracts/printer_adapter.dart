import '../formatting/receipt_document.dart';
import '../models/device.dart';
import '../models/hardware_result.dart';

/// Connection parameters for one print attempt. Built from a [Device], but
/// kept separate so an adapter never depends on the client-side registry
/// shape -- only on the handful of fields it actually needs.
class PrinterDeviceConfig {
  final String host;
  final int port;
  final Duration connectTimeout;
  final Duration writeTimeout;

  const PrinterDeviceConfig({
    required this.host,
    required this.port,
    this.connectTimeout = const Duration(seconds: 5),
    this.writeTimeout = const Duration(seconds: 5),
  });

  /// Throws [ArgumentError] if [device] has no host/port -- callers must
  /// treat that as a NOT_CONFIGURED failure, not let it propagate raw.
  factory PrinterDeviceConfig.fromDevice(Device device) {
    final host = device.host;
    final port = device.port;
    if (host == null || host.isEmpty || port == null) {
      throw ArgumentError('Device ${device.id} has no host/port configured');
    }
    return PrinterDeviceConfig(
      host: host,
      port: port,
      connectTimeout: Duration(milliseconds: device.connectTimeoutMs),
      writeTimeout: Duration(milliseconds: device.connectTimeoutMs),
    );
  }
}

/// Stable capability contract that POS presentation/service code depends on.
/// Concrete adapters (LAN/ESC-POS today; USB/Bluetooth/Serial later) sit
/// behind this -- the UI must never reference a concrete adapter, a socket,
/// or ESC/POS bytes directly.
abstract class PrinterAdapter {
  HardwareConnectionStatus get status;

  /// Establishes the connection described by [config]. Throws a
  /// [HardwareFailure] on failure; never throws a raw platform exception.
  Future<void> connect(PrinterDeviceConfig config);

  /// Releases the connection. Must never throw -- callers rely on being
  /// able to call this unconditionally in a `finally` block.
  Future<void> disconnect();

  Future<HardwareConnectionStatus> healthCheck();

  /// Sends [document] to the printer. Must return a [PrintResult] rather
  /// than throw for any failure that happens after a connection was
  /// established, and must report [PrintOutcome.uncertain] rather than
  /// [PrintOutcome.failed] whenever it cannot tell whether the printer
  /// actually received the data.
  Future<PrintResult> print(ReceiptDocument document);
}
