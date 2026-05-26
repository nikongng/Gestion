import 'package:flutter/material.dart';

import '../data/sample_chart_data.dart';
import '../models/app_role.dart';
import '../models/user_profile.dart';
import '../services/collections_live_listener.dart';
import '../utils/error_messages.dart';
import 'dashboard_repository.dart';

class DashboardController extends ChangeNotifier {
  DashboardController({required this.profile, DashboardRepository? repository})
    : _repository = repository ?? DashboardRepository() {
    _selectedRange = _defaultRange();
    _searchCtrl.addListener(_onLocalFilterChanged);
    _collectionsLiveListener = CollectionsLiveListener(
      profile: profile,
      onCollectionInserted: () => load(silent: true),
    )..start();
  }

  final UserProfile profile;
  final DashboardRepository _repository;
  late final CollectionsLiveListener _collectionsLiveListener;

  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _collections = const [];
  Map<String, String> _creatorNames = const {};
  List<({String id, String name})> _communes = const [];
  int _agentsTotal = 0;
  int _alertsOpen = 0;
  int _alertsCritiques = 0;
  bool _mobileFiltersExpanded = false;

  late DateTimeRange _selectedRange;
  String? _selectedCommuneId;
  String? _selectedTaxCategory;
  String? _selectedPaymentChannel;

  bool get loading => _loading;
  String? get error => _error;
  TextEditingController get searchController => _searchCtrl;
  bool get mobileFiltersExpanded => _mobileFiltersExpanded;

  bool get canViewMairieRevenue => profile.role.isGlobalSupervisor;

  List<Map<String, dynamic>> get collections =>
      _collections.where(_isVisibleForRole).toList();
  Map<String, String> get creatorNames => _creatorNames;
  List<({String id, String name})> get communes => _communes;
  int get agentsTotal => _agentsTotal;
  int get alertsOpen => _alertsOpen;
  int get alertsCritiques => _alertsCritiques;

  DateTimeRange get selectedRange => _selectedRange;
  String? get selectedCommuneId => _selectedCommuneId;
  String? get selectedTaxCategory => _selectedTaxCategory;
  String? get selectedPaymentChannel => _selectedPaymentChannel;

  String? get scope =>
      profile.role.isGlobalSupervisor ? null : profile.communeId;

  String? get taxpayerScope =>
      profile.role == AppRole.contribuable ? profile.id : null;

  String? get activeCommuneScope =>
      profile.role.isGlobalSupervisor ? _selectedCommuneId : scope;

  List<Map<String, dynamic>> get filteredRows {
    final query = _searchCtrl.text.trim().toLowerCase();

    return collections.where((row) {
      final taxCategory = row['tax_category']?.toString() ?? '';
      final paymentChannel = row['payment_channel']?.toString() ?? '';
      final taxpayerId = row['taxpayer_identifier']?.toString() ?? '';
      final communeName = communeNameOf(row).toLowerCase();

      final matchesTax =
          _selectedTaxCategory == null || taxCategory == _selectedTaxCategory;
      final matchesChannel =
          _selectedPaymentChannel == null ||
          paymentChannel == _selectedPaymentChannel;
      final matchesQuery =
          query.isEmpty ||
          taxCategory.toLowerCase().contains(query) ||
          paymentChannel.toLowerCase().contains(query) ||
          taxpayerId.toLowerCase().contains(query) ||
          communeName.contains(query);

      return matchesTax && matchesChannel && matchesQuery;
    }).toList();
  }

  List<String> get availableTaxCategories {
    final values =
        collections
            .map((row) => row['tax_category']?.toString())
            .whereType<String>()
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return values;
  }

  List<String> get availablePaymentChannels {
    final values =
        collections
            .map((row) => row['payment_channel']?.toString())
            .whereType<String>()
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return values;
  }

  DashboardComputed get dashboard => _computeDashboard(filteredRows);

  // Nouvelles métriques pour le haut du dashboard
  double get totalTaxesCollectees => _computeDashboard(collections).totalAmount;

  int get totalTransactions => collections.length;

  double get totalRecettesMairie =>
      canViewMairieRevenue ? _sumCollectionsWhere(_isMairieCollection) : 0;

  double get totalRecettesCommunes =>
      _sumCollectionsWhere((row) => !_isMairieCollection(row));

  int get contribuablesActifs {
    final uniqueTaxpayers = <String>{};
    for (final row in collections) {
      final taxpayerId = row['taxpayer_identifier']?.toString().trim();
      final taxpayerProfileId = row['taxpayer_profile_id']?.toString().trim();
      if (taxpayerId != null && taxpayerId.isNotEmpty) {
        uniqueTaxpayers.add(taxpayerId);
      } else if (taxpayerProfileId != null && taxpayerProfileId.isNotEmpty) {
        uniqueTaxpayers.add(taxpayerProfileId);
      }
    }
    return uniqueTaxpayers.length;
  }

