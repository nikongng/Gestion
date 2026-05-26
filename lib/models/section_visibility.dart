import 'app_role.dart';
import 'app_section.dart';

List<AppSection> sectionsVisibleForRole(AppRole role) {
  switch (role) {
    case AppRole.adminProvincial:
    case AppRole.ministreFinances:
    case AppRole.gouverneur:
      return AppSection.values.toList();
    case AppRole.bourgmestre:
      return [
        AppSection.dashboard,
        AppSection.collecte,
        AppSection.notePerception,
        AppSection.communes,
        AppSection.rapports,
        AppSection.alertes,
        AppSection.parametres,
      ];
    case AppRole.agent:
      return [
        AppSection.dashboard,
        AppSection.collecte,
        AppSection.notePerception,
        AppSection.rapports,
        AppSection.parametres,
      ];
    case AppRole.contribuable:
      return [
        AppSection.dashboard,
        AppSection.collecte,
        AppSection.rapports,
        AppSection.parametres,
      ];
  }
}

bool isSectionVisible(AppRole role, AppSection section) =>
    sectionsVisibleForRole(role).contains(section);

AppSection defaultSectionForRole(AppRole role) =>
    role == AppRole.agent || role == AppRole.contribuable
    ? AppSection.collecte
    : AppSection.dashboard;
