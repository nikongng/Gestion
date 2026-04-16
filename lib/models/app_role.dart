enum AppRole {
  adminProvincial,
  ministreFinances,
  gouverneur,
  bourgmestre,
  agent,
  contribuable;

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
      case 'contribuable':
        return AppRole.contribuable;
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
        AppRole.contribuable => 'contribuable',
      };

  String get shortLabel => switch (this) {
        AppRole.adminProvincial => 'Admin provincial',
        AppRole.ministreFinances => 'Ministre des finances',
        AppRole.gouverneur => 'Gouverneur',
        AppRole.bourgmestre => 'Bourgmestre',
        AppRole.agent => 'Agent',
        AppRole.contribuable => 'Contribuable',
      };

  bool get canManageApp => this == AppRole.adminProvincial;

  bool get canEditOwnProfile =>
      this == AppRole.adminProvincial ||
      this == AppRole.agent ||
      this == AppRole.contribuable;

  bool get canChangeOwnAvatar => true;

  bool get canChangePassword => true;

  bool get canSubmitCollections =>
      this == AppRole.adminProvincial ||
      this == AppRole.agent ||
      this == AppRole.contribuable;

  bool get isReadOnlyUser =>
      this == AppRole.ministreFinances ||
      this == AppRole.gouverneur ||
      this == AppRole.bourgmestre;

  bool get isGlobalSupervisor =>
      this == AppRole.adminProvincial ||
      this == AppRole.ministreFinances ||
      this == AppRole.gouverneur;

  bool get hasAlertsAccess =>
      isGlobalSupervisor || this == AppRole.bourgmestre;

  bool get hasPersonalTaxIdentifier => this == AppRole.contribuable;
}
