import 'printer_service.dart';
import 'registry/device_registry.dart';

/// Top-level facade so POS presentation code depends on one object instead
/// of instantiating adapters/services itself. Add a field here (e.g.
/// `scanner`) when a future module gets its own service -- do not grow
/// [PrinterService] to cover unrelated device types.
class HardwareService {
  final PrinterService printer;
  final DeviceRegistry registry;

  const HardwareService({required this.printer, required this.registry});
}
