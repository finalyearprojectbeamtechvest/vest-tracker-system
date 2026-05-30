import 'package:flutter_local_notifications/flutter_local_notifications.dart';


enum WetAlertOrigin {
  
  test,
  
  foregroundMonitor,
  
  backgroundPoll,
}

class NotificationService {
  NotificationService._();

  
  static const int _testNotificationId = 0x7E574573; 

  static const String channelId = 'wet_alerts';
  static const String channelName = 'Wet Alerts';
  static const String channelDescription = 'Alerts when a vest becomes wet.';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: android);
    await _plugin.initialize(settings: initSettings);

    
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDescription,
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    ));

    _initialized = true;
  }

  
  static Future<bool?> areAndroidNotificationsEnabled() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return null;
    return android.areNotificationsEnabled();
  }

  static Future<void> requestAndroidPermissionIfNeeded() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    await android.requestNotificationsPermission();
  }

  static Future<void> showWetAlert({
    required String deviceId,
    WetAlertOrigin origin = WetAlertOrigin.foregroundMonitor,
  }) async {
    await ensureInitialized();

    const realTitle = 'Water detected';
    const realTicker = 'Water detected — Vest Tracker';
    final realBody =
        'Moisture was reported for vest $deviceId. Please check the unit, '
        'dry the sensor if it is wet, and open Vest Tracker for details.';

    final (String title, String body, String ticker, String payload) = switch (origin) {
      WetAlertOrigin.test => (
          'Test notification',
          'This is a test notification. It does not mean a vest became wet. '
              'Device id used for preview: $deviceId.',
          'Test notification',
          'test:$deviceId',
        ),
      WetAlertOrigin.foregroundMonitor ||
      WetAlertOrigin.backgroundPoll =>
        (
          realTitle,
          realBody,
          realTicker,
          'wet:$deviceId',
        ),
    };

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      ticker: ticker,
    );

    final details = NotificationDetails(android: androidDetails);
    final id = origin == WetAlertOrigin.test ? _testNotificationId : deviceId.hashCode;
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }
}
