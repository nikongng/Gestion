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
  bool _loading = true;
  String? _error;
  double _today = 0;
  ({String name, double amount})? _topCommune;
  List<CommuneRevenue> _byCommune = [];
  List<TaxSlice> _taxSlices = [];
  List<DailyRevenue> _last7 = [];
  int _alertsOpen = 0;
  int _alertsCritiques = 0;

  String? get _scope =>
      widget.profile.role.isGlobalSupervisor ? null : widget.profile.communeId;

  String _fmtMoney(double v) {
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
      final today = await GestiaDataService.sumToday(communeId: _scope);
      final top = await GestiaDataService.topCommuneToday(
        scopeCommuneId: _scope,
      );
      final byC = await GestiaDataService.revenueByCommuneLast30Days(
        communeId: _scope,
      );
      final tax = await GestiaDataService.taxBreakdownLast30Days(
        communeId: _scope,
      );
      final d7 = await GestiaDataService.last7DaysRevenue(communeId: _scope);
      var open = 0;
      var crit = 0;
      if (widget.profile.role != AppRole.agent) {
        final s = await GestiaDataService.fetchAlertsSummary(widget.profile);
        open = s.openTotal;
        crit = s.critiques;
      }
      if (!mounted) return;
      setState(() {
        _today = today;
        _topCommune = top;
        _byCommune = byC;
        _taxSlices = tax;
        _last7 = d7;
        _alertsOpen = open;
        _alertsCritiques = crit;
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

    final topName = _topCommune?.name ?? '—';
    final topAmt = _topCommune != null
        ? _fmtMoney(_topCommune!.amount)
        : '—';

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tableau de Bord Centralisé',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                MetricCard(
                  title: 'Revenus totaux (jour)',
                  value: _fmtMoney(_today),
                  subtitle: 'Données chiffrées',
                ),
                MetricCard(
                  title: 'Top commune (jour)',
                  value: topName,
                  subtitle: topAmt != '—' ? topAmt : 'Pas encore de recettes',
                ),
                const MetricCard(
                  title: 'Comparatif 7 jours',
                  value: 'Voir courbe',
                  subtitle: 'Évolution ci-dessous',
                ),
                if (widget.profile.role != AppRole.agent)
                  MetricCard(
                    title: 'Alertes actives',
                    value: '$_alertsOpen',
                    subtitle: _alertsCritiques > 0
                        ? 'Dont $_alertsCritiques critiques — action prioritaire'
                        : 'Montant, fréquence, agents, délais de traitement',
                  )
                else
                  const MetricCard(
                    title: 'Alertes',
                    value: '—',
                    subtitle: 'Réservé aux superviseurs',
                  ),
              ],
            ),
            const SizedBox(height: 16),
            ResponsiveTwoCards(
              left: RevenueBarChartCard(
                title: 'Revenus par commune (30 j.)',
                data: _byCommune,
              ),
              right: TaxBreakdownPieCard(
                title: 'Répartition par type de taxe (30 j.)',
                slices: _taxSlices,
              ),
            ),
            const SizedBox(height: 16),
            RevenueLineChartCard(
              title: 'Évolution des revenus — 7 jours',
              data: _last7,
            ),
          ],
        ),
      ),
    );
  }
}
