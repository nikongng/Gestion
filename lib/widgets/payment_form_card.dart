import 'package:flutter/material.dart';

import '../models/app_role.dart';
import '../models/user_profile.dart';
import '../services/gestia_data_service.dart';
import 'two_fields_layout.dart';

const kLegacyTaxTypes = <String>[
  'Taxes marchés',
  'Taxe mairie',
  'Taxe commune',
  'Taxe province',
  'Permis & licences',
  'Stationnement',
  'Autre',
];

const _paymentTaxTypes = <String>['Impôt', 'Taxe', 'Redevance'];

const _incomeTaxTypes = <String>[
  'Impôt sur revenu (IPR / IRPP)',
  'Impôt sur sociétés (IS / IBP)',
  'Impôt foncier',
  'Impôt sur véhicules (vignette)',
  'Impôt mobilier',
];

const _taxReceiptTypes = <String>[
  'Taxe sur occupation du domaine public',
  'Taxe sur la superficie des proprietes',
  'Taxe d urbanisme',
  'Taxe sur les mutations foncieres',
  'Taxe sur les constructions et permis',
  'Taxe sur les enseignes et affichages',
  'Taxe sur l exploitation miniere artisanale',
  'Taxe sur le transport des minerais',
  'Taxe sur la transformation des minerais',
  'Taxe sur la vente des matieres precieuses',
  'Taxe sur la detention et vente de diamants',
  'Taxe sur l extraction des materiaux de construction',
  'Taxe sur les dragues et motopompes',
  'Taxe d agrement des sites miniers artisanaux',
  'Taxe de piste de feu (zones minieres)',
  'Taxe de vente des produits miniers artisanaux',
  'Taxe de voirie sur produits miniers',
  'Taxe d incitation a la transformation locale',
  'Taxe sur autorisation de minage temporaire',
  'Taxe sur enregistrement des exploitants artisanaux',
  'Taxe de patente (commerce et activite)',
  'Taxe de marche',
  'Taxe d etalage',
  'Taxe sur licences commerciales',
  'Taxe sur publicite commerciale',
  'Taxe sur activites economiques informelles',
  'Taxe de circulation routiere (provinciale)',
  'Taxe de stationnement',
  'Taxe sur transport de marchandises',
  'Taxe sur transport de minerais',
  'Taxe sur exploitation de taxi/moto',
  'Taxe sur immatriculation locale',
  'Taxe de pollution',
  'Taxe environnementale industrielle',
  'Taxe de gestion des dechets',
  'Taxe de rehabilitation des sites exploites',
  'Taxe de protection ecologique',
  'Taxe sur betail',
  'Taxe sur exploitation agricole',
  'Taxe de marche agricole',
  'Taxe sur produits agricoles',
  'Permis de chasse et peche (souvent redevance mais classe taxe locale)',
  'Taxe d agrement sanitaire',
  'Taxe sur etablissements de sante prives',
  'Taxe d hygiene',
  'Taxe de controle sanitaire',
  'Taxe d exploitation de structures medicales',
  'Taxe de legalisation de documents',
  'Taxe de certification',
  'Taxe de delivrance d attestation',
];

const _redevanceReceiptTypes = <String>[
  'Redevance miniere (industrie extractive - cuivre, cobalt, etc.)',
  'Redevance d exploitation artisanale des minerais',
  'Redevance sur achat de produits miniers artisanaux',
  'Redevance de transformation des minerais',
  'Redevance de transport ou transfert des minerais',
  'Redevance sur les centres de negoce minier',
  'Redevance d agrement des exploitants miniers',
  'Redevance d exploitation de carrieres (sable, gravier, pierres)',
  'Redevance d utilisation de sites miniers',
  'Redevance sur exportation miniere (selon mecanismes administratifs)',
  'Redevance d occupation du domaine public',
  'Redevance de superficie fonciere',
  'Redevance d utilisation des terrains publics',
  'Redevance d autorisation de construction',
  'Redevance de mutation fonciere (actes administratifs lies au terrain)',
  'Redevance de voirie (utilisation routes/axes publics commerciaux)',
  'Redevance d eclairage public (dans certaines communes)',
  'Redevance d amenagement urbain',
  'Redevance d assainissement / gestion des dechets',
  'Redevance d utilisation des infrastructures publiques',
  'Redevance de stationnement public',
  'Redevance de transport de marchandises',
  'Redevance de transport de minerais',
  'Redevance d exploitation de transport public (taxi, bus, moto selon cadre)',
  'Redevance d immatriculation ou autorisation de transport',
  'Redevance de delivrance de documents administratifs',
  'Redevance de legalisation de documents',
  'Redevance de certification officielle',
  'Redevance de chancellerie',
  'Redevance de delivrance d attestations diverses',
  'Redevance de permis et autorisations administratives',
  'Redevance environnementale',
  'Redevance de gestion des dechets',
  'Redevance de protection de l ecosysteme',
  'Redevance de rehabilitation des sites exploites',
  'Redevance de controle environnemental',
  'Redevance d agrement sanitaire',
  'Redevance d inspection hygienique',
  'Redevance d exploitation d etablissement medical prive',
  'Redevance de controle sanitaire',
  'Redevance d autorisation d ouverture de structures de sante',
  'Redevance de permis de peche',
  'Redevance de permis de chasse',
  'Redevance d exploitation agricole',
  'Redevance sur marches agricoles',
  'Redevance d exploitation forestiere',
];

