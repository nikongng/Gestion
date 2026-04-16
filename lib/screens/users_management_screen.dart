import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_role.dart';
import '../models/user_profile.dart';
import '../services/gestia_data_service.dart';
import '../widgets/profile_avatar.dart';

enum _UserKindFilter { all, internal, contribuable }

enum _UserSortMode { nameAsc, nameDesc, roleAsc, communeAsc }

class UsersManagementScreen extends StatefulWidget {
  const UsersManagementScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<UsersManagementScreen> createState() => _UsersManagementScreenState();
}

class _UsersManagementScreenState extends State<UsersManagementScreen> {
  static const _noCommuneValue = '__no_commune__';

  final _searchCtrl = TextEditingController();

  List<UserProfile> _profiles = [];
  List<({String id, String name})> _communes = [];
  bool _loading = true;
  String? _deletingUserId;
  String? _error;

  AppRole? _roleFilter;
  String? _communeFilterValue;
  _UserKindFilter _kindFilter = _UserKindFilter.all;
  _UserSortMode _sortMode = _UserSortMode.nameAsc;

  bool get _canManageUsers => widget.profile.role.canManageApp;

  List<UserProfile> get _filteredProfiles {
    final query = _searchCtrl.text.trim().toLowerCase();

    final list = _profiles.where((profile) {
      final matchesQuery =
          query.isEmpty || _matchesProfileQuery(profile, query);
      final matchesRole = _roleFilter == null || profile.role == _roleFilter;
      final matchesKind = switch (_kindFilter) {
        _UserKindFilter.all => true,
        _UserKindFilter.internal => profile.role != AppRole.contribuable,
        _UserKindFilter.contribuable => profile.role == AppRole.contribuable,
      };

      final matchesCommune = switch (_communeFilterValue) {
        null => true,
        _noCommuneValue => profile.communeId == null,
        final communeId => profile.communeId == communeId,
      };

      return matchesQuery && matchesRole && matchesKind && matchesCommune;
    }).toList();

    list.sort((a, b) {
      switch (_sortMode) {
        case _UserSortMode.nameAsc:
          return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
        case _UserSortMode.nameDesc:
          return b.fullName.toLowerCase().compareTo(a.fullName.toLowerCase());
        case _UserSortMode.roleAsc:
          final byRole =
              a.role.shortLabel.toLowerCase().compareTo(b.role.shortLabel.toLowerCase());
          if (byRole != 0) return byRole;
          return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
        case _UserSortMode.communeAsc:
          final aCommune = a.communeName ?? 'zzz';
          final bCommune = b.communeName ?? 'zzz';
          final byCommune =
              aCommune.toLowerCase().compareTo(bCommune.toLowerCase());
          if (byCommune != 0) return byCommune;
          return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
      }
    });

    return list;
  }

  @override
  void initState() {
    super.initState();
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
    setState(() {});
  }

