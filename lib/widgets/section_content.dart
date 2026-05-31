import 'package:flutter/material.dart';

import '../models/app_section.dart';
import '../models/user_profile.dart';
import '../screens/collecte_screen.dart';
import '../screens/alerts_screen.dart';
import '../screens/communes_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/ordonnancement_screen.dart';
import '../screens/placeholder_screen.dart';
import '../screens/rapports_screen.dart';
import '../screens/recouvrement_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/taxation_home_screen.dart';
import '../screens/taxation_list_screen.dart';
import '../screens/taxation_nomenclature_screen.dart';
import '../screens/taxation_taxpayers_screen.dart';
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
      case AppSection.taxation:
        return TaxationHomeScreen(profile: profile);
      case AppSection.taxationList:
        return TaxationListScreen(profile: profile);
      case AppSection.taxationTaxpayers:
        return TaxationTaxpayersScreen(profile: profile);
      case AppSection.taxationNomenclature:
        return const TaxationNomenclatureScreen();
      case AppSection.ordonnancement:
        return OrdonnancementScreen(profile: profile);
      case AppSection.apurement:
        return CollecteScreen(
          profile: profile,
          focusRecoveryControlOnOpen: focusRecoveryControlOnCollecte,
          onRecoveryControlOpened: onRecoveryControlOpened,
        );
      case AppSection.recouvrement:
        return RecouvrementScreen(profile: profile);
      case AppSection.communes:
        return CommunesScreen(profile: profile);
      case AppSection.rapports:
        return RapportsScreen(profile: profile);
      case AppSection.alertes:
        return AlertsScreen(profile: profile);
      case AppSection.utilisateurs:
      case AppSection.utilisateursAgents:
      case AppSection.utilisateursContribuables:
        if (!profile.isGlobalSupervisor) {
          return const PlaceholderScreen(title: 'Accès réservé');
        }
        return UsersManagementScreen(
          profile: profile,
          mode: section == AppSection.utilisateursContribuables
              ? UsersManagementMode.contribuables
              : UsersManagementMode.agents,
        );
      case AppSection.parametres:
        return SettingsScreen(
          profile: profile,
          onSectionSelected: onSectionSelected,
          onProfileChanged: onProfileChanged,
        );
    }
  }
}
