import 'package:flutter/material.dart';

import '../models/app_role.dart';
import '../models/user_profile.dart';
import '../services/gestia_data_service.dart';
import '../widgets/profile_avatar.dart';

/// Réservé à l’admin provincial : liste des comptes et création (Edge Function).
class UsersManagementScreen extends StatefulWidget {
  const UsersManagementScreen({super.key});

  @override
  State<UsersManagementScreen> createState() => _UsersManagementScreenState();
}

class _UsersManagementScreenState extends State<UsersManagementScreen> {
  List<UserProfile> _profiles = [];
  List<({String id, String name})> _communes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await GestiaDataService.fetchAllProfiles();
      final c = await GestiaDataService.fetchCommunes();
      if (!mounted) return;
      setState(() {
        _profiles = p;
        _communes = c;
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

  Future<void> _openCreateDialog() async {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    AppRole role = AppRole.agent;
    String? communeId = _communes.isNotEmpty ? _communes.first.id : null;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
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
                      decoration: const InputDecoration(labelText: 'Rôle'),
                      items: const [
                        DropdownMenuItem(
                          value: AppRole.bourgmestre,
                          child: Text('Bourgmestre'),
                        ),
                        DropdownMenuItem(
                          value: AppRole.agent,
                          child: Text('Agent'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setDialogState(() => role = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: communeId,
                      decoration: const InputDecoration(labelText: 'Commune'),
                      items: [
                        for (final co in _communes)
                          DropdownMenuItem(value: co.id, child: Text(co.name)),
                      ],
                      onChanged: _communes.isEmpty
                          ? null
                          : (v) => setDialogState(() => communeId = v),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'La création du compte appelle la fonction Edge '
                      '`create-staff-user` (clé service côté Supabase).',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Créer'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true || !mounted) return;
    if (communeId == null && role != AppRole.adminProvincial) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choisissez une commune.')),
      );
      return;
    }

    try {
      await GestiaDataService.createStaffUserViaEdgeFunction(
        email: emailCtrl.text.trim(),
        password: passCtrl.text,
        fullName: nameCtrl.text.trim(),
        role: role,
        communeId: communeId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Utilisateur créé. Il peut se connecter.')),
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(20),
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
                      FilledButton.icon(
                        onPressed: _openCreateDialog,
                        icon: const Icon(Icons.person_add_outlined),
                        label: const Text('Ajouter'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Seul l’admin provincial peut créer des bourgmestres et des agents '
                    'et leur attribuer e-mail et mot de passe.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final p = _profiles[i];
                return ListTile(
                  leading: ProfileAvatar(
                    fullName: p.fullName,
                    avatarUrl: p.avatarUrl,
                    radius: 20,
                  ),
                  title: Text(p.fullName),
                  subtitle: Text(
                    '${p.role.shortLabel}${p.communeName != null ? ' • ${p.communeName}' : ''}',
                  ),
                );
              },
              childCount: _profiles.length,
            ),
          ),
        ],
      ),
    );
  }
}
