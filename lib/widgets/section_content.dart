import 'package:flutter/material.dart';

import '../models/app_role.dart';
import '../models/app_section.dart';
import '../models/user_profile.dart';
import '../screens/collecte_screen.dart';
import '../screens/alerts_screen.dart';
import '../screens/communes_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/placeholder_screen.dart';
import '../screens/rapports_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/users_management_screen.dart';

class SectionContent extends StatelessWidget {
  const SectionContent({
    super.key,
    required this.section,
    required this.profile,
    this.onProfileChanged,
  });

  final AppSection section;
  final UserProfile profile;
  final VoidCallback? onProfileChanged;

  @override
  Widget build(BuildContext context) {
    switch (section) {
      case AppSection.dashboard:
        return DashboardScreen(profile: profile);
      case AppSection.collecte:
        return CollecteScreen(profile: profile);
      case AppSection.communes:
        return CommunesScreen(profile: profile);
      case AppSection.rapports:
        return RapportsScreen(profile: profile);
      case AppSection.alertes:
        return AlertsScreen(profile: profile);
      case AppSection.utilisateurs:
        if (!profile.role.isGlobalSupervisor) {
          return const PlaceholderScreen(title: 'Accès réservé');
        }
        return UsersManagementScreen(profile: profile);
      case AppSection.parametres:
        return SettingsScreen(
          profile: profile,
          onProfileChanged: onProfileChanged,
        );
      default:
        return PlaceholderScreen(title: _title(section));
    }
  }

  String _title(AppSection section) {
    switch (section) {
      default:
        return '';
    }
  }
}
