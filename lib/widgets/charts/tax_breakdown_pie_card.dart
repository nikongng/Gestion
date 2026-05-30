import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/chart_data.dart';
import '../../theme/app_colors.dart';

class TaxBreakdownPieCard extends StatelessWidget {
  const TaxBreakdownPieCard({
    super.key,
    required this.title,
    this.slices,
    this.compact = false,
    this.embedded = false,
  });

  final String title;
  final List<TaxSlice>? slices;
  final bool compact;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final series = (slices ?? const <TaxSlice>[])
        .where((slice) => slice.percent > 0)
        .toList(growable: false);

    final body = series.isEmpty
        ? _EmptyTaxBreakdown(title: title, embedded: embedded)
        : _TaxBreakdownBody(
            title: title,
            slices: series,
            compact: compact,
            embedded: embedded,
          );

    if (embedded) return body;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: cs.surface,
        border: Border.all(color: cs.outline.withValues(alpha: 0.18)),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: body),
    );
  }
}

class _TaxBreakdownBody extends StatelessWidget {
  const _TaxBreakdownBody({
    required this.title,
    required this.slices,
    required this.compact,
    required this.embedded,
  });

  final String title;
  final List<TaxSlice> slices;
  final bool compact;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<double>(0, (sum, slice) => sum + slice.percent);

    return LayoutBuilder(
      builder: (context, constraints) {
        final useCompact = compact || constraints.maxWidth < 420;
        final chart = _TaxPieChart(
          slices: slices,
          total: total,
          compact: useCompact,
        );
        final legend = _TaxLegend(slices: slices);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!embedded) ...[
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
            ],
            if (useCompact) ...[
              Center(child: chart),
              const SizedBox(height: 16),
              legend,
            ] else
              Row(
                children: [
                  Expanded(child: chart),
                  const SizedBox(width: 18),
                  Expanded(child: legend),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _TaxPieChart extends StatelessWidget {
  const _TaxPieChart({
    required this.slices,
    required this.total,
    required this.compact,
  });

  final List<TaxSlice> slices;
  final double total;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final chartSize = compact ? 166.0 : 186.0;

    return SizedBox(
      width: chartSize,
      height: chartSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 2,
              startDegreeOffset: -90,
              centerSpaceRadius: compact ? 36 : 42,
              centerSpaceColor: cs.surface,
              pieTouchData: PieTouchData(enabled: false),
              sections: [
                for (final slice in slices)
                  PieChartSectionData(
                    value: slice.percent,
                    color: Color(slice.colorValue),
                    radius: compact ? 48 : 56,
                    title: slice.percent >= 12
                        ? _formatPercent(slice.percent)
                        : '',
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                    borderSide: BorderSide(color: cs.surface, width: 3),
                    titlePositionPercentageOffset: 0.68,
                  ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatPercent(total),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: cs.onSurface,
                ),
              ),
              Text(
                'total',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.mutedText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaxLegend extends StatelessWidget {
  const _TaxLegend({required this.slices});

  final List<TaxSlice> slices;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < slices.length; i++) ...[
          _TaxLegendItem(slice: slices[i]),
          if (i != slices.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _TaxLegendItem extends StatelessWidget {
  const _TaxLegendItem({required this.slice});

  final TaxSlice slice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: Color(slice.colorValue),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            slice.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _formatPercent(slice.percent),
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.mutedText,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _EmptyTaxBreakdown extends StatelessWidget {
  const _EmptyTaxBreakdown({required this.title, required this.embedded});

  final String title;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!embedded) ...[
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
        ],
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outline.withValues(alpha: 0.14)),
          ),
          child: Text(
            'Aucune donnée disponible.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

String _formatPercent(double value) {
  final rounded = value.roundToDouble();
  if ((value - rounded).abs() < 0.05) {
    return '${rounded.toInt()}%';
  }
  return '${value.toStringAsFixed(1)}%';
}
