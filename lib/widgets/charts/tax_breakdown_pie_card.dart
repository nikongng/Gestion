import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/sample_chart_data.dart';
import '../../theme/app_colors.dart';

class TaxBreakdownPieCard extends StatelessWidget {
  const TaxBreakdownPieCard({
    super.key,
    required this.title,
    this.compact = false,
    this.slices,
    this.embedded = false,
  });

  final String title;
  final bool compact;
  final List<TaxSlice>? slices;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final data = slices ?? kTaxBreakdown;

    final body = data.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(20),
            child: Text(title, style: theme.textTheme.titleMedium),
          )
        : _PieChartBody(
            title: title,
            compact: compact,
            embedded: embedded,
            data: data,
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

class _PieChartBody extends StatelessWidget {
  const _PieChartBody({
    required this.title,
    required this.compact,
    required this.embedded,
    required this.data,
  });

  final String title;
  final bool compact;
  final bool embedded;
  final List<TaxSlice> data;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final centerRadius = compact ? 38.0 : 56.0;
    final sectionRadius = compact ? 44.0 : 58.0;
    final topSlice = data.reduce((a, b) => a.percent >= b.percent ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!embedded) ...[
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
        ],
        Center(
          child: SizedBox(
            width: compact ? 160 : 220,
            height: compact ? 160 : 220,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 3,
                    centerSpaceRadius: centerRadius,
                    sections: [
                      for (final slice in data)
                        PieChartSectionData(
                          value: slice.percent,
                          color: Color(slice.colorValue),
                          radius: sectionRadius,
                          title: '${slice.percent.toStringAsFixed(0)}%',
                          titleStyle: TextStyle(
                            fontSize: compact ? 9 : 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Mix fiscal',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.mutedText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${data.length}',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'categories',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.mutedText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: isDark
                ? cs.surface.withValues(alpha: 0.92)
                : Colors.white.withValues(alpha: 0.72),
            border: Border.all(color: cs.outline.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Color(topSlice.colorValue),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  topSlice.label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.mutedText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${topSlice.percent.toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ...data.map(
          (slice) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Color(slice.colorValue),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    slice.label,
                    style: TextStyle(
                      fontSize: compact ? 12 : 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.mutedText,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${slice.percent.toStringAsFixed(0)}%',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
