import 'package:flutter/material.dart';

import '../branding/branding_scope.dart';
import '../data/official_tariffs.dart';
import '../models/user_profile.dart';
import '../services/gestia_data_service.dart';
import '../utils/error_messages.dart';
import '../utils/perception_note_exporter.dart';
import '../widgets/two_fields_layout.dart';

const _noteReceiptTypes = RevenueReceiptType.values;

class PerceptionNoteScreen extends StatefulWidget {
  const PerceptionNoteScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<PerceptionNoteScreen> createState() => _PerceptionNoteScreenState();
}

class _PerceptionNoteScreenState extends State<PerceptionNoteScreen> {
  final _amountCtrl = TextEditingController();
  final _paymentDelayCtrl = TextEditingController(text: '8');
  final _taxpayerIdCtrl = TextEditingController();
  final _taxpayerNameCtrl = TextEditingController();
  final _taxpayerPhoneCtrl = TextEditingController();
  final _taxpayerEmailCtrl = TextEditingController();
  final _taxpayerAddressCtrl = TextEditingController();

  List<({String id, String name})> _communes = [];
  List<OfficialTariff> _tariffs = [];
  String? _communeId;
  String? _tariffId;
  String _receiptType = _noteReceiptTypes.first;
  String _channel = 'Banque';
  bool _loading = true;
  bool _exporting = false;
  String? _error;

  List<OfficialTariff> get _currentTariffs => _tariffs
      .where((tariff) => tariff.receiptType == _receiptType)
      .toList(growable: false);

