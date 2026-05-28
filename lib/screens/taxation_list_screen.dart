import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/gestia_data_service.dart';
import '../theme/app_colors.dart';
import '../utils/error_messages.dart';

class TaxationListScreen extends StatefulWidget {
  const TaxationListScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<TaxationListScreen> createState() => _TaxationListScreenState();
}

class _TaxationListScreenState extends State<TaxationListScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

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
          'note_perception_generee',
          'paiement_declare',
          'en_recouvrement',
          'apuree_cpi_genere',
        ],
        communeId: _scope,
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
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

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Card(
        elevation: 0,
        child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
      );
    }
    if (_rows.isEmpty) {
      return Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            'Aucune taxation enregistrée dans votre périmètre.',
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
            DataColumn(label: Text('Contribuable')),
            DataColumn(label: Text('Taxe')),
            DataColumn(label: Text('Montant')),
            DataColumn(label: Text('Statut')),
          ],
          rows: [
            for (final row in _rows)
              DataRow(
                cells: [
                  DataCell(Text(row['note_number']?.toString() ?? '-')),
                  DataCell(Text(_communeName(row))),
                  DataCell(Text(row['taxpayer_name']?.toString() ?? '-')),
                  DataCell(Text(row['tax_category']?.toString() ?? '-')),
                  DataCell(Text(_money(row))),
                  DataCell(Text(row['status']?.toString() ?? '-')),
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
              Icon(Icons.format_list_bulleted_outlined, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Liste des taxations',
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
          const SizedBox(height: 16),
          _buildBody(context),
        ],
      ),
    );
  }
}
