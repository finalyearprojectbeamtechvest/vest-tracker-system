import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../firebase/firebase_client.dart';

enum LogLevel { debug, info, warn, error }

@immutable
class AppLogEntry {
  const AppLogEntry({
    required this.id,
    required this.ts,
    required this.level,
    required this.message,
    required this.context,
    required this.stack,
  });

  final String id;
  final DateTime ts;
  final LogLevel level;
  final String message;
  final Map<String, Object?> context;
  final String? stack;

  Map<String, Object?> toJson() => {
        'id': id,
        'ts': ts.toIso8601String(),
        'level': level.name,
        'message': message,
        'context': context,
        'stack': stack,
      };

  static AppLogEntry fromJson(Map<String, Object?> json) {
    return AppLogEntry(
      id: (json['id'] as String?) ?? const Uuid().v4(),
      ts: DateTime.tryParse((json['ts'] as String?) ?? '') ?? DateTime.now(),
      level: LogLevel.values.firstWhere(
        (e) => e.name == (json['level'] as String?),
        orElse: () => LogLevel.info,
      ),
      message: (json['message'] as String?) ?? '',
      context: (json['context'] as Map?)?.cast<String, Object?>() ?? const {},
      stack: json['stack'] as String?,
    );
  }
}

class AppLogger {
  AppLogger._();
  static final AppLogger instance = AppLogger._();

  static const _prefsKey = 'vest_tracker.logs.v1';
  static const _clientIdKey = 'vest_tracker.client_instance_id.v1';
  static const int _maxEntries = 200;

  final ValueNotifier<List<AppLogEntry>> logs = ValueNotifier(const <AppLogEntry>[]);

  String? _clientInstanceId;
  FirebaseClient? _firebase;
  AppConfigController? _config;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _clientInstanceId ??= prefs.getString(_clientIdKey) ?? const Uuid().v4();
    await prefs.setString(_clientIdKey, _clientInstanceId!);

    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          logs.value = decoded
              .whereType<Map>()
              .map((m) => AppLogEntry.fromJson(m.cast<String, Object?>()))
              .toList()
              .reversed
              .toList();
        }
      } catch (_) {}
    }
  }

  void attachFirebase({required FirebaseClient client, required AppConfigController configController}) {
    _firebase = client;
    _config = configController;
  }

  void debug(String message, {Map<String, Object?> context = const {}}) =>
      _add(LogLevel.debug, message, context: context);
  void info(String message, {Map<String, Object?> context = const {}}) =>
      _add(LogLevel.info, message, context: context);
  void warn(String message, {Map<String, Object?> context = const {}}) =>
      _add(LogLevel.warn, message, context: context);
  void error(String message, {Map<String, Object?> context = const {}, Object? error, StackTrace? stack}) {
    final stackStr = stack?.toString() ?? (error is Error ? error.stackTrace?.toString() : null);
    _add(LogLevel.error, message, context: {...context, if (error != null) 'error': '$error'}, stack: stackStr);
  }

  Future<void> clear() async {
    logs.value = const <AppLogEntry>[];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  void _add(LogLevel level, String message, {Map<String, Object?> context = const {}, String? stack}) {
    final entry = AppLogEntry(
      id: const Uuid().v4(),
      ts: DateTime.now(),
      level: level,
      message: message,
      context: context,
      stack: stack,
    );

    final next = [entry, ...logs.value];
    logs.value = next.take(_maxEntries).toList(growable: false);

    unawaited(_persist());
    unawaited(_uploadIfEnabled(entry));
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final list = logs.value.reversed.map((e) => e.toJson()).toList();
    await prefs.setString(_prefsKey, jsonEncode(list));
  }

  Future<void> _uploadIfEnabled(AppLogEntry entry) async {
    final firebase = _firebase;
    final cfg = _config?.value;
    if (firebase == null || cfg == null) return;
    if (!cfg.logsUploadEnabled) return;
    if (_clientInstanceId == null) return;

    try {
      final ref = firebase.vestRootRef.root.child('appLogs/$_clientInstanceId/${entry.ts.toIso8601String()}');
      await ref.set({
        ...entry.toJson(),
        'uid': firebase.currentUser?.uid,
      });
    } catch (_) {
      
    }
  }
}

