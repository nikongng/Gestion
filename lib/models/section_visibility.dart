import 'app_role.dart';
import 'app_section.dart';

List<AppSection> sectionsVisibleForRole(AppRole role) {
  switch (role) {
    case AppRole.adminProvincial:
    case AppRole.ministreFinances:
    case AppRole.gouverneur:
      return AppSection.values
          .where((section) => section != AppSection.communes)
          .toList();
    case AppRole.bourgmestre:
      return [
        AppSection.dashboard,
        AppSection.taxation,
        AppSection.taxationList,
        AppSection.taxationTaxpayers,
        AppSection.taxationNomenclature,
        AppSection.ordonnancement,
        AppSection.apurement,
        AppSection.recouvrement,
        AppSection.rapports,
        AppSection.alertes,
        AppSection.parametres,
      ];
    case AppRole.agent:
      return [AppSection.recouvrement, AppSection.parametres];
    case AppRole.taxateur:
      return [AppSection.taxation, AppSection.parametres];
    case AppRole.ordonnateur:
      return [AppSection.ordonnancement, AppSection.parametres];
    case AppRole.apureur:
      return [AppSection.apurement, AppSection.parametres];
    case AppRole.contribuable:
      return [
        AppSection.dashboard,
        AppSection.apurement,
        AppSection.rapports,
        AppSection.parametres,
      ];
  }
}

List<AppSection> sectionsVisibleForRoles(Iterable<AppRole> roles) {
  final result = <AppSection>[];
  for (final role in roles) {
    for (final section in sectionsVisibleForRole(role)) {
      if (!result.contains(section)) result.add(section);
    }
  }
  return result;
}

bool isSectionVisible(AppRole role, AppSection section) =>
    sectionsVisibleForRole(role).contains(section);

bool isSectionVisibleForRoles(Iterable<AppRole> roles, AppSection section) =>
    sectionsVisibleForRoles(roles).contains(section);

AppSection defaultSectionForRole(AppRole role) => role == AppRole.agent
    ? AppSection.recouvrement
    : role == AppRole.apureur || role == AppRole.contribuable
    ? AppSection.apurement
    : role == AppRole.taxateur
    ? AppSection.taxation
    : role == AppRole.ordonnateur
    ? AppSection.ordonnancement
    : AppSection.dashboard;
