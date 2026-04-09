enum AppRole {
  adminProvincial,
  bourgmestre,
  agent;

  static AppRole? fromDb(String? value) {
    final v = value?.trim().toLowerCase();
    switch (v) {
      case 'admin_provincial':
        return AppRole.adminProvincial;
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
        AppRole.bourgmestre => 'bourgmestre',
        AppRole.agent => 'agent',
      };

  String get shortLabel => switch (this) {
        AppRole.adminProvincial => 'Admin provincial',
        AppRole.bourgmestre => 'Bourgmestre',
        AppRole.agent => 'Agent',
      };
}
