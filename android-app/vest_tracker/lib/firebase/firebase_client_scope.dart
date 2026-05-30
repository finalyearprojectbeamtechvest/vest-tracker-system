import 'package:flutter/widgets.dart';

import 'firebase_client.dart';

class FirebaseClientScope extends InheritedWidget {
  const FirebaseClientScope({super.key, required this.client, required super.child});

  final FirebaseClient client;

  static FirebaseClient of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<FirebaseClientScope>();
    assert(scope != null, 'FirebaseClientScope not found in widget tree');
    return scope!.client;
  }

  static FirebaseClient? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<FirebaseClientScope>()?.client;
  }

  @override
  bool updateShouldNotify(FirebaseClientScope oldWidget) => client != oldWidget.client;
}