  double get impayes {
    // Pour l'instant, on retourne 0 car il n'y a pas de table d'impayés
    // À implémenter avec une vraie requête SQL plus tard
    return 0.0;
  }

  ({String name, double amount})? get communeChampionne {
    if (collections.isEmpty) return null;

    final revenueByCommune = <String, double>{};
    for (final row in collections) {
      if (_isMairieCollection(row)) continue;
      final communeName = communeNameOf(row);
      final amount = (row['amount'] as num?)?.toDouble() ?? 0;
      revenueByCommune[communeName] =
          (revenueByCommune[communeName] ?? 0) + amount;
    }

    if (revenueByCommune.isEmpty) return null;

    var bestCommune = revenueByCommune.entries.first;
    for (final entry in revenueByCommune.entries) {
      if (entry.value > bestCommune.value) {
        bestCommune = entry;
      }
    }

    return (name: bestCommune.key, amount: bestCommune.value);
  }

  String get rangeLabel {
    String two(int value) => value.toString().padLeft(2, '0');
    final start = _selectedRange.start;
    final end = _selectedRange.end;
    return '${two(start.day)}/${two(start.month)}/${start.year} - '
        '${two(end.day)}/${two(end.month)}/${end.year}';
  }

  String get scopeLabel {
    if (profile.role == AppRole.contribuable) {
      return profile.taxpayerIdentifier != null
          ? 'ID ${profile.taxpayerIdentifier}'
          : 'Mon compte';
    }
    if (activeCommuneScope == null) {
      return 'Toutes les communes';
    }
    final commune = _communes.where((item) => item.id == activeCommuneScope);
    if (commune.isNotEmpty) {
      return commune.first.name;
    }
    return profile.communeName ?? 'Commune courante';
  }

  bool get isDefaultRangeSelected {
    final defaultRange = _defaultRange();
    return _sameDay(_selectedRange.start, defaultRange.start) &&
        _sameDay(_selectedRange.end, defaultRange.end);
  }

  int get activeFiltersCount {
    var count = 0;
    if (!isDefaultRangeSelected) count++;
    if (_selectedCommuneId != null) count++;
    if (_selectedTaxCategory != null) count++;
    if (_selectedPaymentChannel != null) count++;
    if (_searchCtrl.text.trim().isNotEmpty) count++;
    return count;
  }

  void toggleMobileFiltersExpanded() {
    _mobileFiltersExpanded = !_mobileFiltersExpanded;
    notifyListeners();
  }

  void setSelectedTaxCategory(String? value) {
    _selectedTaxCategory = value;
    notifyListeners();
  }

  void setSelectedPaymentChannel(String? value) {
    _selectedPaymentChannel = value;
    notifyListeners();
  }

  void setSelectedCommune(String? value) {
    _selectedCommuneId = value;
    notifyListeners();
  }

  void setDateRange(DateTimeRange range) {
    _selectedRange = DateTimeRange(
      start: _rangeStartAtDayStart(range.start),
      end: _rangeStartAtDayStart(range.end),
    );
    notifyListeners();
  }

  Future<void> applyQuickRange(int days) async {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);

