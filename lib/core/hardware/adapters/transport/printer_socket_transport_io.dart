import 'dart:io';

import 'printer_socket_transport.dart';

PrinterSocketTransport createPrinterSocketTransport() => _IoPrinterSocketTransport();

class _IoPrinterSocketTransport implements PrinterSocketTransport {
  Socket? _socket;

  @override
  Future<void> connect(String host, int port, Duration timeout) async {
    try {
      _socket = await Socket.connect(host, port, timeout: timeout);
    } on SocketException catch (e) {
      if (e.message.toLowerCase().contains('timed out')) {
        throw const PrinterTransportTimeoutException();
      }
      throw PrinterTransportConnectionException(e.message);
    }
  }

  @override
  Future<void> write(List<int> bytes, Duration timeout) async {
    final socket = _socket;
    if (socket == null) {
      throw StateError('PrinterSocketTransport.write called before connect');
    }
    socket.add(bytes);
    await socket.flush().timeout(timeout);
  }

  @override
  Future<void> close() async {
    await _socket?.close();
    _socket = null;
  }
}
