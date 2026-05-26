# Dossier de presentation

## 1. Resume executif

**GESTIA - Gestion et Suivi des Taxes, Impots et Assimiles** est une plateforme numerique destinee a renforcer la mobilisation, la tracabilite et le pilotage des recettes provinciales et communales dans la Province du Lualaba.

Le projet propose au Gouvernement provincial un outil operationnel pour enregistrer les paiements, suivre les recettes en temps reel, produire des rapports exploitables, verifier les paiements par identifiant contribuable et donner aux autorites une vision consolidee des performances par commune, periode, categorie de recette et canal de paiement.

GESTIA repond a un besoin simple: transformer la collecte des donnees fiscales et non fiscales en un systeme controle, lisible et partage entre les acteurs autorises. La solution ne cree pas de taxe et ne modifie pas les taux. Elle numerise les operations de suivi, de recouvrement, de preuve, de controle et de reporting selon les nomenclatures et decisions administratives validees par l'autorite competente.

## 2. Contexte et justification

Le Lualaba est une province economiquement strategique. La qualite de la mobilisation des recettes provinciales conditionne la capacite du Gouvernement provincial a financer les infrastructures, les services publics et les programmes de developpement.

Dans un environnement de collecte multi-acteurs, plusieurs difficultes peuvent apparaitre:

- consolidation lente des recettes entre communes, centres de perception et services provinciaux;
- faible visibilite temps reel pour les autorites de supervision;
- difficulte a verifier rapidement si un contribuable a effectivement paye;
- risques d'erreurs de saisie, de doublons, de paiements non rattaches ou de pieces justificatives dispersees;
- manque de tableaux de bord simples pour comparer les performances;
- rapports manuels difficiles a produire et a auditer;
- faible autonomie du contribuable dans la consultation de son statut.

GESTIA vise a repondre a ces defis par une plateforme unique, parametree pour le contexte provincial.

## 3. Vision du projet

La vision est de mettre en place, au service du Gouvernement provincial du Lualaba, une infrastructure numerique de confiance pour les recettes publiques locales.

Cette infrastructure doit permettre:

- une saisie fiable des paiements par les agents autorises;
- une vue consolidee des recettes pour les autorites provinciales;
- une lecture par commune, periode, taxe, canal et type de recette;
- une identification claire des contribuables;
- une production rapide de rapports;
- une detection d'anomalies et alertes;
- une meilleure transparence entre administration et contribuables.

## 4. Objectifs

### Objectif general

Ameliorer la mobilisation, la tracabilite et le pilotage des recettes provinciales et communales du Lualaba grace a une plateforme numerique securisee.

### Objectifs specifiques

- Centraliser les donnees de collecte dans une base unique controlee.
- Reduire le temps de consolidation administrative des recettes.
- Faciliter la verification du statut de paiement des contribuables.
- Equiper les autorites d'indicateurs simples et actualises.
- Produire des rapports PDF/Excel standardises.
- Encadrer les droits d'acces selon les roles institutionnels.
- Prepararer l'integration progressive avec les canaux de paiement, banques, mobile money et services publics competents.

## 5. Beneficiaires

Les beneficiaires directs sont:

- Gouvernement provincial du Lualaba;
- Ministre provincial ayant les finances dans ses attributions;
- administrations provinciales chargees des recettes fiscales et non fiscales;
- communes et bourgmestres;
- agents de collecte et de controle;
- contribuables personnes physiques et morales;
- services d'audit, inspection et controle.

Les beneficiaires indirects sont les citoyens de la province, a travers une meilleure mobilisation des ressources publiques et une plus grande transparence dans la gestion des recettes.

## 6. Description de la solution

GESTIA est une application web/mobile basee sur Flutter et Supabase. Elle comprend aujourd'hui les modules suivants:

