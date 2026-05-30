import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../firebase/firebase_client_scope.dart';
import '../../firebase/vest_models.dart';
import '../../firebase/vest_repository.dart';

class LiveMapScreen extends StatefulWidget {
  const LiveMapScreen({super.key});

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  final _mapController = MapController();
  String _focusDeviceId = '';
  String _selectedDeviceId = '';
  LatLng _lastCenter = const LatLng(6.46002, 100.35931);
  double _lastZoom = 15;

  @override
  Widget build(BuildContext context) {
    return _LiveMapAuthedBody(
      mapController: _mapController,
      initialCenter: _lastCenter,
      initialZoom: _lastZoom,
      onCameraChanged: (center, zoom) {
        _lastCenter = center;
        _lastZoom = zoom;
      },
      focusDeviceId: _focusDeviceId,
      onFocusDeviceId: (v) => setState(() => _focusDeviceId = v),
      selectedDeviceId: _selectedDeviceId,
      onSelectedDeviceId: (v) => setState(() => _selectedDeviceId = v),
    );
  }
}

class _LiveMapAuthedBody extends StatelessWidget {
  const _LiveMapAuthedBody({
    required this.mapController,
    required this.initialCenter,
    required this.initialZoom,
    required this.onCameraChanged,
    required this.focusDeviceId,
    required this.onFocusDeviceId,
    required this.selectedDeviceId,
    required this.onSelectedDeviceId,
  });

  final MapController mapController;
  final LatLng initialCenter;
  final double initialZoom;
  final void Function(LatLng center, double zoom) onCameraChanged;
  final String focusDeviceId;
  final ValueChanged<String> onFocusDeviceId;
  final String selectedDeviceId;
  final ValueChanged<String> onSelectedDeviceId;

