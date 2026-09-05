// Selects the platform-specific transport implementation at compile time:
// the real `dart:io` Socket implementation everywhere `dart:io` is
// available (Windows, Android, ...), and a stub that fails explicitly on
// Flutter Web (which cannot open arbitrary TCP sockets). This keeps
// `dart:io` out of any file that must also compile for Web -- importing it
// unconditionally would break `flutter build web` entirely.
export 'printer_socket_transport_io.dart'
    if (dart.library.html) 'printer_socket_transport_web.dart';

/// Minimal raw-TCP contract the ESC/POS LAN adapter needs. Deliberately
/// smaller than `dart:io`'s `Socket` -- adapters depend on this, never on
/// `Socket` directly, so the platform split above is invisible above this
/// file.
abstract class PrinterSocketTransport {
  Future<void> connect(String host, int port, Duration timeout);
  Future<void> write(List<int> bytes, Duration timeout);
  Future<void> close();
}

/// Platform-neutral stand-ins for `dart:io`'s `SocketException` (which the
/// io transport translates its own connect-timeout/connect-refused cases
/// into) so the adapter above can distinguish them without importing
/// `dart:io` itself -- keeping the adapter file safe to compile for Web.
class PrinterTransportTimeoutException implements Exception {
  final String message;
  const PrinterTransportTimeoutException([this.message = 'Connection timed out']);
}

class PrinterTransportConnectionException implements Exception {
  final String message;
  const PrinterTransportConnectionException(this.message);
}
