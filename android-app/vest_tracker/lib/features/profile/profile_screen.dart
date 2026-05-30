import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../config/app_config_scope.dart';
import '../../firebase/firebase_client.dart';
import '../../firebase/firebase_client_scope.dart';
import '../../logging/app_logger.dart';
import '../../notifications/notification_service.dart';
import '../auth/auth_credentials_store.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final _firebaseUrl = TextEditingController();
  late final _allowedUid = TextEditingController();
  late final _selectedDeviceId = TextEditingController();
  late final _pollInterval = TextEditingController();

  @override
  void dispose() {
    _firebaseUrl.dispose();
    _allowedUid.dispose();
    _selectedDeviceId.dispose();
    _pollInterval.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppConfigScope.of(context);
    final config = controller.value;
    final firebase = FirebaseClientScope.maybeOf(context);

    _firebaseUrl.value = _firebaseUrl.value.copyWith(text: config.firebaseDatabaseUrl);
    _allowedUid.value = _allowedUid.value.copyWith(text: config.allowedUid);
    _selectedDeviceId.value = _selectedDeviceId.value.copyWith(text: config.selectedDeviceId);
    _pollInterval.value = _pollInterval.value.copyWith(text: '${config.pollIntervalMinutes}');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const _ProfileIntro(),
          const SizedBox(height: 16),
          if (firebase != null) ...[
            _AccountSection(firebase: firebase),
            const SizedBox(height: 16),
          ],
          _NotificationsSection(
            onNotificationsEnabledChanged: (v) =>
                controller.update(config.copyWith(notificationsEnabled: v)),
          ),
          const SizedBox(height: 16),
          _AppSettingsSection(
            config: config,
            firebaseUrl: _firebaseUrl,
            allowedUid: _allowedUid,
            selectedDeviceId: _selectedDeviceId,
            pollInterval: _pollInterval,
            onSave: (next) => controller.update(next),
          ),
          const SizedBox(height: 16),
          const _LogsSection(),
        ],
      ),
    );
  }
}


class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    this.subtitle,
    this.icon,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: const Border(),
        collapsedShape: const Border(),
        leading: icon != null
            ? Icon(icon, size: 22, color: scheme.primary)
            : null,
        title: Text(title, style: theme.textTheme.titleMedium),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
        children: [child],
      ),
    );
  }
}

class _ProfileIntro extends StatelessWidget {
  const _ProfileIntro();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset('assets/icons/vest_tracker_icon.png', width: 48, height: 48),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Vest Tracker', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Tap a section below to open it. Account, notifications, app settings, and on-device logs are grouped separately.',
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppSettingsSection extends StatelessWidget {
  const _AppSettingsSection({
    required this.config,
    required this.firebaseUrl,
    required this.allowedUid,
    required this.selectedDeviceId,
    required this.pollInterval,
    required this.onSave,
  });

  final AppConfig config;
  final TextEditingController firebaseUrl;
  final TextEditingController allowedUid;
  final TextEditingController selectedDeviceId;
  final TextEditingController pollInterval;
  final Future<void> Function(AppConfig next) onSave;

  bool _isValidRtdbUrl(String value) {
    final v = value.trim();
    if (v.isEmpty) return true; 
    final uri = Uri.tryParse(v);
    return uri != null && uri.isAbsolute && (uri.scheme == 'https' || uri.scheme == 'http');
  }

  int _parseInterval(String value) {
    final v = int.tryParse(value.trim());
    if (v == null) return AppConfig.defaults.pollIntervalMinutes;
    return v.clamp(15, 240);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _SectionCard(
      title: 'App settings',
      subtitle: 'Firebase connection, which device to watch, and diagnostics.',
      icon: Icons.tune_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Firebase & access', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: firebaseUrl,
            decoration: InputDecoration(
              labelText: 'Firebase RTDB URL',
              hintText: 'https://<project>.asia-southeast1.firebasedatabase.app',
              errorText: _isValidRtdbUrl(firebaseUrl.text) ? null : 'Enter a valid URL',
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: allowedUid,
            decoration: const InputDecoration(
              labelText: 'Allowed UID',
              hintText: 'T23KmMSm7gY0Ui43aBavfbFWU842',
            ),
          ),
          const Divider(height: 28),
          Text('Device & background', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: selectedDeviceId,
            decoration: const InputDecoration(
              labelText: 'Selected device ID',
              hintText: 'Leave empty to watch all devices',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: pollInterval,
            decoration: const InputDecoration(
              labelText: 'Background poll interval (minutes)',
              helperText: 'Android may throttle background work; minimum 15 minutes.',
            ),
            keyboardType: TextInputType.number,
          ),
          const Divider(height: 28),
          Text('Diagnostics', style: theme.textTheme.titleSmall),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: config.logsUploadEnabled,
            title: const Text('Upload logs to Firebase'),
            onChanged: (v) => onSave(config.copyWith(logsUploadEnabled: v)),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              final url = firebaseUrl.text.trim();
              if (!_isValidRtdbUrl(url)) return;
              await onSave(
                config.copyWith(
                  firebaseDatabaseUrl: url,
                  allowedUid: allowedUid.text.trim(),
                  selectedDeviceId: selectedDeviceId.text.trim(),
                  pollIntervalMinutes: _parseInterval(pollInterval.text),
                ),
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
            },
            child: const Text('Save settings'),
          ),
        ],
      ),
    );
  }
}

