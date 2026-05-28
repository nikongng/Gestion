import 'package:flutter/material.dart';

import '../branding/branding_scope.dart';
import '../models/app_section.dart';
import '../models/section_visibility.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
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
  bool _isTaxationExpanded = false;
  bool _isUsersExpanded = false;

  String _labelFor(AppSection section) {
    if (section == AppSection.apurement &&
        widget.profile.role.hasPersonalTaxIdentifier) {
      return 'Payer mes taxes';
    }
    return 'Apurement';
  }

  bool _isTaxationSection(AppSection section) =>
      section == AppSection.taxation ||
      section == AppSection.taxationList ||
      section == AppSection.taxationTaxpayers ||
      section == AppSection.taxationNomenclature;

  bool _isUsersSection(AppSection section) =>
      section == AppSection.utilisateurs ||
      section == AppSection.utilisateursAgents ||
      section == AppSection.utilisateursContribuables;

  void _selectSection(AppSection section) {
    setState(() {
      _isTaxationExpanded = _isTaxationSection(section);
      _isUsersExpanded = _isUsersSection(section);
    });
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
      (AppSection.communes, Icons.location_city_outlined, 'Communes'),
      (AppSection.rapports, Icons.bar_chart_outlined, 'Rapports'),
      (AppSection.parametres, Icons.settings_outlined, 'Paramètres'),
    ];
    final taxationItems = <(AppSection, IconData, String)>[
      (AppSection.taxation, Icons.add_circle_outline, 'Nouvelle taxation'),
      (
        AppSection.taxationList,
        Icons.format_list_bulleted_outlined,
        'Liste des taxations',
      ),
      (AppSection.taxationTaxpayers, Icons.badge_outlined, 'Contribuables'),
      (
        AppSection.taxationNomenclature,
        Icons.library_books_outlined,
        'Nomenclature',
      ),
    ];

    final visible = sectionsVisibleForRole(widget.profile.role).toSet();
    final showTaxation = taxationItems.any((item) => visible.contains(item.$1));
    final usersItems = <(AppSection, IconData, String)>[
      (
        AppSection.utilisateursAgents,
        Icons.admin_panel_settings_outlined,
        'Agents',
      ),
      (
        AppSection.utilisateursContribuables,
        Icons.badge_outlined,
        'Contribuables',
      ),
    ];
    final showUsers =
        visible.contains(AppSection.utilisateurs) ||
        usersItems.any((item) => visible.contains(item.$1));

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
                        trailingIcon: Icons.expand_more,
                        trailingTurns: _isTaxationExpanded ? 0.5 : 0,
                        onTap: () {
                          setState(
                            () => _isTaxationExpanded = !_isTaxationExpanded,
                          );
                        },
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: _isTaxationExpanded
                          ? _SidebarSubmenu(
                              children: [
                                for (final item in taxationItems)
                                  if (visible.contains(item.$1))
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: SidebarNavButton(
                                        icon: item.$2,
                                        label: item.$3,
                                        isActive:
                                            widget.currentSection == item.$1,
                                        compact: true,
                                        onTap: () => _selectSection(item.$1),
                                      ),
                                    ),
                              ],
                            )
                          : const SizedBox(width: double.infinity),
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
                        isActive: _isUsersSection(widget.currentSection),
                        trailingIcon: Icons.expand_more,
                        trailingTurns: _isUsersExpanded ? 0.5 : 0,
                        onTap: () {
                          setState(() => _isUsersExpanded = !_isUsersExpanded);
                        },
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: _isUsersExpanded
                          ? _SidebarSubmenu(
                              children: [
                                for (final item in usersItems)
                                  if (visible.contains(item.$1) ||
                                      visible.contains(AppSection.utilisateurs))
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: SidebarNavButton(
                                        icon: item.$2,
                                        label: item.$3,
                                        isActive:
                                            widget.currentSection == item.$1,
                                        compact: true,
                                        onTap: () => _selectSection(item.$1),
                                      ),
                                    ),
                              ],
                            )
                          : const SizedBox(width: double.infinity),
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
    return Material(
      color: isActive
          ? AppColors.primary.withValues(alpha: 0.94)
          : Colors.transparent,
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
              Icon(icon, color: Colors.white, size: compact ? 20 : 24),
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
    );
  }
}

class _SidebarSubmenu extends StatelessWidget {
  const _SidebarSubmenu({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(left: 14, bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 2,
              height: (children.length * 46).toDouble(),
              margin: const EdgeInsets.only(left: 4, right: 10, top: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Expanded(child: Column(children: children)),
          ],
        ),
      ),
    );
  }
}
