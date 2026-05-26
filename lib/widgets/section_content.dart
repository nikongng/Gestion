import 'package:flutter/material.dart';

import '../models/app_section.dart';
import '../models/user_profile.dart';
import '../screens/collecte_screen.dart';
import '../screens/alerts_screen.dart';
import '../screens/communes_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/perception_note_screen.dart';
import '../screens/placeholder_screen.dart';
import '../screens/rapports_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/users_management_screen.dart';

class SectionContent extends StatelessWidget {
  const SectionContent({
    super.key,
    required this.section,
    required this.profile,
    this.onSectionSelected,
    this.onProfileChanged,
    this.onOpenRecoveryControl,
    this.focusRecoveryControlOnCollecte = false,
    this.onRecoveryControlOpened,
  });

  final AppSection section;
  final UserProfile profile;
  final ValueChanged<AppSection>? onSectionSelected;
  final VoidCallback? onProfileChanged;
  final VoidCallback? onOpenRecoveryControl;
  final bool focusRecoveryControlOnCollecte;
  final VoidCallback? onRecoveryControlOpened;

  @override
  Widget build(BuildContext context) {
    switch (section) {
      case AppSection.dashboard:
        return DashboardScreen(
          profile: profile,
          onOpenSection: onSectionSelected,
          onOpenRecoveryControl: onOpenRecoveryControl,
        );
      case AppSection.collecte:
        return CollecteScreen(
          profile: profile,
          focusRecoveryControlOnOpen: focusRecoveryControlOnCollecte,
          onRecoveryControlOpened: onRecoveryControlOpened,
        );
      case AppSection.notePerception:
        return PerceptionNoteScreen(profile: profile);
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
