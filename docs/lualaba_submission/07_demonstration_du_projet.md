# Demonstration du projet

## 1. Objectif de la demonstration

Montrer au Gouvernement provincial du Lualaba que GESTIA est deja un prototype operationnel capable de:

- connecter des utilisateurs par role;
- afficher un tableau de bord de recettes;
- enregistrer un paiement;
- rattacher un paiement a un identifiant contribuable;
- verifier le statut d'un contribuable;
- produire un rapport;
- consulter des alertes;
- administrer les utilisateurs.

## 2. Duree recommandee

Demonstration courte: 12 minutes.  
Demonstration complete: 30 a 45 minutes.

## 3. Prerequis

Avant la demonstration:

- application lancee et accessible;
- base Supabase configuree;
- comptes de demo crees;
- communes pilotes parametrees;
- quelques transactions de demo disponibles;
- connexion Internet stable;
- navigateur en plein ecran;
- support de presentation ouvert.

## 4. Comptes de demo a preparer

| Role | Email exemple | Mot de passe | Objet |
| --- | --- | --- | --- |
| Admin provincial | admin.demo@gestia.cd | `[a definir]` | administration complete |
| Gouverneur | gouverneur.demo@gestia.cd | `[a definir]` | supervision globale |
| Ministre finances | finances.demo@gestia.cd | `[a definir]` | supervision recettes |
| Bourgmestre | bourgmestre.dilala@gestia.cd | `[a definir]` | lecture commune |
| Agent | agent.dilala@gestia.cd | `[a definir]` | saisie commune |
| Contribuable | contribuable.demo@gestia.cd | `[a definir]` | paiement personnel |

Ne pas utiliser de mots de passe reels dans les documents transmis.

## 5. Donnees de demo

Creer ou preparer quelques transactions:

| Commune | Type | Categorie | Canal | Montant |
| --- | --- | --- | --- | ---: |
| Dilala | Taxe | Taxe de marche | Caisse | 150 |
| Manika | Redevance | Redevance d'assainissement | Mobile Money | 250 |
| Fungurume | Taxe | Taxe sur transport de minerais | Banque | 1 200 |
| Dilala | Impot | Impot foncier | Banque | 600 |

Identifiant contribuable de demo:

- `CTB-0001` ou identifiant genere par l'application.

## 6. Script court - 12 minutes

### Etape 1 - Introduction

Dire:

> Nous allons montrer comment GESTIA permet de suivre les recettes, enregistrer un paiement, verifier un contribuable et produire un rapport dans un perimetre pilote du Lualaba.

Duree: 1 minute.

### Etape 2 - Connexion administrateur

Actions:

1. Ouvrir l'application.
2. Se connecter avec le compte admin.
3. Montrer la page d'accueil/tableau de bord.

Message cle:

> Chaque utilisateur se connecte avec son propre compte et voit les donnees correspondant a son role.

Duree: 1 minute.

### Etape 3 - Tableau de bord provincial

Actions:

1. Montrer les recettes totales.
2. Montrer transactions, contribuables actifs, commune championne.
3. Changer la periode.
4. Filtrer par commune ou categorie.

Message cle:

> La supervision n'attend plus une consolidation manuelle: les donnees sont visibles et filtrables.

Duree: 2 minutes.

### Etape 4 - Saisie d'une recette

Actions:

1. Aller dans Collecte.
2. Choisir couverture mairie ou commune.
3. Choisir commune.
4. Choisir type de recette.
5. Entrer montant.
6. Choisir canal.
7. Ajouter identifiant contribuable.
8. Enregistrer.

Message cle:

> La saisie est structuree: qui a saisi, quand, pour quelle commune, quel montant, quel canal et quel contribuable.

Duree: 2 minutes.

### Etape 5 - Verification par identifiant contribuable

Actions:

1. Dans Collecte, ouvrir le panneau de controle.
2. Entrer l'identifiant contribuable.
3. Lancer la verification.
4. Montrer le statut, le total, le dernier paiement et l'historique.

