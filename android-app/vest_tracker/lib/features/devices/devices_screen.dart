import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/app_config_scope.dart';
import '../../firebase/firebase_client_scope.dart';
import '../../firebase/vest_models.dart';
import '../../firebase/vest_repository.dart';

class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _DevicesAuthedBody();
  }
}

class _DevicesAuthedBody extends StatelessWidget {
  static const _malaysiaOffset = Duration(hours: 8);
  static final DateFormat _myFormat = DateFormat('h:mm a dd-MM-yyyy');
  static const _onlineWindow = Duration(minutes: 10);

  DateTime _toMalaysiaTime(DateTime dt) {
    
    return dt.toUtc().add(_malaysiaOffset);
  }

  bool _isOnline(DateTime? lastSeen) {
    if (lastSeen == null) return false;
    final nowUtc = DateTime.now().toUtc();
    return lastSeen.toUtc().isAfter(nowUtc.subtract(_onlineWindow));
  }

  String _formatMalaysiaDateTime(DateTime dt) {
    final my = _toMalaysiaTime(dt);
    return _myFormat.format(my);
  }

  String _formatLastSeen(DateTime? dt) {
    if (dt == null) return 'Last seen: unknown';
    return 'Last seen: ${_formatMalaysiaDateTime(dt)}';
  }

  @override
  Widget build(BuildContext context) {
    final client = FirebaseClientScope.of(context);
    final repo = VestRepository(client);
    final configController = AppConfigScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
      ),
      body: StreamBuilder<List<VestTelemetry>>(
        stream: repo.watchAllTelemetry(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error loading devices: ${snap.error}'),
            );
          }

          final devices = snap.data ?? const <VestTelemetry>[];
          if (devices.isEmpty) {
            return const Center(child: Text('No devices found under /vest.'));
          }

          final selected = configController.value.selectedDeviceId.trim();

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: devices.length,
            separatorBuilder: (_, index) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final d = devices[i];
              final isSelected = selected.isNotEmpty && selected == d.deviceId;
              final wet = d.wet == true;

              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: wet ? Colors.red : Colors.green,
                    child: Icon(wet ? Icons.water_drop : Icons.check, color: Colors.white),
                  ),
                  title: Text(d.deviceName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_formatLastSeen(d.lastSeen)),
                      const SizedBox(height: 2),
                      Builder(
                        builder: (context) {
                          final online = _isOnline(d.lastSeen);
                          return Text(
                            online ? 'Status: Online' : 'Status: Offline',
                            style: TextStyle(
                              color: online ? Colors.green : Theme.of(context).hintColor,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Builder(
                        builder: (context) {
                          final online = _isOnline(d.lastSeen);
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Icon(
                              online ? Icons.wifi : Icons.wifi_off,
                              color: online ? Colors.green : Theme.of(context).hintColor,
                            ),
                          );
                        },
                      ),
                      if (wet)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Chip(
                            label: Text('WET'),
                            labelStyle: TextStyle(color: Colors.white),
                            backgroundColor: Colors.red,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      if (isSelected) const Icon(Icons.check_circle),
                    ],
                  ),
                  onTap: () async {
                    await configController.update(configController.value.copyWith(selectedDeviceId: d.deviceId));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Selected device: ${d.deviceName}')),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

