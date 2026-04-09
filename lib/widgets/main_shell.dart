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
  });

  final UserProfile profile;
  final AppSection currentSection;
  final ValueChanged<AppSection> onSectionSelected;
  final VoidCallback onLogout;
  final VoidCallback? onProfileChanged;

  List<AppSection> _mobileTabs() {
    final visible = sectionsVisibleForRole(profile.role).toSet();
    const order = [
      AppSection.dashboard,
      AppSection.collecte,
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
    final index = tabs.indexOf(currentSection);
    return index >= 0 ? index : 0;
  }

  static IconData _iconFor(AppSection section) {
    switch (section) {
      case AppSection.dashboard:
        return Icons.dashboard_outlined;
      case AppSection.collecte:
        return Icons.payments_outlined;
      case AppSection.communes:
        return Icons.location_city_outlined;
      case AppSection.rapports:
        return Icons.bar_chart_outlined;
      case AppSection.alertes:
        return Icons.warning_amber_outlined;
      case AppSection.utilisateurs:
        return Icons.group_outlined;
      case AppSection.parametres:
        return Icons.settings_outlined;
    }
  }

  static String _labelFor(AppSection section) {
    switch (section) {
      case AppSection.dashboard:
        return 'Tableau';
      case AppSection.collecte:
        return 'Collecte';
      case AppSection.communes:
        return 'Communes';
      case AppSection.rapports:
        return 'Rapports';
      case AppSection.alertes:
        return 'Alertes';
      case AppSection.utilisateurs:
        return 'Utilisateurs';
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
          onProfileChanged: onProfileChanged,
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
                IconButton(
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout),
                ),
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
