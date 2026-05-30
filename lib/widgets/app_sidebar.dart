import 'package:flutter/material.dart';

import '../branding/branding_scope.dart';
import '../models/app_section.dart';
import '../models/section_visibility.dart';
import '../models/user_profile.dart';
import 'app_logo.dart';
import 'profile_avatar.dart';

class AppSidebar extends StatefulWidget {
  const AppSidebar({
    super.key,
    required this.profile,
    required this.currentSection,
    required this.onSectionSelected,
  });

  final UserProfile profile;
  final AppSection currentSection;
  final ValueChanged<AppSection> onSectionSelected;

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  String _labelFor(AppSection section) {
    if (section == AppSection.apurement &&
        widget.profile.hasPersonalTaxIdentifier) {
      return 'Payer mes taxes';
    }
    return 'Apurement';
  }

  bool _isTaxationSection(AppSection section) =>
      section == AppSection.taxation ||
      section == AppSection.taxationList ||
      section == AppSection.taxationTaxpayers ||
      section == AppSection.taxationNomenclature;

  void _selectSection(AppSection section) {
    widget.onSectionSelected(section);
  }

  @override
  Widget build(BuildContext context) {
    final items = <(AppSection, IconData, String)>[
      (AppSection.dashboard, Icons.dashboard_outlined, 'Tableau de Bord'),
      (AppSection.ordonnancement, Icons.description_outlined, 'Ordonnancement'),
      (
        AppSection.apurement,
        Icons.fact_check_outlined,
        _labelFor(AppSection.apurement),
      ),
      (
        AppSection.recouvrement,
        Icons.notification_important_outlined,
        'Recouvrement',
      ),
      (AppSection.rapports, Icons.bar_chart_outlined, 'Rapports'),
      (AppSection.parametres, Icons.settings_outlined, 'Paramètres'),
    ];
    final visible = sectionsVisibleForRoles(widget.profile.roles).toSet();
    final showTaxation = visible.contains(AppSection.taxation);
    final showUsers = visible.contains(AppSection.utilisateurs);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF061A44), Color(0xFF0A2C6B), Color(0xFF061225)],
        ),
      ),
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
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  if (visible.contains(AppSection.dashboard))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: SidebarNavButton(
                        icon: Icons.dashboard_outlined,
                        label: 'Tableau de Bord',
                        isActive: widget.currentSection == AppSection.dashboard,
                        onTap: () => _selectSection(AppSection.dashboard),
                      ),
                    ),
                  if (showTaxation) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: SidebarNavButton(
                        icon: Icons.person_add_alt_1_outlined,
                        label: 'Taxation',
                        isActive: _isTaxationSection(widget.currentSection),
                        onTap: () => _selectSection(AppSection.taxation),
                      ),
                    ),
                  ],
                  for (final item in items)
                    if (item.$1 != AppSection.dashboard &&
                        visible.contains(item.$1))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: SidebarNavButton(
                          icon: item.$2,
                          label: item.$3,
                          isActive: widget.currentSection == item.$1,
                          onTap: () => _selectSection(item.$1),
                        ),
                      ),
                  if (showUsers) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: SidebarNavButton(
                        icon: Icons.group_outlined,
                        label: 'Utilisateurs',
                        isActive:
                            widget.currentSection == AppSection.utilisateurs,
                        onTap: () => _selectSection(AppSection.utilisateurs),
                      ),
                    ),
                  ],
                  if (visible.contains(AppSection.alertes))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: SidebarNavButton(
                        icon: Icons.warning_amber_outlined,
                        label: 'Alertes',
                        isActive: widget.currentSection == AppSection.alertes,
                        onTap: () => _selectSection(AppSection.alertes),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProfileAvatar(
                fullName: widget.profile.fullName,
                avatarUrl: widget.profile.avatarUrl,
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
                      widget.profile.fullName,
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
                      widget.profile.sidebarRoleLabel,
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
    this.compact = false,
    this.trailingIcon,
    this.trailingTurns = 0,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final bool compact;
  final IconData? trailingIcon;
  final double trailingTurns;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isActive
            ? Colors.white.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive
              ? Colors.white.withValues(alpha: 0.18)
              : Colors.transparent,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 12,
              vertical: compact ? 9 : 12,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isActive ? const Color(0xFF78B7FF) : Colors.white,
                  size: compact ? 20 : 24,
                ),
                SizedBox(width: compact ? 10 : 12),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (trailingIcon != null) ...[
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: trailingTurns,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: Icon(trailingIcon, color: Colors.white, size: 18),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
