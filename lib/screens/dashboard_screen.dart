import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../data/sample_chart_data.dart';
import '../models/app_role.dart';
import '../models/app_section.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../widgets/charts/revenue_bar_chart_card.dart';
import '../widgets/charts/revenue_line_chart_card.dart';
import '../widgets/charts/tax_breakdown_pie_card.dart';
import 'dashboard_controller.dart';

enum _DashboardQuickPanel { filters, communes, taxes }

final DateTime _pilotStartDate = DateTime(2026, 4, 10);

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.profile,
    this.onOpenSection,
    this.onOpenRecoveryControl,
  });

  final UserProfile profile;
  final ValueChanged<AppSection>? onOpenSection;
  final VoidCallback? onOpenRecoveryControl;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late final DashboardController _controller;
  late final AnimationController _revealController;
  bool _wasLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = DashboardController(profile: widget.profile);
    _controller.addListener(_handleControllerStateChange);
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _controller.load();
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerStateChange);
    _revealController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleControllerStateChange() {
    if (_wasLoading && !_controller.loading) {
      _revealController.forward(from: 0);
    } else if (!_wasLoading && _controller.loading) {
      _revealController.value = 0;
    }
    _wasLoading = _controller.loading;
  }

  Future<void> _refreshDashboard() async {
    _revealController.value = 0;
    await _controller.refresh();
  }

  String _fmtMoney(double value) {
    final source = value.toStringAsFixed(0);
    final buffer = StringBuffer();
    for (var i = 0; i < source.length; i++) {
      if (i > 0 && (source.length - i) % 3 == 0) {
        buffer.write(' ');
      }
      buffer.write(source[i]);
    }
    return '$buffer \$';
  }

  String _fmtCompactMoney(double value) {
    if (value >= 1000000) {
      final digits = value >= 10000000 ? 0 : 1;
      return '${(value / 1000000).toStringAsFixed(digits)} M\$';
    }
    if (value >= 1000) {
      final digits = value >= 100000 ? 0 : 1;
      return '${(value / 1000).toStringAsFixed(digits)} k\$';
    }
    return '${value.toStringAsFixed(0)} \$';
  }

  String _firstName(String fullName) {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return 'Utilisateur';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  ({int elapsed, double progress}) _pilotDayCount() {
    final start = DateTime(
      _pilotStartDate.year,
      _pilotStartDate.month,
      _pilotStartDate.day,
    );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final rawElapsed = today.difference(start).inDays + 1;
    final elapsed = rawElapsed.clamp(0, 90);
    return (elapsed: elapsed, progress: elapsed / 90);
  }

  String _truncate(String value, {int maxLength = 22}) {
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength - 1)}...';
  }

  BoxDecoration _pageBackgroundDecoration(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [
                const Color(0xFF101613),
                Color.alphaBlend(
                  cs.primary.withValues(alpha: 0.10),
                  const Color(0xFF18201C),
                ),
                Color.alphaBlend(
                  cs.secondary.withValues(alpha: 0.08),
                  const Color(0xFF1B2520),
                ),
              ]
            : [
                const Color(0xFFF7F2E8),
                const Color(0xFFF2E9DB),
                Color.alphaBlend(
                  cs.primary.withValues(alpha: 0.04),
                  const Color(0xFFF7F2E8),
                ),
              ],
      ),
    );
  }

  int _metricColumnCount(double width) {
    if (width >= 1280) return 4;
    if (width >= 840) return 2;
    return 1;
  }

  Widget _scrollableCard({required Widget child, required double minWidth}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final targetWidth = minWidth > constraints.maxWidth
            ? minWidth
            : constraints.maxWidth;
        if (targetWidth <= constraints.maxWidth) {
          return child;
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: SizedBox(width: targetWidth, child: child),
        );
      },
    );
  }

  Widget _revealSection({
    required int index,
    required Widget child,
    double yOffset = 26,
  }) {
    final start = (index * 0.12).clamp(0.0, 0.86);
    final end = (start + 0.24).clamp(start + 0.01, 1.0);
    final animation = CurvedAnimation(
      parent: _revealController,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, animatedChild) {
        return Opacity(
          opacity: animation.value,
          child: Transform.translate(
            offset: Offset(0, (1 - animation.value) * yOffset),
            child: animatedChild,
          ),
        );
      },
    );
  }

  Widget _sectionHeader({
    required BuildContext context,
    required String title,
    required String subtitle,
    String? eyebrow,
    Widget? action,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null) ...[
                Text(
                  eyebrow.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.primary,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        ?action,
      ],
    );
  }

  Widget _modernPanel({
    required BuildContext context,
    required Widget child,
    EdgeInsetsGeometry? padding,
    Color? accentColor,
  }) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final accent = accentColor ?? cs.primary;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            isDark
                ? Color.alphaBlend(
                    accent.withValues(alpha: 0.06),
                    cs.surface.withValues(alpha: 0.98),
                  )
                : Colors.white.withValues(alpha: 0.94),
            cs.surface.withValues(alpha: isDark ? 0.98 : 0.92),
            accent.withValues(alpha: isDark ? 0.08 : 0.04),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent, accent.withValues(alpha: 0.24)],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -32,
              right: -10,
              child: Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.08),
                ),
              ),
            ),
            Positioned(
              bottom: -44,
              left: -24,
              child: Container(
                width: 144,
                height: 144,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.05),
                ),
              ),
            ),
            Padding(padding: padding ?? const EdgeInsets.all(20), child: child),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildHeroCard(
    BuildContext context,
    dynamic dashboard, {
    required bool isPhone,
  }) {
    final theme = Theme.of(context);

    final roleLabel = widget.profile.role == AppRole.contribuable
        ? 'Workspace personnel'
        : 'Tableau de bord opérationnel';

    final quickStats = <({String label, String value, IconData icon})>[
      (
        label: 'Période',
        value: _controller.rangeLabel,
        icon: Icons.calendar_month_outlined,
      ),
      (
        label: 'Périmètre',
        value: _controller.scopeLabel,
        icon: widget.profile.role == AppRole.contribuable
            ? Icons.badge_outlined
            : Icons.location_on_outlined,
      ),
      (
        label: 'Flux',
        value: '${dashboard.transactionCount} transactions',
        icon: Icons.receipt_long_outlined,
      ),
      if (_controller.activeFiltersCount > 0)
        (
          label: 'Filtres',
          value: '${_controller.activeFiltersCount} actifs',
          icon: Icons.tune_outlined,
        ),
    ];

    final averageTicket = dashboard.transactionCount == 0
        ? 0.0
        : dashboard.totalAmount / dashboard.transactionCount;
    final dailySeries = List<DailyRevenue>.from(dashboard.dailySeries as List);
    final pulseStartIndex = dailySeries.length > 7 ? dailySeries.length - 7 : 0;
    final pulseSeries = dailySeries.sublist(pulseStartIndex);
    final topCommuneName = dashboard.topCommune?.name ?? '-';
    final topCommuneAmount = dashboard.topCommune != null
        ? _fmtMoney(dashboard.topCommune!.amount)
        : 'Aucune recette';
    final taxSlices = List<TaxSlice>.from(dashboard.taxSlices as List);
    final dominantTax = taxSlices.isEmpty
        ? null
        : taxSlices.reduce((a, b) => a.percent >= b.percent ? a : b);
    final dominantTaxLabel = dominantTax?.label ?? 'Aucune dominante';

    var peakDailyAmount = 0.0;
    for (final point in dailySeries) {
      peakDailyAmount = math.max(peakDailyAmount, point.amountUsd).toDouble();
    }

    final actionButton = FilledButton.icon(
      onPressed: _refreshDashboard,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.14),
        foregroundColor: Colors.white,
        shadowColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        ),
      ),
      icon: const Icon(Icons.refresh_rounded),
      label: const Text('Actualiser'),
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.sidebar, Color(0xFF315447), AppColors.primary],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.sidebar.withValues(alpha: 0.24),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          children: [
            Positioned(
              top: -30,
              right: -20,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
            ),
            Positioned(
              bottom: -50,
              left: -30,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 0.2, sigmaY: 0.2),
                child: const SizedBox(),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(isPhone ? 18 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.14),
                                ),
                              ),
                              child: Text(
                                roleLabel.toUpperCase(),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.9,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Bonjour ${_firstName(widget.profile.fullName)} 👋🏽',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isPhone) actionButton,
                    ],
                  ),
                  const SizedBox(height: 22),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: quickStats.map((item) {
                      return _HeroStatPill(
                        icon: item.icon,
                        label: item.label,
                        value: item.value,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.profile.role == AppRole.contribuable
                                  ? 'Total paye'
                                  : 'Total recettes',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: Colors.white.withValues(alpha: 0.76),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            _AnimatedHeroAmount(
                              value: dashboard.totalAmount,
                              formatter: _fmtMoney,
                              style:
                                  (isPhone
                                          ? theme.textTheme.displaySmall
                                          : theme.textTheme.displayMedium)
                                      ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: -1.0,
                                      ),
                            ),
                          ],
                        ),
                      ),
                      if (!isPhone)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.trending_up_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Ticket ${_fmtCompactMoney(averageTicket)}',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _buildHeroSignalPanel(
                    context: context,
                    averageTicket: averageTicket,
                    peakDailyAmount: peakDailyAmount,
                    topCommuneName: topCommuneName,
                    topCommuneAmount: topCommuneAmount,
                    dominantTaxLabel: dominantTaxLabel,
                    pulseSeries: pulseSeries,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroSignalPanel({
    required BuildContext context,
    required double averageTicket,
    required double peakDailyAmount,
    required String topCommuneName,
    required String topCommuneAmount,
    required String dominantTaxLabel,
    required List<DailyRevenue> pulseSeries,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        color: Colors.white.withValues(alpha: 0.10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Signal board',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tendance recente et points de controle',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
              const _DashboardBadge(
                icon: Icons.bolt_rounded,
                label: 'Live',
                light: true,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _PulseBars(data: pulseSeries),
          const SizedBox(height: 18),
          _SignalMetricTile(
            icon: Icons.payments_outlined,
            label: 'Ticket moyen',
            value: _fmtCompactMoney(averageTicket),
            subtitle: 'Montant moyen par transaction',
          ),
          const SizedBox(height: 10),
          _SignalMetricTile(
            icon: Icons.location_city_outlined,
            label: 'Commune phare',
            value: topCommuneName == '-' ? 'Aucune' : topCommuneName,
            subtitle: topCommuneAmount,
          ),
          const SizedBox(height: 10),
          _SignalMetricTile(
            icon: Icons.local_fire_department_outlined,
            label: 'Point haut',
            value: _fmtCompactMoney(peakDailyAmount),
            subtitle: dominantTaxLabel,
          ),
        ],
      ),
    );
  }

  DateTime? _collectedAtOf(Map<String, dynamic> row) {
    return DateTime.tryParse(row['collected_at']?.toString() ?? '')?.toLocal();
  }

  List<Map<String, dynamic>> _recentTransactions(
    List<Map<String, dynamic>> rows,
  ) {
    final sorted = List<Map<String, dynamic>>.from(rows)
      ..sort((a, b) {
        final aTs = _collectedAtOf(a)?.millisecondsSinceEpoch ?? 0;
        final bTs = _collectedAtOf(b)?.millisecondsSinceEpoch ?? 0;
        return bTs.compareTo(aTs);
      });
    return sorted.take(4).toList();
  }

  String _fmtDateTimeShort(DateTime? value) {
    if (value == null) return 'Date inconnue';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  String _paymentModeOf(Map<String, dynamic> row) {
    final paymentMode = row['payment_channel']?.toString().trim() ?? '';
    return paymentMode.isEmpty ? 'Non precise' : paymentMode;
  }

  String _taxCategoryOf(Map<String, dynamic> row) {
    final taxCategory = row['tax_category']?.toString().trim() ?? '';
    return taxCategory.isEmpty ? 'Paiement de taxe' : taxCategory;
  }

  // ignore: unused_element
  Widget _buildRecentTransactionsPanel({
    required BuildContext context,
    required List<Map<String, dynamic>> rows,
    required bool isPhone,
  }) {
    final recent = _recentTransactions(rows);
    const accent = Color(0xFF0F766E);

    return _modernPanel(
      context: context,
      accentColor: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            context: context,
            eyebrow: 'Live',
            title: 'Transactions recentes',
            subtitle: recent.isEmpty
                ? 'Aucune transaction visible sur la periode et les filtres actuels.'
                : 'Les 3 transactions les plus recentes du perimetre courant.',
            action: isPhone
                ? null
                : const _DashboardBadge(
                    icon: Icons.bolt_rounded,
                    label: '3 dernieres',
                    color: accent,
                  ),
          ),
          const SizedBox(height: 18),
          if (recent.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.72),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.12),
                ),
              ),
              child: Text(
                'Les transactions recentes apparaitront ici automatiquement.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            Column(
              children: [
                for (var i = 0; i < recent.length; i++) ...[
                  _RecentTransactionRow(
                    amount: _fmtMoney(
                      (recent[i]['amount'] as num?)?.toDouble() ?? 0,
                    ),
                    commune: _controller.communeNameOf(recent[i]),
                    author: _controller.authorNameOf(recent[i]),
                    collectedAt: _fmtDateTimeShort(_collectedAtOf(recent[i])),
                    paymentMode: _paymentModeOf(recent[i]),
                    accentColor: accent,
                  ),
                  if (i != recent.length - 1) const SizedBox(height: 12),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildQuickRangeChip(int days) {
    final selected = _matchesQuickRange(days);
    return ChoiceChip(
      label: Text('$days j'),
      showCheckmark: false,
      selected: selected,
      onSelected: (_) async {
        await _controller.applyQuickRange(days);
      },
    );
  }

  bool _matchesQuickRange(int days) {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    final expected = end.subtract(Duration(days: days - 1));
    final start = _controller.selectedRange.start;
    return start.year == expected.year &&
        start.month == expected.month &&
        start.day == expected.day &&
        _controller.selectedRange.duration.inDays == days - 1;
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _controller.selectedRange,
    );
    if (range == null) return;
    _controller.setDateRange(range);
    await _controller.load();
  }

  Widget _buildQuickRangeControls({required bool isPhone}) {
    final dateButton = FilledButton.tonalIcon(
      onPressed: _pickDateRange,
      icon: const Icon(Icons.date_range_outlined),
      label: Text(
        isPhone
            ? 'Période : ${_controller.rangeLabel}'
            : _controller.rangeLabel,
      ),
    );

    final chips = [
      _buildQuickRangeChip(7),
      _buildQuickRangeChip(30),
      _buildQuickRangeChip(90),
    ];

    if (isPhone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                chips[0],
                const SizedBox(width: 8),
                chips[1],
                const SizedBox(width: 8),
                chips[2],
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: dateButton),
        ],
      );
    }

    return Wrap(spacing: 8, runSpacing: 8, children: [...chips, dateButton]);
  }

  InputDecoration _panelInputDecoration({
    required String label,
    String? hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    OutlineInputBorder border(Color color) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: color),
      );
    }

    return InputDecoration(
      labelText: label,
      hintText: hintText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: isDark
          ? cs.surface.withValues(alpha: 0.94)
          : Colors.white.withValues(alpha: 0.82),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border(cs.outline.withValues(alpha: 0.18)),
      enabledBorder: border(cs.outline.withValues(alpha: 0.12)),
      focusedBorder: border(cs.primary.withValues(alpha: 0.48)),
    );
  }

  List<Widget> _activeFilterBadges() {
    final badges = <Widget>[];

    if (!_controller.isDefaultRangeSelected) {
      badges.add(
        const _DashboardBadge(
          icon: Icons.date_range_outlined,
          label: 'Periode personnalisee',
        ),
      );
    }
    if (_controller.selectedCommuneId != null) {
      badges.add(
        _DashboardBadge(
          icon: Icons.location_on_outlined,
          label: _controller.scopeLabel,
        ),
      );
    }
    if (_controller.selectedTaxCategory != null) {
      badges.add(
        _DashboardBadge(
          icon: Icons.pie_chart_outline_rounded,
          label: _truncate(_controller.selectedTaxCategory!),
        ),
      );
    }
    if (_controller.selectedPaymentChannel != null) {
      badges.add(
        _DashboardBadge(
          icon: Icons.account_balance_wallet_outlined,
          label: _truncate(_controller.selectedPaymentChannel!),
        ),
      );
    }
    final query = _controller.searchController.text.trim();
    if (query.isNotEmpty) {
      badges.add(
        _DashboardBadge(
          icon: Icons.search_rounded,
          label: 'Recherche "${_truncate(query, maxLength: 16)}"',
        ),
      );
    }

    return badges;
  }

  List<Widget> _filterFields({required bool isPhone}) {
    return [
      SizedBox(
        width: isPhone ? double.infinity : 280,
        child: TextField(
          controller: _controller.searchController,
          decoration: _panelInputDecoration(
            label: 'Recherche',
            hintText: 'Commune, taxe, canal, ID...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _controller.searchController.text.isEmpty
                ? null
                : IconButton(
                    onPressed: () => _controller.searchController.clear(),
                    icon: const Icon(Icons.close),
                  ),
          ),
        ),
      ),
      if (widget.profile.role.isGlobalSupervisor)
        SizedBox(
          width: isPhone ? double.infinity : 220,
          child: DropdownButtonFormField<String?>(
            initialValue: _controller.selectedCommuneId,
            decoration: _panelInputDecoration(label: 'Commune'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Toutes les communes'),
              ),
              for (final commune in _controller.communes)
                DropdownMenuItem<String?>(
                  value: commune.id,
                  child: Text(commune.name),
                ),
            ],
            onChanged: (value) async {
              _controller.setSelectedCommune(value);
              await _controller.load();
            },
          ),
        ),
      SizedBox(
        width: isPhone ? double.infinity : 220,
        child: DropdownButtonFormField<String?>(
          initialValue: _controller.selectedTaxCategory,
          decoration: _panelInputDecoration(label: 'Type de taxe'),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Toutes les taxes'),
            ),
            for (final tax in _controller.availableTaxCategories)
              DropdownMenuItem<String?>(value: tax, child: Text(tax)),
          ],
          onChanged: (value) {
            _controller.setSelectedTaxCategory(value);
          },
        ),
      ),
      SizedBox(
        width: isPhone ? double.infinity : 220,
        child: DropdownButtonFormField<String?>(
          initialValue: _controller.selectedPaymentChannel,
          decoration: _panelInputDecoration(label: 'Canal de paiement'),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Tous les canaux'),
            ),
            for (final channel in _controller.availablePaymentChannels)
              DropdownMenuItem<String?>(value: channel, child: Text(channel)),
          ],
          onChanged: (value) {
            _controller.setSelectedPaymentChannel(value);
          },
        ),
      ),
    ];
  }

  Widget _buildFiltersCard({
    required BuildContext context,
    required bool isPhone,
    required int filteredCount,
  }) {
    final theme = Theme.of(context);
    final summary = _controller.activeFiltersCount > 0
        ? '${_controller.activeFiltersCount} filtres actifs · $filteredCount resultats'
        : '$filteredCount resultats · ${_controller.scopeLabel}';
    final fields = _filterFields(isPhone: isPhone);
    final activeBadges = _activeFilterBadges();

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _DashboardBadge(
              icon: Icons.visibility_outlined,
              label: '$filteredCount visibles',
              color: Theme.of(context).colorScheme.secondary,
            ),
            _DashboardBadge(
              icon: Icons.inventory_2_outlined,
              label: '${_controller.collections.length} source(s)',
              color: Theme.of(context).colorScheme.secondary,
            ),
            if (_controller.activeFiltersCount > 0)
              _DashboardBadge(
                icon: Icons.tune_outlined,
                label: '${_controller.activeFiltersCount} filtre(s)',
                color: Theme.of(context).colorScheme.secondary,
              ),
          ],
        ),
        if (activeBadges.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: activeBadges),
        ],
        const SizedBox(height: 16),
        Text(
          '$filteredCount transaction(s) visibles sur ${_controller.collections.length} collection(s) chargee(s).',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        _buildQuickRangeControls(isPhone: isPhone),
        const SizedBox(height: 16),
        if (isPhone)
          Column(
            children: [
              for (var i = 0; i < fields.length; i++) ...[
                fields[i],
                if (i != fields.length - 1) const SizedBox(height: 12),
              ],
            ],
          )
        else
          Wrap(spacing: 12, runSpacing: 12, children: fields),
        if (isPhone) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                _controller.resetFilters();
                await _controller.load();
              },
              icon: const Icon(Icons.refresh_outlined),
              label: const Text('Reinitialiser les filtres'),
            ),
          ),
        ],
      ],
    );

    return _modernPanel(
      context: context,
      accentColor: Theme.of(context).colorScheme.secondary,
      padding: EdgeInsets.all(isPhone ? 14 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPhone)
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _controller.toggleMobileFiltersExpanded,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Control center',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            summary,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: _controller.mobileFiltersExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(Icons.expand_more),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            _sectionHeader(
              context: context,
              eyebrow: 'Control',
              title: 'Centre de pilotage',
              subtitle: summary,
              action: OutlinedButton.icon(
                onPressed: () async {
                  _controller.resetFilters();
                  await _controller.load();
                },
                icon: const Icon(Icons.refresh_outlined),
                label: const Text('Reinitialiser'),
              ),
            ),
            const SizedBox(height: 16),
            body,
          ],
          if (isPhone)
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              crossFadeState: _controller.mobileFiltersExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: body,
              ),
            ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildMetricGrid({
    required double width,
    required List<Widget> cards,
  }) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _metricColumnCount(width),
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        mainAxisExtent: width < 520 ? 202 : 188,
      ),
      itemBuilder: (context, index) => cards[index],
    );
  }

  void _showQuickPanel(_DashboardQuickPanel panel, {required bool isPhone}) {
    final dashboard = _controller.dashboard;
    final filteredRows = _controller.filteredRows;
    final byCommune = List<CommuneRevenue>.from(dashboard.byCommune as List);
    final taxSlices = List<TaxSlice>.from(dashboard.taxSlices as List);
    final dominantTax = taxSlices.isEmpty
        ? null
        : taxSlices.reduce((a, b) => a.percent >= b.percent ? a : b);

    final modalChild = switch (panel) {
      _DashboardQuickPanel.filters => _buildFiltersCard(
        context: context,
        isPhone: false,
        filteredCount: filteredRows.length,
      ),
      _DashboardQuickPanel.communes => _chartSection(
        context: context,
        eyebrow: 'Analytics',
        accentColor: AppColors.primary,
        title: 'Revenus par commune',
        subtitle: 'Lecture immediate des montants par territoire actif.',
        action: _DashboardBadge(
          icon: Icons.location_on_outlined,
          label: '${byCommune.length} commune(s)',
          color: AppColors.primary,
        ),
        child: _scrollableCard(
          minWidth: math.max(360.0, byCommune.length * 96.0),
          child: RevenueBarChartCard(
            title: 'Revenus par commune',
            data: byCommune,
            embedded: true,
          ),
        ),
      ),
      _DashboardQuickPanel.taxes => _chartSection(
        context: context,
        eyebrow: 'Mix',
        accentColor: AppColors.chartOrange,
        title: 'Repartition par type de taxe',
        subtitle: 'Vision claire de la structure fiscale dominante.',
        action: _DashboardBadge(
          icon: Icons.pie_chart_outline_rounded,
          label: _truncate(dominantTax?.label ?? 'Aucune dominante'),
          color: AppColors.chartOrange,
        ),
        child: TaxBreakdownPieCard(
          title: 'Repartition par type de taxe',
          compact: isPhone,
          slices: taxSlices,
          embedded: true,
        ),
      ),
    };

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final height = MediaQuery.sizeOf(sheetContext).height;
        return SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              constraints: BoxConstraints(maxHeight: height * 0.86),
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(sheetContext).colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
              ),
              child: SingleChildScrollView(child: modalChild),
            ),
          ),
        );
      },
    );
  }

  void _showAddContribuableInfo() {
    final canOpenUsers =
        widget.profile.role.isGlobalSupervisor && widget.onOpenSection != null;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final cs = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: cs.outline.withValues(alpha: 0.14)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.person_add_alt_1_rounded, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Ajouter un contribuable',
                        style: Theme.of(sheetContext).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Les comptes contribuables se creent via l inscription contribuable. Vous pouvez ensuite les retrouver dans la gestion des utilisateurs.',
                  style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                if (canOpenUsers) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        widget.onOpenSection!(AppSection.utilisateurs);
                      },
                      icon: const Icon(Icons.group_add_outlined),
                      label: const Text('Ouvrir les utilisateurs'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _openRecoveryControl() {
    final handler = widget.onOpenRecoveryControl;
    if (handler != null) {
      handler();
      return;
    }
    widget.onOpenSection?.call(AppSection.collecte);
  }

  Widget _buildMobileInspiredDashboard({
    required BuildContext context,
    required List<Map<String, dynamic>> filteredRows,
    required List<DailyRevenue> dailySeries,
    required bool isPhone,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = cs.outlineVariant.withValues(
      alpha: isDark ? 0.30 : 0.58,
    );
    final titleColor = cs.onSurface;
    final mutedColor = cs.onSurfaceVariant;
    final recent = _recentTransactions(filteredRows);
    final champion = _controller.communeChampionne;
    final pilotDayCount = _pilotDayCount();
    final totalRevenueSubtitle = _controller.canViewMairieRevenue
        ? 'Mairie ${_fmtCompactMoney(_controller.totalRecettesMairie)}\nCommunes ${_fmtCompactMoney(_controller.totalRecettesCommunes)}'
        : 'Recettes communales\n${_controller.scopeLabel}';

    final metrics = <Widget>[
      _DashboardKpiTile(
        icon: Icons.account_balance_wallet_rounded,
        title: 'Total recettes',
        value: _fmtMoney(_controller.totalTaxesCollectees),
        subtitle: totalRevenueSubtitle,
        color: cs.primary,
      ),
      _DashboardKpiTile(
        icon: Icons.receipt_long_rounded,
        title: 'Transactions',
        value: '${_controller.totalTransactions}',
        subtitle: 'Transactions totales',
        color: cs.secondary,
      ),
      _DashboardKpiTile(
        icon: Icons.groups_rounded,
        title: 'Contribuables',
        value: '${_controller.contribuablesActifs}',
        subtitle: 'Total actifs',
        color: cs.tertiary,
      ),
      _DashboardKpiTile(
        icon: Icons.emoji_events_rounded,
        title: 'Commune championne',
        value: champion?.name ?? 'Aucune',
        subtitle: champion != null
            ? _fmtMoney(champion.amount)
            : 'Pas de donnees',
        color: cs.primary,
      ),
    ];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: Container(
          padding: EdgeInsets.all(isPhone ? 14 : 22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                  cs.primary.withValues(alpha: isDark ? 0.08 : 0.045),
                  cs.surface,
                ),
                cs.surface.withValues(alpha: isDark ? 0.98 : 0.96),
                Color.alphaBlend(
                  cs.secondary.withValues(alpha: isDark ? 0.07 : 0.035),
                  cs.surface,
                ),
              ],
            ),
            borderRadius: BorderRadius.circular(isPhone ? 16 : 24),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.08),
                blurRadius: 36,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 620;
                  final titleBlock = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _DashboardHeaderChip(
                            icon: Icons.verified_user_outlined,
                            label: widget.profile.role.shortLabel,
                            color: cs.primary,
                          ),
                          _DashboardHeaderChip(
                            icon: Icons.location_on_outlined,
                            label: _controller.scopeLabel,
                            color: cs.secondary,
                          ),
                          if (_controller.activeFiltersCount > 0)
                            _DashboardHeaderChip(
                              icon: Icons.tune_rounded,
                              label:
                                  '${_controller.activeFiltersCount} filtre(s)',
                              color: cs.tertiary,
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Bonjour, ${_firstName(widget.profile.fullName)} 👋🏽',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: titleColor,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Voici un apercu de l\'activité fiscale pour la période séléctionnée.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: mutedColor,
                          height: 1.45,
                        ),
                      ),
                    ],
                  );
                  final dateButton = _DashboardDateButton(
                    label: _controller.rangeLabel,
                    onTap: _pickDateRange,
                  );
                  final refreshButton = IconButton.filledTonal(
                    tooltip: 'Actualiser',
                    onPressed: _controller.loading ? null : _refreshDashboard,
                    icon: const Icon(Icons.refresh_rounded),
                  );

                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        titleBlock,
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(child: dateButton),
                            const SizedBox(width: 10),
                            refreshButton,
                          ],
                        ),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: titleBlock),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          dateButton,
                          const SizedBox(height: 10),
                          refreshButton,
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              _DashboardHorizontalDeck(
                itemWidth: isPhone ? 126 : 0,
                spacing: 10,
                children: metrics,
              ),
              const SizedBox(height: 16),
              _DashboardSectionCard(
                title: 'Evolution des recettes',
                trailing: _DashboardPeriodChip(
                  label: 'Cette periode',
                  onTap: _pickDateRange,
                ),
                child: RevenueLineChartCard(
                  title: 'Evolution des recettes',
                  data: dailySeries,
                  embedded: true,
                ),
              ),
              const SizedBox(height: 14),
              _DashboardSectionCard(
                title: 'Acces rapides',
                actionLabel: 'Voir tout',
                child: _DashboardHorizontalDeck(
                  itemWidth: isPhone ? 106 : 0,
                  spacing: 10,
                  children: [
                    _QuickAccessTile(
                      icon: Icons.tune_rounded,
                      title: 'Filtres',
                      subtitle: 'Piloter',
                      onTap: () => _showQuickPanel(
                        _DashboardQuickPanel.filters,
                        isPhone: isPhone,
                      ),
                    ),
                    _QuickAccessTile(
                      icon: Icons.location_city_rounded,
                      title: 'Communes',
                      subtitle: 'Revenus',
                      color: cs.secondary,
                      onTap: () => _showQuickPanel(
                        _DashboardQuickPanel.communes,
                        isPhone: isPhone,
                      ),
                    ),
                    _QuickAccessTile(
                      icon: Icons.pie_chart_rounded,
                      title: 'Taxes',
                      subtitle: 'Mix',
                      color: cs.tertiary,
                      onTap: () => _showQuickPanel(
                        _DashboardQuickPanel.taxes,
                        isPhone: isPhone,
                      ),
                    ),
                    _QuickAccessTile(
                      icon: Icons.person_add_alt_1_rounded,
                      title: 'Ajouter',
                      subtitle: 'Contribuable',
                      onTap: _showAddContribuableInfo,
                    ),
                    _QuickAccessTile(
                      icon: Icons.fact_check_rounded,
                      title: 'Recouvrement',
                      subtitle: 'Controle',
                      onTap: _openRecoveryControl,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _DashboardSectionCard(
                title: 'Activites recentes',
                actionLabel: 'Voir tout',
                child: recent.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          'Aucune activite recente sur cette periode.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: mutedColor,
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < recent.length; i++) ...[
                            _DashboardActivityRow(
                              title: _taxCategoryOf(recent[i]),
                              subtitle: _controller.communeNameOf(recent[i]),
                              meta: _fmtDateTimeShort(
                                _collectedAtOf(recent[i]),
                              ),
                              badge: _paymentModeOf(recent[i]),
                              amount: _fmtMoney(
                                (recent[i]['amount'] as num?)?.toDouble() ?? 0,
                              ),
                              icon: Icons.account_balance_rounded,
                              color: i.isEven ? cs.primary : cs.secondary,
                            ),
                            if (i != recent.length - 1)
                              const SizedBox(height: 8),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: 14),
              _PilotProgressCard(
                elapsed: pilotDayCount.elapsed,
                progress: pilotDayCount.progress,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chartSection({
    required BuildContext context,
    required String title,
    required String subtitle,
    required Widget child,
    Color? accentColor,
    String? eyebrow,
    Widget? action,
  }) {
    return _modernPanel(
      context: context,
      accentColor: accentColor ?? Theme.of(context).colorScheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            context: context,
            eyebrow: eyebrow,
            title: title,
            subtitle: subtitle,
            action: action,
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildContribuableSpotlightPanel({
    required BuildContext context,
    required String topCommuneName,
    required String topCommuneAmount,
    required String dominantTaxLabel,
    required double averageTicket,
    required int transactionCount,
  }) {
    final taxpayerId =
        widget.profile.taxpayerIdentifier?.trim().isNotEmpty == true
        ? widget.profile.taxpayerIdentifier!
        : 'Non renseigne';

    return _modernPanel(
      context: context,
      accentColor: AppColors.chartTeal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            context: context,
            eyebrow: 'Mon compte',
            title: 'Espace contribuable',
            subtitle:
                'Un dashboard plus personnel centre sur votre activite fiscale et vos paiements.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DashboardBadge(
                icon: Icons.badge_outlined,
                label: 'ID $taxpayerId',
                color: AppColors.chartTeal,
              ),
              _DashboardBadge(
                icon: Icons.receipt_long_outlined,
                label: '$transactionCount transaction(s)',
                color: AppColors.chartTeal,
              ),
              _DashboardBadge(
                icon: Icons.auto_graph_rounded,
                label: 'Ticket ${_fmtCompactMoney(averageTicket)}',
                color: AppColors.chartTeal,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _InsightTile(
                icon: Icons.location_city_outlined,
                label: 'Commune dominante',
                value: topCommuneName == '-' ? 'Aucune donnee' : topCommuneName,
                subtitle: topCommuneAmount,
              ),
              _InsightTile(
                icon: Icons.pie_chart_outline_rounded,
                label: 'Categorie dominante',
                value: dominantTaxLabel,
                subtitle: 'Lecture de votre structure fiscale',
              ),
              _InsightTile(
                icon: Icons.calendar_today_outlined,
                label: 'Periode active',
                value: _controller.rangeLabel,
                subtitle: _controller.scopeLabel,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (_controller.loading && _controller.collections.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (_controller.error != null && _controller.collections.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_controller.error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _refreshDashboard,
                    child: const Text('Reessayer'),
                  ),
                ],
              ),
            ),
          );
        }

        return Container(
          decoration: _pageBackgroundDecoration(context),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final contentWidth = constraints.maxWidth;
              final isPhone = contentWidth < 760;
              final horizontalPadding = isPhone ? 14.0 : 20.0;

              final dashboard = _controller.dashboard;
              final filteredRows = _controller.filteredRows;
              final dailySeries = List<DailyRevenue>.from(
                dashboard.dailySeries as List,
              );

              return RefreshIndicator(
                onRefresh: _refreshDashboard,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.all(horizontalPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _revealSection(
                        index: 0,
                        child: _buildMobileInspiredDashboard(
                          context: context,
                          filteredRows: filteredRows,
                          dailySeries: dailySeries,
                          isPhone: isPhone,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _DashboardHeaderChip extends StatelessWidget {
  const _DashboardHeaderChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardBadge extends StatelessWidget {
  const _DashboardBadge({
    required this.icon,
    required this.label,
    this.light = false,
    this.color,
  });

  final IconData icon;
  final String label;
  final bool light;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = color ?? (light ? Colors.white : cs.primary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: light
              ? [
                  Colors.white.withValues(alpha: 0.16),
                  Colors.white.withValues(alpha: 0.10),
                ]
              : [
                  accent.withValues(alpha: 0.12),
                  accent.withValues(alpha: 0.06),
                ],
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: light
              ? Colors.white.withValues(alpha: 0.22)
              : accent.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: light ? Colors.white : accent),
          const SizedBox(width: 7),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: light ? Colors.white : cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStatPill extends StatelessWidget {
  const _HeroStatPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentTransactionRow extends StatelessWidget {
  const _RecentTransactionRow({
    required this.amount,
    required this.commune,
    required this.author,
    required this.collectedAt,
    required this.paymentMode,
    required this.accentColor,
  });

  final String amount;
  final String commune;
  final String author;
  final String collectedAt;
  final String paymentMode;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 640;

        final amountCard = Container(
          constraints: BoxConstraints(
            minWidth: compact ? double.infinity : 138,
          ),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accentColor.withValues(alpha: 0.18),
                accentColor.withValues(alpha: 0.08),
              ],
            ),
            border: Border.all(color: accentColor.withValues(alpha: 0.16)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Montant',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                amount,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
        );

        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: accentColor.withValues(alpha: 0.10),
                  ),
                  child: Icon(
                    Icons.location_city_outlined,
                    color: accentColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        commune,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Transaction recente du perimetre courant',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _RecentMetaPill(
                  icon: Icons.person_outline_rounded,
                  label: 'Auteur',
                  value: author,
                  accentColor: accentColor,
                ),
                _RecentMetaPill(
                  icon: Icons.schedule_rounded,
                  label: 'Date',
                  value: collectedAt,
                  accentColor: accentColor,
                ),
                _RecentMetaPill(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Mode',
                  value: paymentMode,
                  accentColor: accentColor,
                ),
              ],
            ),
          ],
        );

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: cs.surface.withValues(alpha: 0.78),
            border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [amountCard, const SizedBox(height: 14), details],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    amountCard,
                    const SizedBox(width: 16),
                    Expanded(child: details),
                  ],
                ),
        );
      },
    );
  }
}

class _RecentMetaPill extends StatelessWidget {
  const _RecentMetaPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.accentColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: accentColor.withValues(alpha: 0.08),
        border: Border.all(color: accentColor.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: accentColor),
          const SizedBox(width: 8),
          Text(
            '$label : ',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
  });

  final IconData icon;
  final String label;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: cs.surface.withValues(alpha: 0.72),
        border: Border.all(color: cs.outline.withValues(alpha: 0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: cs.primary.withValues(alpha: 0.10),
            ),
            child: Icon(icon, color: cs.primary, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalMetricTile extends StatelessWidget {
  const _SignalMetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
  });

  final IconData icon;
  final String label;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.white.withValues(alpha: 0.14),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.64),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseBars extends StatelessWidget {
  const _PulseBars({required this.data});

  final List<DailyRevenue> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Container(
        height: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Colors.white.withValues(alpha: 0.06),
        ),
      );
    }

    var maxValue = 0.0;
    for (final point in data) {
      maxValue = math.max(maxValue, point.amountUsd).toDouble();
    }

    return Container(
      height: 108,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < data.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(
                            begin: 0,
                            end: maxValue == 0
                                ? 0
                                : data[i].amountUsd / maxValue,
                          ),
                          duration: Duration(milliseconds: 520 + (i * 70)),
                          curve: Curves.easeOutCubic,
                          builder: (context, progress, _) {
                            return Container(
                              height: 18 + (progress * 48),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    Colors.white.withValues(alpha: 0.18),
                                    Colors.white.withValues(alpha: 0.75),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      data[i].label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.70),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DashboardHorizontalDeck extends StatelessWidget {
  const _DashboardHorizontalDeck({
    required this.children,
    required this.spacing,
    required this.itemWidth,
  });

  final List<Widget> children;
  final double spacing;
  final double itemWidth;

  @override
  Widget build(BuildContext context) {
    if (itemWidth > 0) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              SizedBox(width: itemWidth, child: children[i]),
              if (i != children.length - 1) SizedBox(width: spacing),
            ],
          ],
        ),
      );
    }

    return Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          Expanded(child: children[i]),
          if (i != children.length - 1) SizedBox(width: spacing),
        ],
      ],
    );
  }
}

