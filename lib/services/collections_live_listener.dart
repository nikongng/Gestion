import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_env.dart';
import '../models/app_role.dart';
import '../models/user_profile.dart';

class CollectionsLiveListener {
  CollectionsLiveListener({
    required this.profile,
    required this.onCollectionInserted,
  });

  final UserProfile profile;
  final Future<void> Function() onCollectionInserted;

  RealtimeChannel? _channel;
  Timer? _debounce;
  bool _disposed = false;
  bool _refreshInFlight = false;
  bool _refreshQueued = false;

  void start() {
    if (_disposed || !SupabaseEnv.isConfigured) return;

    final client = Supabase.instance.client;
    final channelName =
        'collections-live-${profile.id}-${DateTime.now().millisecondsSinceEpoch}';

    _channel = client.channel(channelName)
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'collections',
        callback: _handleInsert,
      )
      ..subscribe();
  }

  void dispose() {
    _disposed = true;
    _debounce?.cancel();

    final channel = _channel;
    _channel = null;
    if (channel != null && SupabaseEnv.isConfigured) {
      unawaited(Supabase.instance.client.removeChannel(channel));
    }
  }

  void _handleInsert(PostgresChangePayload payload) {
    if (!_matchesProfileScope(payload.newRecord)) return;

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), _runRefresh);
  }

  bool _matchesProfileScope(Map<String, dynamic> row) {
    if (row.isEmpty) return false;

    if (profile.role == AppRole.contribuable) {
      return row['taxpayer_profile_id']?.toString() == profile.id;
    }

    if (profile.role.isGlobalSupervisor) {
      return true;
    }

    return row['commune_id']?.toString() == profile.communeId;
  }

  Future<void> _runRefresh() async {
    if (_disposed) return;

    if (_refreshInFlight) {
      _refreshQueued = true;
      return;
    }

    _refreshInFlight = true;
    try {
      await onCollectionInserted();
    } finally {
      _refreshInFlight = false;

      if (_refreshQueued && !_disposed) {
        _refreshQueued = false;
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 300), _runRefresh);
      }
    }
  }
}
