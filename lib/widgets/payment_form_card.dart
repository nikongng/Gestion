import 'package:flutter/material.dart';

import '../models/app_role.dart';
import '../models/user_profile.dart';
import '../services/gestia_data_service.dart';
import 'two_fields_layout.dart';

const _taxTypes = <String>[
  'Taxes marchés',
  'Permis & licences',
  'Stationnement',
  'Autres',
];

class PaymentFormCard extends StatefulWidget {
  const PaymentFormCard({super.key, required this.profile, this.onSaved});

  final UserProfile profile;
  final VoidCallback? onSaved;

  @override
  State<PaymentFormCard> createState() => _PaymentFormCardState();
}

class _PaymentFormCardState extends State<PaymentFormCard> {
  final _amountCtrl = TextEditingController();
  List<({String id, String name})> _communes = [];
  String? _communeId;
  String _tax = _taxTypes.first;
  String _channel = 'Caisse';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCommunes();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCommunes() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var list = await GestiaDataService.fetchCommunes();
      if (widget.profile.role != AppRole.adminProvincial) {
        final cid = widget.profile.communeId;
        if (cid != null) {
          list = list.where((c) => c.id == cid).toList();
        }
      }
      if (!mounted) return;
      setState(() {
        _communes = list;
        _communeId = list.isNotEmpty ? list.first.id : null;
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

  Future<void> _submit() async {
    final raw = _amountCtrl.text.trim().replaceAll(',', '.');
    final amount = double.tryParse(raw);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Montant invalide.')),
      );
      return;
    }
    if (_communeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune commune disponible.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await GestiaDataService.insertCollection(
        communeId: _communeId!,
        amountUsd: amount,
        taxCategory: _tax,
        paymentChannel: _channel,
      );
      if (!mounted) return;
      _amountCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recette enregistrée.')),
      );
      widget.onSaved?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        elevation: 0,
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_error != null) {
      return Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_error!),
        ),
      );
    }

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nouveau paiement',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TwoFieldsLayout(
              firstLabel: 'Commune',
              secondLabel: 'Type de taxe',
              firstChild: DropdownButtonFormField<String>(
                initialValue: _communeId,
                items: [
                  for (final c in _communes)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: widget.profile.role == AppRole.adminProvincial
                    ? (v) => setState(() => _communeId = v)
                    : null,
                decoration: const InputDecoration(),
              ),
              secondChild: DropdownButtonFormField<String>(
                initialValue: _tax,
                items: [
                  for (final t in _taxTypes)
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _tax = v);
                },
                decoration: const InputDecoration(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Montant (USD)',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Canal',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final ch in ['Mobile Money', 'Banque', 'Caisse'])
                  FilterChip(
                    label: Text(ch),
                    selected: _channel == ch,
                    onSelected: (_) => setState(() => _channel = ch),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Enregistrement…' : 'Enregistrer la recette'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
