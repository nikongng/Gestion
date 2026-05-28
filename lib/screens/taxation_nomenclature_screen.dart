import 'package:flutter/material.dart';

import '../data/official_tariffs.dart';
import '../theme/app_colors.dart';
import '../utils/error_messages.dart';

class TaxationNomenclatureScreen extends StatefulWidget {
  const TaxationNomenclatureScreen({super.key});

  @override
  State<TaxationNomenclatureScreen> createState() =>
      _TaxationNomenclatureScreenState();
}

class _TaxationNomenclatureScreenState
    extends State<TaxationNomenclatureScreen> {
  List<OfficialTariff> _tariffs = [];
  bool _loading = true;
  String? _error;
  String _receiptType = 'Tous';

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
      final tariffs = await OfficialTariffCatalog.load();
      if (!mounted) return;
      setState(() {
        _tariffs = tariffs;
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

  List<OfficialTariff> get _visibleTariffs {
    if (_receiptType == 'Tous') return _tariffs;
    return _tariffs
        .where((tariff) => tariff.receiptType == _receiptType)
        .toList(growable: false);
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
    return Card(
      elevation: 0,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Type')),
            DataColumn(label: Text('Article')),
            DataColumn(label: Text('Tarif')),
            DataColumn(label: Text('Source')),
          ],
          rows: [
            for (final tariff in _visibleTariffs)
              DataRow(
                cells: [
                  DataCell(Text(tariff.receiptType)),
                  DataCell(
                    SizedBox(
                      width: 280,
                      child: Text(
                        tariff.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(Text(tariff.amountHelper)),
                  DataCell(
                    SizedBox(
                      width: 220,
                      child: Text(
                        tariff.source,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
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
              Icon(Icons.library_books_outlined, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Nomenclature',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              DropdownButton<String>(
                value: _receiptType,
                items: [
                  const DropdownMenuItem(value: 'Tous', child: Text('Tous')),
                  for (final type in RevenueReceiptType.values)
                    DropdownMenuItem(value: type, child: Text(type)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _receiptType = value);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_visibleTariffs.length} article(s) tarifaire(s)',
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
