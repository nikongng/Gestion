# Dossier technique

## 1. Objet technique

Ce dossier presente l'architecture, les composants, les flux de donnees, les exigences de securite et le plan de deploiement technique de GESTIA pour un pilote provincial au Lualaba.

Le prototype analyse dans le depot repose sur:

- Flutter pour l'application multi-plateforme;
- Supabase pour l'authentification, la base de donnees PostgreSQL, les politiques de securite, le stockage et les fonctions serveur;
- exports PDF/Excel;
- tableaux de bord et graphiques;
- ecoute temps reel des nouvelles collectes.

## 2. Architecture cible

### Couche utilisateur

Application Flutter accessible sur:

- navigateur web;
- Android;
- iOS;
- Windows/macOS/Linux si necessaire.

Les interfaces sont adaptees aux roles:

- superviseurs provinciaux;
- administrateurs;
- bourgmestres;
- agents;
- contribuables.

### Couche applicative

La logique applicative comprend:

- controle de session;
- routage par role;
- formulaires de paiement;
- calculs d'indicateurs;
- filtres de periode, commune, categorie et canal;
- verification par identifiant contribuable;
- generation de rapports;
- gestion des alertes.

### Couche backend

Supabase fournit:

- Auth: creation et connexion des utilisateurs;
- PostgreSQL: stockage structure des communes, profils, collectes, alertes et parametres;
- Row Level Security: restrictions par role et commune;
- Edge Functions: creation/suppression des utilisateurs internes et auto-inscription contribuable;
- Storage: avatars et fichiers associes si necessaire;
- Realtime: rafraichissement des donnees de collecte.

## 3. Modules fonctionnels

### Tableau de bord

Fonctions:

- recettes totales sur periode;
- nombre de transactions;
- recettes mairie et recettes communes;
- contribuables actifs;
- commune championne;
- tendances journalieres;
- repartition par categorie de recette;
- filtres par date, commune, taxe, canal et recherche.

### Collecte et paiement

Fonctions:

- choix de la couverture: mairie ou commune selon role;
- choix de la commune;
- selection du type de recette: impot, taxe, redevance;
- selection de categories detaillees;
- montant en USD;
- canal: mobile money, banque, caisse;
- identifiant contribuable facultatif pour agent, automatique pour contribuable;
- enregistrement dans la table `collections`.

### Controle du recouvrement

Fonctions:

- recherche par identifiant contribuable;
- verification du profil rattache;
- historique des paiements visibles;
- montant total visible;
- date du dernier paiement;
- nom du collecteur si disponible.

### Rapports

Fonctions:

- total sur 30 jours;
- moyenne journaliere;
- taux de realisation indicatif;
- nombre de transactions;
- graphique objectif/realise sur six mois;
- repartition par taxe;
- export PDF;
- export Excel.

### Alertes

Fonctions:

- alertes par gravite: critique, moyenne, faible;
- categories: probleme, fraude, retard, securite;
- visibilite provinciale ou communale selon role;
- marquage de consultation locale.

### Gestion des utilisateurs

Fonctions:

- creation de comptes internes par l'administrateur provincial;
- roles: ministre des finances, gouverneur, bourgmestre, agent;
- rattachement commune pour agents et bourgmestres;
- suppression de comptes internes;
- recherche, filtres et tri.

### Espace contribuable

Fonctions:

- auto-inscription;
- identifiant contribuable unique;
- paiement personnel;
- historique et rapports personnels.

## 4. Modele de donnees

### `communes`

Stocke les entites territoriales ou centres pilotes.

Champs principaux:

- `id`
- `name`
- `created_at`

Valeurs pilotes observees:

- Dilala
- Manika
- Fungurume
- Autre

### `profiles`

Stocke les profils applicatifs rattaches aux comptes Auth.

Champs principaux:

- `id`
- `full_name`
- `role`
- `commune_id`
- `avatar_url`
- `taxpayer_identifier`
- `created_at`

Contraintes importantes:

- les roles globaux n'ont pas de commune obligatoire;
- les agents et bourgmestres sont rattaches a une commune;
- les contribuables ont un identifiant contribuable.

### `collections`

Stocke les paiements/recettes enregistres.

Champs principaux:

- `id`
- `commune_id`
- `amount`
- `tax_category`
- `payment_channel`
- `collection_scope`
- `collected_at`
- `created_by`
- `taxpayer_profile_id`
- `taxpayer_identifier`

`collection_scope` distingue notamment:

- `mairie`
- `commune`

### `alerts`

Stocke les alertes metier.

Champs principaux:

- `id`
- `severity`
- `category`
- `title`
- `body`
- `commune_id`
- `created_at`
- `resolved_at`

### `app_settings`

Stocke les parametres generaux de l'application.

## 5. Matrice d'acces technique

