/// Connection lifecycle state for a hardware adapter. Mirrors the frozen
/// hardware-architecture failure model: hardware state is always tracked
/// separately from financial transaction state.
enum HardwareConnectionStatus {
  connected,
  disconnected,
  connecting,
  error,
  timeout,
  unknown,
  disabled,
}

/// Stable, UI-safe error classification. Never expose a raw socket
/// exception or other platform error to presentation code -- translate it
/// into one of these first.
enum HardwareErrorCode {
  notConfigured,
  disabled,
  connectionFailed,
  timeout,
  writeFailed,
  printerError,
  unsupportedOperation,
  unknown,
}

/// A hardware-layer failure. Deliberately implements [Exception] so adapters
/// may either throw it (e.g. from `connect`) or embed it in a [PrintResult]
/// (from `print`) -- callers only ever need to branch on [code].
class HardwareFailure implements Exception {
  final HardwareErrorCode code;
  final String message;

  const HardwareFailure(this.code, this.message);

  @override
  String toString() => 'HardwareFailure($code): $message';
}

/// Whether a print attempt is known to have reached the printer. Plain
/// ESC/POS-over-TCP has no application-level acknowledgement, so a failure
/// partway through a write can mean the printer received nothing, received
/// everything, or received a partial receipt -- [uncertain] exists so the
/// adapter never has to lie about which of those happened.
enum PrintOutcome { confirmed, failed, uncertain }

class PrintResult {
  final PrintOutcome outcome;
  final HardwareFailure? failure;

  const PrintResult._(this.outcome, this.failure);

  const PrintResult.confirmed() : this._(PrintOutcome.confirmed, null);
  const PrintResult.failed(HardwareFailure failure) : this._(PrintOutcome.failed, failure);
  const PrintResult.uncertain(HardwareFailure failure) : this._(PrintOutcome.uncertain, failure);

  bool get isConfirmed => outcome == PrintOutcome.confirmed;
}