enum _RevenueCoverage { mairie, commune }

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
  _RevenueCoverage _coverage = _RevenueCoverage.mairie;
  String _receiptType = _paymentTaxTypes.first;
  String _tax = _incomeTaxTypes.first;
  String _channel = 'Caisse';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _isContribuable => widget.profile.role == AppRole.contribuable;
  bool get _canChooseCommune =>
      widget.profile.role.canManageApp || _isContribuable;
  bool get _showTaxpayerIdentifierField =>
      !_isContribuable && widget.profile.role.canSubmitCollections;
  bool get _canViewMairieCoverage => widget.profile.role.isGlobalSupervisor;

  String get _coverageLabel =>
      _coverage == _RevenueCoverage.mairie ? 'Mairie' : 'Commune';

  String get _coverageDbValue =>
      _coverage == _RevenueCoverage.mairie ? 'mairie' : 'commune';

  String get _storedTaxCategory {
    final value = _tax.trim();
    if (value.isEmpty) return _coverageLabel;
    final lower = value.toLowerCase();
    if (lower.startsWith('mairie - ') || lower.startsWith('commune - ')) {
      return value;
    }
    return '$_coverageLabel - $value';
  }

  @override
  void initState() {
    super.initState();
    if (!_canViewMairieCoverage) {
      _coverage = _RevenueCoverage.commune;
    }
    _loadCommunes();
  }

  @override
  void didUpdateWidget(covariant PaymentFormCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.role != widget.profile.role &&
        !_canViewMairieCoverage) {
      _coverage = _RevenueCoverage.commune;
    }
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Montant invalide.')));
      return;
    }

    final effectiveCommuneId = _communeId ?? widget.profile.communeId;

    if (effectiveCommuneId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune commune disponible.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      var taxpayerProfileId = _isContribuable ? widget.profile.id : null;
      var taxpayerIdentifier = _isContribuable
          ? widget.profile.taxpayerIdentifier
          : null;
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
        communeId: effectiveCommuneId,
        amountUsd: amount,
        taxCategory: _storedTaxCategory,
        paymentChannel: _channel,
        collectionScope: _coverageDbValue,
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _buildIncomeTaxDropdownField() {
    return DropdownButtonFormField<String>(
      initialValue: _tax,
      items: [
        for (final type in _incomeTaxTypes)
          DropdownMenuItem(
            value: type,
            child: Text(type, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: widget.profile.role.canSubmitCollections
          ? (value) {
              if (value != null) {
                setState(() => _tax = value);
              }
            }
          : null,
      decoration: const InputDecoration(labelText: 'Impôt'),
    );
  }

  Widget _buildTaxDropdownField() {
    return DropdownButtonFormField<String>(
      initialValue: _tax,
      items: [
        for (final type in _taxReceiptTypes)
          DropdownMenuItem(
            value: type,
            child: Text(type, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: widget.profile.role.canSubmitCollections
          ? (value) {
              if (value != null) {
                setState(() => _tax = value);
              }
            }
          : null,
      decoration: const InputDecoration(labelText: 'Taxe'),
    );
  }

  Widget _buildRedevanceDropdownField() {
    return DropdownButtonFormField<String>(
      initialValue: _tax,
      items: [
        for (final type in _redevanceReceiptTypes)
          DropdownMenuItem(
            value: type,
            child: Text(type, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: widget.profile.role.canSubmitCollections
          ? (value) {
              if (value != null) {
                setState(() => _tax = value);
              }
            }
          : null,
      decoration: const InputDecoration(labelText: 'Redevance'),
    );
  }

  Widget buildIncomeTaxField() {
    final canEdit = widget.profile.role.canSubmitCollections;

    return Autocomplete<String>(
      initialValue: TextEditingValue(text: _tax),
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.trim().toLowerCase();
        if (query.isEmpty) return _incomeTaxTypes;

        return _incomeTaxTypes.where(
          (type) => type.toLowerCase().startsWith(query),
        );
      },
      onSelected: (value) => setState(() => _tax = value),
      fieldViewBuilder:
          (context, textEditingController, focusNode, onFieldSubmitted) {
            return TextField(
              controller: textEditingController,
              focusNode: focusNode,
              readOnly: !canEdit,
              onChanged: canEdit
                  ? (value) => setState(() => _tax = value)
                  : null,
              decoration: const InputDecoration(
                labelText: 'Impôt',
                hintText: 'Tapez pour rechercher',
              ),
            );
          },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220, maxWidth: 520),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(option, overflow: TextOverflow.ellipsis),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCoverageSelector() {
    final canEdit = widget.profile.role.canSubmitCollections;

    return SegmentedButton<_RevenueCoverage>(
      segments: const [
        ButtonSegment<_RevenueCoverage>(
          value: _RevenueCoverage.mairie,
          icon: Icon(Icons.account_balance_outlined),
          label: Text('Mairie'),
        ),
        ButtonSegment<_RevenueCoverage>(
          value: _RevenueCoverage.commune,
          icon: Icon(Icons.location_city_outlined),
          label: Text('Commune'),
        ),
      ],
      selected: {_coverage},
      onSelectionChanged: canEdit
          ? (values) {
              final next = values.first;
              setState(() {
                _coverage = next;
                if (next == _RevenueCoverage.commune && _communeId == null) {
                  _communeId = _communes.isNotEmpty ? _communes.first.id : null;
                }
              });
            }
          : null,
    );
  }

  Widget _buildCommuneDropdownField() {
    return DropdownButtonFormField<String>(
      initialValue: _communeId,
      items: [
        for (final c in _communes)
          DropdownMenuItem(value: c.id, child: Text(c.name)),
      ],
      onChanged: _canChooseCommune
          ? (value) => setState(() => _communeId = value)
          : null,
      decoration: const InputDecoration(),
    );
  }

  void _updateReceiptType(String? value) {
    if (value == null) return;
    setState(() {
      _receiptType = value;
      if (value == _paymentTaxTypes.first) {
        _tax = _incomeTaxTypes.first;
      } else if (value == _paymentTaxTypes[1]) {
        _tax = _taxReceiptTypes.first;
      } else if (value == _paymentTaxTypes[2]) {
        _tax = _redevanceReceiptTypes.first;
      } else {
        _tax = value;
      }
    });
  }

  Widget _buildReceiptTypeDropdownField() {
    return DropdownButtonFormField<String>(
      initialValue: _receiptType,
      items: [
        for (final type in _paymentTaxTypes)
          DropdownMenuItem(value: type, child: Text(type)),
      ],
      onChanged: widget.profile.role.canSubmitCollections
          ? (value) => _updateReceiptType(value)
          : null,
      decoration: const InputDecoration(),
    );
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
        child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
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
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.08),
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
            if (_canViewMairieCoverage) ...[
              Text('Couverture', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              _buildCoverageSelector(),
              const SizedBox(height: 12),
            ],
            if (_coverage == _RevenueCoverage.commune)
              TwoFieldsLayout(
                firstLabel: 'Commune',
                secondLabel: 'Type de recette',
                firstChild: _buildCommuneDropdownField(),
                secondChild: _buildReceiptTypeDropdownField(),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _receiptType,
                items: [
                  for (final type in _paymentTaxTypes)
                    DropdownMenuItem(value: type, child: Text(type)),
                ],
                onChanged: widget.profile.role.canSubmitCollections
                    ? (value) => _updateReceiptType(value)
                    : null,
                decoration: const InputDecoration(labelText: 'Type de recette'),
              ),
            if (_receiptType == _paymentTaxTypes.first) ...[
              const SizedBox(height: 12),
              _buildIncomeTaxDropdownField(),
            ],
            if (_receiptType == _paymentTaxTypes[1]) ...[
              const SizedBox(height: 12),
              _buildTaxDropdownField(),
            ],
            if (_receiptType == _paymentTaxTypes[2]) ...[
              const SizedBox(height: 12),
              _buildRedevanceDropdownField(),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              readOnly: !widget.profile.role.canSubmitCollections,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Montant (USD)'),
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
            Text('Canal', style: Theme.of(context).textTheme.labelLarge),
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