    _selectedRange = DateTimeRange(
      start: end.subtract(Duration(days: days - 1)),
      end: end,
    );
    notifyListeners();
    await load();
  }

  void resetFilters() {
    _selectedRange = _defaultRange();
    _selectedCommuneId = null;
    _selectedTaxCategory = null;
    _selectedPaymentChannel = null;
    _searchCtrl.clear();
    notifyListeners();
  }

  Future<void> load({bool silent = false}) async {
    _error = null;
    if (!silent) {
      _loading = true;
      notifyListeners();
    }

    try {
      final rows = await _repository.fetchCollectionsInRange(
        from: _rangeStartAtDayStart(_selectedRange.start),
        to: _rangeEndAtDayEnd(_selectedRange.end),
        communeId: activeCommuneScope,
        taxpayerProfileId: taxpayerScope,
      );

      final profiles = await _repository.fetchAllProfiles();
      final creatorNames = rows.isEmpty
          ? const <String, String>{}
          : {for (final item in profiles) item.id: item.fullName};
      final agentsTotal = profiles
          .where((profile) => profile.role == AppRole.agent)
          .length;

      List<({String id, String name})> communes = _communes;
      if (profile.role.isGlobalSupervisor) {
        communes = await _repository.fetchCommunes();
      }

      var alertsOpen = 0;
      var alertsCritiques = 0;
      if (profile.role.hasAlertsAccess) {
        final summary = await _repository.fetchAlertsSummary(profile);
        alertsOpen = summary.openTotal;
        alertsCritiques = summary.critiques;
      }

      _collections = rows;
      _creatorNames = creatorNames;
      _communes = communes;
      _agentsTotal = agentsTotal;
      _alertsOpen = alertsOpen;
      _alertsCritiques = alertsCritiques;
      _loading = false;
      notifyListeners();
    } catch (e) {
      if (!silent) {
        _error = userFacingErrorMessage(e);
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refresh() => load();

  @override
  void dispose() {
    _collectionsLiveListener.dispose();
    _searchCtrl.removeListener(_onLocalFilterChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onLocalFilterChanged() {
    notifyListeners();
  }

  DateTimeRange _defaultRange() {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    return DateTimeRange(
      start: end.subtract(const Duration(days: 29)),
      end: end,
    );
  }

  DateTime _rangeStartAtDayStart(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime _rangeEndAtDayEnd(DateTime date) =>
      DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

  String communeNameOf(Map<String, dynamic> row) {
    final scope = row['collection_scope']?.toString().trim().toLowerCase();
    if (scope == 'mairie') {
      return 'Mairie';
    }
    final nested = row['communes'];
    if (nested is Map) {
      final name = nested['name']?.toString();
      if (name != null && name.isNotEmpty) {
        return name;
      }
    }
    return profile.communeName ?? 'Non renseignée';
  }

  String authorNameOf(Map<String, dynamic> row) {
    final createdBy = row['created_by']?.toString();
    final creatorName = createdBy == null
        ? null
        : _creatorNames[createdBy]?.trim();
    if (creatorName != null && creatorName.isNotEmpty) {
      return creatorName;
    }

    final taxpayerId = row['taxpayer_identifier']?.toString().trim();
    if (taxpayerId != null && taxpayerId.isNotEmpty) {
      return 'ID $taxpayerId';
    }

    return 'Utilisateur';
  }

  double _sumCollectionsWhere(bool Function(Map<String, dynamic> row) test) {
    var total = 0.0;
    for (final row in collections) {
      if (test(row)) {
        total += (row['amount'] as num?)?.toDouble() ?? 0;
      }
    }
    return total;
  }

  bool _isVisibleForRole(Map<String, dynamic> row) {
    return canViewMairieRevenue || !_isMairieCollection(row);
  }

  bool _isMairieCollection(Map<String, dynamic> row) {
    final scope = row['collection_scope']?.toString().trim().toLowerCase();
    if (scope == 'mairie') return true;
    if (scope == 'commune') return false;
    final taxCategory = row['tax_category']?.toString().toLowerCase() ?? '';
    return taxCategory.contains('mairie');
  }

  DashboardComputed _computeDashboard(List<Map<String, dynamic>> rows) {
    final byCommune = <String, double>{};
    final byTax = <String, double>{};
    final byDay = <String, double>{};
    var totalAmount = 0.0;

    for (final row in rows) {
      final amount = (row['amount'] as num?)?.toDouble() ?? 0;
      final taxCategory = row['tax_category']?.toString() ?? 'Autres';
      final communeName = communeNameOf(row);
      final collectedAt = DateTime.tryParse(
        row['collected_at']?.toString() ?? '',
      )?.toLocal();

      totalAmount += amount;
      if (!_isMairieCollection(row)) {
        byCommune[communeName] = (byCommune[communeName] ?? 0) + amount;
      }
      byTax[taxCategory] = (byTax[taxCategory] ?? 0) + amount;

      if (collectedAt != null) {
        final key = _dayKey(collectedAt);
        byDay[key] = (byDay[key] ?? 0) + amount;
      }
    }

    final communeSeries =
        byCommune.entries
            .map((entry) => CommuneRevenue(entry.key, entry.value))
            .toList()
          ..sort((a, b) => b.amountUsd.compareTo(a.amountUsd));

    final topCommune = communeSeries.isEmpty
        ? null
        : (
            name: communeSeries.first.label,
            amount: communeSeries.first.amountUsd,
          );

    final totalTaxAmount = byTax.values.fold<double>(
      0,
      (sum, value) => sum + value,
    );

    const colors = [0xFF1366FF, 0xFF0FC2A5, 0xFFFF9F43, 0xFFE74C3C, 0xFF7C3AED];

    var colorIndex = 0;
    final taxSlices = byTax.entries.map((entry) {
      final percent = totalTaxAmount == 0
          ? 0.0
          : (entry.value / totalTaxAmount) * 100;
      final color = colors[colorIndex % colors.length];
      colorIndex++;
      return TaxSlice(entry.key, percent, color);
    }).toList();

    final dailySeries = <DailyRevenue>[];
    final start = _rangeStartAtDayStart(_selectedRange.start);
    final end = _rangeStartAtDayStart(_selectedRange.end);

    for (
      var day = start;
      !day.isAfter(end);
      day = day.add(const Duration(days: 1))
    ) {
      dailySeries.add(DailyRevenue(_dayLabel(day), byDay[_dayKey(day)] ?? 0));
    }

    return DashboardComputed(
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
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(day.day)}/${two(day.month)}';
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class DashboardComputed {
  const DashboardComputed({
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
