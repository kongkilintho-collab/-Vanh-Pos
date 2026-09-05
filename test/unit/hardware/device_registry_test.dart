import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beauty_clinic_pos/core/hardware/models/device.dart';
import 'package:beauty_clinic_pos/core/hardware/registry/device_registry.dart';

Device _printer(String id, {bool enabled = true, bool isDefault = false}) {
  return Device(
    id: id,
    type: DeviceType.receiptPrinter,
    name: 'Printer $id',
    connectionType: ConnectionType.lan,
    host: '10.0.0.$id',
    port: 9100,
    enabled: enabled,
    isDefault: isDefault,
  );
}

Future<DeviceRegistry> _emptyRegistry() async {
  SharedPreferences.setMockInitialValues({});
  return DeviceRegistry.load(await SharedPreferences.getInstance());
}

void main() {
  group('DeviceRegistry', () {
    test('register adds a device and persists it across a reload', () async {
      final registry = await _emptyRegistry();
      await registry.register(_printer('1'));

      expect(registry.list(), hasLength(1));

      final reloaded = await DeviceRegistry.load(await SharedPreferences.getInstance());
      expect(reloaded.list(), hasLength(1));
      expect(reloaded.get('1')?.host, '10.0.0.1');
    });

    test('register replaces an existing device with the same id', () async {
      final registry = await _emptyRegistry();
      await registry.register(_printer('1'));
      await registry.register(_printer('1', enabled: false));

      expect(registry.list(), hasLength(1));
      expect(registry.get('1')?.enabled, isFalse);
    });

    test('remove deletes a device', () async {
      final registry = await _emptyRegistry();
      await registry.register(_printer('1'));
      await registry.remove('1');

      expect(registry.list(), isEmpty);
      expect(registry.get('1'), isNull);
    });

    test('setDefault clears any previous default of the same type', () async {
      final registry = await _emptyRegistry();
      await registry.register(_printer('1', isDefault: true));
      await registry.register(_printer('2'));

      await registry.setDefault('2');

      expect(registry.get('1')?.isDefault, isFalse);
      expect(registry.get('2')?.isDefault, isTrue);
      expect(registry.getDefault(DeviceType.receiptPrinter)?.id, '2');
    });

    test('setEnabled toggles a device without touching others', () async {
      final registry = await _emptyRegistry();
      await registry.register(_printer('1'));
      await registry.register(_printer('2'));

      await registry.setEnabled('1', false);

      expect(registry.get('1')?.enabled, isFalse);
      expect(registry.get('2')?.enabled, isTrue);
    });

    test('getDefault ignores a default device that is disabled', () async {
      final registry = await _emptyRegistry();
      await registry.register(_printer('1', enabled: false, isDefault: true));

      expect(registry.getDefault(DeviceType.receiptPrinter), isNull);
    });

    test('a corrupt persisted value loads as an empty registry rather than throwing', () async {
      SharedPreferences.setMockInitialValues({'hardware_devices_v1': 'not json'});
      final registry = await DeviceRegistry.load(await SharedPreferences.getInstance());

      expect(registry.list(), isEmpty);
    });
  });
}
