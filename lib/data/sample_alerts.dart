import '../models/app_alert.dart';
import '../models/app_role.dart';

/// Données de démonstration si la table `alerts` est vide ou indisponible.
List<AppAlert> sampleAlertsFallback(AppRole role, String? communeId) {
  final t = DateTime.now();
  final list = <AppAlert>[
    AppAlert(
      id: 'demo-probleme',
      severity: AlertSeverity.moyenne,
      category: AlertCategory.probleme,
      title: 'Montant inhabituel pour la catégorie',
      body:
          'Un paiement sort des plages habituelles (trop élevé ou trop faible). Vérifier la saisie et le justificatif.',
      createdAt: t.subtract(const Duration(hours: 3)),
      communeName: 'Exemple',
    ),
    AppAlert(
      id: 'demo-fraude',
      severity: AlertSeverity.critique,
      category: AlertCategory.fraude,
      title: 'Transactions répétées suspectes',
      body:
          'Plusieurs enregistrements quasi identiques (montant, canal) dans une courte fenêtre pour le même agent.',
      createdAt: t.subtract(const Duration(hours: 5)),
      communeName: 'Exemple',
    ),
    AppAlert(
      id: 'demo-retard',
      severity: AlertSeverity.moyenne,
      category: AlertCategory.retard,
      title: 'Traitement long en attente',
      body:
          'Des opérations restent en statut EN_ATTENTE au-delà du délai attendu, ou la synchronisation a échoué.',
      createdAt: t.subtract(const Duration(days: 1)),
      communeName: 'Exemple',
    ),
    AppAlert(
      id: 'demo-securite',
      severity: AlertSeverity.critique,
      category: AlertCategory.securite,
      title: 'Activité de connexion suspecte',
      body:
          'Plusieurs échecs de mot de passe puis réussite, ou connexion depuis un contexte inhabituel pour un compte admin.',
      createdAt: t.subtract(const Duration(minutes: 45)),
    ),
  ];

  if (role.isGlobalSupervisor) return list;
  if (role == AppRole.bourgmestre) {
    return list
        .map(
          (a) => AppAlert(
            id: a.id,
            severity: a.severity,
            category: a.category,
            title: a.title,
            body: a.body,
            createdAt: a.createdAt,
            communeName: communeId != null ? 'Votre commune' : a.communeName,
            resolvedAt: a.resolvedAt,
          ),
        )
        .toList();
  }
  return [];
}
