import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../config/app_config.dart';
import 'firebase_options.dart';

class FirebaseClient {
  FirebaseClient._(this._db, this._auth, this.databaseUrl);

  final FirebaseDatabase _db;
  final FirebaseAuth _auth;

  
  final String databaseUrl;

  
  static FirebaseClient? _cached;
  static Future<FirebaseClient>? _pending;

  static Future<FirebaseClient> initialize(AppConfig config) {
    final url = config.firebaseDatabaseUrl.trim();

    final existing = _cached;
    if (existing != null && existing.databaseUrl == url) {
      return Future.value(existing);
    }

    final inFlight = _pending;
    if (inFlight != null) return inFlight;

    final future = _doInitialize(url);
    _pending = future;
    return future.then((client) {
      _cached = client;
      _pending = null;
      return client;
    }, onError: (Object e, StackTrace st) {
      _pending = null;
      throw e;
    });
  }

  static Future<FirebaseClient> _doInitialize(String url) async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    final app = Firebase.app();
    final db = url.isEmpty
        ? FirebaseDatabase.instance
        : FirebaseDatabase.instanceFor(app: app, databaseURL: url);
    return FirebaseClient._(db, FirebaseAuth.instance, url);
  }

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential> signInAnonymously() => _auth.signInAnonymously();

  Future<UserCredential> signInWithEmailPassword({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signOut() => _auth.signOut();

  DatabaseReference get vestRootRef => _db.ref('vest');

  DatabaseReference deviceRef(String deviceId) => _db.ref('vest/$deviceId');

  Stream<DatabaseEvent> watchVestRoot() => vestRootRef.onValue;

  Stream<DatabaseEvent> watchDevice(String deviceId) => deviceRef(deviceId).onValue;
}
