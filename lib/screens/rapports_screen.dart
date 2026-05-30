import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/app_role.dart';
import '../models/user_profile.dart';
import '../services/collections_live_listener.dart';
import '../services/gestia_data_service.dart';
import '../theme/app_colors.dart';
import '../utils/error_messages.dart';
import '../utils/report_exporter.dart';
import '../widgets/metric_card.dart';

class RapportsScreen extends StatefulWidget {
  const RapportsScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<RapportsScreen> createState() => _RapportsScreenState();
}

class _RapportsScreenState extends State<RapportsScreen> {
  late CollectionsLiveListener _collectionsLiveListener;
  late DateTimeRange _selectedRange;

  final _searchCtrl = TextEditingController();

  bool _loading = true;
  bool _exporting = false;
  String? _error;
  String _typeFilter = 'all';
  String _statusFilter = 'all';
  List<Map<String, dynamic>> _collections = const [];

  String? get _scope =>
      widget.profile.isGlobalSupervisor ? null : widget.profile.communeId;

  String? get _taxpayerScope =>
      widget.profile.hasRole(AppRole.contribuable) ? widget.profile.id : null;

  List<Map<String, dynamic>> get _visibleCollections {
    return _collections;
  }

  double get _totalRevenue => _sumRows(_visibleCollections);

  double get _taxesCollected => _sumRows(
    _visibleCollections.where((row) {
      final phase = row['revenue_phase']?.toString().toLowerCase() ?? '';
      final status = row['workflow_status']?.toString().toLowerCase() ?? '';
      return !phase.contains('recouvrement') &&
          !status.contains('recouvrement');
    }),
  );

  double get _recoveryAmount => _sumRows(
    _visibleCollections.where((row) {
      final phase = row['revenue_phase']?.toString().toLowerCase() ?? '';
      final status = row['workflow_status']?.toString().toLowerCase() ?? '';
      return phase.contains('recouvrement') || status.contains('recouvrement');
    }),
  );

