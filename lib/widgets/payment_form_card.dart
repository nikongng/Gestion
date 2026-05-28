import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../branding/branding_scope.dart';
import '../data/official_tariffs.dart';
import '../models/app_role.dart';
import '../models/user_profile.dart';
import '../services/gestia_data_service.dart';
import '../utils/cpi_exporter.dart';
import '../utils/error_messages.dart';
import 'two_fields_layout.dart';

const _paymentTaxTypes = RevenueReceiptType.values;
const _cpiPrintPreferenceKey = 'payment_form_card.print_cpi_after_save';

enum _RevenueCoverage { mairie, commune }

class _CpiPrintDecision {
  const _CpiPrintDecision({required this.printCpi, required this.remember});

  final bool printCpi;
  final bool remember;
}

class PaymentFormCard extends StatefulWidget {
  const PaymentFormCard({super.key, required this.profile, this.onSaved});

  final UserProfile profile;
  final VoidCallback? onSaved;

  @override
  State<PaymentFormCard> createState() => _PaymentFormCardState();
}

class _PaymentFormCardState extends State<PaymentFormCard> {
  final _amountCtrl = TextEditingController();
  final _perceptionNoteNumberCtrl = TextEditingController();
  final _taxpayerIdCtrl = TextEditingController();
  final _legalTaxpayerNameCtrl = TextEditingController();
  final _legalPhoneCtrl = TextEditingController();
  final _legalAddressCtrl = TextEditingController();
  final _legalDenominationCtrl = TextEditingController();
  final _legalNifCtrl = TextEditingController();

  List<({String id, String name})> _communes = [];
  List<OfficialTariff> _tariffs = [];
  List<String> _receiptTypes = _paymentTaxTypes;
  String? _communeId;
  String? _tariffId;
  _RevenueCoverage _coverage = _RevenueCoverage.mairie;
  String _receiptType = _paymentTaxTypes.first;
  String _channel = 'Caisse';
  bool _isLegalEntity = false;
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

  String get _effectiveReceiptType => _normalizeReceiptType(_receiptType);

  List<OfficialTariff> get _currentTariffs => _tariffs
      .where((tariff) => tariff.receiptType == _effectiveReceiptType)
      .toList(growable: false);

  OfficialTariff? get _selectedTariff {
    final id = _tariffId;
    if (id == null) return null;
    for (final tariff in _tariffs) {
      if (tariff.id == id) return tariff;
    }
    return null;
  }