  bool _matchesProfileQuery(UserProfile profile, String query) {
    final parts = [
      profile.fullName,
      profile.role.shortLabel,
      profile.communeName,
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
      final communes = await GestiaDataService.fetchCommunes();
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _communes = communes;
        if (_communeFilterValue != null &&
            _communeFilterValue != _noCommuneValue &&
            !_communes.any((commune) => commune.id == _communeFilterValue)) {
          _communeFilterValue = null;
        }
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

  void _resetFilters() {
    setState(() {
      _searchCtrl.clear();
      _roleFilter = null;
      _communeFilterValue = null;
      _kindFilter = _UserKindFilter.all;
      _sortMode = _UserSortMode.nameAsc;
    });
  }

  Future<void> _openCreateDialog() async {
    if (!_canManageUsers) return;
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    AppRole role = AppRole.agent;
    String? communeId = _communes.isNotEmpty ? _communes.first.id : null;
    bool requiresCommune(AppRole r) =>
        r == AppRole.agent || r == AppRole.bourgmestre;

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        var submitting = false;
        String? dialogError;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Nouvel utilisateur'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nom complet',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailCtrl,
                      decoration: const InputDecoration(
                        labelText: 'E-mail (identifiant)',
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Mot de passe initial',
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<AppRole>(
                      initialValue: role,
                      decoration: const InputDecoration(labelText: 'Role'),
                      items: const [
                        DropdownMenuItem(
                          value: AppRole.ministreFinances,
                          child: Text('Ministre des finances'),
                        ),
                        DropdownMenuItem(
                          value: AppRole.gouverneur,
                          child: Text('Gouverneur'),
                        ),
                        DropdownMenuItem(
                          value: AppRole.bourgmestre,
                          child: Text('Bourgmestre'),
                        ),
                        DropdownMenuItem(
                          value: AppRole.agent,
                          child: Text('Agent'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          role = value;
                          if (requiresCommune(role)) {
                            communeId ??=
                                _communes.isNotEmpty ? _communes.first.id : null;
                          } else {
                            communeId = null;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: communeId,
                      decoration: const InputDecoration(labelText: 'Commune'),
                      items: [
                        for (final commune in _communes)
                          DropdownMenuItem(
                            value: commune.id,
                            child: Text(commune.name),
                          ),
                      ],
                      onChanged: _communes.isEmpty || !requiresCommune(role)
                          ? null
                          : (value) => setDialogState(() => communeId = value),
                    ),
                    const SizedBox(height: 8),
                    if (dialogError != null) ...[
                      const SizedBox(height: 6),
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
                FilledButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          final email = emailCtrl.text.trim();
                          final password = passCtrl.text;
                          final fullName = nameCtrl.text.trim();
                          if (fullName.isEmpty || email.isEmpty || password.isEmpty) {
                            setDialogState(() {
                              dialogError = 'Nom, e-mail et mot de passe requis.';
                            });
                            return;
                          }
                          if (communeId == null && requiresCommune(role)) {
                            setDialogState(() {
                              dialogError = 'Choisissez une commune.';
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
                              communeId: communeId,
                            );
                            if (!context.mounted) return;
                            Navigator.pop(ctx, true);
                          } catch (e) {
                            setDialogState(() {
                              submitting = false;
                              dialogError = 'Erreur : $e';
                            });
                          }
                        },
                  child: submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Créer'),
                ),
              ],
            );
          },
        );
      },
    );

    if (created != true || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Utilisateur créé. Il peut se connecter.'),
      ),
    );
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
      await GestiaDataService.deleteStaffUserViaEdgeFunction(userId: profile.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${profile.fullName} supprimé.')),
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    } finally {
      if (mounted && _deletingUserId == profile.id) {
        setState(() => _deletingUserId = null);
      }
    }
  }

  String _userSubtitle(UserProfile profile) {
    final parts = <String>[profile.role.shortLabel];
    if (profile.communeName != null && profile.communeName!.isNotEmpty) {
      parts.add(profile.communeName!);
    }
    if (profile.taxpayerIdentifier != null &&
        profile.taxpayerIdentifier!.isNotEmpty) {
      parts.add('ID ${profile.taxpayerIdentifier!}');
    }
    return parts.join(' • ');
  }

  String _kindLabel(_UserKindFilter filter) {
    switch (filter) {
      case _UserKindFilter.all:
        return 'Tous les comptes';
      case _UserKindFilter.internal:
        return 'Internes';
      case _UserKindFilter.contribuable:
        return 'Contribuables';
    }
  }

