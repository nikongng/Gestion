/// Rôle fonctionnel d’une alerte (pourquoi elle existe).
enum AlertCategory {
  probleme,
  fraude,
  retard,
  securite,
}

/// Niveau d’urgence — action attendue.
enum AlertSeverity {
  critique,
  moyenne,
  faible,
}

class AppAlert {
  const AppAlert({
    required this.id,
    required this.severity,
    required this.category,
    required this.title,
    required this.body,
    required this.createdAt,
    this.communeName,
    this.resolvedAt,
  });

  final String id;
  final AlertSeverity severity;
  final AlertCategory category;
  final String title;
  final String body;
  final DateTime createdAt;
  final String? communeName;
  final DateTime? resolvedAt;

  bool get isOpen => resolvedAt == null;

  static AlertSeverity? _severityFromDb(String? s) {
    switch (s) {
      case 'critique':
        return AlertSeverity.critique;
      case 'moyenne':
        return AlertSeverity.moyenne;
      case 'faible':
        return AlertSeverity.faible;
      default:
        return null;
    }
  }

  static AlertCategory? _categoryFromDb(String? s) {
    switch (s) {
      case 'probleme':
        return AlertCategory.probleme;
      case 'fraude':
        return AlertCategory.fraude;
      case 'retard':
        return AlertCategory.retard;
      case 'securite':
        return AlertCategory.securite;
      default:
        return null;
    }
  }

  static AppAlert? fromRow(Map<String, dynamic> row) {
    final sev = _severityFromDb(row['severity']?.toString());
    final cat = _categoryFromDb(row['category']?.toString());
    if (sev == null || cat == null) return null;
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return null;
    final title = row['title']?.toString() ?? '';
    final body = row['body']?.toString() ?? '';
    final created = row['created_at']?.toString();
    if (created == null) return null;
    final createdAt = DateTime.tryParse(created);
    if (createdAt == null) return null;
    final communes = row['communes'] as Map<String, dynamic>?;
    final resolvedRaw = row['resolved_at']?.toString();
    return AppAlert(
      id: id,
      severity: sev,
      category: cat,
      title: title,
      body: body,
      createdAt: createdAt.toLocal(),
      communeName: communes?['name']?.toString(),
      resolvedAt: resolvedRaw != null
          ? DateTime.tryParse(resolvedRaw)?.toLocal()
          : null,
    );
  }
}

extension AlertSeverityDisplay on AlertSeverity {
  String get labelFr => switch (this) {
        AlertSeverity.critique => 'Critique',
        AlertSeverity.moyenne => 'Moyenne',
        AlertSeverity.faible => 'Faible',
      };

  String get hintFr => switch (this) {
        AlertSeverity.critique => 'Action immédiate requise',
        AlertSeverity.moyenne => 'À vérifier rapidement',
        AlertSeverity.faible => 'Information',
      };
}

extension AlertCategoryDisplay on AlertCategory {
  String get labelFr => switch (this) {
        AlertCategory.probleme => 'Problème',
        AlertCategory.fraude => 'Fraude possible',
        AlertCategory.retard => 'Retard / blocage',
        AlertCategory.securite => 'Sécurité',
      };
}
