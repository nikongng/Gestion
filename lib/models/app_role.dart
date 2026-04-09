enum AppRole {
  adminProvincial,
  ministreFinances,
  gouverneur,
  bourgmestre,
  agent;

  static AppRole? fromDb(String? value) {
    final v = value?.trim().toLowerCase();
    switch (v) {
      case 'admin_provincial':
        return AppRole.adminProvincial;
      case 'ministre_finances':
        return AppRole.ministreFinances;
      case 'gouverneur':
        return AppRole.gouverneur;
      case 'bourgmestre':
        return AppRole.bourgmestre;
      case 'agent':
        return AppRole.agent;
      default:
        return null;
    }
  }

  String get dbValue => switch (this) {
        AppRole.adminProvincial => 'admin_provincial',
        AppRole.ministreFinances => 'ministre_finances',
        AppRole.gouverneur => 'gouverneur',
        AppRole.bourgmestre => 'bourgmestre',
        AppRole.agent => 'agent',
      };

  String get shortLabel => switch (this) {
        AppRole.adminProvincial => 'Admin provincial',
        AppRole.ministreFinances => 'Ministre des finances',
        AppRole.gouverneur => 'Gouverneur',
        AppRole.bourgmestre => 'Bourgmestre',
        AppRole.agent => 'Agent',
      };

  bool get isGlobalSupervisor =>
      this == AppRole.adminProvincial ||
      this == AppRole.ministreFinances ||
      this == AppRole.gouverneur;
}
