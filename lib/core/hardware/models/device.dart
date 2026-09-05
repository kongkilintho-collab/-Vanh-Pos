/// Kinds of hardware device this POS can be configured to talk to. Only
/// [receiptPrinter] has an adapter implementation today (LAN/ESC-POS); the
/// other values exist so the [Device] shape does not need to change again
/// when future adapters (scanner, drawer, label printer, ...) are added.
enum DeviceType {
  receiptPrinter,
  labelPrinter,
  barcodeScanner,
  cashDrawer,
  customerDisplay,
}

/// How the POS reaches a device. Only [lan] is implemented in this slice;
/// the others are reserved so device configuration does not need reshaping
/// when a USB/Bluetooth/Serial adapter is added later.
enum ConnectionType { lan, usb, bluetooth, serial }

/// Client-side-only description of one configured hardware device. This is
/// local configuration metadata, not a source of truth for any financial or
/// business data, and it is never written to Supabase by this slice.
class Device {
  final String id;
  final DeviceType type;
  final String name;
  final String? manufacturer;
  final String? model;
  final ConnectionType connectionType;

  /// Required for [ConnectionType.lan]; unused by other connection types.
  final String? host;
  final int? port;

  final int connectTimeoutMs;
  final bool enabled;
  final bool isDefault;

  const Device({
    required this.id,
    required this.type,
    required this.name,
    this.manufacturer,
    this.model,
    required this.connectionType,
    this.host,
    this.port,
    this.connectTimeoutMs = 5000,
    this.enabled = true,
    this.isDefault = false,
  });

  Device copyWith({bool? enabled, bool? isDefault}) {
    return Device(
      id: id,
      type: type,
      name: name,
      manufacturer: manufacturer,
      model: model,
      connectionType: connectionType,
      host: host,
      port: port,
      connectTimeoutMs: connectTimeoutMs,
      enabled: enabled ?? this.enabled,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'name': name,
      if (manufacturer != null) 'manufacturer': manufacturer,
      if (model != null) 'model': model,
      'connection_type': connectionType.name,
      if (host != null) 'host': host,
      if (port != null) 'port': port,
      'connect_timeout_ms': connectTimeoutMs,
      'enabled': enabled,
      'is_default': isDefault,
    };
  }

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'] as String,
      type: DeviceType.values.byName(json['type'] as String),
      name: json['name'] as String,
      manufacturer: json['manufacturer'] as String?,
      model: json['model'] as String?,
      connectionType: ConnectionType.values.byName(json['connection_type'] as String),
      host: json['host'] as String?,
      port: json['port'] as int?,
      connectTimeoutMs: json['connect_timeout_ms'] as int? ?? 5000,
      enabled: json['enabled'] as bool? ?? true,
      isDefault: json['is_default'] as bool? ?? false,
    );
  }
}
