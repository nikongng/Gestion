import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_role.dart';
import '../models/user_profile.dart';
import '../services/gestia_data_service.dart';
import '../theme/app_colors.dart';
import '../utils/error_messages.dart';
import '../utils/user_directory_exporter.dart';
import '../widgets/profile_avatar.dart';

enum _UserKindFilter { all, internal, contribuable }

enum _UserSortMode { nameAsc, nameDesc, roleAsc }

enum _UserStatusFilter { all, active, suspended }

enum UsersManagementMode { agents, contribuables }

const _mairieOperationalRoles = <AppRole>[
  AppRole.taxateur,
  AppRole.ordonnateur,
  AppRole.apureur,
  AppRole.agent,
];

class UsersManagementScreen extends StatefulWidget {
  const UsersManagementScreen({
    super.key,
    required this.profile,
    this.mode = UsersManagementMode.agents,
  });

  final UserProfile profile;
  final UsersManagementMode mode;

  @override
  State<UsersManagementScreen> createState() => _UsersManagementScreenState();
}

class _UsersManagementScreenState extends State<UsersManagementScreen> {
  final _searchCtrl = TextEditingController();

  List<UserProfile> _profiles = [];
  bool _loading = true;
  String? _deletingUserId;
  String? _updatingStatusUserId;
  String? _error;

  AppRole? _roleFilter;
  _UserKindFilter _kindFilter = _UserKindFilter.all;
  _UserStatusFilter _statusFilter = _UserStatusFilter.all;
  _UserSortMode _sortMode = _UserSortMode.nameAsc;
  int _pageIndex = 0;
  int _pageSize = 10;
  bool _exportingUsers = false;

  bool get _canManageUsers => widget.profile.canManageApp;

  _UserKindFilter get _defaultKindFilter =>
      widget.mode == UsersManagementMode.contribuables
      ? _UserKindFilter.contribuable
      : _UserKindFilter.internal;

  int get _activeFilterCount {
    var count = 0;
    if (_searchCtrl.text.trim().isNotEmpty) count++;
    if (_roleFilter != null) count++;
    if (_kindFilter != _defaultKindFilter) count++;
    if (_statusFilter != _UserStatusFilter.all) count++;
    if (_sortMode != _UserSortMode.nameAsc) count++;
    return count;
  }

  List<UserProfile> get _filteredProfiles {
    final query = _searchCtrl.text.trim().toLowerCase();

    final list = _profiles.where((profile) {
      final matchesQuery =
          query.isEmpty || _matchesProfileQuery(profile, query);
      final isContribuable = profile.hasRole(AppRole.contribuable);
      final matchesRole = _roleFilter == null || profile.hasRole(_roleFilter!);
      final matchesStatus = switch (_statusFilter) {
        _UserStatusFilter.all => true,
        _UserStatusFilter.active => !_isSuspended(profile),
        _UserStatusFilter.suspended => _isSuspended(profile),
      };
      final matchesMode = widget.mode == UsersManagementMode.contribuables
          ? isContribuable
          : !isContribuable;
      final matchesKind = switch (_kindFilter) {
        _UserKindFilter.all => true,
        _UserKindFilter.internal => !isContribuable,
        _UserKindFilter.contribuable => isContribuable,
      };

      return matchesQuery &&
          matchesMode &&
          matchesRole &&
          matchesStatus &&
          matchesKind;
    }).toList();

    list.sort((a, b) {
      switch (_sortMode) {
        case _UserSortMode.nameAsc:
          return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
        case _UserSortMode.nameDesc:
          return b.fullName.toLowerCase().compareTo(a.fullName.toLowerCase());
        case _UserSortMode.roleAsc:
          final byRole = a.rolesLabel.toLowerCase().compareTo(
            b.rolesLabel.toLowerCase(),
          );
          if (byRole != 0) return byRole;
          return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
      }
    });

    return list;
  }

