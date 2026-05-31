import 'app_role.dart';

class UserProfile {
  const UserProfile({
    required this.id,
    required this.fullName,
    required this.role,
    this.extraRoles = const [],
    this.communeId,
    this.communeName,
    this.avatarUrl,
    this.taxpayerIdentifier,
    this.taxpayerEmail,
    this.taxpayerPhone,
    this.taxpayerAddress,
    this.legalNif,
    this.accountStatus = 'actif',
    this.lastSignInAt,
  });

  final String id;
  final String fullName;
  final AppRole role;
  final List<AppRole> extraRoles;

  /// URL publique (Supabase Storage) ou null si aucune photo.
  final String? avatarUrl;
  final String? communeId;
  final String? communeName;
  final String? taxpayerIdentifier;
  final String? taxpayerEmail;
  final String? taxpayerPhone;
  final String? taxpayerAddress;
  final String? legalNif;
  final String accountStatus;
  final DateTime? lastSignInAt;

  List<AppRole> get roles {
    final values = <AppRole>[role];
    for (final item in extraRoles) {
      if (!values.contains(item)) values.add(item);
    }
    return List.unmodifiable(values);
  }

  bool hasRole(AppRole value) => roles.contains(value);

  bool get canManageApp => hasRole(AppRole.adminProvincial);

  bool get canEditOwnProfile => roles.any((item) => item.canEditOwnProfile);

  bool get canChangeOwnAvatar => roles.any((item) => item.canChangeOwnAvatar);

  bool get canChangePassword => roles.any((item) => item.canChangePassword);

  bool get canSubmitCollections =>
      roles.any((item) => item.canSubmitCollections);

  bool get isGlobalSupervisor => roles.any((item) => item.isGlobalSupervisor);

  bool get hasAlertsAccess => roles.any((item) => item.hasAlertsAccess);

  bool get hasPersonalTaxIdentifier =>
      roles.any((item) => item.hasPersonalTaxIdentifier);

  bool get isSuspended => accountStatus.trim().toLowerCase() != 'actif';

  String get rolesLabel => roles.map((item) => item.shortLabel).join(' + ');

  String get displayLine {
    if (role == AppRole.agent) return 'Agent de recouvrement - Mairie';
    if (role == AppRole.taxateur) return 'Taxateur - Mairie';
    if (role == AppRole.ordonnateur) return 'Liquidateur - Mairie';
    if (role == AppRole.apureur) return 'Apureur - Mairie';

    switch (role) {
      case AppRole.adminProvincial:
        return 'Administrateur provincial • Mairie';
      case AppRole.ministreFinances:
        return 'Ministre des finances • Supervision nationale';
      case AppRole.gouverneur:
        return 'Gouverneur • Supervision provinciale';
      case AppRole.bourgmestre:
        return 'Bourgmestre • Mairie';
      case AppRole.agent:
        return 'Agent • Mairie';
      case AppRole.taxateur:
        return 'Taxateur • Mairie';
      case AppRole.ordonnateur:
        return 'Ordonnateur • Mairie';
      case AppRole.apureur:
        return 'Apureur • Mairie';
      case AppRole.contribuable:
        return taxpayerIdentifier != null && taxpayerIdentifier!.isNotEmpty
            ? 'Contribuable • ID $taxpayerIdentifier'
            : 'Contribuable';
    }
  }

  String get sidebarRoleLabel {
    if (roles.any(
      (item) =>
          item == AppRole.agent ||
          item == AppRole.taxateur ||
          item == AppRole.ordonnateur ||
          item == AppRole.apureur,
    )) {
      return '$rolesLabel - Mairie';
    }

    if (roles.length > 1) {
      return '$rolesLabel - Mairie';
    }
    if (role == AppRole.bourgmestre ||
        role == AppRole.agent ||
        role == AppRole.taxateur ||
        role == AppRole.ordonnateur ||
        role == AppRole.apureur) {
      return '${role.shortLabel} — Mairie';
    }
    if (role == AppRole.contribuable &&
        taxpayerIdentifier != null &&
        taxpayerIdentifier!.isNotEmpty) {
      return '${role.shortLabel} — $taxpayerIdentifier';
    }
    return role.shortLabel;
  }

  static UserProfile? fromRow(Map<String, dynamic> row) {
    final role = AppRole.fromDb(row['role']?.toString());
    if (role == null) return null;
    final rawRoles = row['roles'];
    final parsedRoles = rawRoles is List
        ? rawRoles
              .map((value) => AppRole.fromDb(value?.toString()))
              .whereType<AppRole>()
              .toList()
        : const <AppRole>[];
    final commune = row['communes'] as Map<String, dynamic>?;
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return null;
    final rawUrl = row['avatar_url']?.toString();
    return UserProfile(
      id: id,
      fullName: row['full_name']?.toString() ?? 'Utilisateur',
      role: role,
      extraRoles: parsedRoles.where((item) => item != role).toList(),
      communeId: row['commune_id']?.toString(),
      communeName: commune?['name']?.toString(),
      avatarUrl: rawUrl != null && rawUrl.isNotEmpty ? rawUrl : null,
      taxpayerIdentifier: row['taxpayer_identifier']?.toString(),
      taxpayerEmail: row['taxpayer_email']?.toString(),
      taxpayerPhone: row['taxpayer_phone']?.toString(),
      taxpayerAddress: row['taxpayer_address']?.toString(),
      legalNif: row['legal_nif']?.toString(),
      accountStatus:
          row['account_status']?.toString() ??
          row['taxpayer_status']?.toString() ??
          'actif',
      lastSignInAt: _parseDateTime(row['last_sign_in_at']),
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value is DateTime) return value;
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text);
  }
}