  @override
  Widget build(BuildContext context) {
    final client = FirebaseClientScope.of(context);
    final repo = VestRepository(client);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Map'),
        actions: [
          StreamBuilder<List<String>>(
            stream: repo.watchDeviceIds(),
            builder: (context, snap) {
              final ids = snap.data ?? const <String>[];
              if (ids.isEmpty) return const SizedBox.shrink();

              final focusValue = focusDeviceId.isEmpty ? '(all)' : focusDeviceId;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: focusValue,
                    items: <String>['(all)', ...ids]
                        .map((id) => DropdownMenuItem(value: id, child: Text(id)))
                        .toList(),
                    onChanged: (v) {
                      final next = v == '(all)' ? '' : (v ?? '');
                      onFocusDeviceId(next);
                      if (next.isNotEmpty) onSelectedDeviceId(next);
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<VestTelemetry>>(
        stream: repo.watchAllTelemetry(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error loading telemetry: ${snap.error}'),
            );
          }

          final all = snap.data ?? const <VestTelemetry>[];
          final visible = focusDeviceId.isEmpty ? all : all.where((t) => t.deviceId == focusDeviceId).toList();
          final withCoords = visible.where((t) => t.lat != null && t.lon != null).toList();

          final effectiveSelected = selectedDeviceId.isNotEmpty
              ? selectedDeviceId
              : (visible.isNotEmpty ? visible.first.deviceId : '');

          
          final markers = withCoords
              .map(
                (t) => Marker(
                  point: LatLng(t.lat!, t.lon!),
                  
                  
                  width: 100,
                  height: 100,
                  alignment: Alignment.topCenter,
                  child: _DeviceMarker(
                    deviceId: t.deviceId,
                    wet: t.wet,
                    isOnline: _isOnline(t.lastSeen),
                    onTap: () => onSelectedDeviceId(t.deviceId),
                  ),
                ),
              )
              .toList();

          return Stack(
            children: [
              FlutterMap(
                mapController: mapController,
                options: MapOptions(
                  initialCenter: initialCenter,
                  initialZoom: initialZoom,
                  onTap: (_, pos) => FocusManager.instance.primaryFocus?.unfocus(),
                  keepAlive: true,
                  onPositionChanged: (pos, hasGesture) {
                    onCameraChanged(pos.center, pos.zoom);
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.vesttracker.vest_tracker',
                  ),
                  MarkerLayer(markers: markers),
                  if (all.isEmpty)
                    const _MapOverlayMessage(
                      title: 'No devices found',
                      message: 'Nothing under /vest yet, or you are not authorized by the RTDB rules.',
                    )
                  else if (withCoords.isEmpty)
                    const _MapOverlayMessage(
                      title: 'No coordinates',
                      message: 'Devices exist, but lat/lon are missing or invalid.',
                    ),
                ],
              ),
              _RecenterButton(
                selectedDeviceId: effectiveSelected,
                devicesWithCoords: withCoords,
                onRecenter: (point) {
                  final zoom = mapController.camera.zoom;
                  mapController.move(point, zoom);
                },
              ),
              if (effectiveSelected.isNotEmpty)
                _DeviceInfoSheet(
                  repo: repo,
                  deviceId: effectiveSelected,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _RecenterButton extends StatelessWidget {
  const _RecenterButton({
    required this.selectedDeviceId,
    required this.devicesWithCoords,
    required this.onRecenter,
  });

  final String selectedDeviceId;
  final List<VestTelemetry> devicesWithCoords;
  final ValueChanged<LatLng> onRecenter;

  @override
  Widget build(BuildContext context) {
    final match = devicesWithCoords.where((d) => d.deviceId == selectedDeviceId).toList();
    final hasTarget = match.isNotEmpty;
    final target = hasTarget ? LatLng(match.first.lat!, match.first.lon!) : null;

    return Positioned(
      top: 12,
      left: 12,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Theme.of(context).dividerColor),
          boxShadow: const [BoxShadow(blurRadius: 10, spreadRadius: 0, color: Color(0x22000000))],
        ),
        child: IconButton(
          tooltip: 'Recenter to device',
          onPressed: hasTarget ? () => onRecenter(target!) : null,
          icon: const Icon(Icons.my_location),
        ),
      ),
    );
  }
}

class _DeviceMarker extends StatelessWidget {
  const _DeviceMarker({
    required this.deviceId,
    required this.wet,
    required this.isOnline,
    required this.onTap,
  });

  final String deviceId;
  final bool? wet;
  final bool isOnline;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isWet = wet == true;
    final color = isWet ? Colors.red : Colors.green;
    const pinSize = 42.0;
    
    const waveBox = 34.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Text(deviceId, style: Theme.of(context).textTheme.labelSmall),
            ),
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomCenter,
              children: [
                if (isOnline)
                  Positioned(
                    left: (pinSize - waveBox) / 2,
                    bottom: -waveBox / 2,
                    width: waveBox,
                    height: waveBox,
                    child: IgnorePointer(child: _OnlineWave(color: color)),
                  ),
                Icon(Icons.location_on, color: color, size: pinSize),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceInfoSheet extends StatelessWidget {
  const _DeviceInfoSheet({required this.repo, required this.deviceId});

  final VestRepository repo;
  final String deviceId;

  @override
  Widget build(BuildContext context) {
    
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.11,
      minChildSize: 0.11,
      maxChildSize: 0.55,
      snap: true,
      builder: (context, scrollController) {
        return Material(
          elevation: 12,
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: StreamBuilder<VestTelemetry?>(
              stream: repo.watchTelemetry(deviceId),
              builder: (context, snap) {
                final t = snap.data;
                final scheme = Theme.of(context).colorScheme;
                final online = t != null && _isOnline(t.lastSeen);
                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(context).dividerColor,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            t?.deviceName ?? deviceId,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (t != null)
                          Chip(
                            label: Text(online ? 'ONLINE' : 'OFFLINE'),
                            avatar: Icon(
                              online ? Icons.wifi : Icons.wifi_off,
                              size: 16,
                              color: online ? Colors.green : scheme.onSurfaceVariant,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (t == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (t != null)
                      _InfoGrid(
                        items: [
                          _InfoItemData('Latitude', t.lat?.toStringAsFixed(6) ?? '-'),
                          _InfoItemData('Longitude', t.lon?.toStringAsFixed(6) ?? '-'),
                          _InfoItemData('Altitude', t.alt?.toString() ?? '-'),
                          _InfoItemData('Speed', '${t.raw['spd'] ?? '-'}'),
                          _InfoItemData('Satellites', '${t.raw['sat'] ?? '-'}'),
                          _InfoItemData('GSN', '${t.raw['gsn'] ?? '-'}'),
                          _InfoItemData('GS', '${t.raw['gs'] ?? '-'}'),
                          _InfoItemData('Wet', (t.wet == true) ? 'TRUE' : 'FALSE'),
                        ],
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

@immutable
class _InfoItemData {
  const _InfoItemData(this.label, this.value);
  final String label;
  final String value;
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.items});
  final List<_InfoItemData> items;

  @override
  Widget build(BuildContext context) {
    
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final tileW = (constraints.maxWidth - gap) / 2;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final it in items)
              SizedBox(
                width: tileW,
                child: _InfoTile(label: it.label, value: it.value),
              ),
          ],
        );
      },
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

bool _isOnline(DateTime? lastSeen) {
  if (lastSeen == null) return false;
  final nowUtc = DateTime.now().toUtc();
  return lastSeen.toUtc().isAfter(nowUtc.subtract(const Duration(minutes: 5)));
}

class _OnlineWave extends StatefulWidget {
  const _OnlineWave({required this.color});

  final Color color;

  @override
  State<_OnlineWave> createState() => _OnlineWaveState();
}

class _OnlineWaveState extends State<_OnlineWave> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        
        final scale = 0.7 + t * 1.9;
        final opacity = (1.0 - t).clamp(0.0, 1.0).toDouble();

        return Transform.scale(
          scale: scale,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.color.withAlpha(((opacity * 0.55) * 255).round().clamp(0, 255)),
                width: 4,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MapOverlayMessage extends StatelessWidget {
  const _MapOverlayMessage({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(message),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

