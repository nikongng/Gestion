import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:qr/qr.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../branding/app_branding_controller.dart';
import '../branding/branding_scope.dart';
import '../models/app_role.dart';
import '../models/app_section.dart';
import '../models/user_profile.dart';
import '../services/gestia_data_service.dart';
import '../theme/app_colors.dart';
import '../theme/theme_scope.dart';
import '../utils/error_messages.dart';
import '../utils/pick_profile_image.dart';
import '../widgets/profile_avatar.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.profile,
    this.onSectionSelected,
    this.onProfileChanged,
  });

  final UserProfile profile;
  final ValueChanged<AppSection>? onSectionSelected;
  final VoidCallback? onProfileChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

enum _SettingsSection {
  general,
  organisation,
  users,
  appearance,
  security,
  backup,
}

const _allSettingsMenuItems = <_SettingsMenuSpec>[
  _SettingsMenuSpec(
    _SettingsSection.general,
    Icons.settings_outlined,
    'Général',
    'Informations générales du système',
  ),
  _SettingsMenuSpec(
    _SettingsSection.organisation,
    Icons.apartment_rounded,
    'Organisation',
    'Informations sur l’organisation',
  ),
  _SettingsMenuSpec(
    _SettingsSection.users,
    Icons.groups_2_outlined,
    'Utilisateurs & Rôles',
    'Gestion des rôles et permissions',
  ),
  _SettingsMenuSpec(
    _SettingsSection.appearance,
    Icons.palette_outlined,
    'Thèmes & Apparence',
    'Personnalisation de l’interface',
  ),
  _SettingsMenuSpec(
    _SettingsSection.security,
    Icons.verified_user_outlined,
    'Sécurité',
    'Mot de passe et accès',
  ),
  _SettingsMenuSpec(
    _SettingsSection.backup,
    Icons.cloud_sync_outlined,
    'Sauvegarde',
    'Export des données',
  ),
];

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _appCtrl;
  late final TextEditingController _provinceCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _versionCtrl;
  late final TextEditingController _installDateCtrl;
  late final TextEditingController _timezoneCtrl;
  late final TextEditingController _cdfRateCtrl;
  late final TextEditingController _decimalCtrl;
  late final TextEditingController _thousandCtrl;
  late final TextEditingController _fiscalYearCtrl;
  late final TextEditingController _fiscalStartCtrl;
  late final TextEditingController _fiscalEndCtrl;
  late final TextEditingController _interestRateCtrl;
  late final TextEditingController _latePenaltyCtrl;
  late final TextEditingController _profileNameCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _passwordConfirmCtrl;

  _SettingsSection _selected = _SettingsSection.general;
  bool _saving = false;
  bool _savingProfile = false;
  bool _savingPassword = false;
  bool _uploadingAvatar = false;
  bool _uploadingLogo = false;
  bool _exportingBackup = false;
  bool _loadingMfa = false;
  bool _mfaLoaded = false;
  bool _obscurePassword = true;
  bool _obscurePasswordConfirm = true;
  bool _brandingReady = false;
  DateTime? _lastBackupExportedAt;
  List<Factor> _mfaFactors = const [];
  String? _mfaError;

  String _language = 'Français';
  String _dateFormat = 'DD/MM/YYYY';
  String _timeFormat = '24 heures (14:30)';
  String _currency = 'Franc Congolais (FC)';
  bool _emailNotifications = true;
  bool _allowRegistration = true;
  bool _twoFactor = false;
  bool _autoSession = true;
  bool _maintenanceMode = false;

  static const _green = Color(0xFF08A63D);
  static const _blue = Color(0xFF1677FF);
  static const _orange = Color(0xFFFF8A1F);
  static const _purple = Color(0xFF8C2CF2);

  bool get _canManageGlobalSettings => widget.profile.canManageApp;
  bool get _canEditDisplayName => widget.profile.canEditOwnProfile;
  bool get _canEditAvatar => widget.profile.canChangeOwnAvatar;
  bool get _canChangePassword => widget.profile.canChangePassword;
  List<_SettingsMenuSpec> get _visibleSettingsMenuItems {
    if (_canManageGlobalSettings) return _allSettingsMenuItems;
    return _allSettingsMenuItems
        .where(
          (item) =>
              item.section == _SettingsSection.organisation ||
              item.section == _SettingsSection.security,
        )
        .toList(growable: false);
  }

  _SettingsSection get _effectiveSelectedSection {
    final visible = _visibleSettingsMenuItems.map((item) => item.section);
    if (visible.contains(_selected)) return _selected;
    return _canManageGlobalSettings
        ? _SettingsSection.general
        : _SettingsSection.organisation;
  }

  @override
  void initState() {
    super.initState();
    _appCtrl = TextEditingController(text: 'GESTIA');
    _provinceCtrl = TextEditingController();
    _descriptionCtrl = TextEditingController();
    _versionCtrl = TextEditingController();
    _installDateCtrl = TextEditingController();
    _timezoneCtrl = TextEditingController();
    _cdfRateCtrl = TextEditingController();
    _decimalCtrl = TextEditingController();
    _thousandCtrl = TextEditingController();
    _fiscalYearCtrl = TextEditingController();
    _fiscalStartCtrl = TextEditingController();
    _fiscalEndCtrl = TextEditingController();
    _interestRateCtrl = TextEditingController();
    _latePenaltyCtrl = TextEditingController();
    _profileNameCtrl = TextEditingController(text: widget.profile.fullName);
    _passwordCtrl = TextEditingController();
    _passwordConfirmCtrl = TextEditingController();
    if (!_canManageGlobalSettings) {
      _selected = _SettingsSection.organisation;
    }
  }

  @override
  void didUpdateWidget(SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.fullName != widget.profile.fullName) {
      _profileNameCtrl.text = widget.profile.fullName;
    }
    final visible = _visibleSettingsMenuItems.map((item) => item.section);
    if (!visible.contains(_selected)) {
      _selected = _effectiveSelectedSection;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_brandingReady) return;
    _brandingReady = true;
    _syncFromBranding(BrandingScope.of(context));
  }

  void _syncFromBranding(AppBrandingController branding) {
    _appCtrl.text = branding.appName;
    _provinceCtrl.text = branding.provinceName;
    _descriptionCtrl.text = branding.systemDescription;
    _versionCtrl.text = branding.systemVersion;
    _installDateCtrl.text = branding.installationDate;
    _timezoneCtrl.text = branding.timezoneLabel;
    _cdfRateCtrl.text = branding.cdfRate.toStringAsFixed(0);
    _decimalCtrl.text = branding.decimalSeparator;
    _thousandCtrl.text = branding.thousandSeparator;
    _fiscalYearCtrl.text = branding.fiscalYear;
    _fiscalStartCtrl.text = branding.fiscalStartDate;
    _fiscalEndCtrl.text = branding.fiscalEndDate;
    _interestRateCtrl.text = branding.defaultInterestRate.toStringAsFixed(0);
    _latePenaltyCtrl.text = branding.latePenaltyRate.toStringAsFixed(0);
    _language = _pickSupported(branding.defaultLanguage, _languageOptions);
    _dateFormat = _pickSupported(branding.dateFormat, _dateFormatOptions);
    _timeFormat = _pickSupported(branding.timeFormat, _timeFormatOptions);
    _currency = _pickSupported(branding.currencyLabel, _currencyOptions);
    _emailNotifications = branding.emailNotificationsEnabled;
    _allowRegistration = branding.userRegistrationEnabled;
    _twoFactor = branding.twoFactorValidationEnabled;
    _autoSession = branding.autoSessionEnabled;
    _maintenanceMode = branding.maintenanceModeEnabled;
  }

  @override
  void dispose() {
    _appCtrl.dispose();
    _provinceCtrl.dispose();
    _descriptionCtrl.dispose();
    _versionCtrl.dispose();
    _installDateCtrl.dispose();
    _timezoneCtrl.dispose();
    _cdfRateCtrl.dispose();
    _decimalCtrl.dispose();
    _thousandCtrl.dispose();
    _fiscalYearCtrl.dispose();
    _fiscalStartCtrl.dispose();
    _fiscalEndCtrl.dispose();
    _interestRateCtrl.dispose();
    _latePenaltyCtrl.dispose();
    _profileNameCtrl.dispose();
    _passwordCtrl.dispose();
    _passwordConfirmCtrl.dispose();
    super.dispose();
  }

  List<String> get _languageOptions => const [
    'Français',
    'Lingala',
    'Swahili',
    'Anglais',
  ];

  List<String> get _dateFormatOptions => const [
    'DD/MM/YYYY',
    'YYYY-MM-DD',
    'DD-MM-YYYY',
  ];

  List<String> get _timeFormatOptions => const [
    '24 heures (14:30)',
    '12 heures (2:30 PM)',
  ];

  List<String> get _currencyOptions => const [
    'Franc Congolais (FC)',
    'Dollar Américain (USD)',
  ];

  String _pickSupported(String value, List<String> options) {
    return options.contains(value) ? value : options.first;
  }

  void _selectSettingsSection(_SettingsSection section) {
    setState(() => _selected = section);
    if (section == _SettingsSection.security && !_mfaLoaded && !_loadingMfa) {
      Future.microtask(_loadMfaFactors);
    }
  }

  String _extensionFromXFile(XFile x) {
    final name = x.name.toLowerCase();
    if (name.contains('.')) return name.split('.').last;
    final mime = x.mimeType?.toLowerCase();
    if (mime == 'image/jpeg' || mime == 'image/jpg') return 'jpg';
    if (mime == 'image/png') return 'png';
    if (mime == 'image/webp') return 'webp';
    return 'jpg';
  }

  double? _parsePositiveNumber(String raw) {
    final value = double.tryParse(raw.trim().replaceAll(',', '.'));
    if (value == null || value <= 0) return null;
    return value;
  }

  Future<void> _saveAll() async {
    if (!_canManageGlobalSettings) return;

    final cdfRate = _parsePositiveNumber(_cdfRateCtrl.text);
    final interestRate = _parsePositiveNumber(_interestRateCtrl.text);
    final latePenalty = _parsePositiveNumber(_latePenaltyCtrl.text);
    if (cdfRate == null || interestRate == null || latePenalty == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vérifiez les montants et les taux.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final branding = BrandingScope.of(context);
      await branding.saveParameters(
        provinceName: _provinceCtrl.text.trim(),
        cdfRate: cdfRate,
        systemDescription: _descriptionCtrl.text.trim(),
        systemVersion: _versionCtrl.text.trim(),
        installationDate: _installDateCtrl.text.trim(),
        timezoneLabel: _timezoneCtrl.text.trim(),
        defaultLanguage: _language,
        dateFormat: _dateFormat,
        timeFormat: _timeFormat,
        currencyLabel: _currency,
        decimalSeparator: _decimalCtrl.text.trim(),
        thousandSeparator: _thousandCtrl.text.trim(),
        fiscalYear: _fiscalYearCtrl.text.trim(),
        fiscalStartDate: _fiscalStartCtrl.text.trim(),
        fiscalEndDate: _fiscalEndCtrl.text.trim(),
        defaultInterestRate: interestRate,
        latePenaltyRate: latePenalty,
        emailNotificationsEnabled: _emailNotifications,
        userRegistrationEnabled: _allowRegistration,
        twoFactorValidationEnabled: _twoFactor,
        autoSessionEnabled: _autoSession,
        maintenanceModeEnabled: _maintenanceMode,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Paramètres enregistrés.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveProfileName() async {
    if (!_canEditDisplayName) return;
    setState(() => _savingProfile = true);
    try {
      await GestiaDataService.updateMyDisplayName(
        userId: widget.profile.id,
        fullName: _profileNameCtrl.text.trim(),
      );
      if (!mounted) return;
      widget.onProfileChanged?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nom d’affichage enregistré.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _pickAvatar() async {
    if (!_canEditAvatar) return;
    final file = await pickProfileImageFile();
    if (file == null || !mounted) return;

    setState(() => _uploadingAvatar = true);
    try {
      final bytes = await file.readAsBytes();
      await GestiaDataService.uploadMyAvatarAndSaveProfile(
        userId: widget.profile.id,
        bytes: bytes,
        fileExtension: _extensionFromXFile(file),
      );
      if (!mounted) return;
      widget.onProfileChanged?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo de profil mise à jour.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _removeAvatar() async {
    if (!_canEditAvatar) return;
    setState(() => _uploadingAvatar = true);
    try {
      await GestiaDataService.clearMyAvatar(userId: widget.profile.id);
      if (!mounted) return;
      widget.onProfileChanged?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo de profil supprimée.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _pickLogo() async {
    if (!_canManageGlobalSettings) return;
    final file = await pickProfileImageFile();
    if (file == null || !mounted) return;

    setState(() => _uploadingLogo = true);
    try {
      final branding = BrandingScope.of(context);
      final bytes = await file.readAsBytes();
      await branding.uploadLogo(
        bytes: bytes,
        fileExtension: _extensionFromXFile(file),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Logo mis à jour.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _exportBackup() async {
    if (!_canManageGlobalSettings || _exportingBackup) return;
    setState(() => _exportingBackup = true);
    try {
      final payload = await GestiaDataService.buildBackupSnapshot(
        profile: widget.profile,
      );
      final json = const JsonEncoder.withIndent('  ').convert(payload);
      final bytes = Uint8List.fromList(utf8.encode(json));
      final now = DateTime.now();
      final fileName =
          'gestia_backup_${_fileDateStamp(now)}_${_fileTimeStamp(now)}.json';
      final path = await FilePicker.saveFile(
        dialogTitle: 'Enregistrer la sauvegarde GESTIA',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: bytes,
      );
      if (!mounted) return;
      if (path != null) {
        setState(() => _lastBackupExportedAt = now);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Sauvegarde exportée : $path')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _exportingBackup = false);
    }
  }

  String _fileDateStamp(DateTime value) {
    String two(int input) => input.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}';
  }

  String _fileTimeStamp(DateTime value) {
    String two(int input) => input.toString().padLeft(2, '0');
    return '${two(value.hour)}${two(value.minute)}';
  }

  String _dateTimeLabel(DateTime value) {
    String two(int input) => input.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year}, '
        '${two(value.hour)}:${two(value.minute)}';
  }

  Future<void> _loadMfaFactors() async {
    if (!mounted) return;
    setState(() {
      _loadingMfa = true;
      _mfaError = null;
    });
    try {
      if (Supabase.instance.client.auth.currentUser == null) {
        if (!mounted) return;
        setState(() {
          _mfaFactors = const [];
          _loadingMfa = false;
          _mfaLoaded = true;
          _mfaError = 'Session introuvable.';
        });
        return;
      }
      final response = await Supabase.instance.client.auth.mfa.listFactors();
      if (!mounted) return;
      setState(() {
        _mfaFactors = response.all;
        _loadingMfa = false;
        _mfaLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mfaError = userFacingErrorMessage(e);
        _loadingMfa = false;
        _mfaLoaded = true;
      });
    }
  }

  Future<void> _openMfaEnrollDialog() async {
    if (_loadingMfa) return;
    try {
      final enrollment = await Supabase.instance.client.auth.mfa.enroll(
        factorType: FactorType.totp,
        issuer: 'GESTIA',
        friendlyName: 'GESTIA',
      );
      if (!mounted) return;
      final verified = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _MfaEnrollDialog(enrollment: enrollment),
      );
      if (verified == true) {
        await _loadMfaFactors();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('DFA configurée pour ce compte.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(e))));
    }
  }

  Future<void> _removeMfaFactor(Factor factor) async {
    try {
      await Supabase.instance.client.auth.mfa.unenroll(factor.id);
      await _loadMfaFactors();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Facteur DFA supprimé.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(e))));
    }
  }

  Future<void> _savePassword() async {
    if (!_canChangePassword) return;

    final password = _passwordCtrl.text;
    final confirm = _passwordConfirmCtrl.text;
    if (password.isEmpty || confirm.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Renseignez le nouveau mot de passe et sa confirmation.',
          ),
        ),
      );
      return;
    }
    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Le mot de passe doit contenir au moins 6 caractères.'),
        ),
      );
      return;
    }
    if (password != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Les mots de passe ne correspondent pas.'),
        ),
      );
      return;
    }

    setState(() => _savingPassword = true);
    try {
      await GestiaDataService.updateMyPassword(newPassword: password);
      if (!mounted) return;
      _passwordCtrl.clear();
      _passwordConfirmCtrl.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Mot de passe mis à jour.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  Future<void> _copyTaxpayerId() async {
    final taxpayerId = widget.profile.taxpayerIdentifier;
    if (taxpayerId == null || taxpayerId.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: taxpayerId));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Identifiant copié.')));
  }

  String _scopeLabel() {
    if (_canManageGlobalSettings) return 'Mairie';
    if (widget.profile.isGlobalSupervisor) return 'Supervision';
    if (widget.profile.hasRole(AppRole.contribuable)) {
      return 'Compte individuel';
    }
    return 'Mairie';
  }

  Color _pageColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? const Color(0xFF080D18) : const Color(0xFFF7F9FC);
  }

  Color _cardColor(BuildContext context) {
    final theme = Theme.of(context);
    return theme.brightness == Brightness.dark
        ? const Color(0xFF111827)
        : Colors.white;
  }

  Color _softFill(BuildContext context) {
    final theme = Theme.of(context);
    return theme.brightness == Brightness.dark
        ? const Color(0xFF0D1525)
        : const Color(0xFFF8FAFD);
  }

  BorderSide _softBorder(BuildContext context) {
    final theme = Theme.of(context);
    return BorderSide(
      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
    );
  }

  List<BoxShadow> _softShadow(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.06),
        blurRadius: 24,
        offset: const Offset(0, 12),
      ),
    ];
  }

  InputDecoration _fieldDecoration(
    BuildContext context,
    String label, {
    Widget? suffixIcon,
    String? suffixText,
  }) {
    return InputDecoration(
      labelText: label,
      suffixIcon: suffixIcon,
      suffixText: suffixText,
      filled: true,
      fillColor: _softFill(context),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: _softBorder(context),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _green, width: 1.4),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: _softBorder(context),
      ),
    );
  }

  Widget _textField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    bool readOnly = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    Widget? suffixIcon,
    String? suffixText,
  }) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: _fieldDecoration(
        context,
        label,
        suffixIcon: suffixIcon,
        suffixText: suffixText,
      ),
    );
  }

  Widget _dropdownField({
    required BuildContext context,
    required String label,
    required String value,
    required List<String> values,
    required ValueChanged<String> onChanged,
    bool enabled = true,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: values.contains(value) ? value : values.first,
      items: [
        for (final item in values)
          DropdownMenuItem(value: item, child: Text(item)),
      ],
      onChanged: enabled
          ? (next) {
              if (next != null) onChanged(next);
            }
          : null,
      decoration: _fieldDecoration(context, label),
    );
  }

  Widget _switchRow({
    required BuildContext context,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: _green,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }

  Widget _settingsHeader(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final subtitle = _canManageGlobalSettings
            ? 'Gérez les paramètres de votre système.'
            : 'Gérez votre profil, votre photo et votre mot de passe.';
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paramètres',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );

        return title;
      },
    );
  }

  Widget _settingsSidebar(BuildContext context, bool compact) {
    final items = _visibleSettingsMenuItems;
    final selectedSection = _effectiveSelectedSection;

    final content = compact
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: SizedBox(
                      width: 238,
                      child: _SettingsNavTile(
                        spec: item,
                        selected: selectedSection == item.section,
                        onTap: () => _selectSettingsSection(item.section),
                      ),
                    ),
                  ),
              ],
            ),
          )
        : Column(
            children: [
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _SettingsNavTile(
                    spec: item,
                    selected: selectedSection == item.section,
                    onTap: () => _selectSettingsSection(item.section),
                  ),
                ),
              if (_canManageGlobalSettings) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton.filledTonal(
                    onPressed: () =>
                        _selectSettingsSection(_SettingsSection.general),
                    icon: const Icon(Icons.chevron_left_rounded),
                    tooltip: 'Retour aux paramètres généraux',
                  ),
                ),
              ],
            ],
          );

    return Container(
      width: compact ? double.infinity : 270,
      padding: EdgeInsets.all(compact ? 0 : 12),
      decoration: compact
          ? null
          : BoxDecoration(
              color: _cardColor(context),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _softBorder(context).color),
              boxShadow: _softShadow(context),
            ),
      child: content,
    );
  }

  Widget _sectionShell({
    required BuildContext context,
    required String title,
    required String subtitle,
    Widget? action,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final header = LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 680;
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
        if (action == null) return text;
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [text, const SizedBox(height: 14), action],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: text),
            const SizedBox(width: 16),
            action,
          ],
        );
      },
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _softBorder(context).color),
        boxShadow: _softShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [header, const SizedBox(height: 22), ...children],
      ),
    );
  }

  Widget _cardGrid(BuildContext context, List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 850 ? 2 : 1;
        final spacing = 14.0;
        final width = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - spacing) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }

  Widget _twoFieldRow(BuildContext context, List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                children[i],
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }

  Widget _buildGeneralSection(BuildContext context) {
    final readOnly = !_canManageGlobalSettings;
    return _sectionShell(
      context: context,
      title: 'Paramètres généraux',
      subtitle:
          'Configurez les informations générales et les préférences du système.',
      action: FilledButton.icon(
        onPressed: _canManageGlobalSettings && !_saving ? _saveAll : null,
        style: FilledButton.styleFrom(
          backgroundColor: _green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.save_outlined),
        label: Text(
          _saving ? 'Enregistrement...' : 'Enregistrer les modifications',
        ),
      ),
      children: [
        _cardGrid(context, [
          _SettingsCard(
            icon: Icons.info_outline_rounded,
            title: 'Informations du système',
            color: _green,
            child: Column(
              children: [
                _textField(
                  context,
                  controller: _appCtrl,
                  label: 'Nom du système',
                  readOnly: true,
                ),
                const SizedBox(height: 12),
                _textField(
                  context,
                  controller: _provinceCtrl,
                  label: 'Organisation / service',
                  readOnly: readOnly,
                ),
                const SizedBox(height: 12),
                _textField(
                  context,
                  controller: _descriptionCtrl,
                  label: 'Description',
                  readOnly: readOnly,
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                _twoFieldRow(context, [
                  _textField(
                    context,
                    controller: _versionCtrl,
                    label: 'Version',
                    readOnly: readOnly,
                  ),
                  _textField(
                    context,
                    controller: _installDateCtrl,
                    label: 'Date d’installation',
                    readOnly: readOnly,
                    suffixIcon: const Icon(Icons.calendar_today_outlined),
                  ),
                ]),
                const SizedBox(height: 12),
                _textField(
                  context,
                  controller: _timezoneCtrl,
                  label: 'Fuseau horaire',
                  readOnly: readOnly,
                  suffixIcon: const Icon(Icons.expand_more_rounded),
                ),
              ],
            ),
          ),
          _SettingsCard(
            icon: Icons.public_rounded,
            title: 'Préférences régionales',
            color: _green,
            child: Column(
              children: [
                _twoFieldRow(context, [
                  _dropdownField(
                    context: context,
                    label: 'Langue par défaut',
                    value: _language,
                    values: _languageOptions,
                    enabled: !readOnly,
                    onChanged: (value) => setState(() => _language = value),
                  ),
                  _dropdownField(
                    context: context,
                    label: 'Format de date',
                    value: _dateFormat,
                    values: _dateFormatOptions,
                    enabled: !readOnly,
                    onChanged: (value) => setState(() => _dateFormat = value),
                  ),
                ]),
                const SizedBox(height: 12),
                _twoFieldRow(context, [
                  _dropdownField(
                    context: context,
                    label: 'Format de l’heure',
                    value: _timeFormat,
                    values: _timeFormatOptions,
                    enabled: !readOnly,
                    onChanged: (value) => setState(() => _timeFormat = value),
                  ),
                  _dropdownField(
                    context: context,
                    label: 'Devise',
                    value: _currency,
                    values: _currencyOptions,
                    enabled: !readOnly,
                    onChanged: (value) => setState(() => _currency = value),
                  ),
                ]),
                const SizedBox(height: 12),
                _twoFieldRow(context, [
                  _textField(
                    context,
                    controller: _decimalCtrl,
                    label: 'Séparateur décimal',
                    readOnly: readOnly,
                  ),
                  _textField(
                    context,
                    controller: _thousandCtrl,
                    label: 'Séparateur de milliers',
                    readOnly: readOnly,
                  ),
                ]),
              ],
            ),
          ),
          _SettingsCard(
            icon: Icons.tune_rounded,
            title: 'Options système',
            color: _green,
            child: Column(
              children: [
                _switchRow(
                  context: context,
                  title: 'Activer les notifications par email',
                  value: _emailNotifications,
                  enabled: !readOnly,
                  onChanged: (value) =>
                      setState(() => _emailNotifications = value),
                ),
                _switchRow(
                  context: context,
                  title: 'Autoriser l’inscription des utilisateurs',
                  value: _allowRegistration,
                  enabled: !readOnly,
                  onChanged: (value) =>
                      setState(() => _allowRegistration = value),
                ),
                _switchRow(
                  context: context,
                  title: 'Validation à deux facteurs (2FA)',
                  value: _twoFactor,
                  enabled: !readOnly,
                  onChanged: (value) => setState(() => _twoFactor = value),
                ),
                _switchRow(
                  context: context,
                  title: 'Session automatique',
                  subtitle: 'Déconnexion après 30 minutes d’inactivité',
                  value: _autoSession,
                  enabled: !readOnly,
                  onChanged: (value) => setState(() => _autoSession = value),
                ),
                _switchRow(
                  context: context,
                  title: 'Mode maintenance',
                  subtitle:
                      'Rendre le système indisponible pour les utilisateurs',
                  value: _maintenanceMode,
                  enabled: !readOnly,
                  onChanged: (value) =>
                      setState(() => _maintenanceMode = value),
                ),
              ],
            ),
          ),
          _SettingsCard(
            icon: Icons.request_quote_outlined,
            title: 'Paramètres fiscaux',
            color: _green,
            child: Column(
              children: [
                _twoFieldRow(context, [
                  _textField(
                    context,
                    controller: _fiscalYearCtrl,
                    label: 'Exercice fiscal courant',
                    readOnly: readOnly,
                    suffixIcon: const Icon(Icons.expand_more_rounded),
                  ),
                  _textField(
                    context,
                    controller: _fiscalStartCtrl,
                    label: 'Date de début de l’exercice',
                    readOnly: readOnly,
                    suffixIcon: const Icon(Icons.calendar_today_outlined),
                  ),
                ]),
                const SizedBox(height: 12),
                _twoFieldRow(context, [
                  _textField(
                    context,
                    controller: _fiscalEndCtrl,
                    label: 'Date de fin de l’exercice',
                    readOnly: readOnly,
                    suffixIcon: const Icon(Icons.calendar_today_outlined),
                  ),
                  _textField(
                    context,
                    controller: _interestRateCtrl,
                    label: 'Taux d’intérêt par défaut',
                    readOnly: readOnly,
                    keyboardType: TextInputType.number,
                    suffixText: '%',
                  ),
                ]),
                const SizedBox(height: 12),
                _textField(
                  context,
                  controller: _latePenaltyCtrl,
                  label: 'Pénalité de retard par défaut',
                  readOnly: readOnly,
                  keyboardType: TextInputType.number,
                  suffixText: '%',
                ),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 14),
        _identityPanel(context),
      ],
    );
  }

  Widget _identityPanel(BuildContext context) {
    final logoUrl = BrandingScope.of(context).logoUrl;
    return _SettingsCard(
      icon: Icons.verified_outlined,
      title: 'Identité visuelle',
      color: _green,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: SizedBox(
              height: 118,
              child: logoUrl == null || logoUrl.isEmpty
                  ? Image.asset(
                      'assets/logo/gestia.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.shield_outlined,
                        size: 54,
                        color: _green,
                      ),
                    )
                  : Image.network(
                      logoUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Image.asset(
                        'assets/logo/gestia.png',
                        fit: BoxFit.contain,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _canManageGlobalSettings && !_uploadingLogo
                  ? _pickLogo
                  : null,
              icon: _uploadingLogo
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_outlined),
              label: Text(_uploadingLogo ? 'Import...' : 'Changer le logo'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrganisationSection(BuildContext context) {
    final busy = _savingProfile || _uploadingAvatar;
    return _sectionShell(
      context: context,
      title: 'Organisation',
      subtitle: 'Identité de la mairie, profil connecté et rattachement.',
      children: [
        _cardGrid(context, [
          _SettingsCard(
            icon: Icons.account_circle_outlined,
            title: 'Mon profil',
            color: _blue,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ProfileAvatar(
                      fullName: widget.profile.fullName,
                      avatarUrl: widget.profile.avatarUrl,
                      radius: 42,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.profile.fullName,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.profile.rolesLabel,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _textField(
                  context,
                  controller: _profileNameCtrl,
                  label: 'Nom d’affichage',
                  readOnly: !_canEditDisplayName,
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: busy || !_canEditDisplayName
                          ? null
                          : _saveProfileName,
                      style: FilledButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: Colors.white,
                      ),
                      icon: _savingProfile
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(
                        _savingProfile ? 'Enregistrement...' : 'Enregistrer',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy || !_canEditAvatar ? null : _pickAvatar,
                      icon: _uploadingAvatar
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.photo_camera_outlined),
                      label: const Text('Changer la photo'),
                    ),
                    TextButton.icon(
                      onPressed:
                          busy ||
                              !_canEditAvatar ||
                              widget.profile.avatarUrl == null
                          ? null
                          : _removeAvatar,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Supprimer'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _SettingsCard(
            icon: Icons.badge_outlined,
            title: 'Informations du compte',
            color: _purple,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoLine(label: 'Rôle', value: widget.profile.rolesLabel),
                _InfoLine(label: 'Rattachement', value: _scopeLabel()),
                _InfoLine(label: 'Identifiant', value: widget.profile.id),
                if (widget.profile.taxpayerIdentifier != null &&
                    widget.profile.taxpayerIdentifier!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _orange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _orange.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            widget.profile.taxpayerIdentifier!,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        IconButton(
                          onPressed: _copyTaxpayerId,
                          icon: const Icon(Icons.copy_outlined),
                          tooltip: 'Copier',
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ]),
      ],
    );
  }

  Widget _buildUsersSection(BuildContext context) {
    return _sectionShell(
      context: context,
      title: 'Utilisateurs & Rôles',
      subtitle: 'Rôles et droits du compte connecté.',
      children: [
        _cardGrid(context, [
          _SettingsCard(
            icon: Icons.admin_panel_settings_outlined,
            title: 'Rôles du compte connecté',
            color: _green,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final role in widget.profile.roles)
                  Chip(
                    avatar: const Icon(Icons.verified_user_outlined, size: 18),
                    label: Text(role.shortLabel),
                    side: BorderSide(color: _green.withValues(alpha: 0.22)),
                    backgroundColor: _green.withValues(alpha: 0.08),
                  ),
              ],
            ),
          ),
          _SettingsCard(
            icon: Icons.verified_user_outlined,
            title: 'Droits du compte',
            color: _blue,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoLine(
                  label: 'Paramètres globaux',
                  value: _canManageGlobalSettings ? 'Autorisé' : 'Non autorisé',
                ),
                _InfoLine(
                  label: 'Modifier le profil',
                  value: _canEditDisplayName ? 'Autorisé' : 'Non autorisé',
                ),
                _InfoLine(
                  label: 'Modifier la photo',
                  value: _canEditAvatar ? 'Autorisé' : 'Non autorisé',
                ),
                _InfoLine(
                  label: 'Modifier le mot de passe',
                  value: _canChangePassword ? 'Autorisé' : 'Non autorisé',
                ),
              ],
            ),
          ),
          _SettingsCard(
            icon: Icons.hub_outlined,
            title: 'Liste des rôles',
            color: _purple,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final role in AppRole.values)
                  _RoleInfoRow(
                    label: role.shortLabel,
                    description: _roleDescription(role),
                  ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed:
                        _canManageGlobalSettings &&
                            widget.onSectionSelected != null
                        ? () => widget.onSectionSelected!(
                            AppSection.utilisateursAgents,
                          )
                        : null,
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Ajouter un rôle'),
                  ),
                ),
              ],
            ),
          ),
        ]),
      ],
    );
  }

  String _roleDescription(AppRole role) {
    return switch (role) {
      AppRole.adminProvincial => 'Administration globale',
      AppRole.ministreFinances => 'Consultation et supervision',
      AppRole.gouverneur => 'Consultation et supervision',
      AppRole.bourgmestre => 'Consultation mairie',
      AppRole.agent => 'Recouvrement',
      AppRole.taxateur => 'Taxation',
      AppRole.ordonnateur => 'Ordonnancement',
      AppRole.apureur => 'Apurement',
      AppRole.contribuable => 'Paiement contribuable',
    };
  }

  Widget _buildAppearanceSection(BuildContext context) {
    final themeController = ThemeScope.of(context);
    return _sectionShell(
      context: context,
      title: 'Thèmes & Apparence',
      subtitle: 'Choisissez le mode d’affichage et les repères visuels.',
      children: [
        _cardGrid(context, [
          _SettingsCard(
            icon: Icons.dark_mode_outlined,
            title: 'Mode d’affichage',
            color: _blue,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _ThemeChoice(
                  icon: Icons.brightness_auto_rounded,
                  label: 'Système',
                  selected: themeController.mode == ThemeMode.system,
                  onTap: () {
                    themeController.setMode(ThemeMode.system);
                  },
                ),
                _ThemeChoice(
                  icon: Icons.light_mode_rounded,
                  label: 'Clair',
                  selected: themeController.mode == ThemeMode.light,
                  onTap: () {
                    themeController.setMode(ThemeMode.light);
                  },
                ),
                _ThemeChoice(
                  icon: Icons.dark_mode_rounded,
                  label: 'Sombre',
                  selected: themeController.mode == ThemeMode.dark,
                  onTap: () {
                    themeController.setMode(ThemeMode.dark);
                  },
                ),
              ],
            ),
          ),
          _SettingsCard(
            icon: Icons.color_lens_outlined,
            title: 'Couleurs de l’interface',
            color: _purple,
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ColorSwatch(label: 'Validation', color: _green),
                _ColorSwatch(label: 'Information', color: _blue),
                _ColorSwatch(label: 'Action', color: _orange),
                _ColorSwatch(label: 'Analyse', color: _purple),
              ],
            ),
          ),
        ]),
      ],
    );
  }

  Widget _buildSecuritySection(BuildContext context) {
    final busy = _savingPassword;
    return _sectionShell(
      context: context,
      title: 'Sécurité',
      subtitle: 'Protégez le compte avec mot de passe et contrôles d’accès.',
      children: [
        _cardGrid(context, [
          _SettingsCard(
            icon: Icons.lock_reset_outlined,
            title: 'Mot de passe',
            color: _orange,
            child: Column(
              children: [
                TextField(
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  decoration: _fieldDecoration(
                    context,
                    'Nouveau mot de passe',
                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordConfirmCtrl,
                  obscureText: _obscurePasswordConfirm,
                  decoration: _fieldDecoration(
                    context,
                    'Confirmer le mot de passe',
                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(
                          () => _obscurePasswordConfirm =
                              !_obscurePasswordConfirm,
                        );
                      },
                      icon: Icon(
                        _obscurePasswordConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: busy || !_canChangePassword
                        ? null
                        : _savePassword,
                    style: FilledButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                    ),
                    icon: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.lock_reset_outlined),
                    label: Text(busy ? 'Mise à jour...' : 'Mettre à jour'),
                  ),
                ),
              ],
            ),
          ),
          _SettingsCard(
            icon: Icons.security_outlined,
            title: 'Contrôles système',
            color: _purple,
            child: Column(
              children: [
                _switchRow(
                  context: context,
                  title: 'Exiger la DFA',
                  value: _twoFactor,
                  enabled: _canManageGlobalSettings,
                  onChanged: (value) => setState(() => _twoFactor = value),
                  subtitle: 'Double facteur d’authentification global',
                ),
                _switchRow(
                  context: context,
                  title: 'Session automatique',
                  value: _autoSession,
                  enabled: _canManageGlobalSettings,
                  onChanged: (value) => setState(() => _autoSession = value),
                  subtitle: 'Déconnexion après 30 minutes d’inactivité',
                ),
                _switchRow(
                  context: context,
                  title: 'Mode maintenance',
                  value: _maintenanceMode,
                  enabled: _canManageGlobalSettings,
                  onChanged: (value) =>
                      setState(() => _maintenanceMode = value),
                  subtitle: 'Bloque l’accès aux comptes non administrateurs',
                ),
              ],
            ),
          ),
          _SettingsCard(
            icon: Icons.phonelink_lock_outlined,
            title: 'DFA du compte',
            color: _blue,
            child: _buildMfaCard(context),
          ),
        ]),
      ],
    );
  }

  Widget _buildMfaCard(BuildContext context) {
    final verified = _mfaFactors
        .where(
          (factor) =>
              factor.factorType == FactorType.totp &&
              factor.status == FactorStatus.verified,
        )
        .toList();
    if (_loadingMfa) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_mfaLoaded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'L’état DFA sera chargé à la demande.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loadMfaFactors,
            icon: const Icon(Icons.refresh_outlined),
            label: const Text('Charger la DFA'),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_mfaError != null)
          Text(
            _mfaError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          )
        else if (verified.isEmpty)
          Text(
            'Aucun facteur configuré pour ce compte.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final factor in verified)
            _MfaFactorTile(
              factor: factor,
              onDelete: () => _removeMfaFactor(factor),
            ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: _openMfaEnrollDialog,
              icon: const Icon(Icons.add_moderator_outlined),
              label: const Text('Configurer la DFA'),
            ),
            OutlinedButton.icon(
              onPressed: _loadMfaFactors,
              icon: const Icon(Icons.refresh_outlined),
              label: const Text('Actualiser'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBackupSection(BuildContext context) {
    return _sectionShell(
      context: context,
      title: 'Sauvegarde',
      subtitle: 'Exportez un fichier JSON des données accessibles.',
      children: [
        _SettingsCard(
          icon: Icons.cloud_download_outlined,
          title: 'Export de sauvegarde',
          color: _green,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoLine(
                label: 'Dernier export',
                value: _lastBackupExportedAt == null
                    ? 'Aucun export cette session'
                    : _dateTimeLabel(_lastBackupExportedAt!),
              ),
              _InfoLine(label: 'Format', value: 'JSON'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _canManageGlobalSettings && !_exportingBackup
                    ? _exportBackup
                    : null,
                icon: _exportingBackup
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined),
                label: Text(
                  _exportingBackup
                      ? 'Préparation...'
                      : 'Exporter la sauvegarde',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionBody(BuildContext context) {
    switch (_effectiveSelectedSection) {
      case _SettingsSection.general:
        return _buildGeneralSection(context);
      case _SettingsSection.organisation:
        return _buildOrganisationSection(context);
      case _SettingsSection.users:
        return _buildUsersSection(context);
      case _SettingsSection.appearance:
        return _buildAppearanceSection(context);
      case _SettingsSection.security:
        return _buildSecuritySection(context);
      case _SettingsSection.backup:
        return _buildBackupSection(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 980;
        return Container(
          width: double.infinity,
          height: double.infinity,
          color: _pageColor(context),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.all(compact ? 16 : 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _settingsHeader(context),
                    const SizedBox(height: 20),
                    if (compact) ...[
                      _settingsSidebar(context, true),
                      const SizedBox(height: 14),
                      _buildSectionBody(context),
                    ] else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _settingsSidebar(context, false),
                          const SizedBox(width: 18),
                          Expanded(child: _buildSectionBody(context)),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SettingsMenuSpec {
  const _SettingsMenuSpec(this.section, this.icon, this.title, this.subtitle);

  final _SettingsSection section;
  final IconData icon;
  final String title;
  final String subtitle;
}

class _SettingsNavTile extends StatelessWidget {
  const _SettingsNavTile({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final _SettingsMenuSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.brightness == Brightness.dark
        ? const Color(0xFF0D1525)
        : const Color(0xFFF7FBF8);
    return Material(
      color: selected ? surface : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 3,
                height: 42,
                decoration: BoxDecoration(
                  color: selected
                      ? _SettingsScreenState._green
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 9),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: selected
                      ? _SettingsScreenState._green.withValues(alpha: 0.12)
                      : theme.colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.55,
                        ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  spec.icon,
                  color: selected
                      ? _SettingsScreenState._green
                      : theme.colorScheme.onSurfaceVariant,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spec.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      spec.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.035),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.18 : 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleInfoRow extends StatelessWidget {
  const _RoleInfoRow({required this.label, required this.description});

  final String label;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(
            Icons.verified_user_outlined,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              description,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MfaFactorTile extends StatelessWidget {
  const _MfaFactorTile({required this.factor, required this.onDelete});

  final Factor factor;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final label = factor.friendlyName?.trim().isNotEmpty == true
        ? factor.friendlyName!.trim()
        : 'Application d’authentification';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Supprimer',
          ),
        ],
      ),
    );
  }
}

class _MfaEnrollDialog extends StatefulWidget {
  const _MfaEnrollDialog({required this.enrollment});

  final AuthMFAEnrollResponse enrollment;

  @override
  State<_MfaEnrollDialog> createState() => _MfaEnrollDialogState();
}

class _MfaEnrollDialogState extends State<_MfaEnrollDialog> {
  final _codeCtrl = TextEditingController();
  bool _verifying = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Saisissez le code de vérification.');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final challenge = await Supabase.instance.client.auth.mfa.challenge(
        factorId: widget.enrollment.id,
      );
      await Supabase.instance.client.auth.mfa.verify(
        factorId: widget.enrollment.id,
        challengeId: challenge.id,
        code: code,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = userFacingErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final totp = widget.enrollment.totp;
    return AlertDialog(
      title: const Text('Configurer la DFA'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (totp != null) ...[
                Center(child: _QrCodeView(data: totp.uri, size: 190)),
                const SizedBox(height: 12),
                const Text(
                  'Scannez le QR code avec votre application d’authentification.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                SelectableText('Secret : ${totp.secret}'),
                const SizedBox(height: 14),
              ],
              TextField(
                controller: _codeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Code à 6 chiffres',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _verifying ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _verifying ? null : _verify,
          icon: _verifying
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.verified_outlined),
          label: Text(_verifying ? 'Vérification...' : 'Vérifier'),
        ),
      ],
    );
  }
}

class _QrCodeView extends StatelessWidget {
  const _QrCodeView({required this.data, required this.size});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    final code = QrCode.fromData(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    final image = QrImage(code);
    return CustomPaint(
      size: Size.square(size),
      painter: _QrCodePainter(
        image: image,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

class _QrCodePainter extends CustomPainter {
  const _QrCodePainter({required this.image, required this.color});

  final QrImage image;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final moduleSize = size.width / image.moduleCount;
    for (var x = 0; x < image.moduleCount; x++) {
      for (var y = 0; y < image.moduleCount; y++) {
        if (!image.isDark(y, x)) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            x * moduleSize,
            y * moduleSize,
            moduleSize.ceilToDouble(),
            moduleSize.ceilToDouble(),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrCodePainter oldDelegate) {
    return oldDelegate.image != image || oldDelegate.color != color;
  }
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? _SettingsScreenState._green : AppColors.mutedText;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 128,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? _SettingsScreenState._green.withValues(alpha: 0.10)
              : Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.50),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? _SettingsScreenState._green.withValues(alpha: 0.35)
                : Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
