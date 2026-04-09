import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';

class AlertViewStore {
  AlertViewStore._();

  static final ValueNotifier<int> _changes = ValueNotifier<int>(0);

  static ValueListenable<int> get changes => _changes;

  static Future<DateTime?> loadLastViewedAt(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(profile.id));
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  static Future<void> markViewed(
    UserProfile profile, {
    DateTime? viewedAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final stamp = (viewedAt ?? DateTime.now()).toUtc().toIso8601String();
    await prefs.setString(_key(profile.id), stamp);
    _changes.value = _changes.value + 1;
  }

  static String _key(String userId) => 'alerts_last_viewed_$userId';
}
