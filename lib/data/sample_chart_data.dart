// Données de démonstration pour les graphiques (à remplacer par l’API plus tard).

class CommuneRevenue {
  const CommuneRevenue(this.label, this.amountUsd);
  final String label;
  final double amountUsd;
}

const List<CommuneRevenue> kRevenueByCommune = [
  CommuneRevenue('DILALA', 58700),
  CommuneRevenue('MANIKA', 31800),
  CommuneRevenue('FUNGURUME', 28200),
  CommuneRevenue('AUTRE', 18500),
];

class TaxSlice {
  const TaxSlice(this.label, this.percent, this.colorValue);
  final String label;
  final double percent;
  final int colorValue;
}

const List<TaxSlice> kTaxBreakdown = [
  TaxSlice('Taxes Marchés', 38, 0xFF1366FF),
  TaxSlice('Permis & Licences', 26, 0xFF0FC2A5),
  TaxSlice('Stationnement', 19, 0xFFFF9F43),
  TaxSlice('Autres', 17, 0xFFE74C3C),
];

class DailyRevenue {
  const DailyRevenue(this.label, this.amountUsd);
  final String label;
  final double amountUsd;
}

const List<DailyRevenue> kLast7DaysRevenue = [
  DailyRevenue('Lun', 118000),
  DailyRevenue('Mar', 132000),
  DailyRevenue('Mer', 128000),
  DailyRevenue('Jeu', 145000),
  DailyRevenue('Ven', 151000),
  DailyRevenue('Sam', 98000),
  DailyRevenue('Dim', 87000),
];

class MonthGoalVsActual {
  const MonthGoalVsActual(this.label, this.goalK, this.actualK);
  final String label;
  final double goalK;
  final double actualK;
}

const List<MonthGoalVsActual> kGoalVsRevenueByMonth = [
  MonthGoalVsActual('Jan', 520, 480),
  MonthGoalVsActual('Fév', 540, 510),
  MonthGoalVsActual('Mar', 560, 595),
  MonthGoalVsActual('Avr', 580, 560),
  MonthGoalVsActual('Mai', 600, 620),
  MonthGoalVsActual('Juin', 620, 640),
];
