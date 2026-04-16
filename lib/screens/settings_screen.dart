import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../branding/branding_scope.dart';
import '../models/app_role.dart';
import '../models/user_profile.dart';
import '../services/gestia_data_service.dart';
import '../utils/pick_profile_image.dart';
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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_brandingReady) return;
    _brandingReady = true;
    final b = BrandingScope.of(context);
    _appCtrl.text = b.appName;
    _provinceCtrl.text = b.provinceName;
  }

  @override
  void dispose() {
    _appCtrl.dispose();
    _provinceCtrl.dispose();
    _profileNameCtrl.dispose();
    _passwordCtrl.dispose();
    _passwordConfirmCtrl.dispose();
    for (final c in _communeCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await GestiaDataService.fetchCommunes();
      if (!mounted) return;
      for (final c in list) {
        final existing = _communeCtrls[c.id];
        if (existing != null) {
          existing.text = c.name;
        } else {
          _communeCtrls[c.id] = TextEditingController(text: c.name);
        }
      }
      setState(() {
        _communes = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
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
        fullName: _profileNameCtrl.text,
      );
      if (!mounted) return;
      widget.onProfileChanged?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nom d’affichage enregistré.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  String _extensionFromXFile(XFile x) {
    final n = x.name.toLowerCase();
    if (n.contains('.')) {
      return n.split('.').last;
    }
    final mime = x.mimeType?.toLowerCase();
    if (mime == 'image/jpeg' || mime == 'image/jpg') return 'jpg';
    if (mime == 'image/png') return 'png';
    if (mime == 'image/webp') return 'webp';
    return 'jpg';
  }

  Future<void> _pickAvatar() async {
    if (!_canEditAvatar) return;
    final x = await pickProfileImageFile();
    if (x == null || !mounted) return;

    setState(() => _uploadingAvatar = true);
    try {
      final bytes = await x.readAsBytes();
      final ext = _extensionFromXFile(x);
      await GestiaDataService.uploadMyAvatarAndSaveProfile(
        userId: widget.profile.id,
        bytes: bytes,
        fileExtension: ext,
      );
      if (!mounted) return;
      widget.onProfileChanged?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo de profil mise à jour.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
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
          content: Text(
            'Le mot de passe doit contenir au moins 6 caractères.',
          ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mot de passe mis à jour.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  Future<void> _saveAll() async {
    if (!_canManageGlobalSettings) return;
    setState(() => _saving = true);
    try {
      final branding = BrandingScope.of(context);
      await branding.saveLabels(
        appName: _appCtrl.text,
        provinceName: _provinceCtrl.text,
      );
      for (final c in _communes) {
        final ctrl = _communeCtrls[c.id];
        if (ctrl == null) continue;
        if (ctrl.text.trim() != c.name) {
          await GestiaDataService.updateCommuneName(
            communeId: c.id,
            name: ctrl.text,
          );
        }
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paramètres enregistrés.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Réessayer')),
          ],
        ),
      );
    }

    final busyAccount = _savingProfile || _uploadingAvatar || _savingPassword;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Paramètres',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              _canManageGlobalSettings
                  ? 'Modifiez votre profil, votre mot de passe, le nom de l’application, le libellé province et les noms des communes.'
                  : widget.profile.role == AppRole.contribuable
                      ? 'Modifiez votre profil, votre photo et votre mot de passe. Votre identifiant contribuable personnel est affiché ci-dessous.'
                      : _canEditDisplayName
                          ? 'Modifiez votre nom d’affichage, votre photo et votre mot de passe. Seul l’admin provincial peut changer les libellés globaux.'
                          : 'Vous pouvez modifier votre photo de profil et votre mot de passe. Le reste est en lecture seule.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            Text(
              'Mon compte',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ProfileAvatar(
                          fullName: widget.profile.fullName,
                          avatarUrl: widget.profile.avatarUrl,
                          radius: 36,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              OutlinedButton.icon(
                                onPressed: busyAccount || !_canEditAvatar
                                    ? null
                                    : _pickAvatar,
                                icon: _uploadingAvatar
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.photo_camera_outlined),
                                label: Text(
                                  _uploadingAvatar
                                      ? 'Traitement…'
                                      : 'Choisir une photo',
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: busyAccount ||
                                        !_canEditAvatar ||
                                        widget.profile.avatarUrl == null
                                    ? null
                                    : _removeAvatar,
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Supprimer la photo'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _profileNameCtrl,
                      readOnly: !_canEditDisplayName,
                      decoration: const InputDecoration(
                        labelText: 'Nom d’affichage',
                        hintText: 'Prénom et nom',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                    if (widget.profile.taxpayerIdentifier != null &&
                        widget.profile.taxpayerIdentifier!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'ID contribuable',
                          helperText: 'Identifiant personnel généré par le système',
                          border: OutlineInputBorder(),
                        ),
                        child: SelectableText(
                          widget.profile.taxpayerIdentifier!,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
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
                        _savingProfile ? 'Enregistrement…' : 'Enregistrer le nom',
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Nouveau mot de passe',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordConfirmCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirmer le mot de passe',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
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
                            ? 'Mise à jour…'
                            : 'Modifier le mot de passe',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Application',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _appCtrl,
              readOnly: !_canManageGlobalSettings,
              decoration: const InputDecoration(
                labelText: 'Nom de l’application',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _provinceCtrl,
              readOnly: !_canManageGlobalSettings,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Libellé province (affiché dans l’interface)',
                hintText: 'ex. Province du Haut-Katanga',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Communes',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            ...[
              for (final c in _communes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: _communeCtrls[c.id],
                    readOnly: !_canManageGlobalSettings,
                    decoration: InputDecoration(
                      labelText: 'Commune',
                      border: const OutlineInputBorder(),
                      helperText: 'ID : ${c.id}',
                    ),
                  ),
                ),
            ],
            if (_canManageGlobalSettings) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _saveAll,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Enregistrement…' : 'Enregistrer'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
