import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_env.dart';

/// Noms affichés (app, province) chargés depuis `app_settings`.
class AppBrandingController extends ChangeNotifier {
  AppBrandingController();

  static const String fixedAppName = 'GESTIA';
  static const String _defaultProvince = 'Province du Haut-Katanga';

  String _provinceName = _defaultProvince;

  String get appName => fixedAppName;
  String get provinceName => _provinceName;

  Future<void> load() async {
    if (!SupabaseEnv.isConfigured) return;
    try {
      final row = await Supabase.instance.client
          .from('app_settings')
          .select('province_name')
          .eq('id', 1)
          .maybeSingle();
      if (row == null) return;
      final m = Map<String, dynamic>.from(row as Map);
      final p = m['province_name']?.toString();
      if (p != null && p.isNotEmpty) _provinceName = p;
      notifyListeners();
    } catch (_) {
      // Garde les défauts
    }
  }

  Future<void> saveLabels({required String provinceName}) async {
    if (!SupabaseEnv.isConfigured) return;
    final normalizedProvinceName = provinceName.trim();
    await Supabase.instance.client.from('app_settings').upsert({
      'id': 1,
      'app_name': fixedAppName,
      'province_name': normalizedProvinceName,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    _provinceName = normalizedProvinceName;
    notifyListeners();
  }
}
