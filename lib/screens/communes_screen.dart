import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/collections_live_listener.dart';
import '../services/gestia_data_service.dart';
import '../theme/app_colors.dart';
import '../utils/error_messages.dart';
import '../widgets/metric_card.dart';

class CommunesScreen extends StatefulWidget {
  const CommunesScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<CommunesScreen> createState() => _CommunesScreenState();
}

class _CommunesScreenState extends State<CommunesScreen> {
  late CollectionsLiveListener _collectionsLiveListener;
  bool _loading = true;
  bool _addingCommune = false;
  String? _error;
  List<CommuneOverviewRow> _rows = [];
  double _totalToday = 0;

  String? get _filter =>
      widget.profile.isGlobalSupervisor ? null : widget.profile.communeId;

  String get _scopeLabel => widget.profile.isGlobalSupervisor
      ? 'Toutes les communes'
      : widget.profile.communeName ?? 'Commune courante';

  @override
  void initState() {
    super.initState();
    _startLiveUpdates();
    _load();
  }

  @override
  void didUpdateWidget(covariant CommunesScreen oldWidget) {
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
    _collectionsLiveListener.dispose();
    super.dispose();
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
      setState(() {
        _loading = true;
      });
    }
    try {
      final rows = await GestiaDataService.fetchCommunesOverview(
        filterCommuneId: _filter,
      );
      var total = 0.0;
      for (final row in rows) {
        total += row.revenueToday;
      }
      if (!mounted) return;
      setState(() {
        _error = null;
        _rows = rows;
        _totalToday = total;
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

  Future<void> _showAddCommuneDialog() async {
    if (!widget.profile.canManageApp || _addingCommune) return;

    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Ajouter une commune'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nom de la commune',
              hintText: 'Ex: Dilala',
            ),
            onSubmitted: (text) => Navigator.of(dialogContext).pop(text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    final communeName = value?.trim();
    if (communeName == null || communeName.isEmpty || !mounted) return;
    final duplicate = _rows.any(
      (row) => row.name.trim().toLowerCase() == communeName.toLowerCase(),
    );
    if (duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cette commune existe deja.')),
      );
      return;
    }

    setState(() => _addingCommune = true);
    try {
      await GestiaDataService.insertCommune(name: communeName);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Commune ajoutee: $communeName')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _addingCommune = false);
    }
  }

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

  String _fmtCompact(double value) {
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

  String _bourgmestreLabel(CommuneOverviewRow row) {
    final name = row.bourgmestreName.trim();
    if (name.isEmpty ||
        name == '-' ||
        name.startsWith('A') ||
        name.startsWith('à ')) {
      return 'Non renseigné';
    }
    if (name.isEmpty || name == 'de”' || name == '-') {
      return 'Non renseigné';
    }
    return name;
  }

  double _progressFor(CommuneOverviewRow row, double maxRevenue) {
    if (maxRevenue <= 0) {
      return row.transactionsToday > 0 ? 0.18 : 0.0;
    }
    return (row.revenueToday / maxRevenue).clamp(0.0, 1.0).toDouble();
  }

  String _statusLabel(CommuneOverviewRow row, double maxRevenue) {
    if (row.transactionsToday == 0 && row.revenueToday <= 0) {
      return 'A rélancer';
    }
    if (maxRevenue > 0 && row.revenueToday >= maxRevenue * 0.75) {
      return 'Leader du jour';
    }
    if (row.transactionsToday >= 5 || row.revenueToday >= 300) {
      return 'Bon rythme';
    }
    if (row.revenueToday > 0 && row.revenueToday < 100) {
      return 'Sous seuil';
    }
    return 'Stable';
  }

  Color _statusColor(CommuneOverviewRow row, double maxRevenue) {
    final label = _statusLabel(row, maxRevenue);
    switch (label) {
      case 'Leader du jour':
        return AppColors.primary;
      case 'Bon rythme':
        return AppColors.chartTeal;
      case 'Sous seuil':
        return AppColors.chartOrange;
      case 'A rélancer':
        return AppColors.chartRed;
      default:
        return const Color(0xFF4F46E5);
    }
  }

  int _metricColumns(double width) {
    if (width >= 1280) return 4;
    if (width >= 820) return 2;
    return 1;
  }

  Widget _buildMetricGrid(double width, List<Widget> cards) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _metricColumns(width),
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        mainAxisExtent: width < 520 ? 206 : 188,
      ),
      itemBuilder: (context, index) => cards[index],
    );
  }

