

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;


class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCCRhvgG8D0iGZEXxui6GJbXf7j-kHBIGc',
    appId: '1:710547669825:web:99486767cf20d1210a17c0',
    messagingSenderId: '710547669825',
    projectId: 'vest-tracker-system',
    authDomain: 'vest-tracker-system.firebaseapp.com',
    databaseURL: 'https://vest-tracker-system-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'vest-tracker-system.firebasestorage.app',
    measurementId: 'G-NEQWT5H2X3',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA0WC18bVO2nE7ZupP_NKSq-qW3j6GCCpQ',
    appId: '1:710547669825:android:7ab23e3791bb47ca0a17c0',
    messagingSenderId: '710547669825',
    projectId: 'vest-tracker-system',
    databaseURL: 'https://vest-tracker-system-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'vest-tracker-system.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBG1DVW9ZBZjyeq2yJJTz0rwvY_aGHOA94',
    appId: '1:710547669825:ios:ffc61139a246f9f50a17c0',
    messagingSenderId: '710547669825',
    projectId: 'vest-tracker-system',
    databaseURL: 'https://vest-tracker-system-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'vest-tracker-system.firebasestorage.app',
    iosBundleId: 'com.example.vestTracker',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyBG1DVW9ZBZjyeq2yJJTz0rwvY_aGHOA94',
    appId: '1:710547669825:ios:ffc61139a246f9f50a17c0',
    messagingSenderId: '710547669825',
    projectId: 'vest-tracker-system',
    databaseURL: 'https://vest-tracker-system-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'vest-tracker-system.firebasestorage.app',
    iosBundleId: 'com.example.vestTracker',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyCCRhvgG8D0iGZEXxui6GJbXf7j-kHBIGc',
    appId: '1:710547669825:web:34e8a6a3c86edbd60a17c0',
    messagingSenderId: '710547669825',
    projectId: 'vest-tracker-system',
    authDomain: 'vest-tracker-system.firebaseapp.com',
    databaseURL: 'https://vest-tracker-system-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'vest-tracker-system.firebasestorage.app',
    measurementId: 'G-EFR51WN8X4',
  );
}
