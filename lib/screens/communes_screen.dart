import 'package:flutter/material.dart';

import '../models/app_role.dart';
import '../models/user_profile.dart';
import '../services/gestia_data_service.dart';
import '../widgets/metric_card.dart';

class CommunesScreen extends StatefulWidget {
  const CommunesScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<CommunesScreen> createState() => _CommunesScreenState();
}

class _CommunesScreenState extends State<CommunesScreen> {
  bool _loading = true;
  String? _error;
  List<CommuneOverviewRow> _rows = [];
  double _totalToday = 0;

  String? get _filter =>
      widget.profile.role == AppRole.adminProvincial
          ? null
          : widget.profile.communeId;

  String _fmt(double v) {
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return '$buf \$';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows =
          await GestiaDataService.fetchCommunesOverview(
        filterCommuneId: _filter,
      );
      var total = 0.0;
      for (final r in rows) {
        total += r.revenueToday;
      }
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _totalToday = total;
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

    final best = _rows.isEmpty
        ? null
        : _rows.reduce(
            (a, b) => a.revenueToday >= b.revenueToday ? a : b,
          );
    final alertCount =
        _rows.where((r) => r.revenueToday > 0 && r.revenueToday < 100).length;

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Gestion des Communes',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                MetricCard(
                  title: 'Recettes (jour)',
                  value: _fmt(_totalToday),
                  subtitle: 'Somme des communes affichées',
                ),
                MetricCard(
                  title: 'Commune la plus active (jour)',
                  value: best?.name ?? '—',
                  subtitle: best != null ? _fmt(best.revenueToday) : '—',
                ),
                MetricCard(
                  title: 'Communes sous seuil (démo)',
                  value: '$alertCount',
                  subtitle: 'Moins de 100 USD (à ajuster)',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Commune')),
                    DataColumn(label: Text('Bourgmestre')),
                    DataColumn(label: Text('Recettes (jour)')),
                    DataColumn(label: Text('Transactions')),
                  ],
                  rows: [
                    for (final r in _rows)
                      DataRow(
                        cells: [
                          DataCell(Text(r.name)),
                          DataCell(Text(r.bourgmestreName)),
                          DataCell(Text(_fmt(r.revenueToday))),
                          DataCell(Text('${r.transactionsToday}')),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