  String get _storedTaxCategory {
    final value = (_selectedTariff?.label ?? _effectiveReceiptType).trim();
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
    _loadFormData();
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
    _perceptionNoteNumberCtrl.dispose();
    _taxpayerIdCtrl.dispose();
    _legalTaxpayerNameCtrl.dispose();
    _legalPhoneCtrl.dispose();
    _legalAddressCtrl.dispose();
    _legalDenominationCtrl.dispose();
    _legalNifCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFormData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final communesFuture = GestiaDataService.fetchCommunes();
      final tariffsFuture = OfficialTariffCatalog.load();
      final receiptTypesFuture = GestiaDataService.fetchCustomReceiptTypes();
      var list = await communesFuture;
      final tariffs = await tariffsFuture;
      final receiptTypes = _mergeReceiptTypes(await receiptTypesFuture);
      if (!widget.profile.role.isGlobalSupervisor) {
        final cid = widget.profile.communeId;
        if (cid != null) {
          list = list.where((c) => c.id == cid).toList();
        }
      }
      if (!mounted) return;
      setState(() {
        _communes = list;
        _tariffs = tariffs;
        _receiptTypes = receiptTypes;
        _communeId = list.isNotEmpty ? list.first.id : null;
        _receiptType = _effectiveReceiptType;
        _tariffId = _firstTariffIdFor(_effectiveReceiptType, tariffs);
        _prefillAmountFromSelectedTariff();
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

  String? _firstTariffIdFor(String receiptType, List<OfficialTariff> tariffs) {
    for (final tariff in tariffs) {
      if (tariff.receiptType == receiptType) return tariff.id;
    }
    return null;
  }

  void _prefillAmountFromSelectedTariff() {
    final amount = _selectedTariff?.amountUsd;
    if (amount != null) {
      _amountCtrl.text = formatUsdAmount(amount);
    }
  }

  List<String> _mergeReceiptTypes(List<String> customTypes) {
    final seen = <String>{};
    final result = <String>[];
    for (final type in [..._paymentTaxTypes, ...customTypes]) {
      final trimmed = type.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed.toLowerCase())) result.add(trimmed);
    }
    return result;
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

    final effectiveCommuneId = _coverage == _RevenueCoverage.mairie
        ? null
        : _communeId ?? widget.profile.communeId;

    if (_coverage == _RevenueCoverage.commune && effectiveCommuneId == null) {
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

      if (!_isContribuable && _isLegalEntity) {
        final typedNif = _legalNifCtrl.text.trim();
        taxpayerIdentifier = typedNif.isEmpty ? null : typedNif;
      } else if (!_isContribuable) {
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

      final paidAt = DateTime.now();
      final cpiNumber = _generateCpiNumber(paidAt);
      final perceptionNoteNumber = _perceptionNoteNumberCtrl.text.trim();
      final controlIdentifier = _controlIdentifierFor(
        taxpayerIdentifier: taxpayerIdentifier,
        perceptionNoteNumber: perceptionNoteNumber,
        cpiNumber: cpiNumber,
      );
      final cpiData = _buildCpiData(
        amount: amount,
        effectiveCommuneId: effectiveCommuneId,
        paidAt: paidAt,
        cpiNumber: cpiNumber,
        taxpayerProfile: taxpayerProfile,
        taxpayerIdentifier: taxpayerIdentifier,
        verificationIdentifier: controlIdentifier,
      );

      await GestiaDataService.insertCollection(
        communeId: effectiveCommuneId,
        amountUsd: amount,
        taxCategory: _storedTaxCategory,
        paymentChannel: _channel,
        collectionScope: _coverageDbValue,
        taxpayerProfileId: taxpayerProfileId,
        taxpayerIdentifier: controlIdentifier,
        perceptionNoteNumber: perceptionNoteNumber,
        cpiNumber: cpiNumber,
        revenuePhase: 'apurement',
        workflowStatus: 'apuree_cpi_genere',
        paidAt: paidAt,
        apuredAt: paidAt,
        isAutoLiquidated: perceptionNoteNumber.isEmpty,
      );
      await GestiaDataService.markPerceptionNoteApured(
        noteNumber: perceptionNoteNumber,
        cpiNumber: cpiNumber,
        paidAt: paidAt,
      );

      if (!mounted) return;
      final cpiGenerated = await _maybeExportCpi(cpiData);
      if (!mounted) return;
      _amountCtrl.clear();
      _perceptionNoteNumberCtrl.clear();
      _taxpayerIdCtrl.clear();
      _clearLegalEntityFields();
      setState(() => _isLegalEntity = false);
      final successMessage = _isContribuable
          ? 'Paiement enregistre avec votre ID personnel.'
          : taxpayerIdentifier != null && taxpayerIdentifier.isNotEmpty
          ? taxpayerProfile != null
                ? 'Recette enregistree pour ${taxpayerProfile.fullName}.'
                : 'Recette enregistree avec l identifiant saisi.'
          : 'Recette enregistree.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cpiGenerated ? '$successMessage CPI genere.' : successMessage,
          ),
        ),
      );
      widget.onSaved?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(e))));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  CpiData _buildCpiData({
    required double amount,
    required String? effectiveCommuneId,
    required DateTime paidAt,
    required String cpiNumber,
    required UserProfile? taxpayerProfile,
    required String? taxpayerIdentifier,
    required String verificationIdentifier,
  }) {
    final branding = BrandingScope.of(context);
    final profileTaxpayerName = _isContribuable
        ? widget.profile.fullName
        : taxpayerProfile?.fullName ??
              (taxpayerIdentifier?.trim().isNotEmpty == true
                  ? 'ID ${taxpayerIdentifier!.trim()}'
                  : 'Contribuable non renseigne');
    final legalTaxpayerName = _legalTaxpayerNameCtrl.text.trim();
    final legalDenomination = _legalDenominationCtrl.text.trim();
    final taxpayerName = _isLegalEntity
        ? _firstNotEmpty([
            legalTaxpayerName,
            legalDenomination,
            profileTaxpayerName,
          ])
        : profileTaxpayerName;
    final taxpayerDenomination = _isLegalEntity
        ? _firstNotEmpty([legalDenomination, legalTaxpayerName, taxpayerName])
        : taxpayerName;
    final taxpayerId = _isLegalEntity
        ? _legalNifCtrl.text.trim()
        : taxpayerIdentifier ?? '';
    final communeName = _communeNameFor(effectiveCommuneId);
    final tariff = _selectedTariff;
    final actLabel = tariff?.label.trim().isNotEmpty == true
        ? tariff!.label.trim()
        : _storedTaxCategory;

    return CpiData(
      provinceName: branding.provinceName,
      cpiNumber: cpiNumber,
      generatedAt: paidAt,
      perceptionNoteNumber: _perceptionNoteNumberCtrl.text.trim(),
      taxpayerName: taxpayerName,
      taxpayerDenomination: taxpayerDenomination,
      taxpayerIdentifier: taxpayerId,
      verificationIdentifier: verificationIdentifier,
      taxpayerPhone: _isLegalEntity ? _legalPhoneCtrl.text.trim() : '',
      taxpayerEmail: '',
      taxpayerAddress: _isLegalEntity
          ? _legalAddressCtrl.text.trim()
          : communeName.isEmpty
          ? ''
          : 'Commune de $communeName',
      communeName: communeName,
      natureActe: actLabel,
      exercise: paidAt.year,
      actName: actLabel,
      periodicity: _periodicityFrom(tariff?.details ?? ''),
      actCount: 1,
      rateUsd: amount,
      amountUsd: amount,
      paymentMode: _channel,
      agency: _agencyFromChannel(_channel),
      agentName: widget.profile.fullName,
    );
  }

  Future<bool> _maybeExportCpi(CpiData data) async {
    final shouldPrint = await _resolveCpiPrintChoice();
    if (!mounted || !shouldPrint) return false;

    try {
      final path = await CpiExporter.exportPdf(data);
      return mounted && path != null;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Recette enregistree, mais le CPI n a pas pu etre genere: '
            '${userFacingErrorMessage(e)}',
          ),
        ),
      );
      return false;
    }
  }

  void _clearLegalEntityFields() {
    _legalTaxpayerNameCtrl.clear();
    _legalPhoneCtrl.clear();
    _legalAddressCtrl.clear();
    _legalDenominationCtrl.clear();
    _legalNifCtrl.clear();
  }

  String _firstNotEmpty(List<String> values) {
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  String _controlIdentifierFor({
    required String? taxpayerIdentifier,
    required String perceptionNoteNumber,
    required String cpiNumber,
  }) {
    return _firstNotEmpty([
      taxpayerIdentifier ?? '',
      perceptionNoteNumber,
      cpiNumber,
    ]);
  }

  Future<bool> _resolveCpiPrintChoice() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_cpiPrintPreferenceKey)) {
      return prefs.getBool(_cpiPrintPreferenceKey) ?? false;
    }

    if (!mounted) return false;
    final decision = await showDialog<_CpiPrintDecision>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        var remember = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Imprimer le CPI ?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'La recette est enregistree. Voulez-vous generer le '
                    'Certificat de Paiement Informatise maintenant ?',
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Memoriser mon choix'),
                    value: remember,
                    onChanged: (value) {
                      setDialogState(() => remember = value ?? false);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(
                      _CpiPrintDecision(printCpi: false, remember: remember),
                    );
                  },
                  child: const Text('Non'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(
                      _CpiPrintDecision(printCpi: true, remember: remember),
                    );
                  },
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Imprimer'),
                ),
              ],
            );
          },
        );
      },
    );

    if (decision == null) return false;
    if (decision.remember) {
      await prefs.setBool(_cpiPrintPreferenceKey, decision.printCpi);
    }
    return decision.printCpi;
  }

  String _communeNameFor(String? communeId) {
    if (communeId == null) return '';
    for (final commune in _communes) {
      if (commune.id == communeId) return commune.name;
    }
    return widget.profile.communeName ?? '';
  }

  String _generateCpiNumber(DateTime date) {
    final local = date.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}${two(local.month)}${local.year}'
        '${two(local.hour)}${two(local.minute)}${two(local.second)}'
        '${local.millisecond.toString().padLeft(3, '0')}';
  }

  String _periodicityFrom(String details) {
    final marker = RegExp(
      r'Periodicite:\s*([^-\n]+)',
      caseSensitive: false,
    ).firstMatch(details);
    return marker?.group(1)?.trim().toUpperCase() ?? 'PONCTUELLE';
  }

  String _agencyFromChannel(String channel) {
    final normalized = channel.trim();
    if (normalized.isEmpty) return 'GESTIA';
    if (normalized.toLowerCase() == 'caisse') return 'GESTIA';
    return normalized.toUpperCase();
  }

  void _selectTariff(String? value) {
    if (value == null) return;
    OfficialTariff? selected;
    for (final tariff in _tariffs) {
      if (tariff.id == value) {
        selected = tariff;
        break;
      }
    }
    setState(() => _tariffId = value);
    final amount = selected?.amountUsd;
    if (amount != null) {
      _amountCtrl.text = formatUsdAmount(amount);
    }
  }

  Widget _buildTariffDropdownField() {
    final items = _currentTariffs;
    if (items.isEmpty) {
      return const Text('Aucun tarif officiel disponible pour ce type.');
    }

    final selectedId = items.any((tariff) => tariff.id == _tariffId)
        ? _tariffId
        : null;

    return DropdownButtonFormField<String>(
      key: ValueKey('tariff-$_effectiveReceiptType-$selectedId'),
      initialValue: selectedId,
      isExpanded: true,
      items: [
        for (final tariff in items)
          DropdownMenuItem(
            value: tariff.id,
            child: Text(
              tariff.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: widget.profile.role.canSubmitCollections
          ? _selectTariff
          : null,
      decoration: const InputDecoration(labelText: 'Tarif officiel'),
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
                if (next == _RevenueCoverage.mairie) {
                  _communeId = null;
                } else {
                  _communeId ??= _communes.isNotEmpty
                      ? _communes.first.id
                      : null;
                }
              });
            }
          : null,
    );
  }

  Widget _buildCommuneDropdownField() {
    final selectedCommuneId =
        _communes.any((commune) => commune.id == _communeId)
        ? _communeId
        : null;

    return DropdownButtonFormField<String>(
      key: ValueKey('commune-$selectedCommuneId-${_communes.length}'),
      initialValue: selectedCommuneId,
      isExpanded: true,
      items: [
        for (final c in _communes)
          DropdownMenuItem(
            value: c.id,
            child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: _canChooseCommune
          ? (value) => setState(() => _communeId = value)
          : null,
      decoration: const InputDecoration(),
    );
  }

  void _updateReceiptType(String? value) {
    if (value == null) return;
    final normalizedValue = _normalizeReceiptType(value);
    setState(() {
      _receiptType = normalizedValue;
      _tariffId = _firstTariffIdFor(normalizedValue, _tariffs);
      _prefillAmountFromSelectedTariff();
      if (_selectedTariff?.amountUsd == null) {
        _amountCtrl.clear();
      }
    });
  }

  String _normalizeReceiptType(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return _paymentTaxTypes.first;
    for (final type in _receiptTypes) {
      if (type.toLowerCase() == trimmed.toLowerCase()) return type;
    }

    final lower = trimmed.toLowerCase();
    if (lower.contains('taxe')) return RevenueReceiptType.taxe;
    if (lower.contains('redevance')) return RevenueReceiptType.redevance;
    return RevenueReceiptType.impot;
  }

  Widget _buildReceiptTypeDropdownField({String? labelText}) {
    final selectedType = _effectiveReceiptType;

    return DropdownButtonFormField<String>(
      key: ValueKey('receipt-type-$selectedType'),
      initialValue: selectedType,
      isExpanded: true,
      items: [
        for (final type in _receiptTypes)
          DropdownMenuItem(
            value: type,
            child: Text(type, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: widget.profile.role.canSubmitCollections
          ? (value) => _updateReceiptType(value)
          : null,
      decoration: InputDecoration(labelText: labelText),
    );
  }

  Widget _buildLegalEntityFields() {
    return Column(
      children: [
        TwoFieldsLayout(
          firstLabel: "Nom de l'assujetti",
          secondLabel: 'Telephone',
          firstChild: TextField(
            controller: _legalTaxpayerNameCtrl,
            readOnly: !widget.profile.role.canSubmitCollections,
            decoration: const InputDecoration(labelText: "Nom de l'assujetti"),
          ),
          secondChild: TextField(
            controller: _legalPhoneCtrl,
            readOnly: !widget.profile.role.canSubmitCollections,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Telephone'),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _legalAddressCtrl,
          readOnly: !widget.profile.role.canSubmitCollections,
          decoration: const InputDecoration(labelText: 'Adresse'),
        ),
        const SizedBox(height: 12),
        TwoFieldsLayout(
          firstLabel: 'Denomination',
          secondLabel: 'NIF',
          firstChild: TextField(
            controller: _legalDenominationCtrl,
            readOnly: !widget.profile.role.canSubmitCollections,
            decoration: const InputDecoration(labelText: 'Denomination'),
          ),
          secondChild: TextField(
            controller: _legalNifCtrl,
            readOnly: !widget.profile.role.canSubmitCollections,
            decoration: const InputDecoration(labelText: 'NIF'),
          ),
        ),
      ],
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
              _buildReceiptTypeDropdownField(labelText: 'Type de recette'),
            const SizedBox(height: 12),
            _buildTariffDropdownField(),
            const SizedBox(height: 12),
            TextField(
              controller: _perceptionNoteNumberCtrl,
              readOnly: !widget.profile.role.canSubmitCollections,
              decoration: const InputDecoration(
                labelText: 'Numero de note de perception',
                hintText: 'Ex: 260525112505978-400',
                helperText: 'Optionnel, repris sur le CPI si renseigne.',
              ),
            ),
            const SizedBox(height: 12),
            if (!_isContribuable) ...[
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Personne morale'),
                value: _isLegalEntity,
                onChanged: widget.profile.role.canSubmitCollections
                    ? (value) {
                        setState(() => _isLegalEntity = value ?? false);
                      }
                    : null,
              ),
            ],
            if (!_isContribuable && _isLegalEntity) ...[
              const SizedBox(height: 12),
              _buildLegalEntityFields(),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              readOnly: !widget.profile.role.canSubmitCollections,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Montant (USD)',
                helperText: 'Montant a encaisser.',
              ),
            ),
            if (_showTaxpayerIdentifierField && !_isLegalEntity) ...[
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