  @override
  void initState() {
    super.initState();
    _kindFilter = _defaultKindFilter;
    _searchCtrl.addListener(_handleFilterChanged);
    _reload();
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_handleFilterChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _handleFilterChanged() {
    if (!mounted) return;
    setState(() => _pageIndex = 0);
  }

  bool _matchesProfileQuery(UserProfile profile, String query) {
    final parts = [
      profile.fullName,
      profile.rolesLabel,
      profile.taxpayerIdentifier,
      profile.id,
    ].whereType<String>().map((value) => value.toLowerCase());

    return parts.any((value) => value.contains(query));
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profiles = await GestiaDataService.fetchAllProfiles();
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
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

  void _resetFilters() {
    setState(() {
      _searchCtrl.clear();
      _roleFilter = null;
      _kindFilter = _defaultKindFilter;
      _statusFilter = _UserStatusFilter.all;
      _sortMode = _UserSortMode.nameAsc;
      _pageIndex = 0;
    });
  }

  Future<void> _openCreateDialog() async {
    if (!_canManageUsers) return;

    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    AppRole role = AppRole.taxateur;
    final selectedRoles = <AppRole>{AppRole.taxateur};

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        var submitting = false;
        String? dialogError;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final theme = Theme.of(context);
            final cs = theme.colorScheme;

            return AlertDialog(
              title: const Text('Nouvel utilisateur'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: cs.primary.withValues(alpha: 0.14),
                          ),
                        ),
                        child: Text(
                          'Créez ici un compte interne. Les comptes contribuables restent auto-inscrits.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nom complet',
                          border: OutlineInputBorder(),
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: emailCtrl,
                        decoration: const InputDecoration(
                          labelText: 'E-mail',
                          hintText: 'prenom.nom@taxis.cd',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: passCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Mot de passe initial',
                          border: OutlineInputBorder(),
                        ),
                        obscureText: true,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<AppRole>(
                        key: ValueKey(role),
                        initialValue: role,
                        decoration: const InputDecoration(
                          labelText: 'rôle',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final item in _mairieOperationalRoles)
                            DropdownMenuItem(
                              value: item,
                              child: Text(item.shortLabel),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() {
                            role = value;
                            selectedRoles
                              ..clear()
                              ..add(value);
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Rôles additionnels',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final item in _mairieOperationalRoles)
                            FilterChip(
                              selected: selectedRoles.contains(item),
                              label: Text(item.shortLabel),
                              onSelected: (selected) {
                                setDialogState(() {
                                  if (selected) {
                                    selectedRoles.add(item);
                                  } else if (selectedRoles.length > 1) {
                                    selectedRoles.remove(item);
                                  }
                                  role = selectedRoles.first;
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: cs.outline.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.account_balance_outlined,
                              color: cs.primary,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Rattachement: Mairie',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (dialogError != null) ...[
                        const SizedBox(height: 10),
                        Text(dialogError!, style: TextStyle(color: cs.error)),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.pop(ctx),
                  child: const Text('Annuler'),
                ),
                FilledButton.icon(
                  onPressed: submitting
                      ? null
                      : () async {
                          final email = emailCtrl.text.trim();
                          final password = passCtrl.text;
                          final fullName = nameCtrl.text.trim();

                          if (fullName.isEmpty ||
                              email.isEmpty ||
                              password.isEmpty) {
                            setDialogState(() {
                              dialogError =
                                  'Nom, e-mail et mot de passe réquis.';
                            });
                            return;
                          }

                          setDialogState(() {
                            submitting = true;
                            dialogError = null;
                          });

                          try {
                            await GestiaDataService.createStaffUserViaEdgeFunction(
                              email: email,
                              password: password,
                              fullName: fullName,
                              role: role,
                              roles: selectedRoles.toList(),
                            );
                            if (!context.mounted) return;
                            Navigator.pop(ctx, true);
                          } catch (e) {
                            setDialogState(() {
                              submitting = false;
                              dialogError = userFacingErrorMessage(e);
                            });
                          }
                        },
                  icon: submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.person_add_alt_1_outlined),
                  label: Text(submitting ? 'Création...' : 'Créer'),
                ),
              ],
            );
          },
        );
      },
    );

    emailCtrl.dispose();
    passCtrl.dispose();
    nameCtrl.dispose();

    if (created != true || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Utilisateur créé. Il peut maintenant se connecter.'),
      ),
    );
    await _reload();
  }

  Future<void> _openRolesDialog(UserProfile target) async {
    if (!_canManageUsers ||
        target.hasRole(AppRole.adminProvincial) ||
        target.hasRole(AppRole.contribuable)) {
      return;
    }
    final selectedRoles = target.roles
        .where(_mairieOperationalRoles.contains)
        .toSet();
    if (selectedRoles.isEmpty) selectedRoles.add(AppRole.agent);
    var primaryRole = target.role;
    if (!selectedRoles.contains(primaryRole)) {
      primaryRole = selectedRoles.first;
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        var submitting = false;
        String? dialogError;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Rôles de ${target.fullName}'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final item in _mairieOperationalRoles)
                          FilterChip(
                            selected: selectedRoles.contains(item),
                            label: Text(item.shortLabel),
                            onSelected: submitting
                                ? null
                                : (selected) {
                                    setDialogState(() {
                                      if (selected) {
                                        selectedRoles.add(item);
                                      } else if (selectedRoles.length > 1) {
                                        selectedRoles.remove(item);
                                      }
                                      if (!selectedRoles.contains(
                                        primaryRole,
                                      )) {
                                        primaryRole = selectedRoles.first;
                                      }
                                    });
                                  },
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<AppRole>(
                      key: ValueKey(primaryRole),
                      initialValue: primaryRole,
                      decoration: const InputDecoration(
                        labelText: 'Rôle principal',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final role in selectedRoles)
                          DropdownMenuItem(
                            value: role,
                            child: Text(role.shortLabel),
                          ),
                      ],
                      onChanged: submitting
                          ? null
                          : (value) {
                              if (value == null) return;
                              setDialogState(() => primaryRole = value);
                            },
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.account_balance_outlined),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Rattachement: Mairie',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        dialogError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.pop(ctx),
                  child: const Text('Annuler'),
                ),
                FilledButton.icon(
                  onPressed: submitting
                      ? null
                      : () async {
                          setDialogState(() {
                            submitting = true;
                            dialogError = null;
                          });
                          try {
                            await GestiaDataService.updateProfileRoles(
                              userId: target.id,
                              primaryRole: primaryRole,
                              roles: selectedRoles.toList(),
                            );
                            if (!context.mounted) return;
                            Navigator.pop(ctx, true);
                          } catch (e) {
                            setDialogState(() {
                              submitting = false;
                              dialogError = userFacingErrorMessage(e);
                            });
                          }
                        },
                  icon: submitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(submitting ? 'Enregistrement...' : 'Enregistrer'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true) await _reload();
  }

  Future<void> _openCreateContribuableDialog() async {
    if (!_canManageUsers) return;

    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final idNumberCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final activityCtrl = TextEditingController();
    final legalDenominationCtrl = TextEditingController();
    final legalNifCtrl = TextEditingController();
    var isLegalEntity = false;
    var identificationType = 'Carte d’électeur';
    var status = 'actif';

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        var submitting = false;
        String? dialogError;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final cs = Theme.of(context).colorScheme;
            return AlertDialog(
              title: const Text('Nouveau contribuable'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: false,
                            label: Text('Personne physique'),
                            icon: Icon(Icons.person_outline),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text('Personne morale'),
                            icon: Icon(Icons.apartment_outlined),
                          ),
                        ],
                        selected: {isLegalEntity},
                        onSelectionChanged: (values) {
                          setDialogState(() => isLegalEntity = values.first);
                        },
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: 330,
                            child: TextField(
                              controller: nameCtrl,
                              textCapitalization: TextCapitalization.words,
                              decoration: InputDecoration(
                                labelText: isLegalEntity
                                    ? 'Raison sociale'
                                    : 'Nom complet',
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 330,
                            child: TextField(
                              controller: phoneCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Numéro de téléphone',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 330,
                            child: TextField(
                              controller: addressCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Adresse',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 330,
                            child: TextField(
                              controller: emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 330,
                            child: DropdownButtonFormField<String>(
                              initialValue: identificationType,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Type d’identification',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'Carte d’électeur',
                                  child: Text('Carte d’électeur'),
                                ),
                                DropdownMenuItem(
                                  value: 'Passeport',
                                  child: Text('Passeport'),
                                ),
                                DropdownMenuItem(
                                  value: 'NIP',
                                  child: Text('NIP'),
                                ),
                                DropdownMenuItem(
                                  value: 'RCCM',
                                  child: Text('RCCM'),
                                ),
                                DropdownMenuItem(
                                  value: 'ID national',
                                  child: Text('ID national'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                setDialogState(
                                  () => identificationType = value,
                                );
                              },
                            ),
                          ),
                          SizedBox(
                            width: 330,
                            child: TextField(
                              controller: idNumberCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Numéro d’identification',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 330,
                            child: TextField(
                              controller: locationCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Secteur / quartier',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 330,
                            child: TextField(
                              controller: activityCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Activité ou profession',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 330,
                            child: DropdownButtonFormField<String>(
                              initialValue: status,
                              decoration: const InputDecoration(
                                labelText: 'Statut',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'actif',
                                  child: Text('Actif'),
                                ),
                                DropdownMenuItem(
                                  value: 'inactif',
                                  child: Text('Inactif'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                setDialogState(() => status = value);
                              },
                            ),
                          ),
                          if (isLegalEntity) ...[
                            SizedBox(
                              width: 330,
                              child: TextField(
                                controller: legalDenominationCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Denomination',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 330,
                              child: TextField(
                                controller: legalNifCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'NIP / RCCM',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                          SizedBox(
                            width: 330,
                            child: TextField(
                              controller: passCtrl,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Mot de passe initial',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (dialogError != null) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            dialogError!,
                            style: TextStyle(color: cs.error),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.pop(ctx),
                  child: const Text('Annuler'),
                ),
                FilledButton.icon(
                  onPressed: submitting
                      ? null
                      : () async {
                          setDialogState(() {
                            submitting = true;
                            dialogError = null;
                          });
                          try {
                            await GestiaDataService.createContribuableViaEdgeFunction(
                              email: emailCtrl.text,
                              password: passCtrl.text,
                              fullName: nameCtrl.text,
                              phone: phoneCtrl.text,
                              address: addressCtrl.text,
                              isLegalEntity: isLegalEntity,
                              identificationType: identificationType,
                              identificationNumber: idNumberCtrl.text,
                              locationLabel: locationCtrl.text.trim(),
                              activity: activityCtrl.text,
                              status: status,
                              legalDenomination: legalDenominationCtrl.text,
                              legalNif: legalNifCtrl.text,
                            );
                            if (!context.mounted) return;
                            Navigator.pop(ctx, true);
                          } catch (e) {
                            setDialogState(() {
                              submitting = false;
                              dialogError = userFacingErrorMessage(e);
                            });
                          }
                        },
                  icon: submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.badge_outlined),
                  label: Text(submitting ? 'Création...' : 'Créer'),
                ),
              ],
            );
          },
        );
      },
    );

    emailCtrl.dispose();
    passCtrl.dispose();
    nameCtrl.dispose();
    phoneCtrl.dispose();
    addressCtrl.dispose();
    idNumberCtrl.dispose();
    locationCtrl.dispose();
    activityCtrl.dispose();
    legalDenominationCtrl.dispose();
    legalNifCtrl.dispose();

    if (created != true || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Contribuable créé.')));
    await _reload();
  }

  Future<void> _deleteUser(UserProfile profile) async {
    if (!_canManageUsers) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cet utilisateur ?'),
        content: Text(
          'Le compte "${profile.fullName}" sera supprimé définitivement.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _deletingUserId = profile.id);
    try {
      await GestiaDataService.deleteStaffUserViaEdgeFunction(
        userId: profile.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${profile.fullName} supprimé.')));
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(e))));
    } finally {
      if (mounted && _deletingUserId == profile.id) {
        setState(() => _deletingUserId = null);
      }
    }
  }

  Future<void> _toggleUserStatus(UserProfile profile) async {
    if (!_canManageUsers) return;
    final isSuspended = _isSuspended(profile);
    final nextActive = isSuspended;
    final successMessage = nextActive
        ? '${profile.fullName} réactivé.'
        : '${profile.fullName} désactivé.';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          nextActive
              ? 'Réactiver cet utilisateur ?'
              : 'Désactiver cet utilisateur ?',
        ),
        content: Text(
          nextActive
              ? 'Le compte "${profile.fullName}" pourra de nouveau accéder à l’application.'
              : 'Le compte "${profile.fullName}" ne pourra plus accéder à l’application.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(nextActive ? 'Réactiver' : 'Désactiver'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _updatingStatusUserId = profile.id);
    try {
      await GestiaDataService.updateProfileAccountStatus(
        userId: profile.id,
        active: nextActive,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(e))));
    } finally {
      if (mounted && _updatingStatusUserId == profile.id) {
        setState(() => _updatingStatusUserId = null);
      }
    }
  }

  String _statusFilterLabel(_UserStatusFilter filter) {
    switch (filter) {
      case _UserStatusFilter.all:
        return 'Tous les statuts';
      case _UserStatusFilter.active:
        return 'Actif';
      case _UserStatusFilter.suspended:
        return 'Désactivé';
    }
  }

  Color _roleColor(AppRole role) {
    switch (role) {
      case AppRole.adminProvincial:
        return AppColors.chartRed;
      case AppRole.ministreFinances:
        return AppColors.chartPurple;
      case AppRole.gouverneur:
        return AppColors.chartOrange;
      case AppRole.bourgmestre:
        return AppColors.chartTeal;
      case AppRole.agent:
        return AppColors.chartOrange;
      case AppRole.taxateur:
        return AppColors.chartBlue;
      case AppRole.ordonnateur:
        return AppColors.chartTeal;
      case AppRole.apureur:
        return AppColors.chartPurple;
      case AppRole.contribuable:
        return const Color(0xFF9A7200);
    }
  }

  bool _isSuspended(UserProfile profile) {
    return profile.isSuspended;
  }

  String _statusLabel(UserProfile profile) {
    return _isSuspended(profile) ? 'Désactivé' : 'Actif';
  }

  Color _statusColor(UserProfile profile) {
    return _isSuspended(profile) ? AppColors.chartRed : AppColors.chartTeal;
  }

  String _identifierLabel(UserProfile profile) {
    final taxpayerId = profile.taxpayerIdentifier?.trim();
    if (taxpayerId != null && taxpayerId.isNotEmpty) return taxpayerId;
    final compactId = profile.id.length > 8
        ? profile.id.substring(0, 8)
        : profile.id;
    return 'ID $compactId';
  }

  String _serviceLabel(UserProfile profile) {
    if (profile.hasRole(AppRole.contribuable)) {
      return 'Contribuable';
    }
    if (profile.hasRole(AppRole.adminProvincial) ||
        profile.hasRole(AppRole.ministreFinances) ||
        profile.hasRole(AppRole.gouverneur)) {
      return 'Administration';
    }
    return 'Mairie';
  }

  String _lastConnectionLabel(UserProfile profile, String? currentUserId) {
    final lastSignInAt = profile.lastSignInAt;
    if (lastSignInAt != null) return _formatDateTime(lastSignInAt);
    return profile.id == currentUserId ? 'Session active' : 'Non disponible';
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  List<UserDirectoryExportRow> _buildExportRows(
    List<UserProfile> profiles,
    String? currentUserId,
  ) {
    return [
      for (var i = 0; i < profiles.length; i++)
        UserDirectoryExportRow(
          index: i + 1,
          name: profiles[i].fullName,
          identifier: _identifierLabel(profiles[i]),
          role: profiles[i].rolesLabel,
          service: _serviceLabel(profiles[i]),
          status: _statusLabel(profiles[i]),
          lastConnection: _lastConnectionLabel(profiles[i], currentUserId),
        ),
    ];
  }

  Future<void> _exportUsers({required bool asPdf}) async {
    if (_exportingUsers) return;
    final rows = _buildExportRows(
      _filteredProfiles,
      Supabase.instance.client.auth.currentUser?.id,
    );
    setState(() => _exportingUsers = true);
    try {
      final title = widget.mode == UsersManagementMode.contribuables
          ? 'Gestion des contribuables'
          : 'Gestion des utilisateurs';
      final path = asPdf
          ? await UserDirectoryExporter.exportPdf(title: title, rows: rows)
          : await UserDirectoryExporter.exportExcel(title: title, rows: rows);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            path == null
                ? 'Export annulé.'
                : 'Export ${asPdf ? 'PDF' : 'Excel'} généré.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingErrorMessage(e, prefix: 'Échec de l’export')),
        ),
      );
    } finally {
      if (mounted) setState(() => _exportingUsers = false);
    }
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
                const Color(0xFFF8FAFD),
                const Color(0xFFFFFFFF),
                Color.alphaBlend(
                  cs.primary.withValues(alpha: 0.03),
                  const Color(0xFFF8FAFD),
                ),
              ],
      ),
    );
  }

  int _metricColumns(double width) {
    if (width >= 1180) return 4;
    if (width >= 680) return 2;
    return 1;
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

  Widget _buildMetricGrid(double width, List<Widget> cards) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _metricColumns(width),
        crossAxisSpacing: 20,
        mainAxisSpacing: 18,
        mainAxisExtent: 144,
      ),
      itemBuilder: (context, index) => cards[index],
    );
  }

