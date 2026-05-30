import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/gestia_data_service.dart';
import '../theme/app_colors.dart';
import '../utils/error_messages.dart';

enum _RecoveryStatusFilter { all, normal, reminder, late, veryLate, recovery }

class _RecoveryActionLog {
  const _RecoveryActionLog({
    required this.noteId,
    required this.label,
    required this.createdAt,
    this.observation,
  });

  final String noteId;
  final String label;
  final DateTime createdAt;
  final String? observation;
}

class RecouvrementScreen extends StatefulWidget {
  const RecouvrementScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<RecouvrementScreen> createState() => _RecouvrementScreenState();
}

class _RecouvrementScreenState extends State<RecouvrementScreen> {
  final _searchCtrl = TextEditingController();
  final _minAmountCtrl = TextEditingController();
  final _maxAmountCtrl = TextEditingController();
  final _observationCtrl = TextEditingController();

  List<Map<String, dynamic>> _notes = [];
  List<_RecoveryActionLog> _actionLogs = [];
  bool _loading = true;
  String? _error;
  String? _updatingId;
  String? _selectedId;
  String? _communeFilter;
  _RecoveryStatusFilter _statusFilter = _RecoveryStatusFilter.all;
  DateTimeRange? _deadlineRange;

  String? get _scope =>
      widget.profile.isGlobalSupervisor ? null : widget.profile.communeId;

  Map<String, dynamic>? get _selectedNote {
    if (_selectedId == null) return _filteredNotes.firstOrNull;
    for (final note in _filteredNotes) {
      if (note['id']?.toString() == _selectedId) return note;
    }
    return _filteredNotes.firstOrNull;
  }

  List<Map<String, dynamic>> get _recoveryNotes {
    final rows = _notes.where((row) {
      if (_isPaid(row)) return false;
      return _delayDays(row) > 0 ||
          row['status']?.toString() == 'en_recouvrement';
    }).toList();
    rows.sort((a, b) {
      final delayCompare = _delayDays(b).compareTo(_delayDays(a));
      if (delayCompare != 0) return delayCompare;
      return _deadline(a).compareTo(_deadline(b));
    });
    return rows;
  }

  List<Map<String, dynamic>> get _filteredNotes {
    final query = _searchCtrl.text.trim().toLowerCase();
    final minAmount = double.tryParse(
      _minAmountCtrl.text.trim().replaceAll(',', '.'),
    );
    final maxAmount = double.tryParse(
      _maxAmountCtrl.text.trim().replaceAll(',', '.'),
    );

    return _recoveryNotes.where((row) {
      if (_communeFilter != null && _communeName(row) != _communeFilter) {
        return false;
      }
      if (_deadlineRange != null) {
        final deadline = _deadline(row);
        final start = DateTime(
          _deadlineRange!.start.year,
          _deadlineRange!.start.month,
          _deadlineRange!.start.day,
        );
        final end = DateTime(
          _deadlineRange!.end.year,
          _deadlineRange!.end.month,
          _deadlineRange!.end.day,
          23,
          59,
          59,
        );
        if (deadline.isBefore(start) || deadline.isAfter(end)) return false;
      }
      if (_statusFilter != _RecoveryStatusFilter.all &&
          _statusFilter != _statusBucket(row)) {
        return false;
      }
      final amount = _amount(row);
      if (minAmount != null && amount < minAmount) return false;
      if (maxAmount != null && amount > maxAmount) return false;
      if (query.isEmpty) return true;
      final haystack = [
        row['note_number'],
        row['taxpayer_name'],
        row['taxpayer_identifier'],
        row['tax_category'],
        _communeName(row),
        _statusLabel(row),
      ].map((value) => value?.toString().toLowerCase() ?? '').join(' ');
      return haystack.contains(query);
    }).toList();
  }

