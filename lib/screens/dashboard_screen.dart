import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../data/sample_chart_data.dart';
import '../models/app_role.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../widgets/charts/revenue_bar_chart_card.dart';
import '../widgets/charts/revenue_line_chart_card.dart';
import '../widgets/charts/tax_breakdown_pie_card.dart';
import '../widgets/metric_card.dart';
import '../widgets/responsive_two_cards.dart';
import 'dashboard_controller.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.profile});

  final UserProfile profile;

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
                const Color(0xFF0B1220),
                Color.alphaBlend(
                  cs.primary.withValues(alpha: 0.08),
                  const Color(0xFF101A2D),
                ),
                Color.alphaBlend(
                  cs.secondary.withValues(alpha: 0.06),
                  const Color(0xFF0F1728),
                ),
              ]
            : [
                const Color(0xFFF7FAFF),
                const Color(0xFFF2F6FC),
                Color.alphaBlend(
                  cs.primary.withValues(alpha: 0.03),
                  const Color(0xFFF7FAFF),
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

  Widget _scrollableCard({
    required Widget child,
    required double minWidth,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final targetWidth =
            minWidth > constraints.maxWidth ? minWidth : constraints.maxWidth;
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
                    colors: [
                      accent,
                      accent.withValues(alpha: 0.24),
                    ],
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
            Padding(
              padding: padding ?? const EdgeInsets.all(20),
              child: child,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard(
    BuildContext context,
    dynamic dashboard, {
    required bool isPhone,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

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
          colors: [
            Color(0xFF0F172A),
            Color(0xFF1D4ED8),
            Color(0xFF0EA5E9),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.22),
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
                              widget.profile.role == AppRole.contribuable
                                  ? 'Vue premium de vos paiements'
                                  : 'Cockpit analytique des recettes',
                              style: (isPhone
                                      ? theme.textTheme.headlineMedium
                                      : theme.textTheme.displaySmall)
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    height: 1.02,
                                    letterSpacing: -0.8,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              widget.profile.role == AppRole.contribuable
                                  ? 'Bonjour ${_firstName(widget.profile.fullName)}, suivez vos paiements et vos categories actives dans un cockpit clair et vivant.'
                                  : 'Bonjour ${_firstName(widget.profile.fullName)}, pilotez les recettes, la portee et les signaux critiques depuis un centre de commandement premium.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white.withValues(alpha: 0.88),
                                height: 1.6,
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
                              style: (isPhone
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
    return sorted.take(3).toList();
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
                color: Theme.of(context).colorScheme.surface.withValues(
                  alpha: 0.72,
                ),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withValues(
                    alpha: 0.12,
                  ),
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
                    amount: _fmtMoney((recent[i]['amount'] as num?)?.toDouble() ?? 0),
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
        isPhone ? 'Période : ${_controller.rangeLabel}' : _controller.rangeLabel,
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

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [...chips, dateButton],
    );
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
              DropdownMenuItem<String?>(
                value: tax,
                child: Text(tax),
              ),
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
              DropdownMenuItem<String?>(
                value: channel,
                child: Text(channel),
              ),
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: activeBadges,
          ),
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
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: fields,
          ),
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

  Widget _buildContribuableSpotlightPanel({
    required BuildContext context,
    required String topCommuneName,
    required String topCommuneAmount,
    required String dominantTaxLabel,
    required double averageTicket,
    required int transactionCount,
  }) {
    final theme = Theme.of(context);
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

        final dashboard = _controller.dashboard;
        final filteredRows = _controller.filteredRows;
        final topCommuneName = dashboard.topCommune?.name ?? '-';
        final topCommuneAmount = dashboard.topCommune != null
            ? _fmtMoney(dashboard.topCommune!.amount)
            : 'Aucune recette';
        final byCommune = List<CommuneRevenue>.from(dashboard.byCommune as List);
        final dailySeries = List<DailyRevenue>.from(dashboard.dailySeries as List);
        final taxSlices = List<TaxSlice>.from(dashboard.taxSlices as List);
        final dominantTax = taxSlices.isEmpty
            ? null
            : taxSlices.reduce((a, b) => a.percent >= b.percent ? a : b);
        final isTaxpayer = widget.profile.role == AppRole.contribuable;
        final averageTicket = dashboard.transactionCount == 0
            ? 0.0
            : dashboard.totalAmount / dashboard.transactionCount;

        var peakDailyAmount = 0.0;
        for (final point in dailySeries) {
          peakDailyAmount = math.max(peakDailyAmount, point.amountUsd).toDouble();
        }

        return Container(
          decoration: _pageBackgroundDecoration(context),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final contentWidth = constraints.maxWidth;
              final isPhone = contentWidth < 760;
              final horizontalPadding = isPhone ? 14.0 : 20.0;

              final cards = isTaxpayer
                  ? <Widget>[
                      MetricCard(
                        title: 'Total paye',
                        value: _fmtMoney(dashboard.totalAmount),
                        subtitle: _controller.rangeLabel,
                        width: null,
                        minHeight: 144,
                        icon: Icons.payments_outlined,
                        accentColor: AppColors.primary,
                        badge: 'Compte',
                        highlighted: true,
                        numericValue: dashboard.totalAmount.toDouble(),
                        animatedFormatter: _fmtMoney,
                      ),
                      MetricCard(
                        title: 'Transactions',
                        value: '${dashboard.transactionCount}',
                        subtitle: 'Paiements enregistres',
                        width: null,
                        minHeight: 144,
                        icon: Icons.receipt_long_outlined,
                        accentColor: AppColors.chartTeal,
                        badge: 'Flux',
                        numericValue: dashboard.transactionCount.toDouble(),
                        animatedFormatter: (value) => value.round().toString(),
                      ),
                      MetricCard(
                        title: 'Ticket moyen',
                        value: _fmtCompactMoney(averageTicket),
                        subtitle: 'Montant moyen par paiement',
                        width: null,
                        minHeight: 144,
                        icon: Icons.auto_graph_rounded,
                        accentColor: const Color(0xFF4F46E5),
                        badge: 'Moyenne',
                        numericValue: averageTicket,
                        animatedFormatter: _fmtCompactMoney,
                      ),
                      MetricCard(
                        title: 'Taxes visibles',
                        value: '${dashboard.distinctTaxCount}',
                        subtitle: 'Categories presentes',
                        width: null,
                        minHeight: 144,
                        icon: Icons.pie_chart_outline_rounded,
                        accentColor: AppColors.chartOrange,
                        badge: 'Mix',
                        numericValue: dashboard.distinctTaxCount.toDouble(),
                        animatedFormatter: (value) => value.round().toString(),
                      ),
                    ]
                  : <Widget>[
                      MetricCard(
                        title: 'Total recettes',
                        value: _fmtMoney(dashboard.totalAmount),
                        subtitle: _controller.rangeLabel,
                        width: null,
                        minHeight: 144,
                        icon: Icons.payments_outlined,
                        accentColor: AppColors.primary,
                        badge: 'Revenu',
                        highlighted: true,
                        numericValue: dashboard.totalAmount.toDouble(),
                        animatedFormatter: _fmtMoney,
                      ),
                      MetricCard(
                        title: 'Transactions',
                        value: '${dashboard.transactionCount}',
                        subtitle: _controller.scopeLabel,
                        width: null,
                        minHeight: 144,
                        icon: Icons.receipt_long_outlined,
                        accentColor: AppColors.chartTeal,
                        badge: 'Volume',
                        numericValue: dashboard.transactionCount.toDouble(),
                        animatedFormatter: (value) => value.round().toString(),
                      ),
                      MetricCard(
                        title: 'Commune phare',
                        value: topCommuneName,
                        subtitle: topCommuneAmount,
                        width: null,
                        minHeight: 144,
                        icon: Icons.location_city_outlined,
                        accentColor: const Color(0xFF4F46E5),
                        badge: 'Leader',
                      ),
                      if (widget.profile.role.hasAlertsAccess)
                        MetricCard(
                          title: 'Alertes actives',
                          value: '${_controller.alertsOpen}',
                          subtitle: _controller.alertsCritiques > 0
                              ? '${_controller.alertsCritiques} critiques'
                              : 'Aucune urgence critique',
                          width: null,
                          minHeight: 144,
                          icon: Icons.warning_amber_outlined,
                          accentColor: _controller.alertsCritiques > 0
                              ? AppColors.chartRed
                              : AppColors.chartOrange,
                          badge:
                              _controller.alertsCritiques > 0 ? 'Urgent' : 'Sante',
                          numericValue: _controller.alertsOpen.toDouble(),
                          animatedFormatter: (value) => value.round().toString(),
                        )
                      else
                        MetricCard(
                          title: 'Taxes visibles',
                          value: '${dashboard.distinctTaxCount}',
                          subtitle: 'Apres filtres avances',
                          width: null,
                          minHeight: 144,
                          icon: Icons.pie_chart_outline_rounded,
                          accentColor: AppColors.chartOrange,
                          badge: 'Mix',
                          numericValue: dashboard.distinctTaxCount.toDouble(),
                          animatedFormatter: (value) => value.round().toString(),
                        ),
                    ];

              final barChartMinWidth =
                  isPhone ? math.max(360.0, byCommune.length * 96.0) : 0.0;
              final lineChartMinWidth =
                  isPhone ? math.max(360.0, dailySeries.length * 54.0) : 0.0;

              return RefreshIndicator(
                onRefresh: _refreshDashboard,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.all(horizontalPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _modernPanel(
                        context: context,
                        padding: EdgeInsets.all(isPhone ? 16 : 22),
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
                                      Text(
                                        widget.profile.role == AppRole.contribuable
                                            ? 'Mon espace contribuable'
                                            : 'Cockpit premium',
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: -0.4,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        widget.profile.role == AppRole.contribuable
                                            ? 'Une vue personnelle orientee suivi, comprehension et pilotage de vos paiements.'
                                            : 'Un espace analytique plus visuel, plus fluide et plus proche des interfaces SaaS avancees.',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                              height: 1.4,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!isPhone)
                                  FilledButton.icon(
                                    onPressed: _refreshDashboard,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Actualiser'),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _revealSection(
                              index: 0,
                              child: _buildHeroCard(
                                context,
                                dashboard,
                                isPhone: isPhone,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _revealSection(
                        index: 1,
                        child: _buildRecentTransactionsPanel(
                          context: context,
                          rows: filteredRows,
                          isPhone: isPhone,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _revealSection(
                        index: 2,
                        child: _buildMetricGrid(
                          width: contentWidth,
                          cards: cards,
                        ),
                      ),
                      if (isTaxpayer) ...[
                        const SizedBox(height: 16),
                        _revealSection(
                          index: 3,
                          child: _buildContribuableSpotlightPanel(
                            context: context,
                            topCommuneName: topCommuneName,
                            topCommuneAmount: topCommuneAmount,
                            dominantTaxLabel:
                                dominantTax?.label ?? 'Aucune dominante',
                            averageTicket: averageTicket,
                            transactionCount: dashboard.transactionCount,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _revealSection(
                        index: isTaxpayer ? 4 : 3,
                        child: _buildFiltersCard(
                          context: context,
                          isPhone: isPhone,
                          filteredCount: filteredRows.length,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _revealSection(
                        index: isTaxpayer ? 5 : 4,
                        child: ResponsiveTwoCards(
                        left: _chartSection(
                          context: context,
                          eyebrow: 'Analytics',
                          accentColor: AppColors.primary,
                          title: widget.profile.role == AppRole.contribuable
                              ? 'Mes paiements par commune'
                              : 'Revenus par commune',
                          subtitle: 'Lecture immediate des montants par territoire actif.',
                          action: isPhone
                              ? null
                              : _DashboardBadge(
                                  icon: Icons.location_on_outlined,
                                  label: '${byCommune.length} commune(s)',
                                  color: AppColors.primary,
                                ),
                          child: _scrollableCard(
                            minWidth: barChartMinWidth,
                            child: RevenueBarChartCard(
                              title: widget.profile.role == AppRole.contribuable
                                  ? 'Mes paiements par commune'
                                  : 'Revenus par commune',
                              data: byCommune,
                              embedded: true,
                            ),
                          ),
                        ),
                        right: _chartSection(
                          context: context,
                          eyebrow: 'Mix',
                          accentColor: AppColors.chartOrange,
                          title: widget.profile.role == AppRole.contribuable
                              ? 'Mes taxes par catégorie'
                              : 'Répartition par type de taxe',
                          subtitle:
                              'Vision claire de la structure fiscale dominante.',
                          action: isPhone
                              ? null
                              : _DashboardBadge(
                                  icon: Icons.pie_chart_outline_rounded,
                                  label: _truncate(
                                    dominantTax?.label ?? 'Aucune dominante',
                                    maxLength: 18,
                                  ),
                                  color: AppColors.chartOrange,
                                ),
                          child: TaxBreakdownPieCard(
                            title: widget.profile.role == AppRole.contribuable
                                ? 'Mes taxes par catégorie'
                                : 'Répartition par type de taxe',
                            compact: isPhone,
                            slices: taxSlices,
                            embedded: true,
                          ),
                        ),
                      ),
                      ),
                      const SizedBox(height: 16),
                      _revealSection(
                        index: isTaxpayer ? 6 : 5,
                        child: _chartSection(
                          context: context,
                          eyebrow: 'Evolution',
                          accentColor: AppColors.chartTeal,
                          title: widget.profile.role == AppRole.contribuable
                              ? 'Evolution de mes paiements'
                              : 'Evolution des revenus',
                          subtitle: 'Suivi quotidien sur la periode selectionnee.',
                          action: isPhone
                              ? null
                              : _DashboardBadge(
                                  icon: Icons.trending_up_rounded,
                                  label: 'Pic ${_fmtCompactMoney(peakDailyAmount)}',
                                  color: AppColors.chartTeal,
                                ),
                          child: _scrollableCard(
                            minWidth: lineChartMinWidth,
                            child: RevenueLineChartCard(
                              title: widget.profile.role == AppRole.contribuable
                                  ? 'Evolution de mes paiements'
                                  : 'Evolution des revenus',
                              data: dailySeries,
                              embedded: true,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
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
          Icon(
            icon,
            size: 15,
            color: light ? Colors.white : accent,
          ),
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
                  children: [
                    amountCard,
                    const SizedBox(height: 14),
                    details,
                  ],
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
                            end: maxValue == 0 ? 0 : data[i].amountUsd / maxValue,
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
