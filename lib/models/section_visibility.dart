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
        AppSection.taxation,
        AppSection.taxationList,
        AppSection.taxationTaxpayers,
        AppSection.taxationNomenclature,
        AppSection.ordonnancement,
        AppSection.apurement,
        AppSection.recouvrement,
        AppSection.communes,
        AppSection.rapports,
        AppSection.alertes,
        AppSection.parametres,
      ];
    case AppRole.agent:
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
        AppSection.parametres,
      ];
    case AppRole.taxateur:
      return [
        AppSection.dashboard,
        AppSection.taxation,
        AppSection.taxationList,
        AppSection.taxationTaxpayers,
        AppSection.taxationNomenclature,
        AppSection.rapports,
        AppSection.parametres,
      ];
    case AppRole.ordonnateur:
      return [
        AppSection.dashboard,
        AppSection.ordonnancement,
        AppSection.rapports,
        AppSection.parametres,
      ];
    case AppRole.apureur:
      return [
        AppSection.dashboard,
        AppSection.apurement,
        AppSection.rapports,
        AppSection.parametres,
      ];
    case AppRole.contribuable:
      return [
        AppSection.dashboard,
        AppSection.apurement,
        AppSection.rapports,
        AppSection.parametres,
      ];
  }
}

bool isSectionVisible(AppRole role, AppSection section) =>
    sectionsVisibleForRole(role).contains(section);

AppSection defaultSectionForRole(AppRole role) =>
    role == AppRole.agent ||
        role == AppRole.apureur ||
        role == AppRole.contribuable
    ? AppSection.apurement
    : role == AppRole.taxateur
    ? AppSection.taxation
    : role == AppRole.ordonnateur
    ? AppSection.ordonnancement
    : AppSection.dashboard;