  Widget _buildUsersTable(
    BuildContext context,
    List<UserProfile> allVisibleProfiles,
    List<UserProfile> pageProfiles,
    String? currentUserId,
    int pageIndex,
    int pageCount,
  ) {
    if (allVisibleProfiles.isEmpty) {
      return _SurfacePanel(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 34),
          child: Column(
            children: [
              Icon(
                Icons.search_off_outlined,
                size: 44,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                'Aucun utilisateur ne correspond aux filtres actuels.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final start = pageIndex * _pageSize + 1;
    final end = pageIndex * _pageSize + pageProfiles.length;

    return _SurfacePanel(
      padding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 1035,
              child: Column(
                children: [
                  _buildTableHeader(context),
                  for (var i = 0; i < pageProfiles.length; i++)
                    _buildTableRow(
                      context,
                      profile: pageProfiles[i],
                      index: pageIndex * _pageSize + i + 1,
                      currentUserId: currentUserId,
                    ),
                ],
              ),
            ),
          ),
          Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          _buildPagination(
            visibleCount: allVisibleProfiles.length,
            start: start,
            end: end,
            pageIndex: pageIndex,
            pageCount: pageCount,
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildUserGrid(
    BuildContext context,
    double width,
    List<UserProfile> profiles,
    String? currentUserId,
  ) {
    final pageCount = profiles.isEmpty
        ? 1
        : (profiles.length / _pageSize).ceil();
    final pageIndex = _pageIndex.clamp(0, pageCount - 1).toInt();
    final pageProfiles = profiles
        .skip(pageIndex * _pageSize)
        .take(_pageSize)
        .toList();
    return _buildUsersTable(
      context,
      profiles,
      pageProfiles,
      currentUserId,
      pageIndex,
      pageCount,
    );
  }

  Widget _buildTableHeader(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final style = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w900,
      color: cs.onSurface,
    );
    return Container(
      height: 58,
      color: isDark
          ? Color.alphaBlend(
              AppColors.primary.withValues(alpha: 0.10),
              cs.surfaceContainerHighest,
            )
          : const Color(0xFFFBFCFE),
      child: Row(
        children: [
          _tableCell(width: 52, child: Text('#', style: style)),
          _tableCell(width: 210, child: Text('Nom', style: style)),
          _tableCell(
            width: 205,
            child: Text('Email / Identifiant', style: style),
          ),
          _tableCell(width: 155, child: Text('Rôle', style: style)),
          _tableCell(width: 120, child: Text('Statut', style: style)),
          _tableCell(
            width: 165,
            child: Text('Dernière connexion', style: style),
          ),
          _tableCell(
            width: 128,
            horizontalPadding: 8,
            child: Text('Actions', style: style),
          ),
        ],
      ),
    );
  }

  Widget _buildTableRow(
    BuildContext context, {
    required UserProfile profile,
    required int index,
    required String? currentUserId,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDeleting = _deletingUserId == profile.id;
    final isUpdatingStatus = _updatingStatusUserId == profile.id;
    final isCurrentUser = profile.id == currentUserId;
    final isProtected = profile.hasRole(AppRole.adminProvincial);
    final isContribuable = profile.hasRole(AppRole.contribuable);
    final isSuspended = _isSuspended(profile);
    final canManageRoles =
        _canManageUsers && !isCurrentUser && !isProtected && !isContribuable;
    final canDelete = _canManageUsers && !isProtected && !isCurrentUser;
    final canToggleStatus = _canManageUsers && !isProtected && !isCurrentUser;

    return Container(
      height: 64,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.72),
            width: 0.7,
          ),
        ),
      ),
      child: Row(
        children: [
          _tableCell(width: 52, child: Text('$index')),
          _tableCell(
            width: 210,
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ProfileAvatar(
                      fullName: profile.fullName,
                      avatarUrl: profile.avatarUrl,
                      radius: 18,
                    ),
                    if (isCurrentUser)
                      Positioned(
                        right: -1,
                        bottom: -1,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: AppColors.chartTeal,
                            shape: BoxShape.circle,
                            border: Border.all(color: cs.surface, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    profile.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _tableCell(
            width: 205,
            child: Text(
              _identifierLabel(profile),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
            ),
          ),
          _tableCell(
            width: 155,
            horizontalPadding: 8,
            child: _RoleBadge(
              label: profile.rolesLabel,
              color: _roleColor(profile.role),
            ),
          ),
          _tableCell(
            width: 120,
            child: _StatusBadge(
              label: _statusLabel(profile),
              color: _statusColor(profile),
            ),
          ),
          _tableCell(
            width: 165,
            child: Text(
              _lastConnectionLabel(profile, currentUserId),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _tableCell(
            width: 128,
            horizontalPadding: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _UserActionButton(
                  icon: Icons.edit_outlined,
                  color: AppColors.chartBlue,
                  tooltip: 'Modifier les rôles',
                  onPressed: canManageRoles
                      ? () => _openRolesDialog(profile)
                      : null,
                ),
                const SizedBox(width: 6),
                _UserActionButton(
                  icon: isSuspended
                      ? Icons.play_circle_outline
                      : Icons.block_outlined,
                  color: AppColors.chartOrange,
                  tooltip: isSuspended ? 'Réactiver' : 'Désactiver',
                  loading: isUpdatingStatus,
                  onPressed: canToggleStatus && !isUpdatingStatus
                      ? () => _toggleUserStatus(profile)
                      : null,
                ),
                const SizedBox(width: 6),
                _UserActionButton(
                  icon: Icons.delete_outline,
                  color: AppColors.chartRed,
                  tooltip: 'Supprimer',
                  loading: isDeleting,
                  onPressed: canDelete && !isDeleting
                      ? () => _deleteUser(profile)
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableCell({
    required double width,
    required Widget child,
    double horizontalPadding = 14,
  }) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }

  List<int?> _paginationItems(int pageCount, int pageIndex) {
    if (pageCount <= 6) return [for (var i = 0; i < pageCount; i++) i];
    final items =
        <int?>{0, pageIndex - 1, pageIndex, pageIndex + 1, pageCount - 1}
            .where((item) => item != null && item >= 0 && item < pageCount)
            .cast<int>()
            .toList()
          ..sort();
    final output = <int?>[];
    for (final item in items) {
      if (output.isNotEmpty && item - output.last! > 1) output.add(null);
      output.add(item);
    }
    return output;
  }

  Widget _buildPagination({
    required int visibleCount,
    required int start,
    required int end,
    required int pageIndex,
    required int pageCount,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      child: Wrap(
        spacing: 14,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Affichage $start à $end sur $visibleCount utilisateurs',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _PageButton(
                icon: Icons.chevron_left,
                onPressed: pageIndex == 0
                    ? null
                    : () => setState(() => _pageIndex = pageIndex - 1),
              ),
              for (final item in _paginationItems(pageCount, pageIndex))
                item == null
                    ? const _PageEllipsis()
                    : _PageNumberButton(
                        label: '${item + 1}',
                        selected: item == pageIndex,
                        onPressed: () => setState(() => _pageIndex = item),
                      ),
              _PageButton(
                icon: Icons.chevron_right,
                onPressed: pageIndex >= pageCount - 1
                    ? null
                    : () => setState(() => _pageIndex = pageIndex + 1),
              ),
            ],
          ),
          SizedBox(
            width: 154,
            child: DropdownButtonFormField<int>(
              initialValue: _pageSize,
              isExpanded: true,
              decoration: InputDecoration(
                filled: true,
                fillColor: cs.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: cs.primary, width: 1.3),
                ),
              ),
              items: const [
                DropdownMenuItem(value: 7, child: Text('7 par page')),
                DropdownMenuItem(value: 10, child: Text('10 par page')),
                DropdownMenuItem(value: 20, child: Text('20 par page')),
                DropdownMenuItem(value: 50, child: Text('50 par page')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _pageSize = value;
                  _pageIndex = 0;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorPanel(BuildContext context) {
    final theme = Theme.of(context);
    return _SurfacePanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error, size: 34),
          const SizedBox(height: 12),
          Text(
            'Impossible de charger les utilisateurs',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Les données n’ont pas pu être récupérées. Vous pouvez relancer le chargement.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text(_error!, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _reload,
            icon: const Icon(Icons.refresh_outlined),
            label: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }

  Widget _buildPageTitle(BuildContext context, bool isContribuablesMode) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isContribuablesMode
              ? 'Gestion des contribuables'
              : 'Gestion des utilisateurs',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: theme.colorScheme.onSurface,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: 48,
          height: 3,
          decoration: BoxDecoration(
            color: AppColors.chartTeal,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final fill = isDark
        ? Color.alphaBlend(
            Colors.white.withValues(alpha: 0.03),
            cs.surfaceContainerHighest,
          )
        : Colors.white;

    return TextField(
      controller: _searchCtrl,
      style: TextStyle(color: cs.onSurface),
      decoration: InputDecoration(
        hintText: 'Rechercher...',
        hintStyle: TextStyle(color: cs.onSurfaceVariant),
        prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant),
        suffixIcon: _searchCtrl.text.isEmpty
            ? null
            : IconButton(
                onPressed: () => _searchCtrl.clear(),
                icon: Icon(Icons.close, color: cs.onSurfaceVariant),
              ),
        filled: true,
        fillColor: fill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: cs.primary, width: 1.3),
        ),
      ),
    );
  }

  Widget _buildFilterDropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    double width = 210,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final fill = isDark
        ? Color.alphaBlend(
            Colors.white.withValues(alpha: 0.03),
            cs.surfaceContainerHighest,
          )
        : Colors.white;

    return SizedBox(
      width: width,
      child: DropdownButtonFormField<T>(
        key: ValueKey('$label-$value'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: fill,
          labelStyle: TextStyle(color: cs.onSurfaceVariant),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: cs.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: cs.primary, width: 1.3),
          ),
        ),
        dropdownColor: cs.surface,
        style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildFilterBar(bool isContribuablesMode) {
    return _SurfacePanel(
      padding: const EdgeInsets.all(18),
      child: Wrap(
        spacing: 18,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(width: 276, child: _buildSearchField()),
          _buildFilterDropdown<AppRole?>(
            label: 'Rôle',
            value: _roleFilter,
            items: [
              const DropdownMenuItem<AppRole?>(
                value: null,
                child: Text('Tous les rôles'),
              ),
              for (final role
                  in isContribuablesMode
                      ? const <AppRole>[AppRole.contribuable]
                      : _mairieOperationalRoles)
                DropdownMenuItem<AppRole?>(
                  value: role,
                  child: Text(role.shortLabel),
                ),
            ],
            onChanged: (value) {
              setState(() {
                _roleFilter = value;
                _pageIndex = 0;
              });
            },
          ),
          _buildFilterDropdown<_UserStatusFilter>(
            label: 'Statut',
            value: _statusFilter,
            items: [
              for (final status in _UserStatusFilter.values)
                DropdownMenuItem(
                  value: status,
                  child: Text(_statusFilterLabel(status)),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _statusFilter = value;
                _pageIndex = 0;
              });
            },
          ),
          OutlinedButton.icon(
            onPressed: _exportingUsers
                ? null
                : () => _exportUsers(asPdf: false),
            icon: const Icon(Icons.table_view_outlined),
            label: const Text('Exporter Excel'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.chartTeal,
              side: BorderSide(
                color: AppColors.chartTeal.withValues(alpha: 0.7),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _exportingUsers ? null : () => _exportUsers(asPdf: true),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Exporter PDF'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.chartRed,
              side: BorderSide(
                color: AppColors.chartRed.withValues(alpha: 0.7),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          if (_activeFilterCount > 0)
            TextButton.icon(
              onPressed: _resetFilters,
              icon: const Icon(Icons.refresh_outlined),
              label: const Text('Réinitialiser'),
            ),
        ],
      ),
    );
  }

  Widget _buildAddButton(bool isContribuablesMode) {
    return Material(
      color: Colors.transparent,
      elevation: 18,
      shadowColor: AppColors.chartTeal.withValues(alpha: 0.38),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: isContribuablesMode
            ? _openCreateContribuableDialog
            : _openCreateDialog,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.chartTeal,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add, color: Colors.white, size: 26),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  isContribuablesMode
                      ? 'Ajouter un contribuable'
                      : 'Ajouter un utilisateur',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMetricCards(List<UserProfile> visibleProfiles) {
    final total = _profiles.length;
    final active = _profiles.where((profile) => !_isSuspended(profile)).length;
    final admins = _profiles
        .where((profile) => profile.hasRole(AppRole.adminProvincial))
        .length;
    final suspended = _profiles.length - active;
    List<double> trendFromCount(int value) {
      final normalized = value <= 0 ? 0.0 : value.toDouble();
      return List<double>.filled(7, normalized);
    }

    return [
      _UsersStatCard(
        title: 'Total utilisateurs',
        value: '$total',
        delta: '${visibleProfiles.length} affichés',
        icon: Icons.groups_2_outlined,
        color: AppColors.chartBlue,
        trendValues: trendFromCount(total),
      ),
      _UsersStatCard(
        title: 'Comptes actifs',
        value: '$active',
        delta: 'Comptes autorisés',
        icon: Icons.verified_user_outlined,
        color: AppColors.chartTeal,
        trendValues: trendFromCount(active),
      ),
      _UsersStatCard(
        title: 'Administrateurs',
        value: '$admins',
        delta: 'Accès complets',
        icon: Icons.workspace_premium_outlined,
        color: AppColors.chartPurple,
        trendValues: trendFromCount(admins),
      ),
      _UsersStatCard(
        title: 'Comptes suspendus',
        value: '$suspended',
        delta: suspended == 0 ? 'Aucun blocage' : 'À vérifier',
        icon: Icons.person_off_outlined,
        color: AppColors.chartOrange,
        trendValues: trendFromCount(suspended),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final visibleProfiles = _filteredProfiles;
    final isContribuablesMode =
        widget.mode == UsersManagementMode.contribuables;

    if (_loading) {
      return _buildStateScreen(context, const CircularProgressIndicator());
    }

    if (_error != null) {
      return _buildStateScreen(context, _buildErrorPanel(context));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final addButtonMaxWidth = (width - (width < 640 ? 32 : 76))
            .clamp(120.0, 320.0)
            .toDouble();

        final pageCount = visibleProfiles.isEmpty
            ? 1
            : (visibleProfiles.length / _pageSize).ceil();
        final pageIndex = _pageIndex.clamp(0, pageCount - 1).toInt();
        final pageProfiles = visibleProfiles
            .skip(pageIndex * _pageSize)
            .take(_pageSize)
            .toList();
        final metrics = _buildMetricCards(visibleProfiles);

        return Stack(
          children: [
            Container(
              decoration: _pageBackgroundDecoration(context),
              child: RefreshIndicator(
                onRefresh: _reload,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    width < 640 ? 16 : 24,
                    24,
                    width < 640 ? 16 : 24,
                    _canManageUsers ? 112 : 28,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1360),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildPageTitle(context, isContribuablesMode),
                          const SizedBox(height: 34),
                          _buildMetricGrid(width, metrics),
                          const SizedBox(height: 26),
                          _buildFilterBar(isContribuablesMode),
                          const SizedBox(height: 22),
                          _buildUsersTable(
                            context,
                            visibleProfiles,
                            pageProfiles,
                            currentUserId,
                            pageIndex,
                            pageCount,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_canManageUsers)
              Positioned(
                right: width < 640 ? 16 : 38,
                bottom: width < 640 ? 16 : 28,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: addButtonMaxWidth),
                  child: _buildAddButton(isContribuablesMode),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SurfacePanel extends StatelessWidget {
  const _SurfacePanel({
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.clipBehavior = Clip.none,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final surface = isDark
        ? Color.alphaBlend(Colors.white.withValues(alpha: 0.03), cs.surface)
        : cs.surface;
    final borderColor = isDark
        ? cs.outlineVariant.withValues(alpha: 0.42)
        : AppColors.border.withValues(alpha: 0.8);
    return Container(
      clipBehavior: clipBehavior,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.08),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _UsersStatCard extends StatelessWidget {
  const _UsersStatCard({
    required this.title,
    required this.value,
    required this.delta,
    required this.icon,
    required this.color,
    required this.trendValues,
  });

  final String title;
  final String value;
  final String delta;
  final IconData icon;
  final Color color;
  final List<double> trendValues;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return _SurfacePanel(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color.withValues(alpha: 0.92), color],
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 34),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  delta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 62,
            height: 34,
            child: CustomPaint(
              painter: _SparklinePainter(values: trendValues, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final range = maxValue - minValue == 0 ? 1 : maxValue - minValue;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * (i / (values.length - 1));
      final normalized = (values[i] - minValue) / range;
      final y = size.height - normalized * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.color != color;
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 136),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Icon(Icons.check_circle, size: 12, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 106),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Icon(Icons.check_circle, size: 12, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserActionButton extends StatelessWidget {
  const _UserActionButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
    this.loading = false,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 32,
        height: 32,
        child: IconButton(
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          iconSize: 18,
          style: IconButton.styleFrom(
            foregroundColor: enabled ? color : cs.onSurfaceVariant,
            backgroundColor: enabled
                ? color.withValues(alpha: 0.07)
                : cs.surfaceContainerHighest.withValues(alpha: 0.50),
            side: BorderSide(
              color: enabled
                  ? color.withValues(alpha: 0.28)
                  : cs.outlineVariant,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: loading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              : Icon(icon),
        ),
      ),
    );
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 36,
      height: 36,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.onSurface,
          padding: EdgeInsets.zero,
          side: BorderSide(color: cs.outlineVariant),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Icon(icon, size: 18),
      ),
    );
  }
}

class _PageNumberButton extends StatelessWidget {
  const _PageNumberButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 36,
      height: 36,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: selected ? AppColors.chartTeal : cs.surface,
          foregroundColor: selected ? Colors.white : cs.onSurface,
          side: BorderSide(
            color: selected ? AppColors.chartTeal : cs.outlineVariant,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _PageEllipsis extends StatelessWidget {
  const _PageEllipsis();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
        color: cs.surface,
      ),
      child: Text('...', style: TextStyle(color: cs.onSurface)),
    );
  }
}
