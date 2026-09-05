import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'adapters/escpos_lan_printer_adapter.dart';
import 'contracts/printer_adapter.dart';
import 'hardware_service.dart';
import 'printer_service.dart';
import 'registry/device_registry.dart';

final _hardwarePrefsProvider = FutureProvider<SharedPreferences>((ref) {
  return SharedPreferences.getInstance();
});

final deviceRegistryProvider = FutureProvider<DeviceRegistry>((ref) async {
  final prefs = await ref.watch(_hardwarePrefsProvider.future);
  return DeviceRegistry.load(prefs);
});

/// Adapter factory the PrinterService uses -- swapping this is how a future
/// non-LAN printer adapter, or a test fake, gets substituted without
/// touching PrinterService or any POS presentation code.
final PrinterAdapter Function() escPosLanAdapterFactory = EscPosLanPrinterAdapter.new;

final hardwareServiceProvider = FutureProvider<HardwareService>((ref) async {
  final registry = await ref.watch(deviceRegistryProvider.future);
  final printerService = PrinterService(
    registry: registry,
    adapterFactory: escPosLanAdapterFactory,
  );
  return HardwareService(printer: printerService, registry: registry);
});
