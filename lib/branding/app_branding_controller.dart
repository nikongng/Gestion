import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_env.dart';

/// Noms affichés (app, province) chargés depuis `app_settings`.
class AppBrandingController extends ChangeNotifier {
  AppBrandingController();

  static const String fixedAppName = 'GESTIA';
  static const String _defaultProvince = 'Province du Haut-Katanga';
  static const double defaultCdfRate = 2300;

  String _provinceName = _defaultProvince;
  double _cdfRate = defaultCdfRate;

  String get appName => fixedAppName;
  String get provinceName => _provinceName;
  double get cdfRate => _cdfRate;

  Future<void> load() async {
    if (!SupabaseEnv.isConfigured) return;
    try {
      final row = await Supabase.instance.client
          .from('app_settings')
          .select('province_name,cdf_rate')
          .eq('id', 1)
          .maybeSingle();
      if (row == null) return;
      final m = Map<String, dynamic>.from(row as Map);
      final p = m['province_name']?.toString();
      if (p != null && p.isNotEmpty) _provinceName = p;
      final rate = (m['cdf_rate'] as num?)?.toDouble();
      if (rate != null && rate > 0) _cdfRate = rate;
      notifyListeners();
    } catch (_) {
      // Garde les défauts
    }
  }

  Future<void> saveLabels({
    required String provinceName,
    double? cdfRate,
  }) async {
    if (!SupabaseEnv.isConfigured) return;
    final normalizedProvinceName = provinceName.trim();
    final normalizedCdfRate = cdfRate != null && cdfRate > 0
        ? cdfRate
        : _cdfRate;
    await Supabase.instance.client.from('app_settings').upsert({
      'id': 1,
      'app_name': fixedAppName,
      'province_name': normalizedProvinceName,
      'cdf_rate': normalizedCdfRate,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    _provinceName = normalizedProvinceName;
    _cdfRate = normalizedCdfRate;
    notifyListeners();
  }
}
