import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/sample_chart_data.dart';
import '../../theme/app_colors.dart';

/// Donut : répartition par type de taxe.
class TaxBreakdownPieCard extends StatelessWidget {
  const TaxBreakdownPieCard({
    super.key,
    required this.title,
    this.compact = false,
    this.slices,
  });

  final String title;
  final bool compact;
  final List<TaxSlice>? slices;

  @override
  Widget build(BuildContext context) {
    final data = slices ?? kTaxBreakdown;
    if (data.isEmpty) {
      return Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
      );
    }
    final centerRadius = compact ? 36.0 : 52.0;
    final sectionRadius = compact ? 42.0 : 56.0;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Center(
              child: SizedBox(
                width: compact ? 150 : 200,
                height: compact ? 150 : 200,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: centerRadius,
                    sections: [
                      for (final s in data)
                        PieChartSectionData(
                          value: s.percent,
                          color: Color(s.colorValue),
                          radius: sectionRadius,
                          title: '${s.percent.toStringAsFixed(0)}%',
                          titleStyle: TextStyle(
                            fontSize: compact ? 9 : 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            ...data.map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Color(s.colorValue),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.label,
                        style: TextStyle(
                          fontSize: compact ? 12 : 13,
                          color: AppColors.mutedText,
                        ),
                      ),
                    ),
                    Text(
                      '${s.percent.toStringAsFixed(0)}%',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