class _DashboardKpiTile extends StatelessWidget {
  const _DashboardKpiTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final tileColor = isDark
        ? Color.alphaBlend(
            color.withValues(alpha: 0.06),
            cs.surfaceContainerHighest.withValues(alpha: 0.48),
          )
        : cs.surface.withValues(alpha: 0.94);
    return Container(
      height: 166,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              color.withValues(alpha: isDark ? 0.08 : 0.05),
              tileColor,
            ),
            tileColor,
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.24 : 0.16),
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: isDark ? 0.06 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(height: 4, color: color.withValues(alpha: 0.78)),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: color, size: 19),
                      ),
                      const Spacer(),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FittedBox(
                      alignment: Alignment.centerLeft,
                      fit: BoxFit.scaleDown,
                      child: Text(
                        value,
                        maxLines: 1,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardSectionCard extends StatelessWidget {
  const _DashboardSectionCard({
    required this.title,
    required this.child,
    this.actionLabel,
    this.trailing,
  });

  final String title;
  final String? actionLabel;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent = cs.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? cs.surfaceContainerHighest.withValues(alpha: 0.42)
            : cs.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: isDark ? 0.26 : 0.52),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.08 : 0.035),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 24,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              ?trailing,
              if (trailing == null && actionLabel != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.16 : 0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    actionLabel!,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _DashboardDateButton extends StatelessWidget {
  const _DashboardDateButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _DashboardPillButton(
      icon: Icons.calendar_today_outlined,
      label: label,
      onTap: onTap,
    );
  }
}

class _DashboardPeriodChip extends StatelessWidget {
  const _DashboardPeriodChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _DashboardPillButton(
      icon: Icons.keyboard_arrow_down_rounded,
      label: label,
      onTap: onTap,
      reverseIcon: true,
    );
  }
}

