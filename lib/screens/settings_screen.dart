import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../branding/branding_scope.dart';
import '../models/app_role.dart';
import '../models/user_profile.dart';
import '../services/gestia_data_service.dart';
import '../theme/app_colors.dart';
import '../utils/error_messages.dart';
import '../utils/pick_profile_image.dart';
import '../widgets/modern_section_panel.dart';
import '../widgets/profile_avatar.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.profile,
    this.onProfileChanged,
  });

  final UserProfile profile;
  final VoidCallback? onProfileChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _appCtrl;
  late final TextEditingController _provinceCtrl;
  late final TextEditingController _profileNameCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _passwordConfirmCtrl;
  final Map<String, TextEditingController> _communeCtrls = {};
  List<({String id, String name})> _communes = [];
  bool _loading = true;
  bool _saving = false;
  bool _savingProfile = false;
  bool _savingPassword = false;
  bool _uploadingAvatar = false;
  bool _obscurePassword = true;
  bool _obscurePasswordConfirm = true;
  String? _error;
  bool _brandingReady = false;

  bool get _canManageGlobalSettings => widget.profile.role.canManageApp;
  bool get _canEditDisplayName => widget.profile.role.canEditOwnProfile;
  bool get _canEditAvatar => widget.profile.role.canChangeOwnAvatar;
  bool get _canChangePassword => widget.profile.role.canChangePassword;

  @override
  void initState() {
    super.initState();
    _appCtrl = TextEditingController();
    _provinceCtrl = TextEditingController();
    _profileNameCtrl = TextEditingController(text: widget.profile.fullName);
    _passwordCtrl = TextEditingController();
    _passwordConfirmCtrl = TextEditingController();
    _load();
  }

  @override
  void didUpdateWidget(SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.fullName != widget.profile.fullName) {
      _profileNameCtrl.text = widget.profile.fullName;
    }
    if (oldWidget.profile.role != widget.profile.role) {
      _load();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_brandingReady) return;
    _brandingReady = true;
    final branding = BrandingScope.of(context);
    _appCtrl.text = branding.appName;
    _provinceCtrl.text = branding.provinceName;
  }

  @override
  void dispose() {
    _appCtrl.dispose();
    _provinceCtrl.dispose();
    _profileNameCtrl.dispose();
    _passwordCtrl.dispose();
    _passwordConfirmCtrl.dispose();
    for (final controller in _communeCtrls.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    if (!_canManageGlobalSettings) {
      setState(() {
        _communes = [];
        _loading = false;
      });
      return;
    }

    try {
      final list = await GestiaDataService.fetchCommunes();
      if (!mounted) return;

      final nextIds = list.map((commune) => commune.id).toSet();
      final currentIds = _communeCtrls.keys.toList();
      for (final id in currentIds) {
        if (!nextIds.contains(id)) {
          _communeCtrls.remove(id)?.dispose();
        }
      }

      for (final commune in list) {
        final existing = _communeCtrls[commune.id];
        if (existing != null) {
          existing.text = commune.name;
        } else {
          _communeCtrls[commune.id] = TextEditingController(text: commune.name);
        }
      }

      setState(() {
        _communes = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userFacingErrorMessage(e);
        _loading = false;
      });
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
        const SnackBar(content: Text('Nom d affichage enregistre.')),
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

  String _extensionFromXFile(XFile x) {
    final name = x.name.toLowerCase();
    if (name.contains('.')) {
      return name.split('.').last;
    }
    final mime = x.mimeType?.toLowerCase();
    if (mime == 'image/jpeg' || mime == 'image/jpg') return 'jpg';
    if (mime == 'image/png') return 'png';
    if (mime == 'image/webp') return 'webp';
    return 'jpg';
  }

  Future<void> _pickAvatar() async {
    if (!_canEditAvatar) return;
    final file = await pickProfileImageFile();
    if (file == null || !mounted) return;

    setState(() => _uploadingAvatar = true);
    try {
      final bytes = await file.readAsBytes();
      final extension = _extensionFromXFile(file);
      await GestiaDataService.uploadMyAvatarAndSaveProfile(
        userId: widget.profile.id,
        bytes: bytes,
        fileExtension: extension,
      );
      if (!mounted) return;
      widget.onProfileChanged?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo de profil mise a jour.')),
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
        const SnackBar(content: Text('Photo de profil supprimee.')),
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
          content: Text('Le mot de passe doit contenir au moins 6 caracteres.'),
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
      ).showSnackBar(const SnackBar(content: Text('Mot de passe mis a jour.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  Future<void> _saveAll() async {
    if (!_canManageGlobalSettings) return;
    setState(() => _saving = true);
    try {
      final branding = BrandingScope.of(context);
      await branding.saveLabels(provinceName: _provinceCtrl.text.trim());
      _appCtrl.text = branding.appName;
      for (final commune in _communes) {
        final ctrl = _communeCtrls[commune.id];
        if (ctrl == null) continue;
        if (ctrl.text.trim() != commune.name) {
          await GestiaDataService.updateCommuneName(
            communeId: commune.id,
            name: ctrl.text.trim(),
          );
        }
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Parametres enregistres.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _copyTaxpayerId() async {
    final taxpayerId = widget.profile.taxpayerIdentifier;
    if (taxpayerId == null || taxpayerId.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: taxpayerId));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Identifiant copie.')));
  }

  String _settingsIntroText() {
    if (_canManageGlobalSettings) {
      return 'Pilotez votre compte, votre securite et l identite globale de l application depuis un seul espace.';
    }
    if (widget.profile.role == AppRole.contribuable) {
      return 'Mettez a jour votre profil, votre photo et votre mot de passe depuis votre espace personnel.';
    }
    if (_canEditDisplayName) {
      return 'Gerez vos informations personnelles et votre securite. Les reglages globaux restent reserves a l administration.';
    }
    return 'Consultez vos informations de compte et mettez a jour les elements autorises pour votre role.';
  }

  String _scopeLabel() {
    if (_canManageGlobalSettings) return 'Portee provinciale';
    if (widget.profile.role.isGlobalSupervisor) return 'Supervision globale';
    if (widget.profile.communeName != null &&
        widget.profile.communeName!.trim().isNotEmpty) {
      return widget.profile.communeName!;
    }
    if (widget.profile.role == AppRole.contribuable) {
      return 'Compte individuel';
    }
    return 'Espace personnel';
  }

  BoxDecoration _pageBackgroundDecoration(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [
                const Color(0xFF101613),
                Color.alphaBlend(
                  cs.primary.withValues(alpha: 0.10),
                  const Color(0xFF18201C),
                ),
                Color.alphaBlend(
                  cs.secondary.withValues(alpha: 0.08),
                  const Color(0xFF1B2520),
                ),
              ]
            : [
                const Color(0xFFF7F2E8),
                const Color(0xFFF2E9DB),
                Color.alphaBlend(
                  cs.primary.withValues(alpha: 0.04),
                  const Color(0xFFF7F2E8),
                ),
              ],
      ),
    );
  }

  Widget _buildStateScreen(BuildContext context, Widget child) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: _pageBackgroundDecoration(context),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildSoftCard(
    BuildContext context, {
    required Widget child,
    required Color accentColor,
    EdgeInsetsGeometry? padding,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: isDark ? 0.14 : 0.06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accentColor.withValues(alpha: 0.12)),
      ),
      child: child,
    );
  }

  Widget _buildTag(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  int _communeColumns(double width) {
    if (width >= 1080) return 2;
    return 1;
  }

  Widget _buildAccountPanel(BuildContext context, bool busyAccount) {
    return ModernSectionPanel(
      title: 'Mon compte',
      subtitle:
          'Retouchez votre identite visible, votre photo de profil et les informations utiles associees a votre compte.',
      eyebrow: 'Profil',
      accentColor: AppColors.primary,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 760;

          final identityCard = _buildSoftCard(
            context,
            accentColor: AppColors.primary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ProfileAvatar(
                      fullName: widget.profile.fullName,
                      avatarUrl: widget.profile.avatarUrl,
                      radius: 40,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.profile.fullName,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.3,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.profile.role.shortLabel,
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildTag(
                      context,
                      icon: Icons.public_outlined,
                      label: _scopeLabel(),
                      color: AppColors.chartTeal,
                    ),
                    if (_canEditDisplayName)
                      _buildTag(
                        context,
                        icon: Icons.edit_outlined,
                        label: 'Nom modifiable',
                        color: AppColors.primary,
                      ),
                    if (_canEditAvatar)
                      _buildTag(
                        context,
                        icon: Icons.photo_camera_outlined,
                        label: 'Photo modifiable',
                        color: AppColors.chartOrange,
                      ),
                    if (_canManageGlobalSettings)
                      _buildTag(
                        context,
                        icon: Icons.settings_suggest_outlined,
                        label: 'Reglages globaux',
                        color: AppColors.chartPurple,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: busyAccount || !_canEditAvatar
                          ? null
                          : _pickAvatar,
                      icon: _uploadingAvatar
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.photo_camera_outlined),
                      label: Text(
                        _uploadingAvatar
                            ? 'Traitement...'
                            : 'Choisir une photo',
                      ),
                    ),
                    TextButton.icon(
                      onPressed:
                          busyAccount ||
                              !_canEditAvatar ||
                              widget.profile.avatarUrl == null
                          ? null
                          : _removeAvatar,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Supprimer la photo'),
                    ),
                  ],
                ),
              ],
            ),
          );

          final formCard = _buildSoftCard(
            context,
            accentColor: AppColors.chartTeal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Identite visible',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _profileNameCtrl,
                  readOnly: !_canEditDisplayName,
                  decoration: const InputDecoration(
                    labelText: 'Nom d affichage',
                    hintText: 'Prenom et nom',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                if (!_canEditDisplayName) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Ce role ne peut pas modifier le nom affiche.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (widget.profile.taxpayerIdentifier != null &&
                    widget.profile.taxpayerIdentifier!.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.chartOrange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: AppColors.chartOrange.withValues(alpha: 0.16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ID contribuable',
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 6),
                              SelectableText(
                                widget.profile.taxpayerIdentifier!,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          onPressed: _copyTaxpayerId,
                          tooltip: 'Copier',
                          icon: const Icon(Icons.copy_outlined),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: busyAccount || !_canEditDisplayName
                      ? null
                      : _saveProfileName,
                  icon: _savingProfile
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    _savingProfile ? 'Enregistrement...' : 'Enregistrer le nom',
                  ),
                ),
              ],
            ),
          );

          if (stacked) {
            return Column(
              children: [identityCard, const SizedBox(height: 16), formCard],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: identityCard),
              const SizedBox(width: 16),
              Expanded(flex: 6, child: formCard),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSecurityPanel(BuildContext context, bool busyAccount) {
    return ModernSectionPanel(
      title: 'Securite',
      subtitle:
          'Renouvelez votre mot de passe avec confirmation et gardez le controle de votre acces.',
      eyebrow: 'Protection',
      accentColor: AppColors.chartOrange,
      child: _buildSoftCard(
        context,
        accentColor: AppColors.chartOrange,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildTag(
                  context,
                  icon: Icons.password_outlined,
                  label: '6 caracteres minimum',
                  color: AppColors.chartOrange,
                ),
                _buildTag(
                  context,
                  icon: Icons.verified_outlined,
                  label: 'Confirmation requise',
                  color: AppColors.chartTeal,
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Nouveau mot de passe',
                border: const OutlineInputBorder(),
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
              decoration: InputDecoration(
                labelText: 'Confirmer le mot de passe',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(
                      () => _obscurePasswordConfirm = !_obscurePasswordConfirm,
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
            const SizedBox(height: 12),
            Text(
              'Le changement est applique immediatement a votre compte.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: busyAccount || !_canChangePassword
                  ? null
                  : _savePassword,
              icon: _savingPassword
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.lock_reset_outlined),
              label: Text(
                _savingPassword
                    ? 'Mise a jour...'
                    : 'Mettre a jour le mot de passe',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalSettingsPanel(BuildContext context) {
    return ModernSectionPanel(
      title: 'Configuration globale',
      subtitle:
          'Mettez a jour l identite de l application et les libelles de communes depuis une seule zone d administration.',
      eyebrow: 'Administration',
      accentColor: AppColors.chartTeal,
      action: FilledButton.icon(
        onPressed: _saving ? null : _saveAll,
        icon: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save_outlined),
        label: Text(_saving ? 'Enregistrement...' : 'Enregistrer'),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = _communeColumns(constraints.maxWidth);
          final spacing = 14.0;
          final fieldWidth = columns == 1
              ? constraints.maxWidth
              : (constraints.maxWidth - spacing) / columns;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSoftCard(
                context,
                accentColor: AppColors.primary,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Identite de l application',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [
                        SizedBox(
                          width: fieldWidth,
                          child: TextField(
                            controller: _appCtrl,
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: 'Nom de l application',
                              helperText: 'Nom fixe',
                              suffixIcon: Icon(Icons.lock_outline),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: fieldWidth,
                          child: TextField(
                            controller: _provinceCtrl,
                            readOnly: !_canManageGlobalSettings,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Libelle province',
                              hintText: 'ex. Province du Haut-Katanga',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildSoftCard(
                context,
                accentColor: AppColors.chartPurple,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Communes',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Text(
                          '${_communes.length} element(s)',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Renommez les territoires affiches dans l interface. Chaque champ conserve son identifiant technique.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_communes.isEmpty)
                      Text(
                        'Aucune commune chargee.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    else
                      Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: [
                          for (final commune in _communes)
                            SizedBox(
                              width: fieldWidth,
                              child: _buildSoftCard(
                                context,
                                accentColor: AppColors.chartPurple,
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'ID : ${commune.id}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 10),
                                    TextField(
                                      controller: _communeCtrls[commune.id],
                                      readOnly: !_canManageGlobalSettings,
                                      decoration: const InputDecoration(
                                        labelText: 'Nom de la commune',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busyAccount = _savingProfile || _uploadingAvatar || _savingPassword;

    if (_loading) {
      return _buildStateScreen(context, const CircularProgressIndicator());
    }

    if (_error != null) {
      return _buildStateScreen(
        context,
        ModernSectionPanel(
          title: 'Impossible de charger les parametres',
          subtitle:
              'Les donnees n ont pas pu etre recuperees pour le moment. Vous pouvez relancer le chargement.',
          eyebrow: 'Etat',
          accentColor: AppColors.chartRed,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_error!),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_outlined),
                label: const Text('Reessayer'),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 1040;

        return Container(
          decoration: _pageBackgroundDecoration(context),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ModernSectionPanel(
                      title: 'Parametres',
                      subtitle: _settingsIntroText(),
                      eyebrow: 'Mon espace',
                      accentColor: AppColors.primary,
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          ModernInfoPill(
                            label: 'Role',
                            value: widget.profile.role.shortLabel,
                            icon: Icons.badge_outlined,
                            color: AppColors.primary,
                          ),
                          ModernInfoPill(
                            label: 'Portee',
                            value: _scopeLabel(),
                            icon: Icons.public_outlined,
                            color: AppColors.chartTeal,
                          ),
                          ModernInfoPill(
                            label: 'Photo',
                            value: _canEditAvatar
                                ? 'Modifiable'
                                : 'Verrouillee',
                            icon: Icons.photo_camera_outlined,
                            color: AppColors.chartOrange,
                          ),
                          ModernInfoPill(
                            label: 'Global',
                            value: _canManageGlobalSettings ? 'Oui' : 'Non',
                            icon: Icons.settings_outlined,
                            color: AppColors.chartPurple,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (twoColumns)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 6,
                            child: _buildAccountPanel(context, busyAccount),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            flex: 5,
                            child: _buildSecurityPanel(context, busyAccount),
                          ),
                        ],
                      )
                    else ...[
                      _buildAccountPanel(context, busyAccount),
                      const SizedBox(height: 18),
                      _buildSecurityPanel(context, busyAccount),
                    ],
                    if (_canManageGlobalSettings) ...[
                      const SizedBox(height: 18),
                      _buildGlobalSettingsPanel(context),
                    ],
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
