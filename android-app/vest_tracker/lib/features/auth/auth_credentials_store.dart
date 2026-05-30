import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class AuthCredentials {
  const AuthCredentials({
    required this.email,
    required this.password,
    required this.uid,
    required this.rememberMe,
  });

  final String email;
  final String password;
  final String uid;
  final bool rememberMe;

  static const empty = AuthCredentials(
    email: '',
    password: '',
    uid: '',
    rememberMe: false,
  );

  AuthCredentials copyWith({
    String? email,
    String? password,
    String? uid,
    bool? rememberMe,
  }) {
    return AuthCredentials(
      email: email ?? this.email,
      password: password ?? this.password,
      uid: uid ?? this.uid,
      rememberMe: rememberMe ?? this.rememberMe,
    );
  }
}


class AuthCredentialsStore {
  static const _key = 'vest_tracker.auth_credentials.v1';

  static Future<AuthCredentials> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return AuthCredentials.empty;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return AuthCredentials(
          email: (decoded['email'] as String?) ?? '',
          password: (decoded['password'] as String?) ?? '',
          uid: (decoded['uid'] as String?) ?? '',
          rememberMe: (decoded['rememberMe'] as bool?) ?? false,
        );
      }
    } catch (_) {}
    return AuthCredentials.empty;
  }

  static Future<void> save(AuthCredentials c) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'email': c.email,
        'password': c.password,
        'uid': c.uid,
        'rememberMe': c.rememberMe,
      }),
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
