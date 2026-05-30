import 'package:flutter/material.dart';

import '../models/app_alert.dart';
import '../models/user_profile.dart';
import '../services/alert_view_store.dart';
import '../services/gestia_data_service.dart';
import '../utils/error_messages.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  bool _loading = true;
  String? _error;
  List<AppAlert> _alerts = [];
  AlertSeverity? _filter;

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
      final list = await GestiaDataService.fetchAlertsForProfile(
        widget.profile,
      );
      if (widget.profile.hasAlertsAccess) {
        await AlertViewStore.markViewed(widget.profile);
      }
      if (!mounted) return;
      setState(() {
        _alerts = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userFacingErrorMessage(e);
        _loading = false;
      });
    }
  }

  List<AppAlert> get _visible {
    final f = _filter;
    if (f == null) return _alerts;
    return _alerts.where((a) => a.severity == f).toList();
  }

  IconData _iconFor(AlertCategory c) {
    return switch (c) {
      AlertCategory.probleme => Icons.report_problem_outlined,
      AlertCategory.fraude => Icons.shield_moon_outlined,
      AlertCategory.retard => Icons.schedule_outlined,
      AlertCategory.securite => Icons.lock_outline,
    };
  }

  Color _severityColor(AlertSeverity s, ColorScheme cs) {
    return switch (s) {
      AlertSeverity.critique => cs.error,
      AlertSeverity.moyenne => const Color(0xFFE65100),
      AlertSeverity.faible => const Color(0xFFF9A825),
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (!widget.profile.hasAlertsAccess) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Les notifications ne sont pas disponibles pour ce profil.',
            textAlign: TextAlign.center,
            style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Réessayer')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Centre de notifications',
                    style: tt.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Suivez les actions qui arrivent dans votre file de travail et les alertes de suivi.',
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  Text('Filtrer par gravité', style: tt.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('Toutes'),
                        selected: _filter == null,
                        onSelected: (_) => setState(() => _filter = null),
                      ),
                      FilterChip(
                        label: const Text('Critique'),
                        selected: _filter == AlertSeverity.critique,
                        onSelected: (_) => setState(
                          () => _filter = _filter == AlertSeverity.critique
                              ? null
                              : AlertSeverity.critique,
                        ),
                      ),
                      FilterChip(
                        label: const Text('Moyenne'),
                        selected: _filter == AlertSeverity.moyenne,
                        onSelected: (_) => setState(
                          () => _filter = _filter == AlertSeverity.moyenne
                              ? null
                              : AlertSeverity.moyenne,
                        ),
                      ),
                      FilterChip(
                        label: const Text('Faible'),
                        selected: _filter == AlertSeverity.faible,
                        onSelected: (_) => setState(
                          () => _filter = _filter == AlertSeverity.faible
                              ? null
                              : AlertSeverity.faible,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_visible.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  'Aucune alerte pour ce filtre.',
                  style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, i) {
                  final a = _visible[i];
                  final col = _severityColor(a.severity, cs);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: col.withValues(alpha: 0.65)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  _iconFor(a.category),
                                  color: col,
                                  size: 22,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        a.title,
                                        style: tt.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          Chip(
                                            padding: EdgeInsets.zero,
                                            visualDensity:
                                                VisualDensity.compact,
                                            label: Text(
                                              a.severity.labelFr,
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                            backgroundColor: col.withValues(
                                              alpha: 0.15,
                                            ),
                                            side: BorderSide.none,
                                          ),
                                          Chip(
                                            padding: EdgeInsets.zero,
                                            visualDensity:
                                                VisualDensity.compact,
                                            label: Text(
                                              a.category.labelFr,
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                            side: BorderSide(
                                              color: cs.outlineVariant,
                                            ),
                                          ),
                                          if (a.communeName != null)
                                            Text(
                                              a.communeName!,
                                              style: tt.bodySmall?.copyWith(
                                                color: cs.onSurfaceVariant,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(a.body, style: tt.bodyMedium),
                            const SizedBox(height: 8),
                            Text(
                              _fmtDate(a.createdAt),
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            if (!a.isOpen)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  'Traitée le ${_fmtDate(a.resolvedAt!)}',
                                  style: tt.bodySmall?.copyWith(
                                    color: cs.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }, childCount: _visible.length),
              ),
            ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
  }
}
