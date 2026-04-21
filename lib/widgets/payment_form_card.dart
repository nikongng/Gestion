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
  final _taxpayerIdCtrl = TextEditingController();

  List<({String id, String name})> _communes = [];
  String? _communeId;
  String _tax = _taxTypes.first;
  String _channel = 'Caisse';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _isContribuable => widget.profile.role == AppRole.contribuable;
  bool get _canChooseCommune =>
      widget.profile.role.canManageApp || _isContribuable;
  bool get _showTaxpayerIdentifierField =>
      !_isContribuable && widget.profile.role.canSubmitCollections;

  @override
  void initState() {
    super.initState();
    _loadCommunes();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _taxpayerIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCommunes() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var list = await GestiaDataService.fetchCommunes();
      if (!widget.profile.role.isGlobalSupervisor) {
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
    if (!widget.profile.role.canSubmitCollections) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ce profil est en lecture seule.')),
      );
      return;
    }

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
      var taxpayerProfileId = _isContribuable ? widget.profile.id : null;
      var taxpayerIdentifier =
          _isContribuable ? widget.profile.taxpayerIdentifier : null;
      UserProfile? taxpayerProfile;

      if (!_isContribuable) {
        final typedIdentifier = _taxpayerIdCtrl.text.trim();
        if (typedIdentifier.isNotEmpty) {
          taxpayerProfile =
              await GestiaDataService.fetchProfileByTaxpayerIdentifier(
                typedIdentifier,
              );
          taxpayerProfileId = taxpayerProfile?.id;
          taxpayerIdentifier = typedIdentifier;
        }
      }

      await GestiaDataService.insertCollection(
        communeId: _communeId!,
        amountUsd: amount,
        taxCategory: _tax,
        paymentChannel: _channel,
        taxpayerProfileId: taxpayerProfileId,
        taxpayerIdentifier: taxpayerIdentifier,
      );

      if (!mounted) return;
      _amountCtrl.clear();
      _taxpayerIdCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isContribuable
                ? 'Paiement enregistre avec votre ID personnel.'
                : taxpayerIdentifier != null && taxpayerIdentifier.isNotEmpty
                    ? taxpayerProfile != null
                        ? 'Recette enregistree pour ${taxpayerProfile.fullName}.'
                        : 'Recette enregistree avec l identifiant saisi.'
                    : 'Recette enregistree.',
          ),
        ),
      );
      widget.onSaved?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
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
            if (!widget.profile.role.canSubmitCollections) ...[
              Text(
                'Lecture seule',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Seuls l admin provincial, l agent et le contribuable peuvent enregistrer un paiement.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
            ],
            if (_isContribuable &&
                widget.profile.taxpayerIdentifier != null &&
                widget.profile.taxpayerIdentifier!.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context).colorScheme.primary.withValues(
                        alpha: 0.08,
                      ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ID contribuable',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      widget.profile.taxpayerIdentifier!,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              _isContribuable ? 'Payer mes taxes' : 'Nouveau paiement',
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
                onChanged: _canChooseCommune
                    ? (value) => setState(() => _communeId = value)
                    : null,
                decoration: const InputDecoration(),
              ),
              secondChild: DropdownButtonFormField<String>(
                initialValue: _tax,
                items: [
                  for (final type in _taxTypes)
                    DropdownMenuItem(value: type, child: Text(type)),
                ],
                onChanged: widget.profile.role.canSubmitCollections
                    ? (value) {
                        if (value != null) {
                          setState(() => _tax = value);
                        }
                      }
                    : null,
                decoration: const InputDecoration(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              readOnly: !widget.profile.role.canSubmitCollections,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Montant (USD)',
              ),
            ),
            if (_showTaxpayerIdentifierField) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _taxpayerIdCtrl,
                readOnly: !widget.profile.role.canSubmitCollections,
                decoration: const InputDecoration(
                  labelText: 'Identifiant contribuable',
                  hintText: 'Ex: CTB-0001',
                  helperText:
                      'Ajoutez l identifiant pour faciliter le controle de recouvrement.',
                ),
              ),
            ],
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
                for (final channel in ['Mobile Money', 'Banque', 'Caisse'])
                  FilterChip(
                    label: Text(channel),
                    selected: _channel == channel,
                    onSelected: widget.profile.role.canSubmitCollections
                        ? (_) => setState(() => _channel = channel)
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving || !widget.profile.role.canSubmitCollections
                    ? null
                    : _submit,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(
                  _saving
                      ? 'Enregistrement...'
                      : _isContribuable
                          ? 'Payer maintenant'
                          : 'Enregistrer la recette',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
