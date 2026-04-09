import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_env.dart';

/// Noms affichés (app, province) chargés depuis `app_settings`.
class AppBrandingController extends ChangeNotifier {
  AppBrandingController();

  static const String _defaultApp = 'Gestia';
  static const String _defaultProvince = 'Province du Haut-Katanga';

  String _appName = _defaultApp;
  String _provinceName = _defaultProvince;

  String get appName => _appName;
  String get provinceName => _provinceName;

  Future<void> load() async {
    if (!SupabaseEnv.isConfigured) return;
    try {
      final row = await Supabase.instance.client
          .from('app_settings')
          .select('app_name, province_name')
          .eq('id', 1)
          .maybeSingle();
      if (row == null) return;
      final m = Map<String, dynamic>.from(row as Map);
      final a = m['app_name']?.toString();
      final p = m['province_name']?.toString();
      if (a != null && a.isNotEmpty) _appName = a;
      if (p != null && p.isNotEmpty) _provinceName = p;
      notifyListeners();
    } catch (_) {
      // Garde les défauts
    }
  }

  Future<void> saveLabels({
    required String appName,
    required String provinceName,
  }) async {
    if (!SupabaseEnv.isConfigured) return;
    await Supabase.instance.client.from('app_settings').upsert({
      'id': 1,
      'app_name': appName.trim(),
      'province_name': provinceName.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    _appName = appName.trim();
    _provinceName = provinceName.trim();
    notifyListeners();
  }
}