  OfficialTariff? get _selectedTariff {
    final id = _tariffId;
    if (id == null) return null;
    for (final tariff in _tariffs) {
      if (tariff.id == id) return tariff;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _paymentDelayCtrl.dispose();
    _taxpayerIdCtrl.dispose();
    _taxpayerNameCtrl.dispose();
    _taxpayerPhoneCtrl.dispose();
    _taxpayerEmailCtrl.dispose();
    _taxpayerAddressCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final communesFuture = GestiaDataService.fetchCommunes();
      final tariffsFuture = OfficialTariffCatalog.load();
      var communes = await communesFuture;
      final tariffs = await tariffsFuture;
      if (!widget.profile.role.isGlobalSupervisor) {
        final cid = widget.profile.communeId;
        if (cid != null) {
          communes = communes.where((commune) => commune.id == cid).toList();
        }
      }
      if (!mounted) return;
      setState(() {
        _communes = communes;
        _tariffs = tariffs;
        _communeId = communes.isNotEmpty ? communes.first.id : null;
        _tariffId = _firstTariffIdFor(_receiptType, tariffs);
        _prefillAmount();
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

  void _prefillAmount() {
    final amount = _selectedTariff?.amountUsd;
    if (amount != null) {
      _amountCtrl.text = formatUsdAmount(amount);
    }
  }

  void _selectReceiptType(String? value) {
    if (value == null) return;
    setState(() {
      _receiptType = value;
      _tariffId = _firstTariffIdFor(value, _tariffs);
      _prefillAmount();
    });
  }

  void _selectTariff(String? value) {
    if (value == null) return;
    setState(() => _tariffId = value);
    _prefillAmount();
  }

  double? _readAmount() {
    final amount = double.tryParse(
      _amountCtrl.text.trim().replaceAll(',', '.'),
    );
    if (amount == null || amount <= 0) return null;
    return amount;
  }

  int? _readPaymentDelayDays() {
    final delay = int.tryParse(_paymentDelayCtrl.text.trim());
    if (delay == null || delay <= 0) return null;
    return delay;
  }

  String _paymentDelayLabel(int days) {
    return days == 1 ? '1 jour' : '$days jours';
  }

  String _communeName() {
    for (final commune in _communes) {
      if (commune.id == _communeId) return commune.name;
    }
    return widget.profile.communeName ?? 'Commune courante';
  }

  Future<UserProfile?> _lookupTaxpayerProfile() async {
    final identifier = _taxpayerIdCtrl.text.trim();
    if (identifier.isEmpty) return null;
    final profile = await GestiaDataService.fetchProfileByTaxpayerIdentifier(
      identifier,
    );
    if (profile != null && _taxpayerNameCtrl.text.trim().isEmpty) {
      _taxpayerNameCtrl.text = profile.fullName;
    }
    return profile;
  }

  Future<void> _exportNote() async {
    final amount = _readAmount();
    if (amount == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Montant invalide.')));
      return;
    }
    if (_communeId == null && widget.profile.communeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune commune disponible.')),
      );
      return;
    }
    final paymentDelayDays = _readPaymentDelayDays();
    if (paymentDelayDays == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delai de paiement invalide.')),
      );
      return;
    }

    setState(() => _exporting = true);
    try {
      final taxpayerProfile = await _lookupTaxpayerProfile();
      if (!mounted) return;
      final data = _buildNoteData(amount, taxpayerProfile, paymentDelayDays);
      final path = await PerceptionNoteExporter.exportPdf(data);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            path == null || path.isEmpty
                ? 'Export annule.'
                : 'Note de perception etablie. Fichier: $path',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  PerceptionNoteData _buildNoteData(
    double amount,
    UserProfile? profile,
    int paymentDelayDays,
  ) {
    final now = DateTime.now();
    final tariff = _selectedTariff;
    final branding = BrandingScope.of(context);
    final taxpayerName = _taxpayerNameCtrl.text.trim().isNotEmpty
        ? _taxpayerNameCtrl.text.trim()
        : profile?.fullName ?? '';

    return PerceptionNoteData(
      provinceName: branding.provinceName,
      noteNumber: _noteNumber(now),
      generatedAt: now,
      serviceAssiette: _serviceAssietteFor(tariff),
      articleBudgetaire: tariff?.label ?? _receiptType,
      acteJuridique: _receiptType,
      legalReference: 'Liste tarifaire officielle chargee dans GESTIA.',
      tariffDetails: tariff?.details ?? '',
      tariffLabel: tariff?.tariffLabel ?? '${formatUsdAmount(amount)} USD',
      amountUsd: amount,
      taxpayerName: taxpayerName,
      taxpayerIdentifier: _taxpayerIdCtrl.text.trim(),
      taxpayerPhone: _taxpayerPhoneCtrl.text.trim(),
      taxpayerEmail: _taxpayerEmailCtrl.text.trim(),
      taxpayerAddress: _taxpayerAddressCtrl.text.trim(),
      pointTaxation: 'GESTIA - ${_communeName()}',
      paymentChannel: _channel,
      taxateurName: widget.profile.fullName,
      ordonnateurName: widget.profile.fullName,
      paymentDelayLabel: _paymentDelayLabel(paymentDelayDays),
      paymentDeadline: now.add(Duration(days: paymentDelayDays)),
    );
  }

  String _noteNumber(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}${two(date.month)}${two(date.day)}'
        '${two(date.hour)}${two(date.minute)}${two(date.second)}'
        '-${widget.profile.id.hashCode.abs() % 10000}';
  }

  String _serviceAssietteFor(OfficialTariff? tariff) {
    final source = tariff?.source.toLowerCase() ?? '';
    if (source.contains('foncier')) return 'AFFAIRES FONCIERES';
    if (source.contains('veh') || source.contains('hicules')) {
      return 'TRANSPORTS ET VEHICULES';
    }
    if (source.contains('locatif')) return 'REVENUS LOCATIFS';
    if (source.contains('pompier') || source.contains('extincteur')) {
      return 'SAPEURS-POMPIERS';
    }
    return 'GESTIA RECETTES';
  }

  Widget _buildReceiptTypeDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _receiptType,
      isExpanded: true,
      items: [
        for (final type in _noteReceiptTypes)
          DropdownMenuItem(
            value: type,
            child: Text(type, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: _exporting ? null : _selectReceiptType,
      decoration: const InputDecoration(labelText: 'Type de recette'),
    );
  }

  Widget _buildTariffDropdown() {
    final items = _currentTariffs;
    final selectedId = items.any((tariff) => tariff.id == _tariffId)
        ? _tariffId
        : null;

    return DropdownButtonFormField<String>(
      key: ValueKey('note-tariff-$_receiptType-$selectedId'),
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
      onChanged: _exporting ? null : _selectTariff,
      decoration: const InputDecoration(labelText: 'Article budgetaire'),
    );
  }

  Widget _buildCommuneDropdown() {
    final selectedId = _communes.any((commune) => commune.id == _communeId)
        ? _communeId
        : null;
    return DropdownButtonFormField<String>(
      initialValue: selectedId,
      isExpanded: true,
      items: [
        for (final commune in _communes)
          DropdownMenuItem(
            value: commune.id,
            child: Text(
              commune.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: _exporting
          ? null
          : (value) => setState(() => _communeId = value),
      decoration: const InputDecoration(labelText: 'Point de taxation'),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!),
          ),
        ),
      );
    }

    final tariff = _selectedTariff;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Etablir une note de perception',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'La note de perception n est pas une preuve de paiement.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TwoFieldsLayout(
                    firstLabel: 'Commune',
                    secondLabel: 'Type',
                    firstChild: _buildCommuneDropdown(),
                    secondChild: _buildReceiptTypeDropdown(),
                  ),
                  const SizedBox(height: 12),
                  _buildTariffDropdown(),
                  if (tariff != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${tariff.amountHelper} - ${tariff.source}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 12),
                  TwoFieldsLayout(
                    firstLabel: 'Montant',
                    secondLabel: 'Delai de paiement',
                    firstChild: TextField(
                      controller: _amountCtrl,
                      enabled: !_exporting,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Montant USD',
                      ),
                    ),
                    secondChild: TextField(
                      controller: _paymentDelayCtrl,
                      enabled: !_exporting,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Delai de paiement (jours)',
                        hintText: 'Ex: 8',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Identite de l assujetti',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  TwoFieldsLayout(
                    firstLabel: 'Identifiant',
                    secondLabel: 'Nom',
                    firstChild: TextField(
                      controller: _taxpayerIdCtrl,
                      enabled: !_exporting,
                      decoration: const InputDecoration(
                        hintText: 'Ex: CTB-0001',
                      ),
                    ),
                    secondChild: TextField(
                      controller: _taxpayerNameCtrl,
                      enabled: !_exporting,
                      decoration: const InputDecoration(hintText: 'Nom'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TwoFieldsLayout(
                    firstLabel: 'Telephone',
                    secondLabel: 'E-mail',
                    firstChild: TextField(
                      controller: _taxpayerPhoneCtrl,
                      enabled: !_exporting,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(hintText: '+243 ...'),
                    ),
                    secondChild: TextField(
                      controller: _taxpayerEmailCtrl,
                      enabled: !_exporting,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        hintText: 'email@exemple.cd',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _taxpayerAddressCtrl,
                    enabled: !_exporting,
                    decoration: const InputDecoration(labelText: 'Adresse'),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final channel in [
                        'Banque',
                        'Mobile Money',
                        'Caisse',
                      ])
                        FilterChip(
                          label: Text(channel),
                          selected: _channel == channel,
                          onSelected: _exporting
                              ? null
                              : (_) => setState(() => _channel = channel),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _exporting ? null : _exportNote,
                      icon: _exporting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.description_outlined),
                      label: Text(
                        _exporting
                            ? 'Etablissement...'
                            : 'Etablir la note de perception',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
