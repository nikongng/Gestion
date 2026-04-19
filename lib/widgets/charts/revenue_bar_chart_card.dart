import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/sample_chart_data.dart';
import '../../theme/app_colors.dart';

class RevenueBarChartCard extends StatelessWidget {
  const RevenueBarChartCard({
    super.key,
    required this.title,
    this.data,
    this.embedded = false,
  });

  final String title;
  final List<CommuneRevenue>? data;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final series = data ?? kRevenueByCommune;

    final body = series.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(20),
            child: Text(title, style: theme.textTheme.titleMedium),
          )
        : _BarChartBody(
            title: title,
            embedded: embedded,
            series: series,
          );

    if (embedded) return body;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: cs.surface,
        border: Border.all(color: cs.outline.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: body,
      ),
    );
  }
}

class _BarChartBody extends StatelessWidget {
  const _BarChartBody({
    required this.title,
    required this.embedded,
    required this.series,
  });

  final String title;
  final bool embedded;
  final List<CommuneRevenue> series;

  @override
  Widget build(BuildContext context) {
    final rawMax = series.map((e) => e.amountUsd).reduce((a, b) => a > b ? a : b);
    final maxY = (rawMax > 0 ? rawMax * 1.15 : 100).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!embedded) ...[
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
        ],
        SizedBox(
          height: embedded ? 248 : 230,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: AppColors.border.withValues(alpha: 0.56),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      if (value <= 0) return const SizedBox.shrink();
                      final compact = (value / 1000).round();
                      return Text(
                        '${compact}k',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.mutedText,
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= series.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          series[index].label,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.mutedText,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < series.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: series[i].amountUsd,
                        width: 18,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(10),
                        ),
                        color: AppColors.chartBlue,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
