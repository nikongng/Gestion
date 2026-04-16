import 'package:flutter/material.dart';

import '../data/sample_chart_data.dart';
import '../models/app_role.dart';
import '../models/user_profile.dart';
import '../services/gestia_data_service.dart';
import '../widgets/charts/revenue_bar_chart_card.dart';
import '../widgets/charts/revenue_line_chart_card.dart';
import '../widgets/charts/tax_breakdown_pie_card.dart';
import '../widgets/metric_card.dart';
import '../widgets/responsive_two_cards.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _collections = const [];
  List<({String id, String name})> _communes = const [];
  int _alertsOpen = 0;
  int _alertsCritiques = 0;

  late DateTimeRange _selectedRange;
  String? _selectedCommuneId;
  String? _selectedTaxCategory;
  String? _selectedPaymentChannel;

  String? get _scope =>
      widget.profile.role.isGlobalSupervisor ? null : widget.profile.communeId;
  String? get _taxpayerScope =>
      widget.profile.role == AppRole.contribuable ? widget.profile.id : null;
  String? get _activeCommuneScope =>
      widget.profile.role.isGlobalSupervisor ? _selectedCommuneId : _scope;

  List<Map<String, dynamic>> get _filteredRows {
    final query = _searchCtrl.text.trim().toLowerCase();
    return _collections.where((row) {
      final taxCategory = row['tax_category']?.toString() ?? '';
      final paymentChannel = row['payment_channel']?.toString() ?? '';
      final taxpayerId = row['taxpayer_identifier']?.toString() ?? '';
      final communeName = _communeName(row).toLowerCase();

      final matchesTax = _selectedTaxCategory == null ||
          taxCategory == _selectedTaxCategory;
      final matchesChannel = _selectedPaymentChannel == null ||
          paymentChannel == _selectedPaymentChannel;
      final matchesQuery = query.isEmpty ||
          taxCategory.toLowerCase().contains(query) ||
          paymentChannel.toLowerCase().contains(query) ||
          taxpayerId.toLowerCase().contains(query) ||
          communeName.contains(query);

      return matchesTax && matchesChannel && matchesQuery;
    }).toList();
  }

  List<String> get _availableTaxCategories {
    final values = _collections
        .map((row) => row['tax_category']?.toString())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return values;
  }

  List<String> get _availablePaymentChannels {
    final values = _collections
        .map((row) => row['payment_channel']?.toString())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return values;
  }

  @override
  void initState() {
    super.initState();
    _selectedRange = _defaultRange();
    _searchCtrl.addListener(_handleLocalFilterChanged);
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_handleLocalFilterChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _handleLocalFilterChanged() {
    if (!mounted) return;
    setState(() {});
  }

  DateTimeRange _defaultRange() {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    return DateTimeRange(
      start: end.subtract(const Duration(days: 29)),
      end: end,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await GestiaDataService.fetchCollectionsInRange(
        from: _rangeStartAtDayStart(_selectedRange.start),
        to: _rangeEndAtDayEnd(_selectedRange.end),
        communeId: _activeCommuneScope,
        taxpayerProfileId: _taxpayerScope,
      );
      List<({String id, String name})> communes = _communes;
      if (widget.profile.role.isGlobalSupervisor) {
        communes = await GestiaDataService.fetchCommunes();
      }

      var alertsOpen = 0;
      var alertsCritiques = 0;
      if (widget.profile.role.hasAlertsAccess) {
        final summary = await GestiaDataService.fetchAlertsSummary(widget.profile);
        alertsOpen = summary.openTotal;
        alertsCritiques = summary.critiques;
      }

      if (!mounted) return;
      setState(() {
        _collections = rows;
        _communes = communes;
        _alertsOpen = alertsOpen;
        _alertsCritiques = alertsCritiques;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  DateTime _rangeStartAtDayStart(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime _rangeEndAtDayEnd(DateTime date) => DateTime(
        date.year,
        date.month,
        date.day,
        23,
        59,
        59,
        999,
      );

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _selectedRange,
    );
    if (range == null) return;
    setState(() {
      _selectedRange = DateTimeRange(
        start: _rangeStartAtDayStart(range.start),
        end: _rangeStartAtDayStart(range.end),
      );
    });
    await _load();
  }

  Future<void> _applyQuickRange(int days) async {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    setState(() {
      _selectedRange = DateTimeRange(
        start: end.subtract(Duration(days: days - 1)),
        end: end,
      );
    });
    await _load();
  }

  void _resetFilters() {
    setState(() {
      _selectedRange = _defaultRange();
      _selectedCommuneId = null;
      _selectedTaxCategory = null;
      _selectedPaymentChannel = null;
      _searchCtrl.clear();
    });
    _load();
  }

  bool _matchesQuickRange(int days) {
    final expected = _defaultRange().end.subtract(Duration(days: days - 1));
    return _selectedRange.start.year == expected.year &&
        _selectedRange.start.month == expected.month &&
        _selectedRange.start.day == expected.day &&
        _selectedRange.duration.inDays == days - 1;
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

  String _rangeLabel() {
    String two(int value) => value.toString().padLeft(2, '0');
    final start = _selectedRange.start;
    final end = _selectedRange.end;
    return '${two(start.day)}/${two(start.month)}/${start.year} - '
        '${two(end.day)}/${two(end.month)}/${end.year}';
  }

  String _scopeLabel() {
    if (widget.profile.role == AppRole.contribuable) {
      return widget.profile.taxpayerIdentifier != null
          ? 'ID ${widget.profile.taxpayerIdentifier}'
          : 'Mon compte';
    }
    if (_activeCommuneScope == null) {
      return 'Toutes les communes';
    }
    final commune = _communes.where((item) => item.id == _activeCommuneScope);
    if (commune.isNotEmpty) {
      return commune.first.name;
    }
    return widget.profile.communeName ?? 'Commune courante';
  }

  String _communeName(Map<String, dynamic> row) {
    final nested = row['communes'];
    if (nested is Map) {
      final name = nested['name']?.toString();
      if (name != null && name.isNotEmpty) {
        return name;
      }
    }
    return widget.profile.communeName ?? 'Non renseignée';
  }

  _DashboardComputed _computeDashboard(List<Map<String, dynamic>> rows) {
    final byCommune = <String, double>{};
    final byTax = <String, double>{};
    final byDay = <String, double>{};
    var totalAmount = 0.0;

    for (final row in rows) {
      final amount = (row['amount'] as num?)?.toDouble() ?? 0;
      final taxCategory = row['tax_category']?.toString() ?? 'Autres';
      final communeName = _communeName(row);
      final collectedAt =
          DateTime.tryParse(row['collected_at']?.toString() ?? '')?.toLocal();

      totalAmount += amount;
      byCommune[communeName] = (byCommune[communeName] ?? 0) + amount;
      byTax[taxCategory] = (byTax[taxCategory] ?? 0) + amount;

      if (collectedAt != null) {
        final key = _dayKey(collectedAt);
        byDay[key] = (byDay[key] ?? 0) + amount;
      }
    }

    final communeSeries = byCommune.entries
        .map((entry) => CommuneRevenue(entry.key, entry.value))
        .toList()
      ..sort((a, b) => b.amountUsd.compareTo(a.amountUsd));

    final topCommune =
        communeSeries.isEmpty ? null : (name: communeSeries.first.label, amount: communeSeries.first.amountUsd);

    final totalTaxAmount = byTax.values.fold<double>(0, (sum, value) => sum + value);
    const colors = [0xFF1366FF, 0xFF0FC2A5, 0xFFFF9F43, 0xFFE74C3C, 0xFF7C3AED];
    var colorIndex = 0;
    final taxSlices = byTax.entries.map((entry) {
      final percent =
          totalTaxAmount == 0 ? 0.0 : (entry.value / totalTaxAmount) * 100;
      final color = colors[colorIndex % colors.length];
      colorIndex++;
      return TaxSlice(entry.key, percent, color);
    }).toList();

    final dailySeries = <DailyRevenue>[];
    final start = _rangeStartAtDayStart(_selectedRange.start);
    final end = _rangeStartAtDayStart(_selectedRange.end);
    for (var day = start;
        !day.isAfter(end);
        day = day.add(const Duration(days: 1))) {
      dailySeries.add(
        DailyRevenue(
          _dayLabel(day),
          byDay[_dayKey(day)] ?? 0,
        ),
      );
    }

    return _DashboardComputed(
      totalAmount: totalAmount,
      transactionCount: rows.length,
      topCommune: topCommune,
      byCommune: communeSeries,
      taxSlices: taxSlices,
      dailySeries: dailySeries,
      distinctTaxCount: byTax.length,
    );
  }

  String _dayKey(DateTime day) => '${day.year}-${day.month}-${day.day}';

  String _dayLabel(DateTime day) {
    const weekDays = ['Dim', 'Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam'];
    if (_selectedRange.duration.inDays <= 6) {
      return weekDays[day.weekday % 7];
    }
    final two = (int value) => value.toString().padLeft(2, '0');
    return '${two(day.day)}/${two(day.month)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Réessayer')),
            ],
          ),
        ),
      );
    }

    final filteredRows = _filteredRows;
    final dashboard = _computeDashboard(filteredRows);
    final topCommuneName = dashboard.topCommune?.name ?? '—';
    final topCommuneAmount = dashboard.topCommune != null
        ? _fmtMoney(dashboard.topCommune!.amount)
        : 'Aucune recette';

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.profile.role == AppRole.contribuable
                  ? 'Mon tableau de bord'
                  : 'Tableau de bord centralisé',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Filtrez la période, la commune, la taxe, le canal et vos recherches textuelles pour explorer rapidement les données.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Filtres avancés',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _resetFilters,
                          icon: const Icon(Icons.refresh_outlined),
                          label: const Text('Réinitialiser'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${filteredRows.length} transaction(s) visibles sur ${_collections.length} chargée(s) pour ${_scopeLabel()}.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('7 j'),
                          selected: _matchesQuickRange(7),
                          onSelected: (_) => _applyQuickRange(7),
                        ),
                        ChoiceChip(
                          label: const Text('30 j'),
                          selected: _matchesQuickRange(30),
                          onSelected: (_) => _applyQuickRange(30),
                        ),
                        ChoiceChip(
                          label: const Text('90 j'),
                          selected: _matchesQuickRange(90),
                          onSelected: (_) => _applyQuickRange(90),
                        ),
                        OutlinedButton.icon(
                          onPressed: _pickDateRange,
                          icon: const Icon(Icons.date_range_outlined),
                          label: Text(_rangeLabel()),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: 280,
                          child: TextField(
                            controller: _searchCtrl,
                            decoration: InputDecoration(
                              labelText: 'Recherche',
                              hintText: 'Commune, taxe, canal, ID...',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _searchCtrl.text.isEmpty
                                  ? null
                                  : IconButton(
                                      onPressed: () => _searchCtrl.clear(),
                                      icon: const Icon(Icons.close),
                                    ),
                            ),
                          ),
                        ),
                        if (widget.profile.role.isGlobalSupervisor)
                          SizedBox(
                            width: 220,
                            child: DropdownButtonFormField<String?>(
                              value: _selectedCommuneId,
                              decoration: const InputDecoration(
                                labelText: 'Commune',
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('Toutes les communes'),
                                ),
                                for (final commune in _communes)
                                  DropdownMenuItem<String?>(
                                    value: commune.id,
                                    child: Text(commune.name),
                                  ),
                              ],
                              onChanged: (value) async {
                                setState(() => _selectedCommuneId = value);
                                await _load();
                              },
                            ),
                          ),
                        SizedBox(
                          width: 220,
                          child: DropdownButtonFormField<String?>(
                            value: _selectedTaxCategory,
                            decoration: const InputDecoration(
                              labelText: 'Type de taxe',
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Toutes les taxes'),
                              ),
                              for (final tax in _availableTaxCategories)
                                DropdownMenuItem<String?>(
                                  value: tax,
                                  child: Text(tax),
                                ),
                            ],
                            onChanged: (value) {
                              setState(() => _selectedTaxCategory = value);
                            },
                          ),
                        ),
                        SizedBox(
                          width: 220,
                          child: DropdownButtonFormField<String?>(
                            value: _selectedPaymentChannel,
                            decoration: const InputDecoration(
                              labelText: 'Canal de paiement',
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Tous les canaux'),
                              ),
                              for (final channel in _availablePaymentChannels)
                                DropdownMenuItem<String?>(
                                  value: channel,
                                  child: Text(channel),
                                ),
                            ],
                            onChanged: (value) {
                              setState(() => _selectedPaymentChannel = value);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                MetricCard(
                  title: widget.profile.role == AppRole.contribuable
                      ? 'Total payé'
                      : 'Total recettes',
                  value: _fmtMoney(dashboard.totalAmount),
                  subtitle: _rangeLabel(),
                ),
                MetricCard(
                  title: 'Transactions',
                  value: '${dashboard.transactionCount}',
                  subtitle: _scopeLabel(),
                ),
                MetricCard(
                  title: 'Top commune',
                  value: topCommuneName,
                  subtitle: topCommuneAmount,
                ),
                if (widget.profile.role.hasAlertsAccess)
                  MetricCard(
                    title: 'Alertes actives',
                    value: '$_alertsOpen',
                    subtitle: _alertsCritiques > 0
                        ? 'Dont $_alertsCritiques critiques'
                        : 'Vue globale du rôle',
                  )
                else
                  MetricCard(
                    title: 'Taxes visibles',
                    value: '${dashboard.distinctTaxCount}',
                    subtitle: 'Apres filtres avances',
                  ),
              ],
            ),
            const SizedBox(height: 16),
            ResponsiveTwoCards(
              left: RevenueBarChartCard(
                title: widget.profile.role == AppRole.contribuable
                    ? 'Mes paiements par commune'
                    : 'Revenus par commune',
                data: dashboard.byCommune,
              ),
              right: TaxBreakdownPieCard(
                title: widget.profile.role == AppRole.contribuable
                    ? 'Mes taxes par catégorie'
                    : 'Répartition par type de taxe',
                slices: dashboard.taxSlices,
              ),
            ),
            const SizedBox(height: 16),
            RevenueLineChartCard(
              title: widget.profile.role == AppRole.contribuable
                  ? 'Évolution de mes paiements'
                  : 'Évolution des revenus',
              data: dashboard.dailySeries,
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardComputed {
  const _DashboardComputed({
    required this.totalAmount,
    required this.transactionCount,
    required this.topCommune,
    required this.byCommune,
    required this.taxSlices,
    required this.dailySeries,
    required this.distinctTaxCount,
  });

  final double totalAmount;
  final int transactionCount;
  final ({String name, double amount})? topCommune;
  final List<CommuneRevenue> byCommune;
  final List<TaxSlice> taxSlices;
  final List<DailyRevenue> dailySeries;
  final int distinctTaxCount;
}
