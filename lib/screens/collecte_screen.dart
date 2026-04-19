import 'package:flutter/material.dart';

import '../data/sample_chart_data.dart';
import '../models/app_role.dart';
import '../models/user_profile.dart';
import '../services/collections_live_listener.dart';
import '../services/gestia_data_service.dart';
import '../theme/app_colors.dart';
import '../widgets/charts/tax_breakdown_pie_card.dart';
import '../widgets/modern_section_panel.dart';
import '../widgets/payment_form_card.dart';
import '../widgets/responsive_two_cards.dart';

enum _TransactionRange { today, last7Days, last30Days, all }

class CollecteScreen extends StatefulWidget {
  const CollecteScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<CollecteScreen> createState() => _CollecteScreenState();
}

class _CollecteScreenState extends State<CollecteScreen> {
  late CollectionsLiveListener _collectionsLiveListener;
  final _transactionSearchCtrl = TextEditingController();

  List<TaxSlice> _slices = [];
  List<Map<String, dynamic>> _transactions = [];
  bool _loadingPie = true;
  bool _loadingTransactions = true;
  String? _transactionsError;

  _TransactionRange _range = _TransactionRange.all;
  String? _categoryFilter;
  String? _channelFilter;
  String? _communeFilter;

  String? get _scope =>
      widget.profile.role.isGlobalSupervisor ? null : widget.profile.communeId;
  String? get _taxpayerScope =>
      widget.profile.role == AppRole.contribuable ? widget.profile.id : null;

  List<Map<String, dynamic>> get _filteredTransactions {
    final query = _transactionSearchCtrl.text.trim().toLowerCase();

    final list = _transactions.where((row) {
      final matchesCategory =
          _categoryFilter == null || _transactionCategory(row) == _categoryFilter;
      final matchesChannel =
          _channelFilter == null || _transactionChannel(row) == _channelFilter;
      final matchesCommune = _communeFilter == null ||
          row['commune_id']?.toString() == _communeFilter;

      final matchesQuery = query.isEmpty ||
          [
            _transactionCommuneName(row),
            _transactionCategory(row),
            _transactionChannel(row),
            _transactionTaxpayerId(row),
            _formatMoney(_transactionAmount(row)),
          ].map((value) => value.toLowerCase()).any((value) => value.contains(query));

      return matchesCategory &&
          matchesChannel &&
          matchesCommune &&
          matchesQuery;
    }).toList()
      ..sort(
        (a, b) => _transactionDate(
          b,
        ).compareTo(_transactionDate(a)),
      );

    return list;
  }

  List<String> get _availableCategories {
    final values = _transactions
        .map(_transactionCategory)
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return values;
  }

  List<String> get _availableChannels {
    final values = _transactions
        .map(_transactionChannel)
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return values;
  }

  List<({String id, String name})> get _availableCommunes {
    final map = <String, String>{};
    for (final row in _transactions) {
      final id = row['commune_id']?.toString();
      if (id == null || id.isEmpty) continue;
      map[id] = _transactionCommuneName(row);
    }
    final list = map.entries.map((entry) => (id: entry.key, name: entry.value)).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  @override
  void initState() {
    super.initState();
    _transactionSearchCtrl.addListener(_handleFilterChanged);
    _startLiveUpdates();
    _loadPie();
    _loadTransactions();
  }

  @override
  void didUpdateWidget(covariant CollecteScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final profileChanged =
        oldWidget.profile.id != widget.profile.id ||
        oldWidget.profile.role != widget.profile.role ||
        oldWidget.profile.communeId != widget.profile.communeId;
    if (profileChanged) {
      _collectionsLiveListener.dispose();
      _communeFilter = null;
      _startLiveUpdates();
      _loadPie();
      _loadTransactions();
    }
  }

  @override
  void dispose() {
    _transactionSearchCtrl.removeListener(_handleFilterChanged);
    _transactionSearchCtrl.dispose();
    _collectionsLiveListener.dispose();
    super.dispose();
  }

  void _startLiveUpdates() {
    _collectionsLiveListener = CollectionsLiveListener(
      profile: widget.profile,
      onCollectionInserted: () async {
        await _loadPie(silent: true);
        await _loadTransactions(silent: true);
      },
    )..start();
  }

  void _handleFilterChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _handlePaymentSaved() {
    _loadPie();
    _loadTransactions();
  }

  ({DateTime from, DateTime to}) _rangeBounds() {
    final now = DateTime.now();
    switch (_range) {
      case _TransactionRange.today:
        final start = DateTime(now.year, now.month, now.day);
        return (from: start, to: now);
      case _TransactionRange.last7Days:
        return (
          from: now.subtract(const Duration(days: 7)),
          to: now,
        );
      case _TransactionRange.last30Days:
        return (
          from: now.subtract(const Duration(days: 30)),
          to: now,
        );
      case _TransactionRange.all:
        return (from: DateTime(2000), to: now);
    }
  }

  String _rangeLabel(_TransactionRange range) {
    switch (range) {
      case _TransactionRange.today:
        return 'Aujourd hui';
      case _TransactionRange.last7Days:
        return '7 jours';
      case _TransactionRange.last30Days:
        return '30 jours';
      case _TransactionRange.all:
        return 'Tout';
    }
  }

  Future<void> _loadPie({bool silent = false}) async {
    if (!silent) {
      setState(() => _loadingPie = true);
    }
    try {
      final tax = await GestiaDataService.taxBreakdownLast30Days(
        communeId: _scope,
        taxpayerProfileId: _taxpayerScope,
      );
      if (!mounted) return;
      setState(() {
        _slices = tax;
        _loadingPie = false;
      });
    } catch (_) {
      if (!mounted || silent) return;
      setState(() => _loadingPie = false);
    }
  }

  Future<void> _loadTransactions({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loadingTransactions = true;
        _transactionsError = null;
      });
    }

