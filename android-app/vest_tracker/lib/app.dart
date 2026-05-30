import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'config/app_config_scope.dart';
import 'notifications/notification_service.dart';
import 'notifications/wet_monitor.dart';
import 'features/root/root_screen.dart';

class VestTrackerApp extends StatefulWidget {
  const VestTrackerApp({super.key});

  @override
  State<VestTrackerApp> createState() => _VestTrackerAppState();
}

class _VestTrackerAppState extends State<VestTrackerApp> {
  late final Future<AppConfigController> _controllerFuture = _init();

  Future<AppConfigController> _init() async {
    final store = await AppConfigStore.create();
    final initial = store.load();
    final controller = AppConfigController(store: store, initial: initial);

    await NotificationService.ensureInitialized();
    await NotificationService.requestAndroidPermissionIfNeeded();
    await WetMonitorBackground.initialize();
    await WetMonitorBackground.scheduleFromConfig(controller.value);

    controller.addListener(() {
      
      WetMonitorBackground.scheduleFromConfig(controller.value);
    });

    return controller;
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0A7D84);
    final colorScheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);

    return FutureBuilder<AppConfigController>(
      future: _controllerFuture,
      builder: (context, snap) {
        final controller = snap.data;
        return MaterialApp(
          title: 'Vest Tracker',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: colorScheme,
            useMaterial3: true,
            appBarTheme: const AppBarTheme(centerTitle: false),
          ),
          home: controller == null
              ? const _BootSplash()
              : AppConfigScope(
                  controller: controller,
                  child: const RootScreen(),
                ),
        );
      },
    );
  }
}

class _BootSplash extends StatelessWidget {
  const _BootSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

