import 'printer_socket_transport.dart';

PrinterSocketTransport createPrinterSocketTransport() => _WebPrinterSocketTransport();

/// Flutter Web cannot open an arbitrary TCP socket to a LAN printer -- there
/// is no browser API for it. This stub fails explicitly and immediately
/// (mapped by the adapter to HardwareErrorCode.unsupportedOperation) rather
/// than attempting an unsafe workaround. Web printing requires a future
/// Local Hardware Bridge (a small local service the browser can reach over
/// HTTP/WebSocket), which is out of scope for this slice.
class _WebPrinterSocketTransport implements PrinterSocketTransport {
  @override
  Future<void> connect(String host, int port, Duration timeout) async {
    throw UnsupportedError(
      'Direct LAN/TCP printer connections are not supported on Flutter Web. '
      'A Local Hardware Bridge is required for Web printing (future work).',
    );
  }

  @override
  Future<void> write(List<int> bytes, Duration timeout) async {
    throw UnsupportedError('Not supported on Web.');
  }

  @override
  Future<void> close() async {}
}