  Widget _buildSectionPanel({
    required BuildContext context,
    required String title,
    required String subtitle,
    required Widget child,
    required Color accentColor,
    String? eyebrow,
    Widget? action,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;

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
                    accentColor.withValues(alpha: 0.07),
                    cs.surface.withValues(alpha: 0.98),
                  )
                : Colors.white.withValues(alpha: 0.96),
            cs.surface.withValues(alpha: isDark ? 0.98 : 0.92),
            accentColor.withValues(alpha: isDark ? 0.08 : 0.05),
          ],
        ),
        border: Border.all(color: accentColor.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.08),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
            blurRadius: 20,
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
                    colors: [accentColor, accentColor.withValues(alpha: 0.28)],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -36,
              right: -10,
              child: Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor.withValues(alpha: 0.08),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
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
                            if (eyebrow != null) ...[
                              Text(
                                eyebrow.toUpperCase(),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: accentColor,
                                  fontWeight: FontWeight.w800,
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
                                color: cs.onSurfaceVariant,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ?action,
                    ],
                  ),
                  const SizedBox(height: 18),
                  child,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard({
    required BuildContext context,
    required bool isPhone,
    required CommuneOverviewRow? best,
    required int totalTransactions,
    required int activeCount,
    required int watchCount,
    required double averageTicket,
    required double bestShare,
  }) {
    final theme = Theme.of(context);
    final actionButton = FilledButton.icon(
      onPressed: _load,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.14),
        foregroundColor: Colors.white,
        shadowColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        ),
      ),
      icon: const Icon(Icons.refresh_rounded),
      label: const Text('Actualiser'),
    );
    final addButton = Tooltip(
      message: 'Ajouter une commune',
      child: IconButton.filledTonal(
        onPressed: _addingCommune ? null : _showAddCommuneDialog,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.16),
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.55),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
        ),
        icon: _addingCommune
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
      ),
    );
    final heroActions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.profile.canManageApp) ...[
          addButton,
          const SizedBox(width: 10),
        ],
        actionButton,
      ],
    );

    final heroPills = <({String label, String value, IconData icon})>[
      (
        label: 'Périmètre',
        value: _scopeLabel,
        icon: Icons.location_on_outlined,
      ),
      (
        label: 'Communes actives',
        value: '$activeCount',
        icon: Icons.hub_outlined,
      ),
      (
        label: 'Zones à  suivre',
        value: '$watchCount',
        icon: Icons.radar_outlined,
      ),
      (
        label: 'Transactions',
        value: '$totalTransactions',
        icon: Icons.receipt_long_outlined,
      ),
    ];

    final spotlight = best == null
        ? 'Aucune commune n \'a encore enregistré de recette aujourd\'hui.'
        : '${best.name} mène la journée avec ${_fmt(best.revenueToday)}.';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.sidebar, AppColors.chartTeal, AppColors.primary],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.sidebar.withValues(alpha: 0.24),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Stack(
          children: [
            Positioned(
              top: -30,
              right: -16,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
            ),
            Positioned(
              bottom: -54,
              left: -28,
              child: Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
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
                                'LIVE COMMUNES',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.9,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Gestion des communes',
                              style:
                                  (isPhone
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
                              'Une interface plus vivante pour piloter les recettes du jour, identifier les zones fortes et répérer les communes à  accompagner sans effort.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white.withValues(alpha: 0.88),
                                height: 1.55,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isPhone) heroActions,
                      if (isPhone && widget.profile.canManageApp) addButton,
                    ],
                  ),
                  const SizedBox(height: 22),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final pill in heroPills)
                        _CommuneHeroPill(
                          icon: pill.icon,
                          label: pill.label,
                          value: pill.value,
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  if (isPhone)
                    SizedBox(width: double.infinity, child: actionButton),
                  if (isPhone) const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: Colors.white.withValues(alpha: 0.10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 220),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Recettes du jour',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.76),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _fmt(_totalToday),
                                style:
                                    (isPhone
                                            ? theme.textTheme.displaySmall
                                            : theme.textTheme.displayMedium)
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: -1.0,
                                        ),
                              ),
                            ],
                          ),
                        ),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: isPhone ? 220 : 280,
                            maxWidth: isPhone ? double.infinity : 360,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                best == null
                                    ? 'Signal du jour'
                                    : 'Commune phare',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.76),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                spotlight,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  height: 1.45,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  _HeroMetricChip(
                                    icon: Icons.auto_graph_rounded,
                                    label: 'Ticket moyen',
                                    value: _fmtCompact(averageTicket),
                                  ),
                                  _HeroMetricChip(
                                    icon: Icons.pie_chart_outline_rounded,
                                    label: 'Part du leader',
                                    value:
                                        '${(bestShare * 100).toStringAsFixed(0)}%',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
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

  Widget _buildSpotlightPanel({
    required BuildContext context,
    required CommuneOverviewRow? best,
    required double maxRevenue,
    required int activeCount,
    required int watchCount,
    required double averageTicket,
  }) {
    if (best == null) {
      return _buildSectionPanel(
        context: context,
        title: 'Spotlight terrain',
        subtitle:
            'Les signaux apparaitront ici dès que les communes auront de l\'activité.',
        accentColor: AppColors.chartTeal,
        eyebrow: 'Focus',
        child: Text(
          'Aucune commune active pour le moment.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    final accent = _statusColor(best, maxRevenue);
    final progress = _progressFor(best, maxRevenue);

    return _buildSectionPanel(
      context: context,
      title: 'Spotlight terrain',
      subtitle:
          'La commune la plus dynamique du jour et les principaux signaux operationnels.',
      accentColor: AppColors.chartTeal,
      eyebrow: 'Focus',
      action: const _SoftBadge(
        icon: Icons.bolt_rounded,
        label: 'Temps réel',
        color: AppColors.chartTeal,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.18),
                  accent.withValues(alpha: 0.08),
                ],
              ),
              border: Border.all(color: accent.withValues(alpha: 0.14)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: accent.withValues(alpha: 0.14),
                      ),
                      child: Icon(Icons.location_city_outlined, color: accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            best.name,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _bourgmestreLabel(best),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const _SoftBadge(
                      icon: Icons.emoji_events_outlined,
                      label: 'Leader',
                      color: AppColors.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  _fmt(best.revenueToday),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.9,
                  ),
                ),
                const SizedBox(height: 8),
                _ProgressTrack(progress: progress, color: accent),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _MiniInsightTile(
                      icon: Icons.receipt_long_outlined,
                      label: 'Transactions',
                      value: '${best.transactionsToday}',
                      accentColor: accent,
                    ),
                    _MiniInsightTile(
                      icon: Icons.hub_outlined,
                      label: 'Communes actives',
                      value: '$activeCount',
                      accentColor: AppColors.chartTeal,
                    ),
                    _MiniInsightTile(
                      icon: Icons.radar_outlined,
                      label: 'Zones à suivre',
                      value: '$watchCount',
                      accentColor: AppColors.chartOrange,
                    ),
                    _MiniInsightTile(
                      icon: Icons.auto_graph_rounded,
                      label: 'Ticket moyen',
                      value: _fmtCompact(averageTicket),
                      accentColor: const Color(0xFF4F46E5),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRadarPanel({
    required BuildContext context,
    required List<CommuneOverviewRow> rows,
    required double maxRevenue,
  }) {
    final topThree = rows.take(3).toList();

    return _buildSectionPanel(
      context: context,
      title: 'Radar du jour',
      subtitle:
          'Lecture rapide de la dynamique générale, du leader aux communes à  réactiver.',
      accentColor: const Color(0xFF4F46E5),
      eyebrow: 'Radar',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < topThree.length; i++) ...[
            _RadarRow(
              rank: i + 1,
              name: topThree[i].name,
              subtitle: _statusLabel(topThree[i], maxRevenue),
              value: _fmt(topThree[i].revenueToday),
              accentColor: _statusColor(topThree[i], maxRevenue),
            ),
            if (i != topThree.length - 1) const SizedBox(height: 12),
          ],
          if (topThree.isEmpty)
            Text(
              'Aucune donnée disponible.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
        ],
      ),
    );
  }

  Widget _buildRankingPanel({
    required BuildContext context,
    required List<CommuneOverviewRow> rows,
    required double maxRevenue,
  }) {
    return _buildSectionPanel(
      context: context,
      title: 'Classement live des communes',
      subtitle:
          'Une vue moins statique, avec progression, statut et principaux responsables.',
      accentColor: AppColors.primary,
      eyebrow: 'Classement',
      action: _SoftBadge(
        icon: Icons.location_city_outlined,
        label: '${rows.length} commune(s)',
        color: AppColors.primary,
      ),
      child: rows.isEmpty
          ? Container(
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
                'Les communes apparaitront ici quand des données seront disponibles.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  _CommunePerformanceCard(
                    rank: i + 1,
                    row: rows[i],
                    revenueLabel: _fmt(rows[i].revenueToday),
                    bourgmestreLabel: _bourgmestreLabel(rows[i]),
                    statusLabel: _statusLabel(rows[i], maxRevenue),
                    progress: _progressFor(rows[i], maxRevenue),
                    accentColor: _statusColor(rows[i], maxRevenue),
                    leaderLabel: maxRevenue <= 0
                        ? 'Sans base de comparaison'
                        : '${(_progressFor(rows[i], maxRevenue) * 100).toStringAsFixed(0)}% du leader',
                  ),
                  if (i != rows.length - 1) const SizedBox(height: 14),
                ],
              ],
            ),
    );
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
              FilledButton(onPressed: _load, child: const Text('Reessayer')),
            ],
          ),
        ),
      );
    }

    final sortedRows = List<CommuneOverviewRow>.from(_rows)
      ..sort((a, b) {
        final byRevenue = b.revenueToday.compareTo(a.revenueToday);
        if (byRevenue != 0) return byRevenue;
        return b.transactionsToday.compareTo(a.transactionsToday);
      });
    final best = sortedRows.isEmpty ? null : sortedRows.first;

    var maxRevenue = 0.0;
    var totalTransactions = 0;
    var activeCount = 0;
    var watchCount = 0;
    for (final row in sortedRows) {
      maxRevenue = math.max(maxRevenue, row.revenueToday).toDouble();
      totalTransactions += row.transactionsToday;
      if (row.transactionsToday > 0 || row.revenueToday > 0) {
        activeCount++;
      }
      if (row.transactionsToday == 0 ||
          (row.revenueToday > 0 && row.revenueToday < 100)) {
        watchCount++;
      }
    }

    final bestShare = best == null || _totalToday <= 0
        ? 0.0
        : best.revenueToday / _totalToday;
    final averageTicket = totalTransactions == 0
        ? 0.0
        : _totalToday / totalTransactions;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPhone = constraints.maxWidth < 920;
        final contentWidth = constraints.maxWidth;

        final metricCards = <Widget>[
          MetricCard(
            title: 'Recettes du jour',
            value: _fmt(_totalToday),
            subtitle: _scopeLabel,
            width: null,
            minHeight: 144,
            icon: Icons.payments_outlined,
            accentColor: AppColors.primary,
            badge: 'Live',
            highlighted: true,
            numericValue: _totalToday,
            animatedFormatter: _fmt,
          ),
          MetricCard(
            title: 'Transactions',
            value: '$totalTransactions',
            subtitle: 'Volume enregistré aujourd hui',
            width: null,
            minHeight: 144,
            icon: Icons.receipt_long_outlined,
            accentColor: AppColors.chartTeal,
            badge: 'Flux',
            numericValue: totalTransactions.toDouble(),
            animatedFormatter: (value) => value.round().toString(),
          ),
          MetricCard(
            title: 'Commune leader',
            value: best?.name ?? 'Aucune',
            subtitle: best == null
                ? 'Pas encore d\'activité'
                : _fmt(best.revenueToday),
            width: null,
            minHeight: 144,
            icon: Icons.location_city_outlined,
            accentColor: const Color(0xFF4F46E5),
            badge: 'Top',
          ),
          MetricCard(
            title: 'Zones à suivre',
            value: '$watchCount',
            subtitle: watchCount == 0
                ? 'Aucune commune en tension'
                : 'Activité faible ou absente',
            width: null,
            minHeight: 144,
            icon: Icons.radar_outlined,
            accentColor: watchCount > 0
                ? AppColors.chartOrange
                : AppColors.chartTeal,
            badge: watchCount > 0 ? 'Veille' : 'OK',
            numericValue: watchCount.toDouble(),
            animatedFormatter: (value) => value.round().toString(),
          ),
        ];

        return RefreshIndicator(
          onRefresh: _load,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(isPhone ? 16 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeroCard(
                  context: context,
                  isPhone: isPhone,
                  best: best,
                  totalTransactions: totalTransactions,
                  activeCount: activeCount,
                  watchCount: watchCount,
                  averageTicket: averageTicket,
                  bestShare: bestShare,
                ),
                const SizedBox(height: 16),
                _buildMetricGrid(contentWidth, metricCards),
                const SizedBox(height: 16),
                if (isPhone) ...[
                  _buildSpotlightPanel(
                    context: context,
                    best: best,
                    maxRevenue: maxRevenue,
                    activeCount: activeCount,
                    watchCount: watchCount,
                    averageTicket: averageTicket,
                  ),
                  const SizedBox(height: 16),
                  _buildRadarPanel(
                    context: context,
                    rows: sortedRows,
                    maxRevenue: maxRevenue,
                  ),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildSpotlightPanel(
                          context: context,
                          best: best,
                          maxRevenue: maxRevenue,
                          activeCount: activeCount,
                          watchCount: watchCount,
                          averageTicket: averageTicket,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildRadarPanel(
                          context: context,
                          rows: sortedRows,
                          maxRevenue: maxRevenue,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 16),
                _buildRankingPanel(
                  context: context,
                  rows: sortedRows,
                  maxRevenue: maxRevenue,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CommuneHeroPill extends StatelessWidget {
  const _CommuneHeroPill({
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
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
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

class _HeroMetricChip extends StatelessWidget {
  const _HeroMetricChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            '$label : $value',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SoftBadge extends StatelessWidget {
  const _SoftBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniInsightTile extends StatelessWidget {
  const _MiniInsightTile({
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
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 240),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: cs.surface.withValues(alpha: 0.72),
        border: Border.all(color: accentColor.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: accentColor.withValues(alpha: 0.10),
            ),
            child: Icon(icon, color: accentColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RadarRow extends StatelessWidget {
  const _RadarRow({
    required this.rank,
    required this.name,
    required this.subtitle,
    required this.value,
    required this.accentColor,
  });

  final int rank;
  final String name;
  final String subtitle;
  final String value;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: cs.surface.withValues(alpha: 0.72),
        border: Border.all(color: accentColor.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: accentColor.withValues(alpha: 0.10),
            ),
            alignment: Alignment.center,
            child: Text(
              '$rank',
              style: theme.textTheme.titleSmall?.copyWith(
                color: accentColor,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunePerformanceCard extends StatelessWidget {
  const _CommunePerformanceCard({
    required this.rank,
    required this.row,
    required this.revenueLabel,
    required this.bourgmestreLabel,
    required this.statusLabel,
    required this.progress,
    required this.accentColor,
    required this.leaderLabel,
  });

  final int rank;
  final CommuneOverviewRow row;
  final String revenueLabel;
  final String bourgmestreLabel;
  final String statusLabel;
  final double progress;
  final Color accentColor;
  final String leaderLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 740;
        final agentsLabel = row.agentNames.isEmpty
            ? 'Aucun agent affecte'
            : row.agentNames.join(', ');

        final rankBadge = Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accentColor, accentColor.withValues(alpha: 0.70)],
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            '$rank',
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        );

        final details = Column(
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
                        row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        bourgmestreLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Agents: $agentsLabel',
                        maxLines: compact ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 12),
                  Text(
                    revenueLabel,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ],
            ),
            if (compact) ...[
              const SizedBox(height: 12),
              Text(
                revenueLabel,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
            const SizedBox(height: 14),
            _ProgressTrack(progress: progress, color: accentColor),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetaChip(
                  icon: Icons.receipt_long_outlined,
                  label: '${row.transactionsToday} transaction(s)',
                  accentColor: accentColor,
                ),
                _MetaChip(
                  icon: Icons.support_agent_outlined,
                  label: '${row.agentNames.length} agent(s)',
                  accentColor: accentColor,
                ),
                _MetaChip(
                  icon: Icons.flag_outlined,
                  label: leaderLabel,
                  accentColor: accentColor,
                ),
                _MetaChip(
                  icon: Icons.bolt_outlined,
                  label: statusLabel,
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
            borderRadius: BorderRadius.circular(26),
            color: cs.surface.withValues(alpha: 0.78),
            border: Border.all(color: accentColor.withValues(alpha: 0.12)),
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
                  children: [rankBadge, const SizedBox(height: 14), details],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    rankBadge,
                    const SizedBox(width: 16),
                    Expanded(child: details),
                  ],
                ),
        );
      },
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.accentColor,
  });

  final IconData icon;
  final String label;
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
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressTrack extends StatelessWidget {
  const _ProgressTrack({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 12,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.10),
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: progress),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, animatedProgress, _) {
          return Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: animatedProgress.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.55)],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
