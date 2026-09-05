import 'package:flutter_test/flutter_test.dart';

import 'package:beauty_clinic_pos/core/hardware/models/device.dart';

Device _device({bool enabled = true, bool isDefault = false}) {
  return Device(
    id: 'dev-1',
    type: DeviceType.receiptPrinter,
    name: 'Front counter printer',
    manufacturer: 'Generic',
    model: 'ESC/POS',
    connectionType: ConnectionType.lan,
    host: '192.168.1.50',
    port: 9100,
    connectTimeoutMs: 4000,
    enabled: enabled,
    isDefault: isDefault,
  );
}

void main() {
  group('Device', () {
    test('round-trips through toJson/fromJson', () {
      final device = _device(isDefault: true);
      final restored = Device.fromJson(device.toJson());

      expect(restored.id, device.id);
      expect(restored.type, device.type);
      expect(restored.name, device.name);
      expect(restored.manufacturer, device.manufacturer);
      expect(restored.model, device.model);
      expect(restored.connectionType, device.connectionType);
      expect(restored.host, device.host);
      expect(restored.port, device.port);
      expect(restored.connectTimeoutMs, device.connectTimeoutMs);
      expect(restored.enabled, device.enabled);
      expect(restored.isDefault, device.isDefault);
    });

    test('fromJson defaults missing optional fields safely', () {
      final restored = Device.fromJson({
        'id': 'dev-2',
        'type': 'receiptPrinter',
        'name': 'Minimal',
        'connection_type': 'lan',
      });

      expect(restored.manufacturer, isNull);
      expect(restored.host, isNull);
      expect(restored.port, isNull);
      expect(restored.connectTimeoutMs, 5000);
      expect(restored.enabled, isTrue);
      expect(restored.isDefault, isFalse);
    });

    test('copyWith only overrides enabled/isDefault', () {
      final device = _device();
      final updated = device.copyWith(enabled: false, isDefault: true);

      expect(updated.enabled, isFalse);
      expect(updated.isDefault, isTrue);
      expect(updated.id, device.id);
      expect(updated.host, device.host);
      expect(updated.port, device.port);
    });
  });
}