Message cle:

> Le controle de recouvrement devient immediat: un agent peut verifier rapidement si un contribuable est en regle dans le perimetre visible.

Duree: 2 minutes.

### Etape 6 - Rapports

Actions:

1. Aller dans Rapports.
2. Montrer total 30 jours, moyenne journaliere, transactions.
3. Montrer graphiques.
4. Cliquer export PDF ou Excel.

Message cle:

> Les rapports sont produits rapidement et peuvent etre partages pour controle ou reunion.

Duree: 2 minutes.

### Etape 7 - Alertes et utilisateurs

Actions:

1. Aller dans Alertes.
2. Montrer gravite et categories.
3. Aller dans Utilisateurs.
4. Montrer roles, filtres et creation de compte interne.

Message cle:

> GESTIA ne se limite pas a enregistrer: il aide a piloter, detecter et organiser les acces.

Duree: 2 minutes.

## 7. Script complet - 30 a 45 minutes

### Partie A - Supervision provinciale

- Connexion gouverneur.
- Lecture seule globale.
- Tableau de bord.
- Filtres.
- Alertes.
- Rapports.

### Partie B - Administration

- Connexion admin.
- Creation d'un agent.
- Creation d'un bourgmestre.
- Parametrage commune.
- Verification des droits.

### Partie C - Agent terrain

- Connexion agent.
- Perimetre limite a sa commune.
- Saisie d'une recette.
- Historique de transactions.
- Controle d'un identifiant.

### Partie D - Contribuable

- Auto-inscription ou connexion contribuable.
- Affichage identifiant.
- Paiement personnel.
- Historique.
- Rapport personnel.

### Partie E - Analyse

- Retour admin.
- Visualiser la transaction.
- Exporter rapport.
- Commenter l'impact sur le controle et la consolidation.

## 8. Points a observer pendant la demo

- temps de chargement;
- clarte des libelles;
- pertinence des categories;
- logique de role;
- comprehension par les participants;
- questions juridiques;
- questions budgetaires;
- attentes d'integration paiement;
- besoins de recu officiel.

## 9. Questions probables et reponses proposees

### Est-ce que GESTIA encaisse l'argent?

Reponse:

> Non, pas dans le pilote propose. GESTIA trace les paiements et peut etre connecte plus tard aux canaux officiels valides par la Province. Les recettes restent sous controle de l'autorite publique.

### Peut-on adapter les taxes?

Reponse:

> Oui. Les listes doivent etre validees par les services competents. L'application sera parametree selon la nomenclature officielle.

### Les contribuables peuvent-ils payer seuls?

Reponse:

> Oui, le prototype prevoit un espace contribuable avec identifiant unique. Pendant le pilote, cette fonction peut etre activee progressivement.

### Que se passe-t-il sans Internet?

Reponse:

> Le pilote necessite une connexion. Une evolution peut prevoir un mode de saisie differee/offline, mais cette option doit etre cadree techniquement et juridiquement.

### Qui voit les donnees?

Reponse:

> Les droits dependent du role. Un superviseur provincial voit globalement; un agent voit son perimetre; un contribuable voit ses paiements personnels.

### Les rapports ont-ils une valeur officielle?

Reponse:

> Les rapports sont des exports techniques. Leur valeur administrative doit etre definie dans le protocole, notamment pour les recus, quittances et signatures.

## 10. Checklist de validation a la fin

Faire valider oralement:

- l'interet du tableau de bord;
- la pertinence du flux de saisie;
- les roles utilisateurs;
- le besoin de recu/QR code;
- les categories de recettes a corriger;
- le perimetre pilote;
- le calendrier de lancement;
- les points focaux.

## 11. Livrable apres demonstration

Envoyer sous 48 heures:

- compte rendu de demonstration;
- liste des demandes de correction;
- perimetre pilote propose;
- planning mis a jour;
- budget final revise;
- projet de protocole.