class _AccountSection extends StatelessWidget {
  const _AccountSection({required this.firebase});

  final FirebaseClient firebase;

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You will be returned to the sign-in screen. Saved credentials '
          '(if "Remember me" is on) will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await firebase.signOut();
    } catch (err) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Sign-out failed: $err')));
    }
  }

  Future<void> _clearSaved(BuildContext context) async {
    await AuthCredentialsStore.clear();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved sign-in credentials cleared')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = firebase.currentUser;
    final uid = user?.uid;
    final email = user?.email;

    return _SectionCard(
      title: 'Account',
      subtitle: 'Who is signed in on this device.',
      icon: Icons.person_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.verified_user_outlined),
            title: Text(email == null || email.isEmpty ? 'Signed in' : email),
            subtitle: Text(uid == null ? 'No active session' : 'UID: $uid'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _clearSaved(context),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear saved'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _confirmSignOut(context),
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LogsSection extends StatelessWidget {
  const _LogsSection();

  @override
  Widget build(BuildContext context) {
    final logger = AppLogger.instance;

    return _SectionCard(
      title: 'Logs',
      subtitle: 'On-device log buffer for debugging (not your vest history).',
      icon: Icons.article_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    logger.info('Test log from Profile', context: {'screen': 'profile'});
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Test log added')));
                  },
                  child: const Text('Add test log'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await logger.clear();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Logs cleared')));
                  },
                  child: const Text('Clear logs'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<List<AppLogEntry>>(
            valueListenable: logger.logs,
            builder: (context, logs, _) {
              if (logs.isEmpty) {
                return const Text('No logs yet.');
              }
              final shown = logs.take(20).toList();
              return Column(
                children: [
                  for (final e in shown)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        e.level == LogLevel.error
                            ? Icons.error_outline
                            : e.level == LogLevel.warn
                                ? Icons.warning_amber_outlined
                                : Icons.info_outline,
                      ),
                      title: Text(e.message, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${e.ts.toLocal().toIso8601String()} • ${e.level.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (logs.length > shown.length)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Showing ${shown.length} of ${logs.length}'),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NotificationsSection extends StatefulWidget {
  const _NotificationsSection({required this.onNotificationsEnabledChanged});

  final ValueChanged<bool> onNotificationsEnabledChanged;

  @override
  State<_NotificationsSection> createState() => _NotificationsSectionState();
}

class _NotificationsSectionState extends State<_NotificationsSection>
    with WidgetsBindingObserver {
  bool? _granted;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (_checking) return;
    setState(() => _checking = true);
    final granted = await NotificationService.areAndroidNotificationsEnabled();
    if (!mounted) return;
    setState(() {
      _granted = granted;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = AppConfigScope.of(context).value;
    final cs = Theme.of(context).colorScheme;
    final selected = config.selectedDeviceId.trim();
    final watchingLabel = !config.notificationsEnabled
        ? 'Off — turn on Wet alerts below to watch devices.'
        : selected.isEmpty
            ? 'Watching all devices under vest/*'
            : 'Watching: $selected';

    final permissionLine = _granted == null
        ? const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.hourglass_empty),
            title: Text('Checking notification permission…'),
          )
        : _granted == true
            ? ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.check_circle, color: cs.primary),
                title: const Text('System notifications enabled'),
              )
            : ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.notifications_off, color: cs.error),
                title: const Text('System notifications are disabled'),
                subtitle: const Text(
                  'Wet alerts cannot reach you until you allow notifications '
                  'for Vest Tracker in Android settings.',
                ),
                trailing: FilledButton(
                  onPressed: () async {
                    await NotificationService
                        .requestAndroidPermissionIfNeeded();
                    await _refresh();
                  },
                  child: const Text('Allow'),
                ),
              );

    return _SectionCard(
      title: 'Notifications',
      subtitle: 'Wet alerts and Android permission for this phone.',
      icon: Icons.notifications_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: config.notificationsEnabled,
            title: const Text('Wet alerts'),
            subtitle: const Text(
              'Notify when a vest reports water while the app is open or from background checks.',
            ),
            onChanged: widget.onNotificationsEnabledChanged,
          ),
          const Divider(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.water_drop_outlined),
            title: const Text('Foreground monitor'),
            subtitle: Text(watchingLabel),
          ),
          permissionLine,
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () async {
                try {
                  await NotificationService.requestAndroidPermissionIfNeeded();
                  await NotificationService.showWetAlert(
                    deviceId: selected.isEmpty ? 'device_01' : selected,
                    origin: WetAlertOrigin.test,
                  );
                  await _refresh();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Test notification sent')),
                  );
                } catch (err) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Test failed: $err')),
                  );
                }
              },
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('Send test notification'),
            ),
          ),
        ],
      ),
    );
  }
}

