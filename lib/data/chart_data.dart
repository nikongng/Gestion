class CommuneRevenue {
  const CommuneRevenue(this.label, this.amountUsd);
  final String label;
  final double amountUsd;
}

class TaxSlice {
  const TaxSlice(this.label, this.percent, this.colorValue);
  final String label;
  final double percent;
  final int colorValue;
}

class DailyRevenue {
  const DailyRevenue(this.label, this.amountUsd);
  final String label;
  final double amountUsd;
}

class MonthGoalVsActual {
  const MonthGoalVsActual(this.label, this.goalK, this.actualK);
  final String label;
  final double goalK;
  final double actualK;
}
