import 'package:flutter/material.dart';

import '../models/app_role.dart';
import '../models/user_profile.dart';
import '../services/gestia_data_service.dart';
import '../theme/app_colors.dart';
import '../utils/error_messages.dart';

class TaxationTaxpayersScreen extends StatefulWidget {
  const TaxationTaxpayersScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<TaxationTaxpayersScreen> createState() =>
      _TaxationTaxpayersScreenState();
}

class _TaxationTaxpayersScreenState extends State<TaxationTaxpayersScreen> {
  List<UserProfile> _taxpayers = [];
  bool _loading = true;
  String? _error;

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
      final profiles = await GestiaDataService.fetchAllProfiles();
      final scoped = profiles.where((profile) {
        if (!profile.hasRole(AppRole.contribuable)) return false;
        if (widget.profile.isGlobalSupervisor) return true;
        if (widget.profile.hasRole(AppRole.taxateur) ||
            widget.profile.hasRole(AppRole.ordonnateur) ||
            widget.profile.hasRole(AppRole.apureur) ||
            widget.profile.hasRole(AppRole.agent)) {
          return true;
        }
        return profile.communeId == widget.profile.communeId;
      }).toList();
      if (!mounted) return;
      setState(() {
        _taxpayers = scoped;
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

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Card(
        elevation: 0,
        child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
      );
    }
    if (_taxpayers.isEmpty) {
      return Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            'Aucun contribuable enregistré dans votre périmètre.',
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
            DataColumn(label: Text('Nom')),
            DataColumn(label: Text('ID contribuable')),
            DataColumn(label: Text('Commune')),
            DataColumn(label: Text('Rôle')),
          ],
          rows: [
            for (final taxpayer in _taxpayers)
              DataRow(
                cells: [
                  DataCell(Text(taxpayer.fullName)),
                  DataCell(Text(taxpayer.taxpayerIdentifier ?? '-')),
                  DataCell(Text(taxpayer.communeName ?? '-')),
                  DataCell(Text(taxpayer.role.shortLabel)),
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
              Icon(Icons.badge_outlined, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Contribuables',
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
