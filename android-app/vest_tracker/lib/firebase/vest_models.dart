import 'package:flutter/foundation.dart';


bool? parseVestWetField(Object? v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is int) return v != 0;
  if (v is double) return v != 0.0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true' || s == '1' || s == 'yes' || s == 'on') return true;
    if (s == 'false' || s == '0' || s == 'no' || s == 'off') return false;
  }
  return null;
}

@immutable
class VestTelemetry {
  const VestTelemetry({
    required this.deviceId,
    required this.deviceName,
    required this.lastSeen,
    required this.lat,
    required this.lon,
    required this.wet,
    required this.alt,
    required this.spd,
    required this.sat,
    required this.fixMs,
    required this.timestamp,
    required this.raw,
  });

  final String deviceId;
  final String deviceName;
  final DateTime? lastSeen;
  final double? lat;
  final double? lon;
  final bool? wet;
  final num? alt;
  final num? spd;
  final num? sat;
  final num? fixMs;
  final num? timestamp;
  final Map<String, Object?> raw;

  static DateTime? _tryParseLastSeen(Map<Object?, Object?> map) {
    Object? pick(List<String> keys) {
      for (final k in keys) {
        if (map.containsKey(k)) return map[k];
      }
      return null;
    }

    final v = pick(const [
      'time_my',
      'lastSeen',
      'last_seen',
      'seen',
      'time',
      'timestamp',
      'ts',
      't',
    ]);

    if (v == null) return null;

    if (v is String) {
      final d = DateTime.tryParse(v);
      if (d != null) return d;
      final asNum = num.tryParse(v);
      if (asNum != null) return _fromEpochLike(asNum);
      return null;
    }

    if (v is num) {
      return _fromEpochLike(v);
    }

    return null;
  }

  static DateTime? _fromEpochLike(num v) {
    
    
    if (v >= 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true);
    }
    if (v >= 1000000000) {
      return DateTime.fromMillisecondsSinceEpoch((v * 1000).toInt(), isUtc: true);
    }
    return null;
  }

  static VestTelemetry fromMap(String deviceId, Map<Object?, Object?> map) {
    T? asNum<T extends num>(Object? v) => v is num ? v as T : null;

    double? asDouble(Object? v) => v is num ? v.toDouble() : null;

    final deviceNameRaw = map['deviceName'] ?? map['device_name'] ?? map['name'];
    final deviceName = deviceNameRaw is String && deviceNameRaw.trim().isNotEmpty ? deviceNameRaw.trim() : deviceId;

    return VestTelemetry(
      deviceId: deviceId,
      deviceName: deviceName,
      lastSeen: _tryParseLastSeen(map),
      lat: asDouble(map['lat']),
      lon: asDouble(map['lon']),
      wet: parseVestWetField(map['wet']),
      alt: asNum(map['alt']),
      spd: asNum(map['spd']),
      sat: asNum(map['sat']),
      fixMs: asNum(map['fix_ms']),
      timestamp: asNum(map['t']),
      raw: map.map((k, v) => MapEntry(k.toString(), v)),
    );
  }
}

