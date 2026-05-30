import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class AppConfig {
  const AppConfig({
    required this.firebaseDatabaseUrl,
    required this.allowedUid,
    required this.selectedDeviceId,
    required this.notificationsEnabled,
    required this.pollIntervalMinutes,
    required this.logsUploadEnabled,
  });

  final String firebaseDatabaseUrl;
  final String allowedUid;
  final String selectedDeviceId;
  final bool notificationsEnabled;
  final int pollIntervalMinutes;
  final bool logsUploadEnabled;

  static const defaults = AppConfig(
    firebaseDatabaseUrl: '',
    allowedUid: '',
    selectedDeviceId: '',
    notificationsEnabled: true,
    pollIntervalMinutes: 15,
    logsUploadEnabled: true,
  );

  AppConfig copyWith({
    String? firebaseDatabaseUrl,
    String? allowedUid,
    String? selectedDeviceId,
    bool? notificationsEnabled,
    int? pollIntervalMinutes,
    bool? logsUploadEnabled,
  }) {
    return AppConfig(
      firebaseDatabaseUrl: firebaseDatabaseUrl ?? this.firebaseDatabaseUrl,
      allowedUid: allowedUid ?? this.allowedUid,
      selectedDeviceId: selectedDeviceId ?? this.selectedDeviceId,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      pollIntervalMinutes: pollIntervalMinutes ?? this.pollIntervalMinutes,
      logsUploadEnabled: logsUploadEnabled ?? this.logsUploadEnabled,
    );
  }

  Map<String, Object?> toJson() => {
        'firebaseDatabaseUrl': firebaseDatabaseUrl,
        'allowedUid': allowedUid,
        'selectedDeviceId': selectedDeviceId,
        'notificationsEnabled': notificationsEnabled,
        'pollIntervalMinutes': pollIntervalMinutes,
        'logsUploadEnabled': logsUploadEnabled,
      };

  static AppConfig fromJson(Map<String, Object?> json) {
    String readString(String k) => (json[k] as String?) ?? '';
    bool readBool(String k, bool d) => (json[k] as bool?) ?? d;
    int readInt(String k, int d) => (json[k] as int?) ?? d;

    return AppConfig(
      firebaseDatabaseUrl: readString('firebaseDatabaseUrl'),
      allowedUid: readString('allowedUid'),
      selectedDeviceId: readString('selectedDeviceId'),
      notificationsEnabled: readBool('notificationsEnabled', defaults.notificationsEnabled),
      pollIntervalMinutes: readInt('pollIntervalMinutes', defaults.pollIntervalMinutes),
      logsUploadEnabled: readBool('logsUploadEnabled', defaults.logsUploadEnabled),
    );
  }

  String toStorageString() => jsonEncode(toJson());

  static AppConfig? tryFromStorageString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return fromJson(decoded.cast<String, Object?>());
      }
    } catch (_) {}
    return null;
  }
}

class AppConfigStore {
  AppConfigStore._(this._prefs);

  static const _key = 'vest_tracker.app_config.v1';
  final SharedPreferences _prefs;

  static Future<AppConfigStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return AppConfigStore._(prefs);
  }

  AppConfig load() {
    return AppConfig.tryFromStorageString(_prefs.getString(_key)) ?? AppConfig.defaults;
  }

  Future<void> save(AppConfig config) async {
    await _prefs.setString(_key, config.toStorageString());
  }
}

class AppConfigController extends ValueNotifier<AppConfig> {
  AppConfigController({required AppConfigStore store, required AppConfig initial})
      : _store = store,
        super(initial);

  final AppConfigStore _store;

  Future<void> update(AppConfig next) async {
    value = next;
    await _store.save(next);
  }
}

