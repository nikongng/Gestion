import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_env.dart';
import '../models/app_alert.dart';
import '../models/app_role.dart';
import '../models/user_profile.dart';
import '../services/alert_view_store.dart';
import '../services/gestia_data_service.dart';

class NotificationBellButton extends StatefulWidget {
  const NotificationBellButton({
    super.key,
    required this.profile,
    required this.onOpenAlerts,
  });

  final UserProfile profile;
  final VoidCallback onOpenAlerts;

  @override
  State<NotificationBellButton> createState() => _NotificationBellButtonState();
}

class _NotificationBellButtonState extends State<NotificationBellButton> {
  static const _refreshInterval = Duration(seconds: 45);

  Timer? _timer;
  RealtimeChannel? _alertsChannel;
  bool _loading = false;
  List<AppAlert> _openAlerts = const [];
  DateTime? _lastViewedAt;

  bool get _canOpenAlerts => widget.profile.hasAlertsAccess;
  int get _badgeCount => _openAlerts.where(_isUnseen).length;
  int get _criticalCount => _openAlerts
      .where(
        (alert) => _isUnseen(alert) && alert.severity == AlertSeverity.critique,
      )
      .length;

  @override
  void initState() {
    super.initState();
    AlertViewStore.changes.addListener(_handleViewedChange);
    _scheduleRefresh();
    _startLiveUpdates();
    _loadAlerts();
  }

  @override
  void didUpdateWidget(covariant NotificationBellButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final profileChanged =
        oldWidget.profile.id != widget.profile.id ||
        oldWidget.profile.rolesLabel != widget.profile.rolesLabel ||
        oldWidget.profile.communeId != widget.profile.communeId;
    if (profileChanged) {
      _scheduleRefresh();
      _startLiveUpdates();
      _loadAlerts();
    }
  }

  @override
  void dispose() {
    AlertViewStore.changes.removeListener(_handleViewedChange);
    _timer?.cancel();
    _stopLiveUpdates();
    super.dispose();
  }

  bool _isUnseen(AppAlert alert) {
    final lastViewedAt = _lastViewedAt;
    if (lastViewedAt == null) return true;
    return alert.createdAt.isAfter(lastViewedAt);
  }

  void _handleViewedChange() {
    _syncLastViewedAt();
  }

  void _scheduleRefresh() {
    _timer?.cancel();
    if (!_canOpenAlerts) return;
    _timer = Timer.periodic(_refreshInterval, (_) => _loadAlerts());
  }

