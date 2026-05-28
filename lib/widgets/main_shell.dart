import 'package:flutter/material.dart';

import '../branding/branding_scope.dart';
import '../models/app_section.dart';
import '../models/section_visibility.dart';
import '../models/user_profile.dart';
import 'app_sidebar.dart';
import 'notification_bell_button.dart';
import 'section_content.dart';
import 'theme_mode_menu_button.dart';
import 'top_bar.dart';

class MainShell extends StatelessWidget {
  const MainShell({
    super.key,
    required this.profile,
    required this.currentSection,
    required this.onSectionSelected,
    required this.onLogout,
    this.onProfileChanged,
    this.onOpenRecoveryControl,
    this.focusRecoveryControlOnCollecte = false,
    this.onRecoveryControlOpened,
  });

  final UserProfile profile;
  final AppSection currentSection;
  final ValueChanged<AppSection> onSectionSelected;
  final VoidCallback onLogout;
  final VoidCallback? onProfileChanged;
  final VoidCallback? onOpenRecoveryControl;
  final bool focusRecoveryControlOnCollecte;
  final VoidCallback? onRecoveryControlOpened;

  List<AppSection> _mobileTabs() {
    final visible = sectionsVisibleForRole(profile.role).toSet();
    const order = [
      AppSection.dashboard,
      AppSection.taxation,
      AppSection.ordonnancement,
      AppSection.apurement,
      AppSection.recouvrement,
      AppSection.communes,
      AppSection.rapports,
    ];
    final list = order.where(visible.contains).toList();
    for (final section in visible) {
      if (!list.contains(section) && list.length < 4) {
        list.add(section);
      }
    }
    return list.take(4).toList();
  }

  int _mobileSelectedIndex(List<AppSection> tabs) {
    final selectedSection =
        currentSection == AppSection.taxationList ||
            currentSection == AppSection.taxationTaxpayers ||
            currentSection == AppSection.taxationNomenclature
        ? AppSection.taxation
        : currentSection;
    final index = tabs.indexOf(selectedSection);
    return index >= 0 ? index : 0;
  }

  static IconData _iconFor(AppSection section) {
    switch (section) {
      case AppSection.dashboard:
        return Icons.dashboard_outlined;
      case AppSection.taxation:
      case AppSection.taxationList:
      case AppSection.taxationTaxpayers:
      case AppSection.taxationNomenclature:
        return Icons.person_add_alt_1_outlined;
      case AppSection.ordonnancement:
        return Icons.description_outlined;
      case AppSection.apurement:
        return Icons.fact_check_outlined;
      case AppSection.recouvrement:
        return Icons.notification_important_outlined;
      case AppSection.communes:
        return Icons.location_city_outlined;
      case AppSection.rapports:
        return Icons.bar_chart_outlined;
      case AppSection.alertes:
        return Icons.warning_amber_outlined;
      case AppSection.utilisateurs:
      case AppSection.utilisateursAgents:
      case AppSection.utilisateursContribuables:
        return Icons.group_outlined;
      case AppSection.parametres:
        return Icons.settings_outlined;
    }
  }

  String _labelFor(AppSection section) {
    if (section == AppSection.apurement &&
        profile.role.hasPersonalTaxIdentifier) {
      return 'Payer mes taxes';
    }

    switch (section) {
      case AppSection.dashboard:
        return 'Tableau';
      case AppSection.taxation:
        return 'Taxation';
      case AppSection.taxationList:
        return 'Taxations';
      case AppSection.taxationTaxpayers:
        return 'Contribuables';
      case AppSection.taxationNomenclature:
        return 'Nomenclature';
      case AppSection.ordonnancement:
        return 'Ordre';
      case AppSection.apurement:
        return 'Apurement';
      case AppSection.recouvrement:
        return 'Recouvrement';
      case AppSection.communes:
        return 'Communes';
      case AppSection.rapports:
        return 'Rapports';
      case AppSection.alertes:
        return 'Alertes';
      case AppSection.utilisateurs:
        return 'Utilisateurs';
      case AppSection.utilisateursAgents:
        return 'Agents';
      case AppSection.utilisateursContribuables:
        return 'Contribuables';
      case AppSection.parametres:
        return 'Parametres';
    }
  }

  void _openAlerts() {
    onSectionSelected(AppSection.alertes);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 900;
        final body = SectionContent(
          section: currentSection,
          profile: profile,
          onSectionSelected: onSectionSelected,
          onProfileChanged: onProfileChanged,
          onOpenRecoveryControl: onOpenRecoveryControl,
          focusRecoveryControlOnCollecte: focusRecoveryControlOnCollecte,
          onRecoveryControlOpened: onRecoveryControlOpened,
        );
        final tabs = _mobileTabs();

        if (isMobile) {
          return Scaffold(
            appBar: AppBar(
              title: Text(BrandingScope.of(context).appName),
              actions: [
                NotificationBellButton(
                  profile: profile,
                  onOpenAlerts: _openAlerts,
                ),
                const ThemeModeMenuButton(),
                IconButton(onPressed: onLogout, icon: const Icon(Icons.logout)),
              ],
            ),
            drawer: Drawer(
              child: AppSidebar(
                profile: profile,
                currentSection: currentSection,
                onSectionSelected: (section) {
                  onSectionSelected(section);
                  Navigator.of(context).pop();
                },
              ),
            ),
            body: body,
            bottomNavigationBar: NavigationBar(
              selectedIndex: _mobileSelectedIndex(tabs),
              onDestinationSelected: (index) {
                onSectionSelected(tabs[index]);
              },
              destinations: [
                for (final section in tabs)
                  NavigationDestination(
                    icon: Icon(_iconFor(section)),
                    label: _labelFor(section),
                  ),
              ],
            ),
          );
        }

        return Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 260,
                child: AppSidebar(
                  profile: profile,
                  currentSection: currentSection,
                  onSectionSelected: onSectionSelected,
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    TopBar(
                      profile: profile,
                      onLogout: onLogout,
                      onOpenAlerts: _openAlerts,
                    ),
                    Expanded(child: body),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
