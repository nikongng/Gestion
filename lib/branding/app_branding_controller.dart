import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_env.dart';

/// Noms et preferences affiches depuis `app_settings`.
class AppBrandingController extends ChangeNotifier {
  AppBrandingController();

  static const String fixedAppName = 'GESTIA';
  static const String _defaultProvince = 'Province du Haut-Katanga';
  static const double defaultCdfRate = 2300;

  String _provinceName = _defaultProvince;
  double _cdfRate = defaultCdfRate;
  String _systemDescription = 'Plateforme de gestion fiscale et administrative';
  String _systemVersion = 'v1.0.0';
  String _installationDate = '01/01/2025';
  String _timezoneLabel = '(GMT+1) Afrique/Kinshasa';
  String _defaultLanguage = 'Francais';
  String _dateFormat = 'DD/MM/YYYY';
  String _timeFormat = '24 heures (14:30)';
  String _currencyLabel = 'Franc Congolais (FC)';
  String _decimalSeparator = ',';
  String _thousandSeparator = '.';
  String _fiscalYear = '2025';
  String _fiscalStartDate = '01/01/2025';
  String _fiscalEndDate = '31/12/2025';
  double _defaultInterestRate = 10;
  double _latePenaltyRate = 2;
  bool _emailNotificationsEnabled = true;
  bool _userRegistrationEnabled = true;
  bool _twoFactorValidationEnabled = false;
  bool _autoSessionEnabled = true;
  bool _maintenanceModeEnabled = false;

  String get appName => fixedAppName;
  String get provinceName => _provinceName;
  double get cdfRate => _cdfRate;
  String get systemDescription => _systemDescription;
  String get systemVersion => _systemVersion;
  String get installationDate => _installationDate;
  String get timezoneLabel => _timezoneLabel;
  String get defaultLanguage => _defaultLanguage;
  String get dateFormat => _dateFormat;
  String get timeFormat => _timeFormat;
  String get currencyLabel => _currencyLabel;
  String get decimalSeparator => _decimalSeparator;
  String get thousandSeparator => _thousandSeparator;
  String get fiscalYear => _fiscalYear;
  String get fiscalStartDate => _fiscalStartDate;
  String get fiscalEndDate => _fiscalEndDate;
  double get defaultInterestRate => _defaultInterestRate;
  double get latePenaltyRate => _latePenaltyRate;
  bool get emailNotificationsEnabled => _emailNotificationsEnabled;
  bool get userRegistrationEnabled => _userRegistrationEnabled;
  bool get twoFactorValidationEnabled => _twoFactorValidationEnabled;
  bool get autoSessionEnabled => _autoSessionEnabled;
  bool get maintenanceModeEnabled => _maintenanceModeEnabled;