  int get _reportsGenerated => math.max(5, _collections.length + 5);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedRange = DateTimeRange(
      start: DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 30)),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59),
    );
    _searchCtrl.addListener(_handleSearchChanged);
    _startLiveUpdates();
    _load();
  }

  @override
  void didUpdateWidget(covariant RapportsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final profileChanged =
        oldWidget.profile.id != widget.profile.id ||
        oldWidget.profile.rolesLabel != widget.profile.rolesLabel ||
        oldWidget.profile.communeId != widget.profile.communeId;
    if (profileChanged) {
      _collectionsLiveListener.dispose();
      _startLiveUpdates();
      _load();
    }
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_handleSearchChanged);
    _searchCtrl.dispose();
    _collectionsLiveListener.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    if (mounted) setState(() {});
  }

  void _startLiveUpdates() {
    _collectionsLiveListener = CollectionsLiveListener(
      profile: widget.profile,
      onCollectionInserted: () => _load(silent: true),
    )..start();
  }

  Future<void> _load({bool silent = false}) async {
    _error = null;
    if (!silent) {
      setState(() => _loading = true);
    }

    try {
      final rows = await GestiaDataService.fetchCollectionsInRange(
        from: _selectedRange.start,
        to: _selectedRange.end,
        communeId: _scope,
        taxpayerProfileId: _taxpayerScope,
      );
      if (!mounted) return;
      setState(() {
        _collections = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _error = userFacingErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _pickPeriod() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _selectedRange,
      helpText: 'Choisir la période',
      saveText: 'Appliquer',
    );
    if (picked == null) return;
    setState(() {
      _selectedRange = DateTimeRange(
        start: _startOfDay(picked.start),
        end: _endOfDay(picked.end),
      );
    });
    await _load();
  }

  Future<void> _exportPdf() async {
    await _runExport(
      action: () => ReportExporter.exportPdf(_buildExportData()),
      successMessage: 'Rapport PDF exporte.',
    );
  }

  Future<void> _exportExcel() async {
    await _runExport(
      action: () => ReportExporter.exportExcel(_buildExportData()),
      successMessage: 'Rapport Excel exporte.',
    );
  }

  Future<void> _runExport({
    required Future<String?> Function() action,
    required String successMessage,
  }) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final path = await action();
      if (!mounted) return;
      final message = path == null || path.isEmpty
          ? 'Export annule.'
          : '$successMessage Fichier: $path';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingErrorMessage(e, prefix: 'Échec de l’export')),
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _resetFilters() {
    setState(() {
      _typeFilter = 'all';
      _statusFilter = 'all';
      _searchCtrl.clear();
    });
  }

  void _showActionMessage(String label) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label pret.')));
  }

  ReportExportData _buildExportData() {
    final rows =
        _visibleCollections
            .map(
              (row) => ReportExportRow(
                collectedAt:
                    DateTime.tryParse(
                      row['collected_at']?.toString() ?? '',
                    )?.toLocal() ??
                    DateTime.now(),
                communeName: _communeName(row),
                taxCategory: row['tax_category']?.toString() ?? 'Autres',
                amountUsd: (row['amount'] as num?)?.toDouble() ?? 0,
              ),
            )
            .toList()
          ..sort((a, b) => b.collectedAt.compareTo(a.collectedAt));

    return ReportExportData(
      title: widget.profile.hasRole(AppRole.contribuable)
          ? 'Mes paiements - ${_periodLabel()}'
          : 'Rapport de gestion - ${_periodLabel()}',
      scopeLabel: _scopeLabel(),
      generatedAt: DateTime.now(),
      metrics: [
        ReportExportMetric(label: 'Total recettes', value: _fmt(_totalRevenue)),
        ReportExportMetric(
          label: 'Taxes collectees',
          value: _fmt(_taxesCollected),
        ),
        ReportExportMetric(label: 'Recouvrement', value: _fmt(_recoveryAmount)),
        ReportExportMetric(
          label: 'Transactions',
          value: '${_visibleCollections.length}',
        ),
      ],
      rows: rows,
    );
  }

  List<_DailyRevenuePoint> get _dailySeries {
    final start = _startOfDay(_selectedRange.start);
    final end = _startOfDay(_selectedRange.end);
    final dayCount = end.difference(start).inDays + 1;
    final totals = <DateTime, double>{
      for (var i = 0; i < dayCount; i++) start.add(Duration(days: i)): 0,
    };

    for (final row in _visibleCollections) {
      final parsed = DateTime.tryParse(row['collected_at']?.toString() ?? '');
      if (parsed == null) continue;
      final day = _startOfDay(parsed.toLocal());
      if (!totals.containsKey(day)) continue;
      totals[day] = totals[day]! + ((row['amount'] as num?)?.toDouble() ?? 0);
    }

    return [
      for (final entry in totals.entries)
        _DailyRevenuePoint(entry.key, entry.value),
    ];
  }

  List<_TaxBreakdownItem> get _taxBreakdown {
    final totals = <String, double>{};
    for (final row in _visibleCollections) {
      final label = row['tax_category']?.toString().trim();
      final key = label == null || label.isEmpty ? 'Autres taxes' : label;
      totals[key] =
          (totals[key] ?? 0) + ((row['amount'] as num?)?.toDouble() ?? 0);
    }

    final total = totals.values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) return const [];

    final colors = [
      const Color(0xFF0BAA35),
      AppColors.chartBlue,
      AppColors.chartPurple,
      AppColors.chartOrange,
      AppColors.chartTeal,
      AppColors.chartRed,
    ];

    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (var i = 0; i < entries.length; i++)
        _TaxBreakdownItem(
          label: entries[i].key,
          amount: entries[i].value,
          percent: entries[i].value / total * 100,
          color: colors[i % colors.length],
        ),
    ];
  }

  List<_ReportRow> get _reports {
    final generatedAt = DateTime.now();
    final generator = widget.profile.fullName;
    return [
      _ReportRow(
        index: 1,
        title: 'Rapport des recettes',
        subtitle: 'Résumé des recettes par période',
        type: 'Financier',
        period: _periodLabel(),
        generatedBy: generator,
        generatedAt: generatedAt,
        status: 'Termine',
        color: AppColors.chartTeal,
      ),
      _ReportRow(
        index: 2,
        title: 'Rapport des taxes',
        subtitle: 'Detail des taxes collectees',
        type: 'Taxes',
        period: _periodLabel(),
        generatedBy: 'Marie Kabeya',
        generatedAt: generatedAt.subtract(const Duration(minutes: 38)),
        status: 'Termine',
        color: AppColors.chartBlue,
      ),
      _ReportRow(
        index: 3,
        title: 'Rapport de recouvrement',
        subtitle: 'Performance de recouvrement',
        type: 'Recouvrement',
        period: _periodLabel(),
        generatedBy: 'Patrick Tshibanda',
        generatedAt: generatedAt.subtract(const Duration(hours: 1, minutes: 5)),
        status: _recoveryAmount > 0 ? 'Termine' : 'En cours',
        color: AppColors.chartPurple,
      ),
      _ReportRow(
        index: 4,
        title: 'Rapport par province',
        subtitle: 'Comparatif par province',
        type: 'Analytique',
        period: _periodLabel(),
        generatedBy: 'Grace Mutombo',
        generatedAt: generatedAt.subtract(const Duration(days: 1, hours: 2)),
        status: 'Termine',
        color: AppColors.chartOrange,
      ),
      _ReportRow(
        index: 5,
        title: 'Rapport annuel ${generatedAt.year}',
        subtitle: 'Rapport annuel consolide',
        type: 'Financier',
        period: '01/01/${generatedAt.year} - 31/12/${generatedAt.year}',
        generatedBy: generator,
        generatedAt: DateTime(generatedAt.year, 1, 2, 11, 10),
        status: 'Termine',
        color: AppColors.chartTeal,
      ),
    ];
  }

  List<_ReportRow> get _visibleReports {
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = _reports.where((report) {
      final matchesQuery =
          query.isEmpty ||
          report.title.toLowerCase().contains(query) ||
          report.subtitle.toLowerCase().contains(query) ||
          report.type.toLowerCase().contains(query) ||
          report.generatedBy.toLowerCase().contains(query);
      final matchesType =
          _typeFilter == 'all' || report.type.toLowerCase() == _typeFilter;
      final matchesStatus =
          _statusFilter == 'all' ||
          report.status.toLowerCase() == _statusFilter;
      return matchesQuery && matchesType && matchesStatus;
    }).toList();
    return filtered;
  }

  double _sumRows(Iterable<Map<String, dynamic>> rows) {
    return rows.fold<double>(
      0,
      (sum, row) => sum + ((row['amount'] as num?)?.toDouble() ?? 0),
    );
  }

  String _fmt(double value) {
    final source = value.toStringAsFixed(0);
    final buffer = StringBuffer();
    for (var i = 0; i < source.length; i++) {
      if (i > 0 && (source.length - i) % 3 == 0) buffer.write('.');
      buffer.write(source[i]);
    }
    return '$buffer FC';
  }

  String _compactMoney(double value) {
    if (value >= 1000000000) {
      return '${(value / 1000000000).toStringAsFixed(1)}B';
    }
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(0)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(0)}K';
    return value.toStringAsFixed(0);
  }

  String _periodLabel() {
    return '${_dateLabel(_selectedRange.start)} - ${_dateLabel(_selectedRange.end)}';
  }

  String _scopeLabel() {
    if (widget.profile.hasRole(AppRole.contribuable)) {
      return widget.profile.taxpayerIdentifier != null &&
              widget.profile.taxpayerIdentifier!.isNotEmpty
          ? 'ID ${widget.profile.taxpayerIdentifier}'
          : 'Mes paiements';
    }
    return 'Mairie';
  }

  String _communeName(Map<String, dynamic> row) {
    return 'Mairie';
  }

  String _dateLabel(DateTime value) {
    final local = value.toLocal();
    String two(int input) => input.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year}';
  }

  String _dateTimeLabel(DateTime value) {
    final local = value.toLocal();
    String two(int input) => input.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year}, '
        '${two(local.hour)}:${two(local.minute)}';
  }

  DateTime _startOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  DateTime _endOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day, 23, 59, 59);

  Color _pageColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? const Color(0xFF08111F) : const Color(0xFFF6F8FC);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        color: _pageColor(context),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Container(
        color: _pageColor(context),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_outlined),
                  label: const Text('Reessayer'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      color: _pageColor(context),
      child: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context),
              const SizedBox(height: 16),
              _buildMetricGrid(context),
              const SizedBox(height: 18),
              _buildFilterPanel(context),
              const SizedBox(height: 18),
              _buildCharts(context),
              const SizedBox(height: 18),
              _buildReportsAndActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.profile.hasRole(AppRole.contribuable)
                  ? 'Mes rapports'
                  : 'Rapports',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Consultez, analysez et exportez les données de gestion.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        );

        final search = SizedBox(
          width: compact ? double.infinity : 390,
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Rechercher un rapport...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: _searchCtrl.clear,
                      icon: const Icon(Icons.close),
                    ),
              filled: true,
              fillColor: cs.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: cs.outline.withValues(alpha: 0.2),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: cs.outline.withValues(alpha: 0.2),
                ),
              ),
            ),
          ),
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 14), search],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            search,
          ],
        );
      },
    );
  }

  Widget _buildMetricGrid(BuildContext context) {
    final metricData = [
      (
        title: 'Total recettes',
        value: _fmt(_totalRevenue),
        subtitle: '12,5% ce mois',
        icon: Icons.bar_chart_rounded,
        color: const Color(0xFF0BAA35),
        numeric: _totalRevenue,
      ),
      (
        title: 'Taxes collectees',
        value: _fmt(_taxesCollected),
        subtitle: '8,2% ce mois',
        icon: Icons.shopping_bag_outlined,
        color: AppColors.chartBlue,
        numeric: _taxesCollected,
      ),
      (
        title: 'Recouvrement',
        value: _fmt(_recoveryAmount),
        subtitle: '15,7% ce mois',
        icon: Icons.pie_chart_outline_rounded,
        color: AppColors.chartPurple,
        numeric: _recoveryAmount,
      ),
      (
        title: 'Rapports générés',
        value: '$_reportsGenerated',
        subtitle: '10,3% ce mois',
        icon: Icons.description_outlined,
        color: AppColors.chartOrange,
        numeric: _reportsGenerated.toDouble(),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1180
            ? 4
            : width >= 760
            ? 2
            : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: metricData.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            mainAxisExtent: 138,
          ),
          itemBuilder: (context, index) {
            final item = metricData[index];
            return MetricCard(
              width: null,
              minHeight: 110,
              title: item.title,
              value: item.value,
              subtitle: item.subtitle,
              icon: item.icon,
              accentColor: item.color,
              numericValue: item.numeric,
              animatedFormatter: index == 3
                  ? (value) => value.toStringAsFixed(0)
                  : _fmt,
            );
          },
        );
      },
    );
  }

  Widget _buildFilterPanel(BuildContext context) {
    return _ReportPanel(
      child: Wrap(
        spacing: 14,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          _FieldShell(
            label: 'Période',
            width: 270,
            child: InkWell(
              onTap: _pickPeriod,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_month_outlined),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        _periodLabel(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.expand_more, size: 18),
                  ],
                ),
              ),
            ),
          ),
          _FieldShell(
            label: 'Type de rapport',
            width: 220,
            child: DropdownButtonFormField<String>(
              initialValue: _typeFilter,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Tous les types')),
                DropdownMenuItem(value: 'financier', child: Text('Financier')),
                DropdownMenuItem(value: 'taxes', child: Text('Taxes')),
                DropdownMenuItem(
                  value: 'recouvrement',
                  child: Text('Recouvrement'),
                ),
                DropdownMenuItem(
                  value: 'analytique',
                  child: Text('Analytique'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _typeFilter = value);
              },
            ),
          ),
          _FieldShell(
            label: 'Statut',
            width: 220,
            child: DropdownButtonFormField<String>(
              initialValue: _statusFilter,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Tous les statuts')),
                DropdownMenuItem(value: 'termine', child: Text('Termine')),
                DropdownMenuItem(value: 'en cours', child: Text('En cours')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _statusFilter = value);
              },
            ),
          ),
          SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              onPressed: _resetFilters,
              icon: const Icon(Icons.refresh_outlined),
              label: const Text('Réinitialiser'),
            ),
          ),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: () => setState(() {}),
              icon: const Icon(Icons.filter_alt_outlined),
              label: const Text('Appliquer les filtres'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCharts(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 980;
        final left = _buildRevenuePreview(context);
        final right = _buildTaxBreakdown(context);

        if (compact) {
          return Column(children: [left, const SizedBox(height: 14), right]);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 14),
            Expanded(child: right),
          ],
        );
      },
    );
  }

  Widget _buildRevenuePreview(BuildContext context) {
    final series = _dailySeries;
    final maxValue = series.isEmpty
        ? 1.0
        : series.map((item) => item.amount).reduce(math.max);
    final maxY = math.max(maxValue * 1.18, 1.0);

    return _ReportPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelHeader(
            title: 'Aperçu des recettes',
            trailing: _SmallSelector(label: 'Par jour'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 230,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: math.max(0, series.length - 1).toDouble(),
                minY: 0,
                maxY: maxY,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.16),
                    strokeWidth: 1,
                  ),
                ),
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
                      reservedSize: 48,
                      getTitlesWidget: (value, meta) {
                        if (value <= 0) return const SizedBox.shrink();
                        return Text(
                          _compactMoney(value),
                          style: const TextStyle(
                            color: AppColors.mutedText,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final index = value.round();
                        if (index < 0 || index >= series.length) {
                          return const SizedBox.shrink();
                        }
                        final step = math.max(1, series.length ~/ 5);
                        if (index != 0 &&
                            index != series.length - 1 &&
                            index % step != 0) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _shortDateLabel(series[index].day),
                            style: const TextStyle(
                              color: AppColors.mutedText,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => [
                      for (final spot in spots)
                        LineTooltipItem(
                          _fmt(spot.y),
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                    ],
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < series.length; i++)
                        FlSpot(i.toDouble(), series[i].amount),
                    ],
                    isCurved: true,
                    color: const Color(0xFF0BAA35),
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF0BAA35).withValues(alpha: 0.22),
                          const Color(0xFF0BAA35).withValues(alpha: 0.02),
                        ],
                      ),
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

  Widget _buildTaxBreakdown(BuildContext context) {
    final items = _taxBreakdown;

    return _ReportPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelHeader(
            title: 'Répartition par type de taxe',
            trailing: _SmallSelector(label: 'Ce mois'),
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            SizedBox(
              height: 230,
              child: Center(
                child: Text(
                  'Aucune donnée sur la période.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 560;
                final chart = SizedBox(
                  width: compact ? 220 : 250,
                  height: 230,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          centerSpaceRadius: 58,
                          sectionsSpace: 2,
                          startDegreeOffset: -90,
                          sections: [
                            for (final item in items)
                              PieChartSectionData(
                                color: item.color,
                                value: item.amount,
                                title: '',
                                radius: 48,
                              ),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Total',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          Text(
                            _compactMoney(_totalRevenue),
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const Text('FC', style: TextStyle(fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                );

                final legend = Column(
                  children: [
                    for (final item in items.take(5))
                      _TaxLegendRow(
                        label: item.label,
                        percent: item.percent,
                        amount: _fmt(item.amount),
                        color: item.color,
                      ),
                  ],
                );

                if (compact) {
                  return Column(children: [chart, legend]);
                }
                return Row(
                  children: [
                    chart,
                    const SizedBox(width: 18),
                    Expanded(child: legend),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildReportsAndActions(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1050;
        final list = _buildReportsTable(context);
        final side = _buildSidePanels(context);
        if (compact) {
          return Column(children: [list, const SizedBox(height: 14), side]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 4, child: list),
            const SizedBox(width: 14),
            SizedBox(width: 280, child: side),
          ],
        );
      },
    );
  }

  Widget _buildReportsTable(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _visibleReports;

    return _ReportPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Liste des rapports',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 48,
              dataRowMinHeight: 58,
              dataRowMaxHeight: 70,
              columnSpacing: 28,
              columns: const [
                DataColumn(label: Text('#')),
                DataColumn(label: Text('Nom du rapport')),
                DataColumn(label: Text('Type')),
                DataColumn(label: Text('Période')),
                DataColumn(label: Text('Généré par')),
                DataColumn(label: Text('Date de generation')),
                DataColumn(label: Text('Statut')),
                DataColumn(label: Text('Actions')),
              ],
              rows: [
                for (final row in rows)
                  DataRow(
                    cells: [
                      DataCell(Text('${row.index}')),
                      DataCell(
                        SizedBox(
                          width: 210,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                row.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      DataCell(_TypeBadge(label: row.type, color: row.color)),
                      DataCell(Text(row.period)),
                      DataCell(Text(row.generatedBy)),
                      DataCell(Text(_dateTimeLabel(row.generatedAt))),
                      DataCell(_StatusBadge(label: row.status)),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _TableActionButton(
                              icon: Icons.download_outlined,
                              color: const Color(0xFF0BAA35),
                              tooltip: 'Telecharger',
                              onPressed: _exporting ? null : _exportPdf,
                            ),
                            const SizedBox(width: 6),
                            _TableActionButton(
                              icon: Icons.visibility_outlined,
                              color: AppColors.chartBlue,
                              tooltip: 'Voir',
                              onPressed: () => _showActionMessage(row.title),
                            ),
                            const SizedBox(width: 6),
                            _TableActionButton(
                              icon: Icons.more_vert,
                              color: theme.colorScheme.onSurfaceVariant,
                              tooltip: 'Plus',
                              onPressed: () => _showActionMessage('Options'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 14,
            runSpacing: 12,
            children: [
              Text(
                rows.isEmpty
                    ? 'Aucun rapport trouve'
                    : 'Affichage 1 a ${rows.length} sur $_reportsGenerated rapports',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SpacerShim(),
              _PaginationButton(icon: Icons.chevron_left, onPressed: () {}),
              _PageNumber(label: '1', selected: true),
              _PageNumber(label: '2'),
              _PageNumber(label: '3'),
              _PageNumber(label: '4'),
              _PageNumber(label: '5'),
              const Text('...'),
              _PageNumber(label: '26'),
              _PaginationButton(icon: Icons.chevron_right, onPressed: () {}),
              const SizedBox(width: 16),
              SizedBox(
                width: 145,
                child: DropdownButtonFormField<int>(
                  initialValue: 10,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 10, child: Text('10 par page')),
                    DropdownMenuItem(value: 25, child: Text('25 par page')),
                    DropdownMenuItem(value: 50, child: Text('50 par page')),
                  ],
                  onChanged: (_) {},
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSidePanels(BuildContext context) {
    return Column(
      children: [
        _ReportPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Actions rapides',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 14),
              _QuickActionTile(
                icon: Icons.add,
                title: 'Nouveau rapport',
                subtitle: 'Créer un rapport personnalisé',
                onTap: () => _showActionMessage('Nouveau rapport'),
              ),
              _QuickActionTile(
                icon: Icons.calendar_month_outlined,
                title: 'Planifier un rapport',
                subtitle: 'Automatiser la generation',
                onTap: () => _showActionMessage('Planification'),
              ),
              _QuickActionTile(
                icon: Icons.article_outlined,
                title: 'Modeles de rapports',
                subtitle: 'Gerer les modeles existants',
                onTap: () => _showActionMessage('Modeles'),
              ),
              _QuickActionTile(
                icon: Icons.file_download_outlined,
                title: 'Exporter global',
                subtitle: 'Exporter tous les rapports',
                onTap: _exporting ? null : _exportExcel,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _ReportPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Rapports populaires',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 14),
              _PopularReportTile(
                icon: Icons.query_stats_outlined,
                title: 'Rapport des recettes',
                subtitle: '45 generations',
              ),
              _PopularReportTile(
                icon: Icons.badge_outlined,
                title: 'Rapport des taxes',
                subtitle: '32 generations',
              ),
              _PopularReportTile(
                icon: Icons.location_city_outlined,
                title: 'Rapport par province',
                subtitle: '28 generations',
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => _showActionMessage('Tous les rapports'),
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: const Text('Voir tous les rapports'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _shortDateLabel(DateTime value) {
    const months = [
      'Jan',
      'Fev',
      'Mar',
      'Avr',
      'Mai',
      'Juin',
      'Juil',
      'Aou',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${value.day.toString().padLeft(2, '0')} ${months[value.month - 1]}';
  }
}

class _DailyRevenuePoint {
  const _DailyRevenuePoint(this.day, this.amount);

  final DateTime day;
  final double amount;
}

class _TaxBreakdownItem {
  const _TaxBreakdownItem({
    required this.label,
    required this.amount,
    required this.percent,
    required this.color,
  });

  final String label;
  final double amount;
  final double percent;
  final Color color;
}

class _ReportRow {
  const _ReportRow({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.type,
    required this.period,
    required this.generatedBy,
    required this.generatedAt,
    required this.status,
    required this.color,
  });

  final int index;
  final String title;
  final String subtitle;
  final String type;
  final String period;
  final String generatedBy;
  final DateTime generatedAt;
  final String status;
  final Color color;
}

class _ReportPanel extends StatelessWidget {
  const _ReportPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: isDark ? 0.94 : 0.98),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.title, required this.trailing});

  final String title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        trailing,
      ],
    );
  }
}

class _SmallSelector extends StatelessWidget {
  const _SmallSelector({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0BAA35).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF087C2B),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.expand_more, color: Color(0xFF087C2B), size: 16),
        ],
      ),
    );
  }
}

class _FieldShell extends StatelessWidget {
  const _FieldShell({
    required this.label,
    required this.child,
    required this.width,
  });

  final String label;
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _TaxLegendRow extends StatelessWidget {
  const _TaxLegendRow({
    required this.label,
    required this.percent,
    required this.amount,
    required this.color,
  });

  final String label;
  final double percent;
  final String amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.10),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${percent.toStringAsFixed(0)}%',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 18),
          SizedBox(
            width: 118,
            child: Text(
              amount,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final isDone = label.toLowerCase() == 'termine';
    final color = isDone ? const Color(0xFF0BAA35) : AppColors.chartOrange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDone ? Icons.check_circle : Icons.hourglass_bottom,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _TableActionButton extends StatelessWidget {
  const _TableActionButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        style: IconButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.08),
          foregroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: color.withValues(alpha: 0.18)),
          ),
        ),
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF0BAA35)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF087C2B),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
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

class _PopularReportTile extends StatelessWidget {
  const _PopularReportTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF0BAA35), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _PaginationButton extends StatelessWidget {
  const _PaginationButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _PageNumber extends StatelessWidget {
  const _PageNumber({required this.label, this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF0BAA35) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected
              ? const Color(0xFF0BAA35)
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.22),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : null,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class SpacerShim extends StatelessWidget {
  const SpacerShim({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(width: 60);
  }
}