class _DashboardPillButton extends StatelessWidget {
  const _DashboardPillButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.reverseIcon = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool reverseIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final foreground = cs.onSurface;
    final muted = cs.onSurfaceVariant;
    final iconWidget = Icon(icon, size: 16, color: muted);
    final textWidget = Flexible(
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    return Material(
      color: isDark
          ? cs.surfaceContainerHighest.withValues(alpha: 0.46)
          : cs.surface.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: isDark ? 0.28 : 0.50),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: reverseIcon
                ? [textWidget, const SizedBox(width: 6), iconWidget]
                : [iconWidget, const SizedBox(width: 8), textWidget],
          ),
        ),
      ),
    );
  }
}

class _QuickAccessTile extends StatelessWidget {
  const _QuickAccessTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.color,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = color ?? cs.primary;
    final isDark = theme.brightness == Brightness.dark;
    final tileColor = isDark
        ? cs.surfaceContainerHighest.withValues(alpha: 0.46)
        : cs.surface.withValues(alpha: 0.92);
    final textColor = cs.onSurface;
    final mutedColor = cs.onSurfaceVariant;

    return Material(
      color: tileColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 118,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.20)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: mutedColor,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.16 : 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: accent.withValues(alpha: 0.82),
                  size: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardActivityRow extends StatelessWidget {
  const _DashboardActivityRow({
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.badge,
    required this.amount,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final String meta;
  final String badge;
  final String amount;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? cs.surface.withValues(alpha: 0.38)
            : cs.surfaceContainerHighest.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: isDark ? 0.18 : 0.42),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                meta,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 5),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badge,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    amount,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PilotProgressCard extends StatelessWidget {
  const _PilotProgressCard({required this.elapsed, required this.progress});

  final int elapsed;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent = cs.primary;
    final baseColor = isDark
        ? cs.surfaceContainerHighest.withValues(alpha: 0.48)
        : cs.surface.withValues(alpha: 0.94);
    final clamped = progress.clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color.alphaBlend(
              accent.withValues(alpha: isDark ? 0.14 : 0.08),
              baseColor,
            ),
            baseColor,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final titleBlock = Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  Icons.event_available_outlined,
                  color: accent,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pilotage du pilote 90 jours',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Suivi du projet pilote institutionnel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final dayCount = Column(
            crossAxisAlignment: compact
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.end,
            children: [
              Text(
                '$elapsed / 90',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                'jours ecoules',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          );
          final progressRing = SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: clamped,
                  strokeWidth: 5,
                  backgroundColor: cs.outlineVariant.withValues(alpha: 0.34),
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
                Text(
                  '${(clamped * 100).round()}%',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleBlock,
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: dayCount),
                    progressRing,
                  ],
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: titleBlock),
              const SizedBox(width: 12),
              dayCount,
              const SizedBox(width: 14),
              progressRing,
            ],
          );
        },
      ),
    );
  }
}

class _AnimatedHeroAmount extends StatelessWidget {
  const _AnimatedHeroAmount({
    required this.value,
    required this.formatter,
    required this.style,
  });

  final double value;
  final String Function(double value) formatter;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 950),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) {
        return Text(
          formatter(animatedValue),
          style: style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}