| Ressource | Admin provincial | Gouverneur / Ministre | Bourgmestre | Agent | Contribuable |
| --- | --- | --- | --- | --- | --- |
| Toutes collectes | Oui | Lecture | Non | Non | Non |
| Collectes commune | Oui | Lecture | Lecture commune | Lecture/saisie commune | Non |
| Collectes personnelles | Oui | Lecture selon perimetre | Selon perimetre | Selon perimetre | Lecture/saisie personnelle |
| Utilisateurs | Gestion | Lecture selon politique | Lecture limitee | Lecture limitee | Profil personnel |
| Alertes | Toutes | Toutes | Commune | Non | Non |
| Parametres globaux | Gestion | Non | Non | Non | Non |

## 6. Securite

### Principes appliques

- authentification obligatoire;
- separation des droits par role;
- politiques RLS en base de donnees;
- controle des ecritures sensibles cote serveur;
- limitation de l'auto-edition pour eviter l'escalade de privileges;
- fonctions Edge avec verification de session;
- stockage des secrets hors depot via fichier d'environnement;
- preparation a l'audit des operations sensibles.

### Mesures a renforcer avant production

- journal d'audit immuable pour creation, modification, suppression et export;
- sauvegardes automatisees avec retention definie;
- politique de mot de passe renforcee;
- authentification multifacteur pour comptes privilegies;
- chiffrement au repos selon l'offre d'hebergement retenue;
- tests d'intrusion avant deploiement provincial;
- procedure de reponse aux incidents;
- registre de traitement des donnees personnelles.

## 7. Donnees personnelles et confidentialite

Donnees traitees:

- nom complet;
- email d'authentification;
- role institutionnel;
- commune de rattachement;
- identifiant contribuable;
- historique de paiements;
- traces techniques et horodatage.

Mesures recommandees:

- minimisation des donnees;
- politique d'information des utilisateurs;
- conservation limitee et motivee;
- droits d'acces selon le role;
- export controle;
- procedure de rectification;
- convention de confidentialite entre la Province et le prestataire;
- hebergement conforme aux exigences de l'autorite.

## 8. Deploiement

### Option A - Cloud gere

Avantages:

- deploiement rapide;
- haute disponibilite;
- mises a jour simplifiees;
- cout initial limite.

Points de vigilance:

- localisation des donnees;
- clauses contractuelles;
- dependance au fournisseur;
- connectivite Internet.

### Option B - Cloud souverain ou serveur dedie

Avantages:

- meilleur controle institutionnel;
- hebergement sous contrat specifique;
- integration plus directe avec systemes publics.

Points de vigilance:

- cout initial plus eleve;
- besoin d'administration systeme;
- sauvegardes, securite et supervision a organiser.

### Option C - Hybride

Un pilote en cloud gere, puis migration ou replication vers une infrastructure validee par la Province.

## 9. Integrations futures

GESTIA peut etre etendue vers:

- mobile money;
- banques partenaires;
- QR code de recu;
- signature/cachet electronique;
- systeme de quittance officiel;
- API de verification publique;
- interconnexion avec DIL, DRNOFLU, DGRAD ou autres services selon competences;
- cartographie des centres de perception;
- module contentieux/penalites;
- module objectifs par centre et agent;
- module audit et inspection.

## 10. Exploitation et maintenance

Activites recurrentes:

- support utilisateurs;
- sauvegardes;
- surveillance des erreurs;
- controle des acces;
- mise a jour des nomenclatures;
- revue mensuelle des indicateurs;
- formation continue;
- correctifs de securite.

Indicateurs techniques:

- disponibilite de l'application;
- temps moyen de reponse;
- nombre d'erreurs applicatives;
- nombre d'incidents de connexion;
- nombre d'exports;
- volume de transactions;
- temps de resolution des incidents.

## 11. Plan technique du pilote

| Phase | Duree | Actions |
| --- | --- | --- |
| Cadrage | 1 a 2 semaines | valider roles, communes, categories, droits, donnees pilotes |
| Parametrage | 2 semaines | configurer nomenclature, comptes, environnement, branding |
| Formation | 1 semaine | former superviseurs, agents et support |
| Pilote actif | 8 a 10 semaines | collecter, verifier, exporter, mesurer |
| Evaluation | 1 semaine | bilan technique, fonctionnel, financier et juridique |

## 12. Risques techniques

| Risque | Impact | Mitigation |
| --- | --- | --- |
| Connexion Internet instable | Saisie retardee | mode de saisie allege, zones de synchronisation, procedure papier secours |
| Mauvais parametrage des taxes | Donnees inexploitables | validation officielle de la nomenclature avant pilote |
| Comptes mal attribues | Acces excessifs | revue des roles par comite technique |
| Donnees personnelles exposees | Risque juridique | RLS, MFA, audit, formation, politique de confidentialite |
| Adoption faible | Resultats limites | formation terrain et accompagnement quotidien |

## 13. Conditions de passage en production

- validation du bilan pilote;
- audit securite;
- validation juridique;
- validation de l'hebergement;
- validation des integrations paiement;
- procedure officielle de support;
- protocole de sauvegarde et restauration;
- nomenclature definitive;
- manuel utilisateur;
- manuel administrateur.

