import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_role.dart';
import '../models/user_profile.dart';
import '../services/gestia_data_service.dart';
import '../theme/app_colors.dart';
import '../widgets/metric_card.dart';
import '../widgets/modern_section_panel.dart';
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

  int get _activeFilterCount {
    var count = 0;
    if (_searchCtrl.text.trim().isNotEmpty) count++;
    if (_roleFilter != null) count++;
    if (_communeFilterValue != null) count++;
    if (_kindFilter != _UserKindFilter.all) count++;
    if (_sortMode != _UserSortMode.nameAsc) count++;
    return count;
  }

  int get _internalUsersCount =>
      _profiles.where((profile) => profile.role != AppRole.contribuable).length;

  int get _taxpayerUsersCount =>
      _profiles.where((profile) => profile.role == AppRole.contribuable).length;

  int get _coveredCommunesCount =>
      _profiles
          .where(
            (profile) =>
                profile.communeName != null && profile.communeName!.trim().isNotEmpty,
          )
          .map((profile) => profile.communeName!.trim().toLowerCase())
          .toSet()
          .length;

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
          final byRole = a.role.shortLabel
              .toLowerCase()
              .compareTo(b.role.shortLabel.toLowerCase());
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

    bool requiresCommune(AppRole currentRole) =>
        currentRole == AppRole.agent || currentRole == AppRole.bourgmestre;

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
                          'Creez ici un compte interne. Les comptes contribuables restent auto-inscrits.',
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
                          hintText: 'prenom.nom@gestia.cd',
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
                          labelText: 'Role',
                          border: OutlineInputBorder(),
                        ),
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
                        key: ValueKey(communeId ?? 'none'),
                        initialValue: communeId,
                        decoration: InputDecoration(
                          labelText: 'Commune',
                          border: const OutlineInputBorder(),
                          helperText: requiresCommune(role)
                              ? 'Obligatoire pour les agents et bourgmestres'
                              : 'Non necessaire pour ce role',
                        ),
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
                      if (dialogError != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          dialogError!,
                          style: TextStyle(color: cs.error),
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
                  icon: submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.person_add_alt_1_outlined),
                  label: Text(submitting ? 'Creation...' : 'Creer'),
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
        content: Text('Utilisateur cree. Il peut maintenant se connecter.'),
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
          'Le compte "${profile.fullName}" sera supprime definitivement.',
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
        SnackBar(content: Text('${profile.fullName} supprime.')),
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
    return parts.join(' - ');
  }

  String _scopeLabel() {
    if (widget.profile.role.canManageApp) {
      return 'Administration provinciale';
    }
    if (widget.profile.role.isGlobalSupervisor) {
      return 'Supervision globale';
    }
    return widget.profile.communeName ?? 'Commune courante';
  }

  String _kindLabel(_UserKindFilter filter) {
    switch (filter) {
      case _UserKindFilter.all:
        return 'Tous les comptes';
      case _UserKindFilter.internal:
        return 'Comptes internes';
      case _UserKindFilter.contribuable:
        return 'Contribuables';
    }
  }

  String _sortLabel(_UserSortMode mode) {
    switch (mode) {
      case _UserSortMode.nameAsc:
        return 'Nom A -> Z';
      case _UserSortMode.nameDesc:
        return 'Nom Z -> A';
      case _UserSortMode.roleAsc:
        return 'Par role';
      case _UserSortMode.communeAsc:
        return 'Par commune';
    }
  }

  Color _roleColor(AppRole role) {
    switch (role) {
      case AppRole.adminProvincial:
        return AppColors.primary;
      case AppRole.ministreFinances:
        return AppColors.chartPurple;
      case AppRole.gouverneur:
        return AppColors.chartOrange;
      case AppRole.bourgmestre:
        return AppColors.chartTeal;
      case AppRole.agent:
        return AppColors.chartBlue;
      case AppRole.contribuable:
        return const Color(0xFF9A7200);
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
                const Color(0xFF0B1220),
                Color.alphaBlend(
                  cs.primary.withValues(alpha: 0.08),
                  const Color(0xFF101A2D),
                ),
                Color.alphaBlend(
                  cs.secondary.withValues(alpha: 0.06),
                  const Color(0xFF0F1728),
                ),
              ]
            : [
                const Color(0xFFF7FAFF),
                const Color(0xFFF2F6FC),
                Color.alphaBlend(
                  cs.primary.withValues(alpha: 0.03),
                  const Color(0xFFF7FAFF),
                ),
              ],
      ),
    );
  }

  int _metricColumns(double width) {
    if (width >= 1280) return 4;
    if (width >= 840) return 2;
    return 1;
  }

  int _userGridColumns(double width) {
    if (width >= 1320) return 3;
    if (width >= 860) return 2;
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
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        mainAxisExtent: width < 520 ? 206 : 186,
      ),
      itemBuilder: (context, index) => cards[index],
    );
  }

  Widget _buildUserGrid(
    BuildContext context,
    double width,
    List<UserProfile> profiles,
    String? currentUserId,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : width;
        final columns = _userGridColumns(availableWidth);
        const spacing = 14.0;
        final itemWidth = columns == 1
            ? availableWidth
            : (availableWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final profile in profiles)
              SizedBox(
                width: itemWidth,
                child: _buildUserCard(context, profile, currentUserId),
              ),
          ],
        );
      },
    );
  }

  Widget _buildPill(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    BuildContext context, {
    required IconData icon,
    required String text,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUserCard(
    BuildContext context,
    UserProfile profile,
    String? currentUserId,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;
    final accent = _roleColor(profile.role);
    final isDeleting = _deletingUserId == profile.id;
    final isCurrentUser = profile.id == currentUserId;
    final isProtected = profile.role == AppRole.adminProvincial;
    final canDelete = _canManageUsers && !isProtected && !isCurrentUser;

    final scopeText = profile.communeName != null && profile.communeName!.isNotEmpty
        ? 'Rattache a ${profile.communeName}'
        : profile.role == AppRole.contribuable
            ? 'Compte sans rattachement communal'
            : 'Acces transversal';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            isDark
                ? Color.alphaBlend(
                    accent.withValues(alpha: 0.08),
                    cs.surface.withValues(alpha: 0.98),
                  )
                : Colors.white.withValues(alpha: 0.98),
            accent.withValues(alpha: isDark ? 0.12 : 0.06),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProfileAvatar(
                  fullName: profile.fullName,
                  avatarUrl: profile.avatarUrl,
                  radius: 23,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.fullName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _userSubtitle(profile),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildPill(
                  context,
                  icon: Icons.badge_outlined,
                  label: profile.role.shortLabel,
                  color: accent,
                ),
                _buildPill(
                  context,
                  icon: profile.role == AppRole.contribuable
                      ? Icons.receipt_long_outlined
                      : Icons.shield_outlined,
                  label: profile.role == AppRole.contribuable
                      ? 'Contribuable'
                      : 'Interne',
                  color: profile.role == AppRole.contribuable
                      ? const Color(0xFF9A7200)
                      : AppColors.chartTeal,
                ),
                if (isCurrentUser)
                  _buildPill(
                    context,
                    icon: Icons.person_outline,
                    label: 'Vous',
                    color: AppColors.primary,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _buildDetailRow(
              context,
              icon: Icons.location_city_outlined,
              text: scopeText,
            ),
            const SizedBox(height: 10),
            _buildDetailRow(
              context,
              icon: profile.taxpayerIdentifier != null
                  ? Icons.qr_code_2_outlined
                  : Icons.key_outlined,
              text: profile.taxpayerIdentifier != null &&
                      profile.taxpayerIdentifier!.isNotEmpty
                  ? 'Identifiant: ${profile.taxpayerIdentifier}'
                  : isProtected
                      ? 'Compte protege'
                      : canDelete
                          ? 'Suppression autorisee'
                          : 'Lecture seule',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    isProtected
                        ? 'Role critique protege'
                        : canDelete
                            ? 'Action rapide disponible'
                            : 'Aucune action destructive',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (canDelete)
                  IconButton(
                    onPressed: isDeleting ? null : () => _deleteUser(profile),
                    tooltip: 'Supprimer',
                    style: IconButton.styleFrom(
                      backgroundColor: cs.errorContainer.withValues(alpha: 0.72),
                      foregroundColor: cs.error,
                    ),
                    icon: isDeleting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_outline),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final visibleProfiles = _filteredProfiles;

    if (_loading) {
      return _buildStateScreen(
        context,
        const CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return _buildStateScreen(
        context,
        ModernSectionPanel(
          title: 'Impossible de charger les utilisateurs',
          subtitle:
              'Les donnees n ont pas pu etre recuperees. Vous pouvez relancer le chargement.',
          eyebrow: 'Etat',
          accentColor: AppColors.chartRed,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _reload,
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
        final width = constraints.maxWidth;

        final metrics = [
          MetricCard(
            title: 'Utilisateurs',
            value: '${_profiles.length}',
            subtitle: '${visibleProfiles.length} affiches actuellement',
            icon: Icons.group_outlined,
            accentColor: AppColors.primary,
            badge: _activeFilterCount == 0
                ? 'Vue complete'
                : '$_activeFilterCount filtre(s)',
            highlighted: true,
            numericValue: _profiles.length.toDouble(),
            animatedFormatter: (value) => value.toStringAsFixed(0),
          ),
          MetricCard(
            title: 'Comptes internes',
            value: '$_internalUsersCount',
            subtitle: 'Equipes administratives et terrain',
            icon: Icons.admin_panel_settings_outlined,
            accentColor: AppColors.chartTeal,
            numericValue: _internalUsersCount.toDouble(),
            animatedFormatter: (value) => value.toStringAsFixed(0),
          ),
          MetricCard(
            title: 'Contribuables',
            value: '$_taxpayerUsersCount',
            subtitle: 'Comptes autonomes de paiement',
            icon: Icons.badge_outlined,
            accentColor: AppColors.chartOrange,
            numericValue: _taxpayerUsersCount.toDouble(),
            animatedFormatter: (value) => value.toStringAsFixed(0),
          ),
          MetricCard(
            title: 'Communes couvertes',
            value: '$_coveredCommunesCount',
            subtitle: 'Territoires rattaches a au moins un compte',
            icon: Icons.location_city_outlined,
            accentColor: AppColors.chartPurple,
            numericValue: _coveredCommunesCount.toDouble(),
            animatedFormatter: (value) => value.toStringAsFixed(0),
          ),
        ];

        return Container(
          decoration: _pageBackgroundDecoration(context),
          child: RefreshIndicator(
            onRefresh: _reload,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1360),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ModernSectionPanel(
                        title: 'Gestion des utilisateurs',
                        subtitle: _canManageUsers
                            ? 'Visualisez rapidement vos comptes, filtrez les profils et creez les utilisateurs internes depuis un espace plus clair.'
                            : 'Vous etes en lecture seule. Utilisez la recherche et les filtres pour retrouver un profil sans modifier les comptes.',
                        eyebrow: 'Administration',
                        accentColor: AppColors.primary,
                        action: _canManageUsers
                            ? FilledButton.icon(
                                onPressed: _openCreateDialog,
                                icon: const Icon(Icons.person_add_alt_1_outlined),
                                label: const Text('Ajouter un utilisateur'),
                              )
                            : null,
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            ModernInfoPill(
                              label: 'Acces',
                              value: _canManageUsers
                                  ? 'Administration complete'
                                  : 'Lecture seule',
                              icon: _canManageUsers
                                  ? Icons.verified_user_outlined
                                  : Icons.visibility_outlined,
                              color: AppColors.primary,
                            ),
                            ModernInfoPill(
                              label: 'Portee',
                              value: _scopeLabel(),
                              icon: Icons.public_outlined,
                              color: AppColors.chartTeal,
                            ),
                            ModernInfoPill(
                              label: 'Resultats',
                              value:
                                  '${visibleProfiles.length} sur ${_profiles.length}',
                              icon: Icons.filter_alt_outlined,
                              color: AppColors.chartOrange,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildMetricGrid(width, metrics),
                      const SizedBox(height: 18),
                      ModernSectionPanel(
                        title: 'Recherche et filtres',
                        subtitle:
                            'Combinez texte libre, type de compte, role, commune et tri pour cibler rapidement la bonne personne.',
                        eyebrow: 'Exploration',
                        accentColor: AppColors.chartTeal,
                        action: OutlinedButton.icon(
                          onPressed: _activeFilterCount == 0 ? null : _resetFilters,
                          icon: const Icon(Icons.refresh_outlined),
                          label: const Text('Reinitialiser'),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                ModernInfoPill(
                                  label: 'Filtres actifs',
                                  value: _activeFilterCount == 0
                                      ? 'Aucun'
                                      : '$_activeFilterCount',
                                  icon: Icons.tune_outlined,
                                  color: AppColors.chartPurple,
                                ),
                                ModernInfoPill(
                                  label: 'Comptes visibles',
                                  value: '${visibleProfiles.length}',
                                  icon: Icons.grid_view_outlined,
                                  color: AppColors.primary,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                SizedBox(
                                  width: 320,
                                  child: TextField(
                                    controller: _searchCtrl,
                                    decoration: InputDecoration(
                                      labelText: 'Recherche',
                                      hintText: 'Nom, role, commune, identifiant...',
                                      border: const OutlineInputBorder(),
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
                                    key: ValueKey(_kindFilter),
                                    initialValue: _kindFilter,
                                    decoration: const InputDecoration(
                                      labelText: 'Type de compte',
                                      border: OutlineInputBorder(),
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
                                    key: ValueKey(_roleFilter?.dbValue ?? 'all'),
                                    initialValue: _roleFilter,
                                    decoration: const InputDecoration(
                                      labelText: 'Role',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: [
                                      const DropdownMenuItem<AppRole?>(
                                        value: null,
                                        child: Text('Tous les roles'),
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
                                    key: ValueKey(_communeFilterValue ?? 'all'),
                                    initialValue: _communeFilterValue,
                                    decoration: const InputDecoration(
                                      labelText: 'Commune',
                                      border: OutlineInputBorder(),
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
                                    key: ValueKey(_sortMode),
                                    initialValue: _sortMode,
                                    decoration: const InputDecoration(
                                      labelText: 'Tri',
                                      border: OutlineInputBorder(),
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
                      const SizedBox(height: 18),
                      ModernSectionPanel(
                        title: 'Annuaire actif',
                        subtitle: visibleProfiles.isEmpty
                            ? 'Aucun utilisateur ne correspond aux filtres actuels.'
                            : '${visibleProfiles.length} profil(s) affiches dans cette vue. Les cartes mettent en avant le role, la portee et les actions rapides.',
                        eyebrow: 'Resultats',
                        accentColor: AppColors.chartOrange,
                        child: visibleProfiles.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 18,
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.search_off_outlined,
                                        size: 42,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Aucun utilisateur ne correspond aux filtres actuels.',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : _buildUserGrid(
                                context,
                                width,
                                visibleProfiles,
                                currentUserId,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
