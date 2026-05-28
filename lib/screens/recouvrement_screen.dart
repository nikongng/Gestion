import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/gestia_data_service.dart';
import '../theme/app_colors.dart';
import '../utils/error_messages.dart';

class RecouvrementScreen extends StatefulWidget {
  const RecouvrementScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<RecouvrementScreen> createState() => _RecouvrementScreenState();
}

class _RecouvrementScreenState extends State<RecouvrementScreen> {
  List<Map<String, dynamic>> _overdue = [];
  bool _loading = true;
  String? _error;
  String? _updatingId;

  String? get _scope =>
      widget.profile.role.isGlobalSupervisor ? null : widget.profile.communeId;

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
      final rows = await GestiaDataService.fetchPerceptionNotes(
        statuses: const [
          'taxation_creee',
          'ordonnee',
          'note_perception_generee',
          'paiement_declare',
          'en_recouvrement',
        ],
        communeId: _scope,
        overdueOnly: true,
      );
      if (!mounted) return;
      setState(() {
        _overdue = rows;
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

  Future<void> _markRecovery(Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() => _updatingId = id);
    try {
      await GestiaDataService.updatePerceptionNoteStatus(
        noteId: id,
        status: 'en_recouvrement',
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note placée en recouvrement.')),
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

  String _communeName(Map<String, dynamic> row) {
    final commune = row['communes'];
    if (commune is Map) {
      final name = commune['name']?.toString().trim();
      if (name != null && name.isNotEmpty) return name;
    }
    return row['collection_scope'] == 'mairie' ? 'Mairie' : 'Commune';
  }

  String _money(Map<String, dynamic> row) {
    final amount = (row['amount'] as num?)?.toDouble() ?? 0;
    return '${amount.toStringAsFixed(2)} USD';
  }

  int _delayDays(Map<String, dynamic> row) {
    final deadline = DateTime.tryParse(
      row['payment_deadline']?.toString() ?? '',
    )?.toLocal();
    if (deadline == null) return 0;
    return DateTime.now().difference(deadline).inDays.clamp(0, 9999).toInt();
  }

  double _penalty(Map<String, dynamic> row) {
    final amount = (row['amount'] as num?)?.toDouble() ?? 0;
    final days = _delayDays(row);
    return amount * 0.01 * days;
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Card(
        elevation: 0,
        child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
      );
    }
    if (_overdue.isEmpty) {
      return Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            'Aucune note en souffrance dans votre périmètre.',
            style: theme.textTheme.bodyLarge,
          ),
        ),
      );
    }
    return Card(
      elevation: 0,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Note')),
            DataColumn(label: Text('Commune')),
            DataColumn(label: Text('Assujetti')),
            DataColumn(label: Text('Retard')),
            DataColumn(label: Text('Pénalité')),
            DataColumn(label: Text('Statut')),
            DataColumn(label: Text('Action')),
          ],
          rows: [
            for (final row in _overdue)
              DataRow(
                cells: [
                  DataCell(Text(row['note_number']?.toString() ?? '-')),
                  DataCell(Text(_communeName(row))),
                  DataCell(Text(row['taxpayer_name']?.toString() ?? '-')),
                  DataCell(Text('${_delayDays(row)} j')),
                  DataCell(Text(_money({'amount': _penalty(row)}))),
                  DataCell(Text(row['status']?.toString() ?? '-')),
                  DataCell(
                    FilledButton.tonalIcon(
                      onPressed:
                          row['status'] == 'en_recouvrement' ||
                              _updatingId == row['id']
                          ? null
                          : () => _markRecovery(row),
                      icon: _updatingId == row['id']
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.notification_important_outlined),
                      label: const Text('Suivre'),
                    ),
                  ),
                ],
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
                    fontWeight: FontWeight.w800,
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
          const SizedBox(height: 8),
          Text(
            'Détection automatique des retards, pénalités estimées à 1% par jour, et suivi des notes en souffrance.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _buildBody(context),
        ],
      ),
    );
  }
}