  List<String> get _communes {
    final values = _recoveryNotes.map(_communeName).toSet().toList()..sort();
    return values;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _minAmountCtrl.dispose();
    _maxAmountCtrl.dispose();
    _observationCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await GestiaDataService.markOverdueTaxationsForRecovery();
      final rows = await GestiaDataService.fetchPerceptionNotes(
        statuses: const [
          'ordonnee',
          'note_perception_generee',
          'paiement_declare',
          'en_recouvrement',
        ],
        communeId: _scope,
        limit: 5000,
      );
      if (!mounted) return;
      setState(() {
        _notes = rows;
        if (_selectedId != null &&
            !_recoveryNotes.any(
              (row) => row['id']?.toString() == _selectedId,
            )) {
          _selectedId = null;
        }
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

  Future<void> _pickDeadlineRange() async {
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _deadlineRange,
    );
    if (selected == null) return;
    setState(() => _deadlineRange = selected);
  }

  void _clearFilters() {
    _searchCtrl.clear();
    _minAmountCtrl.clear();
    _maxAmountCtrl.clear();
    setState(() {
      _communeFilter = null;
      _statusFilter = _RecoveryStatusFilter.all;
      _deadlineRange = null;
    });
  }

  Future<void> _sendReminder(Map<String, dynamic> row) async {
    _addHistory(row, 'Rappel envoye');
    final phone = row['taxpayer_phone']?.toString().trim();
    final target = phone == null || phone.isEmpty ? 'notification' : 'SMS';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Rappel $target prepare pour cette note.')),
    );
  }

  Future<void> _applyPenalty(Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() => _updatingId = id);
    try {
      await GestiaDataService.updatePerceptionNoteStatus(
        noteId: id,
        status: 'en_recouvrement',
      );
      _addHistory(row, 'Penalite appliquee');
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Penalite calculee: ${_formatMoney(_penalty(row))}.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _updatingId = null);
    }
  }

  Future<void> _markRecovered(Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() => _updatingId = id);
    try {
      await GestiaDataService.updatePerceptionNoteStatus(
        noteId: id,
        status: 'apuree_cpi_genere',
        paidAt: DateTime.now(),
        apuredAt: DateTime.now(),
      );
      _addHistory(row, 'Note marquee comme recouvree');
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note marquee comme recouvree.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _updatingId = null);
    }
  }

  void _addHistory(Map<String, dynamic> row, String label) {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() {
      _actionLogs = [
        _RecoveryActionLog(
          noteId: id,
          label: label,
          createdAt: DateTime.now(),
          observation: _observationCtrl.text.trim().isEmpty
              ? null
              : _observationCtrl.text.trim(),
        ),
        ..._actionLogs,
      ];
    });
  }

  bool _isPaid(Map<String, dynamic> row) {
    final status = row['status']?.toString();
    return status == 'apuree_cpi_genere' ||
        row['apured_at'] != null ||
        row['cpi_number']?.toString().trim().isNotEmpty == true;
  }

  double _amount(Map<String, dynamic> row) {
    return (row['amount'] as num?)?.toDouble() ?? 0;
  }

  DateTime _deadline(Map<String, dynamic> row) {
    final parsed = DateTime.tryParse(row['payment_deadline']?.toString() ?? '');
    return parsed?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  DateTime _createdAt(Map<String, dynamic> row) {
    final parsed = DateTime.tryParse(row['created_at']?.toString() ?? '');
    return parsed?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  int _delayDays(Map<String, dynamic> row) {
    final deadline = _deadline(row);
    if (deadline.millisecondsSinceEpoch == 0) return 0;
    final today = DateTime.now();
    final cleanToday = DateTime(today.year, today.month, today.day);
    final cleanDeadline = DateTime(deadline.year, deadline.month, deadline.day);
    return cleanToday.difference(cleanDeadline).inDays.clamp(0, 9999).toInt();
  }

  double _penaltyRate(Map<String, dynamic> row) {
    final days = _delayDays(row);
    if (days <= 8) return 0;
    if (days <= 30) return 0.05;
    if (days <= 60) return 0.10;
    return 0.15;
  }

  double _penalty(Map<String, dynamic> row) {
    return _amount(row) * _penaltyRate(row);
  }

  double _totalDue(Map<String, dynamic> row) {
    return _amount(row) + _penalty(row);
  }

  _RecoveryStatusFilter _statusBucket(Map<String, dynamic> row) {
    if (row['status']?.toString() == 'en_recouvrement') {
      return _RecoveryStatusFilter.recovery;
    }
    final days = _delayDays(row);
    if (days <= 8) return _RecoveryStatusFilter.normal;
    if (days <= 15) return _RecoveryStatusFilter.reminder;
    if (days <= 30) return _RecoveryStatusFilter.late;
    return _RecoveryStatusFilter.veryLate;
  }

  String _statusLabel(Map<String, dynamic> row) {
    if (row['status']?.toString() == 'en_recouvrement') {
      final ordonnateurId = row['ordonnateur_id']?.toString().trim();
      if (ordonnateurId == null || ordonnateurId.isEmpty) {
        return 'Non ordonnée - recouvrement';
      }
      return 'En recouvrement';
    }
    return switch (_statusBucket(row)) {
      _RecoveryStatusFilter.normal => 'Note normale',
      _RecoveryStatusFilter.reminder => 'A rappeler',
      _RecoveryStatusFilter.late => 'En retard',
      _RecoveryStatusFilter.veryLate => 'Tres en retard',
      _RecoveryStatusFilter.recovery => 'En recouvrement',
      _RecoveryStatusFilter.all => '-',
    };
  }

  String _statusFilterLabel(_RecoveryStatusFilter value) {
    return switch (value) {
      _RecoveryStatusFilter.all => 'Tous les statuts',
      _RecoveryStatusFilter.normal => 'Note normale',
      _RecoveryStatusFilter.reminder => 'A rappeler',
      _RecoveryStatusFilter.late => 'En retard',
      _RecoveryStatusFilter.veryLate => 'Tres en retard',
      _RecoveryStatusFilter.recovery => 'En recouvrement',
    };
  }

  Color _statusColor(Map<String, dynamic> row) {
    return switch (_statusBucket(row)) {
      _RecoveryStatusFilter.normal => AppColors.chartBlue,
      _RecoveryStatusFilter.reminder => AppColors.chartYellow,
      _RecoveryStatusFilter.late => AppColors.chartOrange,
      _RecoveryStatusFilter.veryLate => AppColors.chartRed,
      _RecoveryStatusFilter.recovery => AppColors.chartPurple,
      _RecoveryStatusFilter.all => AppColors.primary,
    };
  }

  String _communeName(Map<String, dynamic> row) {
    final scope = row['collection_scope']?.toString().trim().toLowerCase();
    if (scope == 'mairie') return 'Mairie';
    final commune = row['communes'];
    if (commune is Map) {
      final name = commune['name']?.toString().trim();
      if (name != null && name.isNotEmpty) return name;
    }
    return 'Commune';
  }

  String _formatMoney(double value) {
    return '${value.toStringAsFixed(2)} USD';
  }

  String _formatDate(DateTime value) {
    if (value.millisecondsSinceEpoch == 0) return '-';
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  String _formatDateTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${_formatDate(value)} $hour:$minute';
  }

  Widget _metricCard({
    required BuildContext context,
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
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

  Widget _buildMetrics(BuildContext context) {
    final suffering = _recoveryNotes.where((row) => _delayDays(row) > 8).length;
    final overdue = _recoveryNotes.length;
    final penalties = _recoveryNotes.fold<double>(
      0,
      (sum, row) => sum + _penalty(row),
    );
    final recovered = _notes
        .where(_isPaid)
        .fold<double>(0, (sum, row) => sum + _amount(row));
    final base = _notes.fold<double>(0, (sum, row) => sum + _amount(row));
    final rate = base <= 0 ? 0 : (recovered / base * 100).clamp(0, 100);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1100
            ? 5
            : width >= 760
            ? 3
            : 1;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: columns == 1 ? 4.2 : 2.2,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _metricCard(
              context: context,
              label: 'Notes en souffrance',
              value: '$suffering',
              icon: Icons.warning_amber_outlined,
              color: AppColors.chartOrange,
            ),
            _metricCard(
              context: context,
              label: 'Notes depassees',
              value: '$overdue',
              icon: Icons.schedule_outlined,
              color: AppColors.chartRed,
            ),
            _metricCard(
              context: context,
              label: 'Total penalites',
              value: _formatMoney(penalties),
              icon: Icons.price_change_outlined,
              color: AppColors.chartPurple,
            ),
            _metricCard(
              context: context,
              label: 'Total recouvre',
              value: _formatMoney(recovered),
              icon: Icons.verified_outlined,
              color: AppColors.chartTeal,
            ),
            _metricCard(
              context: context,
              label: 'Taux recouvrement',
              value: '${rate.toStringAsFixed(1)}%',
              icon: Icons.trending_up_outlined,
              color: AppColors.primary,
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilters(BuildContext context) {
    final rangeLabel = _deadlineRange == null
        ? 'Date echeance'
        : '${_formatDate(_deadlineRange!.start)} - ${_formatDate(_deadlineRange!.end)}';

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Recherche',
                  hintText: 'Note, contribuable, taxe...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String?>(
                initialValue: _communeFilter,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Commune',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Toutes les communes'),
                  ),
                  for (final commune in _communes)
                    DropdownMenuItem<String?>(
                      value: commune,
                      child: Text(commune),
                    ),
                ],
                onChanged: (value) => setState(() => _communeFilter = value),
              ),
            ),
            SizedBox(
              width: 210,
              child: DropdownButtonFormField<_RecoveryStatusFilter>(
                initialValue: _statusFilter,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Statut',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final status in _RecoveryStatusFilter.values)
                    DropdownMenuItem(
                      value: status,
                      child: Text(_statusFilterLabel(status)),
                    ),
                ],
                onChanged: (value) => setState(
                  () => _statusFilter = value ?? _RecoveryStatusFilter.all,
                ),
              ),
            ),
            SizedBox(
              width: 150,
              child: TextField(
                controller: _minAmountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Montant min',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            SizedBox(
              width: 150,
              child: TextField(
                controller: _maxAmountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Montant max',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _pickDeadlineRange,
              icon: const Icon(Icons.date_range_outlined),
              label: Text(rangeLabel),
            ),
            IconButton.filledTonal(
              tooltip: 'Réinitialiser',
              onPressed: _clearFilters,
              icon: const Icon(Icons.filter_alt_off_outlined),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildTable(BuildContext context) {
    final rows = _filteredNotes;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Card(
        elevation: 0,
        child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
      );
    }
    if (rows.isEmpty) {
      return Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            'Aucune note impayee ne correspond aux filtres.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 1320),
          child: DataTable(
            showCheckboxColumn: false,
            columns: const [
              DataColumn(label: Text('Numéro note')),
              DataColumn(label: Text('Contribuable')),
              DataColumn(label: Text('Taxe')),
              DataColumn(label: Text('Montant')),
              DataColumn(label: Text('Date emission')),
              DataColumn(label: Text('Date echeance')),
              DataColumn(label: Text('Jours retard')),
              DataColumn(label: Text('Penalite')),
              DataColumn(label: Text('Statut')),
              DataColumn(label: Text('Actions')),
            ],
            rows: [
              for (final row in rows)
                DataRow(
                  selected:
                      row['id']?.toString() == _selectedNote?['id']?.toString(),
                  onSelectChanged: (_) =>
                      setState(() => _selectedId = row['id']?.toString()),
                  cells: [
                    DataCell(Text(row['note_number']?.toString() ?? '-')),
                    DataCell(Text(row['taxpayer_name']?.toString() ?? '-')),
                    DataCell(Text(row['tax_category']?.toString() ?? '-')),
                    DataCell(Text(_formatMoney(_amount(row)))),
                    DataCell(Text(_formatDate(_createdAt(row)))),
                    DataCell(Text(_formatDate(_deadline(row)))),
                    DataCell(Text('${_delayDays(row)} j')),
                    DataCell(Text(_formatMoney(_penalty(row)))),
                    DataCell(
                      _badge(context, _statusLabel(row), _statusColor(row)),
                    ),
                    DataCell(
                      Wrap(
                        spacing: 6,
                        children: [
                          IconButton(
                            tooltip: 'Envoyer rappel',
                            onPressed: () => _sendReminder(row),
                            icon: const Icon(Icons.sms_outlined),
                          ),
                          IconButton(
                            tooltip: 'Appliquer penalite',
                            onPressed: _updatingId == row['id']?.toString()
                                ? null
                                : () => _applyPenalty(row),
                            icon: const Icon(Icons.price_change_outlined),
                          ),
                          IconButton(
                            tooltip: 'Marquer comme recouvree',
                            onPressed: _updatingId == row['id']?.toString()
                                ? null
                                : () => _markRecovered(row),
                            icon: const Icon(Icons.verified_outlined),
                          ),
                        ],
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

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildDetailPanel(BuildContext context) {
    final row = _selectedNote;
    final theme = Theme.of(context);
    if (row == null) {
      return Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Selectionnez une note pour voir le detail.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }
    final logs = _actionLogs
        .where((log) => log.noteId == row['id']?.toString())
        .toList();

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.assignment_outlined, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    row['note_number']?.toString() ?? 'Note',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _badge(context, _statusLabel(row), _statusColor(row)),
              ],
            ),
            const SizedBox(height: 12),
            _detailLine(
              'Contribuable',
              row['taxpayer_name']?.toString() ?? '-',
            ),
            _detailLine('Commune', _communeName(row)),
            _detailLine('Montant initial', _formatMoney(_amount(row))),
            _detailLine('Penalite', _formatMoney(_penalty(row))),
            _detailLine('Total actualise', _formatMoney(_totalDue(row))),
            _detailLine('Emission', _formatDate(_createdAt(row))),
            _detailLine('Echeance', _formatDate(_deadline(row))),
            _detailLine('Retard', '${_delayDays(row)} jours'),
            const SizedBox(height: 14),
            TextField(
              controller: _observationCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Observations',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => _sendReminder(row),
                  icon: const Icon(Icons.sms_outlined),
                  label: const Text('Envoyer rappel'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _updatingId == row['id']?.toString()
                      ? null
                      : () => _applyPenalty(row),
                  icon: const Icon(Icons.price_change_outlined),
                  label: const Text('Appliquer penalite'),
                ),
                FilledButton.icon(
                  onPressed: _updatingId == row['id']?.toString()
                      ? null
                      : () => _markRecovered(row),
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('Marquer recouvree'),
                ),
              ],
            ),
            const Divider(height: 28),
            Text(
              'Historique des actions',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            if (logs.isEmpty)
              Text(
                'Aucune action enregistrée dans cette session.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final log in logs)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history_outlined),
                  title: Text(log.label),
                  subtitle: Text(
                    [
                      _formatDateTime(log.createdAt),
                      if (log.observation != null) log.observation!,
                    ].join(' - '),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.notification_important_outlined,
                color: AppColors.chartOrange,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Recouvrement',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Actualiser',
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Liste des assujettis non en ordre : notes non ordonnees apres 8 jours, impayes, penalites et suivi des actions du receveur.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _buildMetrics(context),
          const SizedBox(height: 16),
          _buildFilters(context),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 980) {
                return Column(
                  children: [
                    _buildTable(context),
                    const SizedBox(height: 16),
                    _buildDetailPanel(context),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: _buildTable(context)),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: _buildDetailPanel(context)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
