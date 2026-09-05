import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/device.dart';

/// Client-side-only registry of configured hardware devices, persisted to
/// local storage (`shared_preferences`, already a POS dependency). This is
/// configuration metadata for this POS terminal only -- it is never synced
/// to Supabase in this slice, never grants access to another business, and
/// is never treated as a source of truth for any financial or business
/// data. business_id/branch_id, if ever stored on a [Device], would be
/// configuration labels only; the registry has no authorization model of
/// its own and must never be used to bypass tenant/RLS validation.
class DeviceRegistry {
  static const _prefsKey = 'hardware_devices_v1';

  final SharedPreferences _prefs;
  List<Device> _devices;

  DeviceRegistry._(this._prefs, this._devices);

  static Future<DeviceRegistry> load(SharedPreferences prefs) async {
    final raw = prefs.getString(_prefsKey);
    final devices = <Device>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List;
        for (final item in decoded) {
          devices.add(Device.fromJson(item as Map<String, dynamic>));
        }
      } catch (_) {
        // Corrupt/unreadable local config must never crash the POS -- fall
        // back to an empty registry rather than propagate the error.
      }
    }
    return DeviceRegistry._(prefs, devices);
  }

  List<Device> list({DeviceType? type}) {
    final devices = type == null ? _devices : _devices.where((d) => d.type == type);
    return List.unmodifiable(devices);
  }

  Device? get(String id) {
    for (final d in _devices) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// The enabled default device for [type], if one is configured. Returns
  /// null (not a thrown error) when none is configured, so callers can
  /// treat "no printer set up yet" as an ordinary, expected state.
  Device? getDefault(DeviceType type) {
    for (final d in _devices) {
      if (d.type == type && d.isDefault && d.enabled) return d;
    }
    return null;
  }

  Future<void> register(Device device) async {
    _devices = [
      for (final d in _devices) if (d.id != device.id) d,
      device,
    ];
    await _persist();
  }

  Future<void> remove(String id) async {
    _devices = [for (final d in _devices) if (d.id != id) d];
    await _persist();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    _devices = [for (final d in _devices) d.id == id ? d.copyWith(enabled: enabled) : d];
    await _persist();
  }

  /// Marks [id] as the default device for its type, clearing any previous
  /// default of that same type (one default per device type).
  Future<void> setDefault(String id) async {
    final target = get(id);
    if (target == null) return;
    _devices = [
      for (final d in _devices)
        d.type == target.type ? d.copyWith(isDefault: d.id == id) : d,
    ];
    await _persist();
  }

  Future<void> _persist() async {
    final raw = jsonEncode(_devices.map((d) => d.toJson()).toList());
    await _prefs.setString(_prefsKey, raw);
  }
}
