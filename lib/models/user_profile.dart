import 'app_role.dart';

class UserProfile {
  const UserProfile({
    required this.id,
    required this.fullName,
    required this.role,
    this.communeId,
    this.communeName,
    this.avatarUrl,
  });

  final String id;
  final String fullName;
  final AppRole role;
  /// URL publique (Supabase Storage) ou null si aucune photo.
  final String? avatarUrl;
  final String? communeId;
  final String? communeName;

  String get displayLine {
    switch (role) {
      case AppRole.adminProvincial:
        return 'Administrateur provincial â€¢ Toutes les communes';
      case AppRole.ministreFinances:
        return 'Ministre des finances â€¢ Supervision nationale';
      case AppRole.gouverneur:
        return 'Gouverneur â€¢ Supervision provinciale';
      case AppRole.bourgmestre:
        return communeName != null
            ? 'Bourgmestre â€¢ $communeName'
            : 'Bourgmestre';
      case AppRole.agent:
        return communeName != null ? 'Agent â€¢ $communeName' : 'Agent';
    }
  }

  String get sidebarRoleLabel {
    if (role == AppRole.bourgmestre || role == AppRole.agent) {
      if (communeName != null) {
        return '${role.shortLabel} â€” $communeName';
      }
    }
    return role.shortLabel;
  }

  static UserProfile? fromRow(Map<String, dynamic> row) {
    final role = AppRole.fromDb(row['role']?.toString());
    if (role == null) return null;
    final commune = row['communes'] as Map<String, dynamic>?;
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return null;
    final rawUrl = row['avatar_url']?.toString();
    return UserProfile(
      id: id,
      fullName: row['full_name']?.toString() ?? 'Utilisateur',
      role: role,
      communeId: row['commune_id']?.toString(),
      communeName: commune?['name']?.toString(),
      avatarUrl: rawUrl != null && rawUrl.isNotEmpty ? rawUrl : null,
    );
  }
}