    try {
      final bounds = _rangeBounds();
      final rows = await GestiaDataService.fetchCollectionsInRange(
        from: bounds.from,
        to: bounds.to,
        communeId: _scope,
        taxpayerProfileId: _taxpayerScope,
      );
      if (!mounted) return;
      setState(() {
        _transactions = rows;
        _loadingTransactions = false;
        _transactionsError = null;

        if (_categoryFilter != null &&
            !_availableCategories.contains(_categoryFilter)) {
          _categoryFilter = null;
        }
        if (_channelFilter != null &&
            !_availableChannels.contains(_channelFilter)) {
          _channelFilter = null;
        }
        if (_communeFilter != null &&
            !_availableCommunes.any((commune) => commune.id == _communeFilter)) {
          _communeFilter = null;
        }
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _loadingTransactions = false;
        _transactionsError = '$e';
      });
    }
  }

  String _transactionCommuneName(Map<String, dynamic> row) {
    final commune = row['communes'];
    if (commune is Map && commune['name'] != null) {
      return commune['name'].toString();
    }
    return 'Sans commune';
  }

  String _transactionCategory(Map<String, dynamic> row) {
    final value = row['tax_category']?.toString().trim();
    return value == null || value.isEmpty ? 'Autres' : value;
  }

  String _transactionChannel(Map<String, dynamic> row) {
    final value = row['payment_channel']?.toString().trim();
    return value == null || value.isEmpty ? 'Non precise' : value;
  }

  String _transactionTaxpayerId(Map<String, dynamic> row) {
    final value = row['taxpayer_identifier']?.toString().trim();
    return value == null || value.isEmpty ? '-' : value;
  }

  double _transactionAmount(Map<String, dynamic> row) {
    return (row['amount'] as num?)?.toDouble() ?? 0;
  }

  DateTime _transactionDate(Map<String, dynamic> row) {
    final raw = row['collected_at']?.toString();
    if (raw == null || raw.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.parse(raw).toLocal();
  }

  String _formatMoney(double value) {
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

  String _formatDateTime(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month/$year - $hour:$minute';
  }

  Color _categoryColor(String category) {
    final lower = category.toLowerCase();
    if (lower.contains('marche')) return AppColors.chartTeal;
    if (lower.contains('permis') || lower.contains('licence')) {
      return AppColors.chartPurple;
    }
    if (lower.contains('station')) return AppColors.chartOrange;
    return AppColors.primary;
  }

  Widget _buildTableBadge(BuildContext context, String label, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
      ),
    );
  }

  Widget _buildTransactionsTable(
    BuildContext context,
    List<Map<String, dynamic>> rows,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: theme.colorScheme.surface.withValues(alpha: isDark ? 0.92 : 0.98),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 980),
          child: DataTable(
            columnSpacing: 22,
            dataRowMinHeight: 66,
            dataRowMaxHeight: 78,
            headingRowHeight: 54,
            columns: const [
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Commune')),
              DataColumn(label: Text('Categorie')),
              DataColumn(label: Text('Canal')),
              DataColumn(label: Text('ID contribuable')),
              DataColumn(
                label: Align(
                  alignment: Alignment.centerRight,
                  child: Text('Montant'),
                ),
                numeric: true,
              ),
            ],
            rows: [
              for (final row in rows)
                DataRow(
                  cells: [
                    DataCell(
                      Text(
                        _formatDateTime(_transactionDate(row)),
                        style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    DataCell(
                      Text(
                        _transactionCommuneName(row),
                        style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    DataCell(
                      _buildTableBadge(
                        context,
                        _transactionCategory(row),
                        _categoryColor(_transactionCategory(row)),
                      ),
                    ),
                    DataCell(
                      _buildTableBadge(
                        context,
                        _transactionChannel(row),
                        AppColors.chartOrange,
                      ),
                    ),
                    DataCell(
                      Text(
                        _transactionTaxpayerId(row),
                        style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                    DataCell(
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          _formatMoney(_transactionAmount(row)),
                          style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: AppColors.primary,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleTransactions = _filteredTransactions;
    final totalVisible = visibleTransactions.fold<double>(
      0,
      (sum, row) => sum + _transactionAmount(row),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.profile.role == AppRole.contribuable
                ? 'Paiement de mes taxes'
                : 'Saisie des recettes',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          ResponsiveTwoCards(
            left: PaymentFormCard(
              profile: widget.profile,
              onSaved: _handlePaymentSaved,
            ),
            right: Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.profile.role == AppRole.contribuable
                          ? 'Contribuable connecte'
                          : 'Utilisateur connecte',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.profile.fullName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      widget.profile.displayLine,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Divider(height: 24),
                    if (_loadingPie)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else
                      TaxBreakdownPieCard(
                        title: widget.profile.role == AppRole.contribuable
                            ? 'Mes paiements (30 j.)'
                            : 'Recettes (30 j.)',
                        compact: true,
                        slices: _slices,
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          ModernSectionPanel(
            title: widget.profile.role == AppRole.contribuable
                ? 'Historique de mes transactions'
                : 'Historique des transactions',
            subtitle:
                'Consultez toutes les recettes enregistrees, filtrez par periode, categorie, canal ou commune, et retrouvez rapidement une transaction.',
            eyebrow: 'Tableau',
            accentColor: AppColors.primary,
            action: OutlinedButton.icon(
              onPressed: _loadingTransactions ? null : _loadTransactions,
              icon: const Icon(Icons.refresh_outlined),
              label: const Text('Actualiser'),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ModernInfoPill(
                      label: 'Transactions',
                      value: '${visibleTransactions.length}',
                      icon: Icons.receipt_long_outlined,
                      color: AppColors.primary,
                    ),
                    ModernInfoPill(
                      label: 'Montant visible',
                      value: _formatMoney(totalVisible),
                      icon: Icons.payments_outlined,
                      color: AppColors.chartTeal,
                    ),
                    ModernInfoPill(
                      label: 'Periode',
                      value: _rangeLabel(_range),
                      icon: Icons.date_range_outlined,
                      color: AppColors.chartOrange,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _transactionSearchCtrl,
                  decoration: InputDecoration(
                    labelText: 'Recherche',
                    hintText: 'Commune, categorie, canal, identifiant...',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _transactionSearchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () => _transactionSearchCtrl.clear(),
                            icon: const Icon(Icons.close),
                          ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Periode',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final range in _TransactionRange.values)
                      ChoiceChip(
                        label: Text(_rangeLabel(range)),
                        selected: _range == range,
                        onSelected: (selected) async {
                          if (!selected) return;
                          setState(() => _range = range);
                          await _loadTransactions();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String?>(
                        key: ValueKey(_categoryFilter ?? 'all-categories'),
                        initialValue: _categoryFilter,
                        decoration: const InputDecoration(
                          labelText: 'Categorie',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Toutes les categories'),
                          ),
                          for (final category in _availableCategories)
                            DropdownMenuItem<String?>(
                              value: category,
                              child: Text(category),
                            ),
                        ],
                        onChanged: (value) {
                          setState(() => _categoryFilter = value);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String?>(
                        key: ValueKey(_channelFilter ?? 'all-channels'),
                        initialValue: _channelFilter,
                        decoration: const InputDecoration(
                          labelText: 'Canal',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Tous les canaux'),
                          ),
                          for (final channel in _availableChannels)
                            DropdownMenuItem<String?>(
                              value: channel,
                              child: Text(channel),
                            ),
                        ],
                        onChanged: (value) {
                          setState(() => _channelFilter = value);
                        },
                      ),
                    ),
                    if (_scope == null)
                      SizedBox(
                        width: 240,
                        child: DropdownButtonFormField<String?>(
                          key: ValueKey(_communeFilter ?? 'all-communes'),
                          initialValue: _communeFilter,
                          decoration: const InputDecoration(
                            labelText: 'Commune',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Toutes les communes'),
                            ),
                            for (final commune in _availableCommunes)
                              DropdownMenuItem<String?>(
                                value: commune.id,
                                child: Text(commune.name),
                              ),
                          ],
                          onChanged: (value) {
                            setState(() => _communeFilter = value);
                          },
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_loadingTransactions)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_transactionsError != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: Theme.of(
                        context,
                      ).colorScheme.errorContainer.withValues(alpha: 0.58),
                    ),
                    child: Text(_transactionsError!),
                  )
                else if (visibleTransactions.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.35),
                    ),
                    child: Text(
                      'Aucune transaction ne correspond aux filtres actuels.',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  )
                else
                  _buildTransactionsTable(context, visibleTransactions),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
