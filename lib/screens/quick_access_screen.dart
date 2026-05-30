import 'package:flutter/material.dart';

import '../branding/branding_scope.dart';
import '../models/app_role.dart';
import '../theme/app_colors.dart';
import '../widgets/app_logo.dart';
import '../widgets/theme_mode_menu_button.dart';

class QuickAccessScreen extends StatelessWidget {
  const QuickAccessScreen({super.key, required this.onSelectAccountType});

  final ValueChanged<AppRole> onSelectAccountType;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 600;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _MeshBackground(brightness: Theme.of(context).brightness),
          SafeArea(
            child: Column(
              children: [
                const _TopBrandBar(),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: isWide ? 32 : 20,
                        vertical: 16,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _IntroPanel(),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              onPressed: () => _openAccountTypeSheet(context),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 18,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: const Icon(Icons.manage_accounts_outlined),
                              label: const Text(
                                'Selectionner le type de compte',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            _FooterNote(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openAccountTypeSheet(BuildContext context) {
    final options = <({AppRole role, IconData icon, String label})>[
      (
        role: AppRole.adminProvincial,
        icon: Icons.admin_panel_settings_outlined,
        label: AppRole.adminProvincial.shortLabel,
      ),
      (
        role: AppRole.taxateur,
        icon: Icons.person_search_outlined,
        label: 'Taxateur',
      ),
      (
        role: AppRole.ordonnateur,
        icon: Icons.receipt_long_outlined,
        label: 'Liquidateur (ordonnateur)',
      ),
      (
        role: AppRole.apureur,
        icon: Icons.fact_check_outlined,
        label: 'Apureur',
      ),
      (
        role: AppRole.agent,
        icon: Icons.notification_important_outlined,
        label: 'Agent de recouvrement',
      ),
    ];

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            itemCount: options.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final option = options[index];
              return ListTile(
                leading: Icon(option.icon, color: AppColors.primary),
                title: Text(
                  option.label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                trailing: const Icon(Icons.chevron_right),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onSelectAccountType(option.role);
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _TopBrandBar extends StatelessWidget {
  const _TopBrandBar();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        children: [
          AppLogo(size: 42, radius: 14, padding: 2),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  BrandingScope.of(context).appName.toUpperCase(),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  'Gestion des recettes',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          ThemeModeMenuButton(iconColor: cs.onSurface),
        ],
      ),
    );
  }
}

class _IntroPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: cs.outline.withValues(alpha: isDark ? 0.35 : 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              const Spacer(),
              Icon(
                Icons.verified_user_outlined,
                size: 20,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppLogo(size: 200, radius: 30, padding: 4),
          const SizedBox(height: 18),
          Text(
            'Bienvenue',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Système de gestion des recettes '
            '${BrandingScope.of(context).appName}.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_outline_rounded, size: 15, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            'Connexion chiffrée - ${BrandingScope.of(context).provinceName}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _MeshBackground extends StatelessWidget {
  const _MeshBackground({required this.brightness});

  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final isDark = brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF070B12), Color(0xFF0B1220)]
              : const [Color(0xFFF8FAFC), Color(0xFFEEF2FF)],
        ),
      ),
    );
  }
}