- **Tableau de bord**: recettes totales, transactions, contribuables actifs, recettes mairie/commune, commune championne, graphiques par jour, commune et categorie.
- **Collecte / paiement**: enregistrement de nouveaux paiements, choix de commune, type de recette, categorie, montant, canal de paiement et identifiant contribuable.
- **Espace contribuable**: auto-inscription, identifiant contribuable unique, paiement autonome et consultation de son historique.
- **Controle du recouvrement**: recherche par identifiant contribuable, verification du statut, historique visible, total paye et dernier paiement.
- **Rapports**: indicateurs sur 30 jours, exports PDF et Excel, repartition par taxe et suivi objectif/realise.
- **Alertes**: signalement d'anomalies, incoherences, retards, risques de fraude et alertes de securite.
- **Gestion des utilisateurs**: creation de comptes internes, attribution de roles, rattachement aux communes, filtrage et annuaire.
- **Parametres**: configuration du nom de l'application, libelles des communes, profil, avatar et mot de passe.

## 7. Roles et gouvernance fonctionnelle

GESTIA distingue les droits d'acces selon les profils:

| Role | Capacites principales |
| --- | --- |
| Gouverneur | Supervision globale, consultation des indicateurs et alertes |
| Ministre provincial des finances | Supervision globale, analyse recettes, rapports et alertes |
| Administrateur provincial | Administration complete, gestion utilisateurs, parametrage, collecte et rapports |
| Bourgmestre | Lecture des donnees de sa commune, alertes rattachees a sa commune |
| Agent | Saisie des recettes de sa commune, consultation de son perimetre |
| Contribuable | Paiement personnel, historique, justificatifs, identifiant contribuable |

## 8. Perimetre pilote propose

Le pilote est propose sur **90 jours**.

Perimetre initial suggere:

- Province: Lualaba
- Ville/zone de lancement: Kolwezi et environs
- Entites de depart: Dilala, Manika, Fungurume, Autre centre pilote
- Categories de recettes: impots, taxes et redevances a valider par la Province
- Utilisateurs pilotes: 1 administrateur provincial, 2 superviseurs, 3 bourgmestres, 10 a 20 agents, 50 a 200 contribuables pilotes

## 9. Resultats attendus du pilote

A la fin des 90 jours, le projet doit permettre de mesurer:

- le volume de paiements enregistres;
- le temps moyen de consolidation des rapports;
- le nombre de contribuables identifies;
- le nombre de controles effectues par identifiant;
- la qualite des donnees saisies;
- le taux d'utilisation par role;
- les anomalies detectees et traitees;
- la satisfaction des agents et contribuables pilotes.

## 10. Valeur ajoutee pour la Province

GESTIA apporte:

- une vue temps reel des recettes;
- une meilleure discipline de saisie;
- des controles par role et par commune;
- une reduction des zones opaques dans la chaine de collecte;
- un historique consultable et exportable;
- une base numerique pour l'audit, la planification et les decisions budgetaires;
- une experience plus moderne pour le contribuable.

## 11. Demande adressee au Gouvernement provincial

Le porteur du projet sollicite:

- l'autorisation de conduire un pilote institutionnel de 90 jours;
- la designation d'un point focal politique et d'un point focal technique;
- la mise a disposition de la nomenclature officielle des recettes a parametrer;
- l'identification des communes, centres et agents pilotes;
- l'acces aux regles de gestion necessaires a l'adaptation de l'application;
- la validation d'un protocole de confidentialite et de traitement des donnees;
- la tenue d'un comite de pilotage bimensuel pendant le pilote;
- l'evaluation finale en vue d'un deploiement provincial.

## 12. Livrables du pilote

- Application GESTIA parametree pour le Lualaba.
- Comptes utilisateurs par role.
- Tableau de bord de pilotage.
- Historique des transactions pilotes.
- Rapports PDF/Excel.
- Registre des alertes et anomalies.
- Rapport de fin de pilote avec indicateurs, lecons apprises et plan de deploiement.

## 13. Conclusion

GESTIA est propose comme un outil concret de modernisation administrative. Le projet met la technologie au service d'une priorite publique: mieux mobiliser, mieux controler et mieux expliquer les recettes provinciales.

L'approche recommandee est progressive: un pilote court, mesure, encadre par la Province, puis une extension par services, communes et centres de perception selon les resultats observes.

