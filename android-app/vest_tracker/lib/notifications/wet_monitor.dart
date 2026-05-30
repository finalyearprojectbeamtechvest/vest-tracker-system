import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../config/app_config.dart';
import '../firebase/firebase_client.dart';
import '../firebase/vest_models.dart';
import '../logging/app_logger.dart';
import 'notification_service.dart';

const wetMonitorTaskName = 'vest_tracker_wet_monitor';


const String wetMonitorLastWetPrefix = 'vest_tracker.lastWet.';

class WetMonitorForeground {
  WetMonitorForeground({
    required FirebaseClient client,
    required AppConfigController configController,
  })  : _client = client,
        _configController = configController;

  final FirebaseClient _client;
  final AppConfigController _configController;

  StreamSubscription<DatabaseEvent>? _sub;
  final Map<String, bool> _lastWet = {};
  
  String _scope = '';
  bool _loaded = false;

  Future<void> start() async {
    await _loadLastWetStates();
    _configController.addListener(_onConfig);
    _onConfig();
  }

  void dispose() {
    _configController.removeListener(_onConfig);
    _sub?.cancel();
    _sub = null;
  }

  Future<void> _loadLastWetStates() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys()) {
      if (!k.startsWith(wetMonitorLastWetPrefix)) continue;
      final device = k.substring(wetMonitorLastWetPrefix.length);
      final v = prefs.getBool(k);
      if (v != null) _lastWet[device] = v;
    }
    _loaded = true;
    AppLogger.instance.debug(
      'Wet monitor loaded last-wet state',
      context: {'count': _lastWet.length},
    );
  }

  Future<void> _persistLastWet(String device, bool wet) async {
    _lastWet[device] = wet;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$wetMonitorLastWetPrefix$device', wet);
  }

  void _onConfig() {
    final cfg = _configController.value;

    if (!cfg.notificationsEnabled) {
      if (_sub != null) {
        AppLogger.instance.info('Wet monitor stopped: notifications disabled');
      }
      _sub?.cancel();
      _sub = null;
      _scope = '';
      return;
    }

    final device = cfg.selectedDeviceId.trim();
    final scope = device.isEmpty ? '__all__' : device;

    if (_scope == scope && _sub != null) return;
    _sub?.cancel();
    _scope = scope;

    if (device.isEmpty) {
      _sub = _client.watchVestRoot().listen(_onRootEvent, onError: _onStreamError);
      AppLogger.instance.info(
        'Wet monitor watching ALL devices',
        context: {'path': 'vest'},
      );
    } else {
      _sub = _client.watchDevice(device).listen(
            (e) => _onDeviceEvent(device, e),
            onError: _onStreamError,
          );
      AppLogger.instance.info(
        'Wet monitor watching device',
        context: {'device': device, 'path': 'vest/$device'},
      );
    }
  }

  void _onStreamError(Object error, StackTrace st) {
    AppLogger.instance.error(
      'Wet monitor stream error',
      context: {'error': '$error'},
      stack: st,
    );
  }

  Future<void> _onRootEvent(DatabaseEvent event) async {
    final value = event.snapshot.value;
    if (value is! Map) return;
    for (final entry in value.entries) {
      final deviceId = entry.key.toString();
      final raw = entry.value;
      if (raw is! Map) continue;
      final wet = parseVestWetField(raw['wet']);
      if (wet == null) continue;
      await _checkAndNotify(deviceId, wet);
    }
  }

  Future<void> _onDeviceEvent(String deviceId, DatabaseEvent event) async {
    final value = event.snapshot.value;
    if (value is! Map) return;
    final wet = parseVestWetField(value['wet']);
    if (wet == null) return;
    await _checkAndNotify(deviceId, wet);
  }

  Future<void> _checkAndNotify(String deviceId, bool wet) async {
    if (!_loaded) return;
    final previous = _lastWet[deviceId];

    if (previous == null) {
      
      
      await _persistLastWet(deviceId, wet);
      AppLogger.instance.debug(
        'Wet monitor baseline recorded',
        context: {'device': deviceId, 'wet': wet},
      );
      return;
    }

    if (previous == wet) return;

    AppLogger.instance.info(
      'Wet state changed',
      context: {'device': deviceId, 'from': previous, 'to': wet},
    );

    await _persistLastWet(deviceId, wet);

    if (previous == false && wet == true) {
      try {
        await NotificationService.showWetAlert(
          deviceId: deviceId,
          origin: WetAlertOrigin.foregroundMonitor,
        );
        AppLogger.instance.info(
          'Wet alert notification fired',
          context: {'device': deviceId},
        );
      } catch (err, st) {
        AppLogger.instance.error(
          'Failed to show wet alert',
          context: {'device': deviceId, 'error': '$err'},
          stack: st,
        );
      }
    }
  }
}

class WetMonitorBackground {
  WetMonitorBackground._();

  static Future<void> initialize() async {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  }

  static Future<void> scheduleFromConfig(AppConfig config) async {
    await Workmanager().cancelByUniqueName(wetMonitorTaskName);

    if (!config.notificationsEnabled) return;

    final freq = Duration(minutes: config.pollIntervalMinutes.clamp(15, 240));
    await Workmanager().registerPeriodicTask(
      wetMonitorTaskName,
      wetMonitorTaskName,
      frequency: freq,
      initialDelay: const Duration(minutes: 1),
      constraints: Constraints(networkType: NetworkType.connected),
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 1),
    );
  }

  static Future<void> runOnce() async {
    final store = await AppConfigStore.create();
    final cfg = store.load();
    if (!cfg.notificationsEnabled) return;

    final client = await FirebaseClient.initialize(cfg);
    
    
    if (client.currentUser == null) {
      try {
        await client.signInAnonymously();
      } catch (_) {
        
        
        return;
      }
    }

    final device = cfg.selectedDeviceId.trim();
    final prefs = await SharedPreferences.getInstance();

    if (device.isEmpty) {
      
      final snap = await client.vestRootRef.get();
      final value = snap.value;
      if (value is! Map) return;
      for (final entry in value.entries) {
        final deviceId = entry.key.toString();
        final raw = entry.value;
        if (raw is! Map) continue;
        final wet = parseVestWetField(raw['wet']);
        if (wet == null) continue;
        await _evaluateAndNotify(prefs, deviceId, wet);
      }
    } else {
      final snap = await client.deviceRef(device).get();
      final value = snap.value;
      if (value is! Map) return;
      final wet = parseVestWetField(value['wet']);
      if (wet == null) return;
      await _evaluateAndNotify(prefs, device, wet);
    }
  }

  static Future<void> _evaluateAndNotify(
    SharedPreferences prefs,
    String deviceId,
    bool wet,
  ) async {
    final key = '$wetMonitorLastWetPrefix$deviceId';
    final previous = prefs.getBool(key);
    if (previous == false && wet == true) {
      await NotificationService.showWetAlert(
        deviceId: deviceId,
        origin: WetAlertOrigin.backgroundPoll,
      );
    }
    if (previous != wet) {
      await prefs.setBool(key, wet);
    }
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    await NotificationService.ensureInitialized();
    await WetMonitorBackground.runOnce();
    return Future.value(true);
  });
}
