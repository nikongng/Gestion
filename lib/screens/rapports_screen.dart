import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../branding/branding_scope.dart';
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
  String _categoryFilter = 'all';
  String _statusFilter = 'all';
  List<Map<String, dynamic>> _collections = const [];

  String? get _scope =>
      widget.profile.isGlobalSupervisor ? null : widget.profile.communeId;

  String? get _taxpayerScope =>
      widget.profile.hasRole(AppRole.contribuable) ? widget.profile.id : null;

  List<Map<String, dynamic>> get _visibleCollections {
    final query = _searchCtrl.text.trim().toLowerCase();
    final rows =
        _collections.where((row) {
            final matchesCategory =
                _categoryFilter == 'all' ||
                _collectionCategory(row) == _categoryFilter;
            final matchesStatus =
                _statusFilter == 'all' ||
                _collectionStatusKey(row) == _statusFilter;
            final searchable = [
              _dateTimeLabel(_collectionDate(row)),
              _collectionNoteNumber(row),
              _collectionTaxpayerId(row),
              _collectionCategory(row),
              _communeName(row),
              _collectionStatusLabel(row),
              _collectionChannel(row),
              row['id']?.toString() ?? '',
            ].join(' ').toLowerCase();
            final matchesQuery = query.isEmpty || searchable.contains(query);
            return matchesQuery && matchesCategory && matchesStatus;
          }).toList()
          ..sort((a, b) => _collectionDate(b).compareTo(_collectionDate(a)));
    return rows;
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

  double get _recoveryAmount =>
      _sumRows(_visibleCollections.where(_isRecoveryRow));

  int get _recoveryOperations =>
      _visibleCollections.where(_isRecoveryRow).length;

  bool _isRecoveryRow(Map<String, dynamic> row) {
    final phase = row['revenue_phase']?.toString().toLowerCase() ?? '';
    final status = row['workflow_status']?.toString().toLowerCase() ?? '';
    return phase.contains('recouvrement') || status.contains('recouvrement');
  }

  DateTime? get _latestCollectionDate {
    DateTime? latest;
    for (final row in _visibleCollections) {
      final parsed = DateTime.tryParse(row['collected_at']?.toString() ?? '');
      if (parsed == null) continue;
      final local = parsed.toLocal();
      if (latest == null || local.isAfter(latest)) {
        latest = local;
      }
    }
    return latest;
  }

  List<String> get _availableTaxCategories {
    final values = _collections.map(_collectionCategory).toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  List<String> get _availableStatusKeys {
    final values = _collections.map(_collectionStatusKey).toSet().toList()
      ..sort((a, b) => _statusLabel(a).compareTo(_statusLabel(b)));
    return values;
  }

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
      successMessage: 'Rapport PDF exporté.',
    );
  }

  Future<void> _exportExcel() async {
    await _runExport(
      action: () => ReportExporter.exportExcel(_buildExportData()),
      successMessage: 'Rapport Excel exporté.',
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
          ? 'Export annulé.'
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
      _categoryFilter = 'all';
      _statusFilter = 'all';
      _searchCtrl.clear();
    });
  }

  ReportExportData _buildExportData() {
    final rows =
        _visibleCollections
            .map(
              (row) => ReportExportRow(
                collectedAt: _collectionDate(row),
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
      cdfRate: _cdfRate,
      metrics: [
        ReportExportMetric(label: 'Total recettes', value: _fmt(_totalRevenue)),
        ReportExportMetric(
          label: 'Taxes collectées',
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

  DateTime _collectionDate(Map<String, dynamic> row) {
    final parsed = DateTime.tryParse(row['collected_at']?.toString() ?? '');
    return parsed?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _collectionCategory(Map<String, dynamic> row) {
    final value = row['tax_category']?.toString().trim();
    return value == null || value.isEmpty ? 'Autres' : value;
  }

  String _collectionChannel(Map<String, dynamic> row) {
    final value = row['payment_channel']?.toString().trim();
    return value == null || value.isEmpty ? 'Non précisé' : value;
  }

  String _collectionTaxpayerId(Map<String, dynamic> row) {
    final value = row['taxpayer_identifier']?.toString().trim();
    return value == null || value.isEmpty ? '-' : value;
  }

  String _collectionNoteNumber(Map<String, dynamic> row) {
    final note = row['perception_note_number']?.toString().trim();
    if (note != null && note.isNotEmpty) return note;
    final cpi = row['cpi_number']?.toString().trim();
    if (cpi != null && cpi.isNotEmpty) return cpi;
    final id = row['id']?.toString().trim();
    if (id == null || id.isEmpty) return '-';
    return id.length > 8 ? id.substring(0, 8) : id;
  }

  String _collectionStatusKey(Map<String, dynamic> row) {
    final workflow = row['workflow_status']?.toString().trim();
    if (workflow != null && workflow.isNotEmpty) return workflow;
    final phase = row['revenue_phase']?.toString().trim();
    if (phase != null && phase.isNotEmpty) return phase;
    return 'non_precise';
  }

  String _collectionStatusLabel(Map<String, dynamic> row) {
    return _statusLabel(_collectionStatusKey(row));
  }

  String _statusLabel(String value) {
    return switch (value) {
      'apuree_cpi_genere' => 'Apurée',
      'paiement_declare' => 'Note payée',
      'en_recouvrement' => 'En recouvrement',
      'ordonnee' => 'Ordonnée',
      'taxation_creee' => 'À ordonnancer',
      'apurement' => 'Apurement',
      'ordonnancement' => 'Ordonnancement',
      'recouvrement' => 'Recouvrement',
      'non_precise' => 'Non précisé',
      _ => value,
    };
  }

  Color _categoryColor(String category) {
    final colors = [
      const Color(0xFF0BAA35),
      AppColors.chartBlue,
      AppColors.chartPurple,
      AppColors.chartOrange,
      AppColors.chartTeal,
      AppColors.chartRed,
    ];
    final index = _availableTaxCategories.indexOf(category);
    return colors[(index < 0 ? 0 : index) % colors.length];
  }

  double _sumRows(Iterable<Map<String, dynamic>> rows) {
    return rows.fold<double>(
      0,
      (sum, row) => sum + ((row['amount'] as num?)?.toDouble() ?? 0),
    );
  }

  String _fmt(double value) {
    return '${_formatWholeNumber(_usdToCdf(value))} FC';
  }

  double get _cdfRate {
    final rate = BrandingScope.of(context).cdfRate;
    return rate > 0 ? rate : 2300;
  }

  double _usdToCdf(double amountUsd) => amountUsd * _cdfRate;

  String _formatWholeNumber(double value) {
    final source = value.toStringAsFixed(0);
    final buffer = StringBuffer();
    for (var i = 0; i < source.length; i++) {
      if (i > 0 && (source.length - i) % 3 == 0) buffer.write('.');
      buffer.write(source[i]);
    }
    return buffer.toString();
  }

  String _compactMoney(double value) {
    final cdfValue = _usdToCdf(value);
    if (cdfValue >= 1000000000) {
      return '${(cdfValue / 1000000000).toStringAsFixed(1)}B';
    }
    if (cdfValue >= 1000000) {
      return '${(cdfValue / 1000000).toStringAsFixed(0)}M';
    }
    if (cdfValue >= 1000) {
      return '${(cdfValue / 1000).toStringAsFixed(0)}K';
    }
    return cdfValue.toStringAsFixed(0);
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
                  label: const Text('Réessayer'),
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
              hintText: 'Rechercher une collection...',
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
        subtitle:
            '${_visibleCollections.length} transaction${_visibleCollections.length > 1 ? 's' : ''}',
        icon: Icons.bar_chart_rounded,
        color: const Color(0xFF0BAA35),
        numeric: _totalRevenue,
      ),
      (
        title: 'Taxes collectées',
        value: _fmt(_taxesCollected),
        subtitle:
            '${_taxBreakdown.length} type${_taxBreakdown.length > 1 ? 's' : ''} de taxe',
        icon: Icons.shopping_bag_outlined,
        color: AppColors.chartBlue,
        numeric: _taxesCollected,
      ),
      (
        title: 'Recouvrement',
        value: _fmt(_recoveryAmount),
        subtitle:
            '$_recoveryOperations opération${_recoveryOperations > 1 ? 's' : ''}',
        icon: Icons.pie_chart_outline_rounded,
        color: AppColors.chartPurple,
        numeric: _recoveryAmount,
      ),
      (
        title: 'Transactions',
        value: '${_visibleCollections.length}',
        subtitle: _collections.isEmpty
            ? 'Aucune donnée chargée'
            : 'Selon les filtres actifs',
        icon: Icons.description_outlined,
        color: AppColors.chartOrange,
        numeric: _visibleCollections.length.toDouble(),
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
    final categories = _availableTaxCategories;
    final statuses = _availableStatusKeys;
    final categoryValue =
        _categoryFilter == 'all' || categories.contains(_categoryFilter)
        ? _categoryFilter
        : 'all';
    final statusValue =
        _statusFilter == 'all' || statuses.contains(_statusFilter)
        ? _statusFilter
        : 'all';

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
            label: 'Type de taxe',
            width: 220,
            child: DropdownButtonFormField<String>(
              initialValue: categoryValue,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(
                  value: 'all',
                  child: Text('Toutes les taxes'),
                ),
                for (final category in categories)
                  DropdownMenuItem(value: category, child: Text(category)),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _categoryFilter = value);
              },
            ),
          ),
          _FieldShell(
            label: 'Statut',
            width: 220,
            child: DropdownButtonFormField<String>(
              initialValue: statusValue,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(
                  value: 'all',
                  child: Text('Tous les statuts'),
                ),
                for (final status in statuses)
                  DropdownMenuItem(
                    value: status,
                    child: Text(_statusLabel(status)),
                  ),
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
            trailing: _SmallSelector(label: 'Période'),
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
    final rows = _visibleCollections;

    return _ReportPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Lignes du rapport',
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
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('N° note')),
                DataColumn(label: Text('NIP')),
                DataColumn(label: Text('Type de taxe')),
                DataColumn(label: Text('Montant')),
                DataColumn(label: Text('Point de taxation')),
                DataColumn(label: Text('Statut')),
              ],
              rows: [
                for (var i = 0; i < rows.length; i++)
                  DataRow(
                    cells: [
                      DataCell(Text('${i + 1}')),
                      DataCell(Text(_dateTimeLabel(_collectionDate(rows[i])))),
                      DataCell(Text(_collectionNoteNumber(rows[i]))),
                      DataCell(Text(_collectionTaxpayerId(rows[i]))),
                      DataCell(
                        SizedBox(
                          width: 210,
                          child: _TypeBadge(
                            label: _collectionCategory(rows[i]),
                            color: _categoryColor(_collectionCategory(rows[i])),
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          _fmt((rows[i]['amount'] as num?)?.toDouble() ?? 0),
                        ),
                      ),
                      DataCell(Text(_communeName(rows[i]))),
                      DataCell(
                        _StatusBadge(label: _collectionStatusLabel(rows[i])),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            rows.isEmpty
                ? 'Aucune collection disponible pour la période sélectionnée'
                : '${rows.length} ligne${rows.length > 1 ? 's' : ''} affichée${rows.length > 1 ? 's' : ''} sur ${_collections.length} collection${_collections.length > 1 ? 's' : ''} chargée${_collections.length > 1 ? 's' : ''}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
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
                icon: Icons.refresh_outlined,
                title: 'Actualiser les données',
                subtitle: 'Recharger les collections',
                onTap: () => _load(),
              ),
              _QuickActionTile(
                icon: Icons.picture_as_pdf_outlined,
                title: 'Exporter PDF',
                subtitle: 'Exporter le rapport filtré',
                onTap: _exporting ? null : _exportPdf,
              ),
              _QuickActionTile(
                icon: Icons.table_chart_outlined,
                title: 'Exporter Excel',
                subtitle: 'Exporter les lignes visibles',
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
                'Synthèse de la période',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 14),
              _SummaryTile(
                icon: Icons.receipt_long_outlined,
                title: 'Transactions',
                subtitle:
                    '${_visibleCollections.length} enregistrée${_visibleCollections.length > 1 ? 's' : ''}',
              ),
              _SummaryTile(
                icon: Icons.category_outlined,
                title: 'Types de taxes',
                subtitle:
                    '${_taxBreakdown.length} catégorie${_taxBreakdown.length > 1 ? 's' : ''}',
              ),
              _SummaryTile(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Recouvrement',
                subtitle:
                    '$_recoveryOperations opération${_recoveryOperations > 1 ? 's' : ''}',
              ),
              _SummaryTile(
                icon: Icons.update_outlined,
                title: 'Dernière collection',
                subtitle: _latestCollectionDate == null
                    ? '-'
                    : _dateTimeLabel(_latestCollectionDate!),
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
      'Fév',
      'Mar',
      'Avr',
      'Mai',
      'Juin',
      'Juil',
      'Aoû',
      'Sep',
      'Oct',
      'Nov',
      'Déc',
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
    final normalized = label.toLowerCase();
    final isWarning = normalized.contains('recouvrement');
    final isPositive =
        normalized.contains('payée') ||
        normalized.contains('apurée') ||
        normalized.contains('ordonnée') ||
        normalized.contains('apurement');
    final color = isWarning
        ? AppColors.chartOrange
        : isPositive
        ? const Color(0xFF0BAA35)
        : AppColors.chartBlue;
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
            isWarning
                ? Icons.warning_amber_rounded
                : isPositive
                ? Icons.check_circle
                : Icons.info_outline,
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

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
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
