import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'firebase/firebase_options.dart';
import 'logging/app_logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogger.instance.initialize();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLogger.instance.error(
      details.exceptionAsString(),
      context: {'library': details.library, 'context': '${details.context}'},
      stack: details.stack,
    );
  };

  
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e, st) {
    AppLogger.instance.error(
      'Firebase core init failed',
      context: {'error': '$e'},
      stack: st,
    );
  }

  runApp(const VestTrackerApp());
}