  Future<void> load() async {
    if (!SupabaseEnv.isConfigured) return;
    try {
      final row = await Supabase.instance.client
          .from('app_settings')
          .select()
          .eq('id', 1)
          .maybeSingle();
      if (row == null) return;
      final m = Map<String, dynamic>.from(row as Map);
      final p = m['province_name']?.toString();
      if (p != null && p.isNotEmpty) _provinceName = p;
      final rate = (m['cdf_rate'] as num?)?.toDouble();
      if (rate != null && rate > 0) _cdfRate = rate;
      _systemDescription = _textOr(m['system_description'], _systemDescription);
      _systemVersion = _textOr(m['system_version'], _systemVersion);
      _installationDate = _textOr(m['installation_date'], _installationDate);
      _timezoneLabel = _textOr(m['timezone_label'], _timezoneLabel);
      _defaultLanguage = _textOr(m['default_language'], _defaultLanguage);
      _dateFormat = _textOr(m['date_format'], _dateFormat);
      _timeFormat = _textOr(m['time_format'], _timeFormat);
      _currencyLabel = _textOr(m['currency_label'], _currencyLabel);
      _decimalSeparator = _textOr(m['decimal_separator'], _decimalSeparator);
      _thousandSeparator = _textOr(m['thousand_separator'], _thousandSeparator);
      _fiscalYear = _textOr(m['fiscal_year'], _fiscalYear);
      _fiscalStartDate = _textOr(m['fiscal_start_date'], _fiscalStartDate);
      _fiscalEndDate = _textOr(m['fiscal_end_date'], _fiscalEndDate);
      _defaultInterestRate =
          (m['default_interest_rate'] as num?)?.toDouble() ??
          _defaultInterestRate;
      _latePenaltyRate =
          (m['late_penalty_rate'] as num?)?.toDouble() ?? _latePenaltyRate;
      _emailNotificationsEnabled =
          m['email_notifications_enabled'] as bool? ??
          _emailNotificationsEnabled;
      _userRegistrationEnabled =
          m['user_registration_enabled'] as bool? ?? _userRegistrationEnabled;
      _twoFactorValidationEnabled =
          m['two_factor_validation_enabled'] as bool? ??
          _twoFactorValidationEnabled;
      _autoSessionEnabled =
          m['auto_session_enabled'] as bool? ?? _autoSessionEnabled;
      _maintenanceModeEnabled =
          m['maintenance_mode_enabled'] as bool? ?? _maintenanceModeEnabled;
      notifyListeners();
    } catch (_) {
      // Garder les valeurs par defaut si Supabase n'est pas encore pret.
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

  Future<void> saveParameters({
    required String provinceName,
    required double cdfRate,
    required String systemDescription,
    required String systemVersion,
    required String installationDate,
    required String timezoneLabel,
    required String defaultLanguage,
    required String dateFormat,
    required String timeFormat,
    required String currencyLabel,
    required String decimalSeparator,
    required String thousandSeparator,
    required String fiscalYear,
    required String fiscalStartDate,
    required String fiscalEndDate,
    required double defaultInterestRate,
    required double latePenaltyRate,
    required bool emailNotificationsEnabled,
    required bool userRegistrationEnabled,
    required bool twoFactorValidationEnabled,
    required bool autoSessionEnabled,
    required bool maintenanceModeEnabled,
  }) async {
    if (!SupabaseEnv.isConfigured) return;

    final normalizedProvinceName = provinceName.trim();
    final normalizedCdfRate = cdfRate > 0 ? cdfRate : _cdfRate;
    await Supabase.instance.client.from('app_settings').upsert({
      'id': 1,
      'app_name': fixedAppName,
      'province_name': normalizedProvinceName,
      'cdf_rate': normalizedCdfRate,
      'system_description': systemDescription.trim(),
      'system_version': systemVersion.trim(),
      'installation_date': installationDate.trim(),
      'timezone_label': timezoneLabel.trim(),
      'default_language': defaultLanguage.trim(),
      'date_format': dateFormat.trim(),
      'time_format': timeFormat.trim(),
      'currency_label': currencyLabel.trim(),
      'decimal_separator': decimalSeparator.trim(),
      'thousand_separator': thousandSeparator.trim(),
      'fiscal_year': fiscalYear.trim(),
      'fiscal_start_date': fiscalStartDate.trim(),
      'fiscal_end_date': fiscalEndDate.trim(),
      'default_interest_rate': defaultInterestRate,
      'late_penalty_rate': latePenaltyRate,
      'email_notifications_enabled': emailNotificationsEnabled,
      'user_registration_enabled': userRegistrationEnabled,
      'two_factor_validation_enabled': twoFactorValidationEnabled,
      'auto_session_enabled': autoSessionEnabled,
      'maintenance_mode_enabled': maintenanceModeEnabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });

    _provinceName = normalizedProvinceName;
    _cdfRate = normalizedCdfRate;
    _systemDescription = systemDescription.trim();
    _systemVersion = systemVersion.trim();
    _installationDate = installationDate.trim();
    _timezoneLabel = timezoneLabel.trim();
    _defaultLanguage = defaultLanguage.trim();
    _dateFormat = dateFormat.trim();
    _timeFormat = timeFormat.trim();
    _currencyLabel = currencyLabel.trim();
    _decimalSeparator = decimalSeparator.trim();
    _thousandSeparator = thousandSeparator.trim();
    _fiscalYear = fiscalYear.trim();
    _fiscalStartDate = fiscalStartDate.trim();
    _fiscalEndDate = fiscalEndDate.trim();
    _defaultInterestRate = defaultInterestRate;
    _latePenaltyRate = latePenaltyRate;
    _emailNotificationsEnabled = emailNotificationsEnabled;
    _userRegistrationEnabled = userRegistrationEnabled;
    _twoFactorValidationEnabled = twoFactorValidationEnabled;
    _autoSessionEnabled = autoSessionEnabled;
    _maintenanceModeEnabled = maintenanceModeEnabled;
    notifyListeners();
  }

  String _textOr(Object? value, String fallback) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? fallback : text;
  }
}
