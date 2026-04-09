import 'app_role.dart';
import 'app_section.dart';

List<AppSection> sectionsVisibleForRole(AppRole role) {
  switch (role) {
    case AppRole.adminProvincial:
      return AppSection.values.toList();
    case AppRole.bourgmestre:
      return [
        AppSection.dashboard,
        AppSection.collecte,
        AppSection.communes,
        AppSection.rapports,
        AppSection.alertes,
        AppSection.parametres,
      ];
    case AppRole.agent:
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
    role == AppRole.agent ? AppSection.collecte : AppSection.dashboard;