  void _startLiveUpdates() {
    _stopLiveUpdates();
    if (!_canOpenAlerts || !SupabaseEnv.isConfigured) return;

    final client = Supabase.instance.client;
    final channelName =
        'alerts-live-${widget.profile.id}-${DateTime.now().millisecondsSinceEpoch}';
    _alertsChannel = client.channel(channelName)
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'alerts',
        callback: _handleAlertChanged,
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'alerts',
        callback: _handleAlertChanged,
      )
      ..subscribe();
  }

  void _stopLiveUpdates() {
    final channel = _alertsChannel;
    _alertsChannel = null;
    if (channel != null && SupabaseEnv.isConfigured) {
      unawaited(Supabase.instance.client.removeChannel(channel));
    }
  }

  void _handleAlertChanged(PostgresChangePayload payload) {
    if (!_matchesAlertRecord(payload.newRecord)) return;
    _loadAlerts();
  }

  bool _matchesAlertRecord(Map<String, dynamic> row) {
    if (row.isEmpty) return false;
    if (widget.profile.isGlobalSupervisor) return true;

    final targetUserId = row['target_user_id']?.toString();
    if (targetUserId != null && targetUserId == widget.profile.id) {
      return true;
    }

    final targetRole = AppRole.fromDb(row['target_role']?.toString());

    if (targetRole == null) {
      return widget.profile.isGlobalSupervisor;
    }

    return widget.profile.hasRole(targetRole);
  }

  Future<void> _loadAlerts() async {
    if (!_canOpenAlerts || _loading) return;
    setState(() => _loading = true);
    try {
      final list = await GestiaDataService.fetchAlertsForProfile(
        widget.profile,
      );
      final lastViewedAt = await AlertViewStore.loadLastViewedAt(
        widget.profile,
      );
      if (!mounted) return;
      setState(() {
        _openAlerts = list.where((alert) => alert.isOpen).toList();
        _lastViewedAt = lastViewedAt;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _syncLastViewedAt() async {
    if (!_canOpenAlerts) return;
    final lastViewedAt = await AlertViewStore.loadLastViewedAt(widget.profile);
    if (!mounted) return;
    setState(() => _lastViewedAt = lastViewedAt);
  }

  void _handleMenuOpened() {
    _loadAlerts();
    AlertViewStore.markViewed(widget.profile);
  }

  void _handleSelection(_BellMenuAction action) {
    if (action == _BellMenuAction.openCenter) {
      AlertViewStore.markViewed(widget.profile);
      widget.onOpenAlerts();
      return;
    }
    _loadAlerts();
  }

  @override
  Widget build(BuildContext context) {
    if (!_canOpenAlerts) {
      return IconButton(
        tooltip: 'Notifications non disponibles',
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Aucune notification n’est disponible pour ce rôle.',
              ),
            ),
          );
        },
        icon: const Icon(Icons.notifications_none),
      );
    }

    return PopupMenuButton<_BellMenuAction>(
      tooltip: 'Notifications',
      onOpened: _handleMenuOpened,
      onSelected: _handleSelection,
      offset: const Offset(0, 12),
      itemBuilder: (context) => _buildMenu(context),
      child: _BellIcon(
        count: _badgeCount,
        highlight: _criticalCount > 0,
        loading: _loading,
      ),
    );
  }

  List<PopupMenuEntry<_BellMenuAction>> _buildMenu(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final preview = _openAlerts.take(5).toList();
    final summary = _openAlerts.isEmpty
        ? 'Aucune notification ouverte'
        : _badgeCount > 0
        ? '$_badgeCount nouvelles sur ${_openAlerts.length} ouvertes'
        : _criticalCount > 0
        ? '${_openAlerts.length} ouvertes, $_criticalCount critiques'
        : '${_openAlerts.length} notifications consultees';

    return [
      PopupMenuItem<_BellMenuAction>(
        enabled: false,
        height: 60,
        child: SizedBox(
          width: 320,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Notifications',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _loading ? 'Actualisation en cours...' : summary,
                style: textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      if (preview.isEmpty)
        const PopupMenuItem<_BellMenuAction>(
          enabled: false,
          height: 70,
          child: SizedBox(
            width: 320,
            child: Text('Aucune notification active pour le moment.'),
          ),
        )
      else
        ...preview.map(
          (alert) => PopupMenuItem<_BellMenuAction>(
            value: _BellMenuAction.openCenter,
            height: 88,
            child: SizedBox(width: 320, child: _AlertPreview(alert: alert)),
          ),
        ),
      const PopupMenuDivider(),
      const PopupMenuItem<_BellMenuAction>(
        value: _BellMenuAction.openCenter,
        child: SizedBox(
          width: 320,
          child: Text('Ouvrir le centre de notifications'),
        ),
      ),
      const PopupMenuItem<_BellMenuAction>(
        value: _BellMenuAction.refresh,
        child: SizedBox(
          width: 320,
          child: Text('Actualiser les notifications'),
        ),
      ),
    ];
  }
}

enum _BellMenuAction { openCenter, refresh }

class _BellIcon extends StatelessWidget {
  const _BellIcon({
    required this.count,
    required this.highlight,
    required this.loading,
  });

  final int count;
  final bool highlight;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = count > 99 ? '99+' : '$count';

    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: loading
                  ? SizedBox(
                      key: const ValueKey('loading'),
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: colorScheme.primary,
                      ),
                    )
                  : Icon(
                      Icons.notifications_none,
                      key: const ValueKey('bell'),
                      color: highlight ? colorScheme.error : null,
                    ),
            ),
          ),
          if (count > 0)
            Positioned(
              top: 2,
              right: -2,
              child: Container(
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: highlight ? colorScheme.error : colorScheme.primary,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: colorScheme.surface, width: 2),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onError,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AlertPreview extends StatelessWidget {
  const _AlertPreview({required this.alert});

  final AppAlert alert;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final color = switch (alert.severity) {
      AlertSeverity.critique => colorScheme.error,
      AlertSeverity.moyenne => const Color(0xFFE65100),
      AlertSeverity.faible => const Color(0xFFF9A825),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                alert.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                alert.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Text(
                _metadata(alert),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _metadata(AppAlert alert) {
    final pieces = <String>[alert.severity.labelFr];
    if (alert.communeName != null && alert.communeName!.isNotEmpty) {
      pieces.add(alert.communeName!);
    }
    pieces.add(_formatDate(alert.createdAt));
    return pieces.join(' | ');
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
  }
}
