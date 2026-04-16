import 'package:flutter/material.dart';

import '../data/sample_chart_data.dart';
import '../models/app_role.dart';
import '../models/user_profile.dart';
import '../services/gestia_data_service.dart';
import '../utils/report_exporter.dart';
import '../widgets/charts/goal_vs_revenue_bar_card.dart';
import '../widgets/charts/tax_breakdown_pie_card.dart';
import '../widgets/metric_card.dart';
import '../widgets/responsive_two_cards.dart';

class RapportsScreen extends StatefulWidget {
  const RapportsScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<RapportsScreen> createState() => _RapportsScreenState();
}

class _RapportsScreenState extends State<RapportsScreen> {
  bool _loading = true;
  bool _exporting = false;
  String? _error;
  double _total30 = 0;
  double _avgDaily = 0;
  int _txCount = 0;
  List<TaxSlice> _tax = [];
  List<MonthGoalVsActual> _goal = [];
  List<Map<String, dynamic>> _collections = const [];

  String? get _scope =>
      widget.profile.role.isGlobalSupervisor ? null : widget.profile.communeId;
  String? get _taxpayerScope =>
      widget.profile.role == AppRole.contribuable ? widget.profile.id : null;

  String _fmt(double value) {
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

  double get _completionRate {
    if (_goal.isEmpty) return 0;
    return _goal.map((item) => item.actualK / item.goalK).reduce((a, b) => a + b) /
        _goal.length *
        100;
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
      final now = DateTime.now();
      final from = now.subtract(const Duration(days: 30));
      final rows = await GestiaDataService.fetchCollectionsInRange(
        from: from,
        to: now,
        communeId: _scope,
        taxpayerProfileId: _taxpayerScope,
      );
      var total = 0.0;
      for (final row in rows) {
        total += (row['amount'] as num).toDouble();
      }
      final tax = await GestiaDataService.taxBreakdownLast30Days(
        communeId: _scope,
        taxpayerProfileId: _taxpayerScope,
      );
      final goal = await GestiaDataService.goalVsActualLast6Months(
        communeId: _scope,
        taxpayerProfileId: _taxpayerScope,
      );
      if (!mounted) return;
      setState(() {
        _total30 = total;
        _avgDaily = total / 30;
        _txCount = rows.length;
        _tax = tax;
        _goal = goal;
        _collections = rows;
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
      final messenger = ScaffoldMessenger.of(context);
      if (path == null || path.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Export annule.')),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text('$successMessage Fichier: $path')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Echec de l export: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  ReportExportData _buildExportData() {
    final rows = _collections
        .map(
          (row) => ReportExportRow(
            collectedAt: DateTime.tryParse(
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
      title: widget.profile.role == AppRole.contribuable
          ? 'Mes paiements - 30 derniers jours'
          : 'Rapport de collecte - 30 derniers jours',
      scopeLabel: _scopeLabel(),
      generatedAt: DateTime.now(),
      metrics: [
        ReportExportMetric(label: 'Total recettes (30 j.)', value: _fmt(_total30)),
        ReportExportMetric(label: 'Moyenne journaliere', value: _fmt(_avgDaily)),
        ReportExportMetric(
          label: 'Taux realisation indicatif',
          value: '${_completionRate.toStringAsFixed(1)}%',
        ),
        ReportExportMetric(
          label: 'Transactions (30 j.)',
          value: '$_txCount',
        ),
      ],
      rows: rows,
    );
  }

  String _scopeLabel() {
    if (widget.profile.role == AppRole.contribuable) {
      return widget.profile.taxpayerIdentifier != null &&
              widget.profile.taxpayerIdentifier!.isNotEmpty
          ? 'ID ${widget.profile.taxpayerIdentifier}'
          : 'Mes paiements';
    }
    if (widget.profile.role.isGlobalSupervisor) {
      return 'Toutes les communes';
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
                  ? 'Mes rapports de paiement'
                  : 'Rapports & Analyses',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Exports',
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.profile.role == AppRole.contribuable
                          ? 'Generez vos justificatifs PDF ou Excel a partir de vos paiements des 30 derniers jours.'
                          : 'Generez un rapport du perimetre courant en PDF ou en Excel a partir des 30 derniers jours.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: _exporting ? null : _exportPdf,
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: Text(_exporting ? 'Export en cours...' : 'Exporter PDF'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _exporting ? null : _exportExcel,
                          icon: const Icon(Icons.table_view_outlined),
                          label: const Text('Exporter Excel'),
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
                      ? 'Total payé (30 j.)'
                      : 'Total recettes (30 j.)',
                  value: _fmt(_total30),
                  subtitle: 'Periode glissante',
                ),
                MetricCard(
                  title: 'Moyenne journaliere',
                  value: _fmt(_avgDaily),
                  subtitle: 'Sur 30 jours',
                ),
                MetricCard(
                  title: 'Taux realisation (indic.)',
                  value: '${_completionRate.toStringAsFixed(1)}%',
                  subtitle: 'Objectif = 105 % du realise',
                ),
                MetricCard(
                  title: 'Transactions (30 j.)',
                  value: '$_txCount',
                  subtitle: 'Enregistrements dans collections',
                ),
              ],
            ),
            const SizedBox(height: 16),
            ResponsiveTwoCards(
              left: GoalVsRevenueBarCard(
                title: widget.profile.role == AppRole.contribuable
                    ? 'Mes paiements vs objectif indicatif (6 mois)'
                    : 'Realise vs objectif indicatif (6 mois)',
                data: _goal,
              ),
              right: TaxBreakdownPieCard(
                title: widget.profile.role == AppRole.contribuable
                    ? 'Mes taxes par catégorie (30 j.)'
                    : 'Repartition par taxe (30 j.)',
                slices: _tax,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