  String _sortLabel(_UserSortMode mode) {
    switch (mode) {
      case _UserSortMode.nameAsc:
        return 'Nom A → Z';
      case _UserSortMode.nameDesc:
        return 'Nom Z → A';
      case _UserSortMode.roleAsc:
        return 'Par rôle';
      case _UserSortMode.communeAsc:
        return 'Par commune';
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final visibleProfiles = _filteredProfiles;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _reload, child: const Text('Réessayer')),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Utilisateurs',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (_canManageUsers)
                        FilledButton.icon(
                          onPressed: _openCreateDialog,
                          icon: const Icon(Icons.person_add_outlined),
                          label: const Text('Ajouter'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _canManageUsers
                        ? 'Seul l’admin provincial peut créer, modifier et supprimer les utilisateurs internes. Les contribuables créent eux-mêmes leur compte.'
                        : 'Lecture seule. Utilisez les filtres pour retrouver rapidement un utilisateur.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Filtres avancés',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: _resetFilters,
                                icon: const Icon(Icons.refresh_outlined),
                                label: const Text('Réinitialiser'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${visibleProfiles.length} résultat(s) sur ${_profiles.length} utilisateur(s).',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              SizedBox(
                                width: 280,
                                child: TextField(
                                  controller: _searchCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'Recherche',
                                    hintText: 'Nom, rôle, commune, ID...',
                                    prefixIcon: const Icon(Icons.search),
                                    suffixIcon: _searchCtrl.text.isEmpty
                                        ? null
                                        : IconButton(
                                            onPressed: () => _searchCtrl.clear(),
                                            icon: const Icon(Icons.close),
                                          ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 220,
                                child: DropdownButtonFormField<_UserKindFilter>(
                                  value: _kindFilter,
                                  decoration: const InputDecoration(
                                    labelText: 'Type de compte',
                                  ),
                                  items: _UserKindFilter.values
                                      .map(
                                        (filter) => DropdownMenuItem(
                                          value: filter,
                                          child: Text(_kindLabel(filter)),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setState(() => _kindFilter = value);
                                  },
                                ),
                              ),
                              SizedBox(
                                width: 220,
                                child: DropdownButtonFormField<AppRole?>(
                                  value: _roleFilter,
                                  decoration: const InputDecoration(
                                    labelText: 'Role',
                                  ),
                                  items: [
                                    const DropdownMenuItem<AppRole?>(
                                      value: null,
                                      child: Text('Tous les rôles'),
                                    ),
                                    for (final role in AppRole.values)
                                      DropdownMenuItem<AppRole?>(
                                        value: role,
                                        child: Text(role.shortLabel),
                                      ),
                                  ],
                                  onChanged: (value) {
                                    setState(() => _roleFilter = value);
                                  },
                                ),
                              ),
                              SizedBox(
                                width: 220,
                                child: DropdownButtonFormField<String?>(
                                  value: _communeFilterValue,
                                  decoration: const InputDecoration(
                                    labelText: 'Commune',
                                  ),
                                  items: [
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('Toutes les communes'),
                                    ),
                                    const DropdownMenuItem<String?>(
                                      value: _noCommuneValue,
                                      child: Text('Sans commune'),
                                    ),
                                    for (final commune in _communes)
                                      DropdownMenuItem<String?>(
                                        value: commune.id,
                                        child: Text(commune.name),
                                      ),
                                  ],
                                  onChanged: (value) {
                                    setState(() => _communeFilterValue = value);
                                  },
                                ),
                              ),
                              SizedBox(
                                width: 220,
                                child: DropdownButtonFormField<_UserSortMode>(
                                  value: _sortMode,
                                  decoration: const InputDecoration(
                                    labelText: 'Tri',
                                  ),
                                  items: _UserSortMode.values
                                      .map(
                                        (mode) => DropdownMenuItem(
                                          value: mode,
                                          child: Text(_sortLabel(mode)),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setState(() => _sortMode = value);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (visibleProfiles.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Aucun utilisateur ne correspond aux filtres actuels.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final profile = visibleProfiles[index];
                    final isDeleting = _deletingUserId == profile.id;
                    final canDelete = _canManageUsers &&
                        profile.role != AppRole.adminProvincial &&
                        profile.id != currentUserId;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        elevation: 0,
                        child: ListTile(
                          leading: ProfileAvatar(
                            fullName: profile.fullName,
                            avatarUrl: profile.avatarUrl,
                            radius: 20,
                          ),
                          title: Text(profile.fullName),
                          subtitle: Text(_userSubtitle(profile)),
                          trailing: canDelete
                              ? IconButton(
                                  onPressed:
                                      isDeleting ? null : () => _deleteUser(profile),
                                  tooltip: 'Supprimer',
                                  icon: isDeleting
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Icon(
                                          Icons.delete_outline,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                        ),
                                )
                              : null,
                        ),
                      ),
                    );
                  },
                  childCount: visibleProfiles.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
