import 'dart:async';

import 'firebase_client.dart';
import 'vest_models.dart';

class VestRepository {
  const VestRepository(this._client);

  final FirebaseClient _client;

  Stream<List<VestTelemetry>> watchAllTelemetry() {
    return _client.watchVestRoot().map((event) {
      final value = event.snapshot.value;
      if (value is Map<Object?, Object?>) {
        final out = <VestTelemetry>[];
        for (final entry in value.entries) {
          final deviceId = entry.key.toString();
          final raw = entry.value;
          if (raw is Map<Object?, Object?>) {
            out.add(VestTelemetry.fromMap(deviceId, raw));
          }
        }
        out.sort((a, b) => a.deviceId.compareTo(b.deviceId));
        return out;
      }
      return const <VestTelemetry>[];
    });
  }

  Stream<List<String>> watchDeviceIds() {
    return _client.watchVestRoot().map((event) {
      final value = event.snapshot.value;
      if (value is Map) {
        return value.keys.map((e) => e.toString()).toList()..sort();
      }
      return const <String>[];
    });
  }

  Stream<VestTelemetry?> watchTelemetry(String deviceId) {
    return _client.watchDevice(deviceId).map((event) {
      final value = event.snapshot.value;
      if (value is Map<Object?, Object?>) {
        return VestTelemetry.fromMap(deviceId, value);
      }
      return null;
    });
  }

  Future<VestTelemetry?> getTelemetryOnce(String deviceId) async {
    final snap = await _client.deviceRef(deviceId).get();
    final v = snap.value;
    if (v is Map<Object?, Object?>) return VestTelemetry.fromMap(deviceId, v);
    return null;
  }
}

