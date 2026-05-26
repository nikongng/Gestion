import 'package:flutter/material.dart';

import '../branding/branding_scope.dart';
import '../models/app_section.dart';
import '../models/section_visibility.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import 'app_logo.dart';
import 'profile_avatar.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.profile,
    required this.currentSection,
    required this.onSectionSelected,
  });

  final UserProfile profile;
  final AppSection currentSection;
  final ValueChanged<AppSection> onSectionSelected;

  String _labelFor(AppSection section) {
    if (section == AppSection.collecte &&
        profile.role.hasPersonalTaxIdentifier) {
      return 'Payer mes taxes';
    }
    return 'Collecte';
  }

  @override
  Widget build(BuildContext context) {
    final items = <(AppSection, IconData, String)>[
      (AppSection.dashboard, Icons.dashboard_outlined, 'Tableau de Bord'),
      (
        AppSection.collecte,
        Icons.point_of_sale_outlined,
        _labelFor(AppSection.collecte),
      ),
      (
        AppSection.notePerception,
        Icons.description_outlined,
        'Etablir une note',
      ),
      (AppSection.communes, Icons.location_city_outlined, 'Communes'),
      (AppSection.rapports, Icons.bar_chart_outlined, 'Rapports'),
      (AppSection.alertes, Icons.warning_amber_outlined, 'Alertes'),
      (AppSection.utilisateurs, Icons.group_outlined, 'Utilisateurs'),
      (AppSection.parametres, Icons.settings_outlined, 'Paramètres'),
    ];

    final visible = sectionsVisibleForRole(profile.role).toSet();

    return Container(
      color: AppColors.sidebar,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: [
                const AppLogo(size: 32, radius: 9, padding: 2),
                const SizedBox(width: 8),
                Text(
                  BrandingScope.of(context).appName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final item in items)
            if (visible.contains(item.$1))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: SidebarNavButton(
                  icon: item.$2,
                  label: item.$3,
                  isActive: currentSection == item.$1,
                  onTap: () => onSectionSelected(item.$1),
                ),
              ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProfileAvatar(
                fullName: profile.fullName,
                avatarUrl: profile.avatarUrl,
                radius: 22,
                backgroundColor: const Color(0xFF2A4A40),
                initialsColor: Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.fullName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile.sidebarRoleLabel,
                      style: const TextStyle(
                        color: Color(0xFFE0C48C),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            BrandingScope.of(context).provinceName,
            style: const TextStyle(color: Color(0xFFA8B8AE), fontSize: 11),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class SidebarNavButton extends StatelessWidget {
  const SidebarNavButton({
    super.key,
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive
          ? AppColors.primary.withValues(alpha: 0.94)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
