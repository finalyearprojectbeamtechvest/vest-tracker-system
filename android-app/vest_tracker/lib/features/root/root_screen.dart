import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../config/app_config_scope.dart';
import '../../firebase/firebase_client.dart';
import '../../firebase/firebase_client_scope.dart';
import '../../logging/app_logger.dart';
import '../../notifications/wet_monitor.dart';
import '../auth/sign_in_screen.dart';
import '../devices/devices_screen.dart';
import '../map/live_map_screen.dart';
import '../profile/profile_screen.dart';

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _index = 0;
  WetMonitorForeground? _wetMonitor;
  FirebaseClient? _wetClient;

  
  Future<FirebaseClient>? _initFuture;
  String? _initFutureUrl;

  static const _tabs = <Widget>[
    LiveMapScreen(),
    DevicesScreen(),
    ProfileScreen(),
  ];

  @override
  void dispose() {
    _wetMonitor?.dispose();
    super.dispose();
  }

  bool _isAuthorized(User? user, String allowedUid) {
    if (user == null) return false;
    final allowed = allowedUid.trim();
    if (allowed.isEmpty) return false;
    return user.uid == allowed;
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppConfigScope.of(context);
    final config = controller.value;

    if (config.firebaseDatabaseUrl.trim().isEmpty) {
      
      
      return _ScaffoldWithNav(
        index: _index,
        onIndex: (i) => setState(() => _index = i),
        child: Stack(
          children: [
            IndexedStack(index: _index, children: _tabs),
            if (_index != 2)
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.icon(
                    onPressed: () => setState(() => _index = 2),
                    icon: const Icon(Icons.settings),
                    label: const Text('Configure Firebase in Profile'),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final url = config.firebaseDatabaseUrl.trim();
    if (_initFuture == null || _initFutureUrl != url) {
      _initFuture = FirebaseClient.initialize(config);
      _initFutureUrl = url;
    }

    return FutureBuilder<FirebaseClient>(
      future: _initFuture,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Vest Tracker')),
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Firebase init failed',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('${snap.error}'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => setState(() {
                      _initFuture = null;
                      _initFutureUrl = null;
                    }),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        if (!snap.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final client = snap.data!;
        AppLogger.instance.attachFirebase(
          client: client,
          configController: controller,
        );
        if (_wetClient != client) {
          _wetMonitor?.dispose();
          _wetClient = client;
          final monitor = WetMonitorForeground(
            client: client,
            configController: controller,
          );
          _wetMonitor = monitor;
          
          unawaited(monitor.start());
        }

        return FirebaseClientScope(
          client: client,
          child: StreamBuilder<User?>(
            stream: client.authStateChanges,
            initialData: client.currentUser,
            builder: (context, authSnap) {
              final user = authSnap.data;
              final authorized = _isAuthorized(user, config.allowedUid);
              if (!authorized) {
                return SignInScreen(firebase: client);
              }
              return _ScaffoldWithNav(
                index: _index,
                onIndex: (i) => setState(() => _index = i),
                child: IndexedStack(index: _index, children: _tabs),
              );
            },
          ),
        );
      },
    );
  }
}

class _ScaffoldWithNav extends StatelessWidget {
  const _ScaffoldWithNav({
    required this.index,
    required this.onIndex,
    required this.child,
  });

  final int index;
  final ValueChanged<int> onIndex;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: onIndex,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'Live Map'),
          NavigationDestination(
              icon: Icon(Icons.devices_outlined),
              selectedIcon: Icon(Icons.devices),
              label: 'Devices'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile'),
        ],
      ),
    );
  }
}
