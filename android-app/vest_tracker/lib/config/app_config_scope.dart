import 'package:flutter/widgets.dart';

import 'app_config.dart';

class AppConfigScope extends InheritedNotifier<AppConfigController> {
  const AppConfigScope({
    super.key,
    required AppConfigController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppConfigController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppConfigScope>();
    assert(scope != null, 'AppConfigScope not found in widget tree');
    return scope!.notifier!;
  }
}

