import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../branding/branding_scope.dart';
import '../branding/app_branding_controller.dart';
import '../data/official_tariffs.dart';
import '../models/app_role.dart';
import '../models/user_profile.dart';
import '../services/gestia_data_service.dart';
import '../theme/app_colors.dart';
import '../utils/error_messages.dart';
import '../utils/perception_note_exporter.dart';
import '../widgets/pdf_document_preview.dart';
import '../widgets/two_fields_layout.dart';

const _noteReceiptTypes = RevenueReceiptType.values;
const _activitySectors = <String>[
  'Environnement',
  'Intérieur',
  'Santé',
  'Tourisme',
  'Industrie',
  'Energie',
  'Economie',
  'PME',
  'Autre',
];
const _pmeActivitySector = 'PME';
const _pmeActTypes = <String>[
  'Vente patente',
  'Vente fichier des fiches de recouvrement PME et Artisanat',
];
const _pmeArticleTariffs = <OfficialTariff>[
  OfficialTariff(
    id: 'pme-patente-commerciale-a-marche',
    receiptType: RevenueReceiptType.taxe,
    label:
        'Patente commerciale catégorie A : vendeur au marché du produit autre que de luxe',
    source: 'PME et Artisanat',
    details: 'Fait générateur: Vente - Périodicité: Ponctuelle',
    tariffLabel: '1 USD',
    amountUsd: 1,
  ),
  OfficialTariff(
    id: 'pme-patente-commerciale-a-voie-publique',
    receiptType: RevenueReceiptType.taxe,
    label:
        'Patente commerciale Catégorie A : Vendeur sur la voie publique secondaire',
    source: 'PME et Artisanat',
    details: 'Fait générateur: Vente - Périodicité: Ponctuelle',
    tariffLabel: '1 USD',
    amountUsd: 1,
  ),
  OfficialTariff(
    id: 'pme-patente-artisanale-d-sante',
    receiptType: RevenueReceiptType.taxe,
    label:
        'Patente artisanale catégorie D : Dispensaire et petit centre de santé',
    source: 'PME et Artisanat',
    details: 'Fait générateur: Vente - Périodicité: Ponctuelle',
    tariffLabel: '1 USD',
    amountUsd: 1,
  ),
  OfficialTariff(
    id: 'pme-patente-marche',
    receiptType: RevenueReceiptType.taxe,
    label: 'Patente marché',
    source: 'PME et Artisanat',
    details: 'Fait générateur: Recensement - Périodicité: Ponctuelle',
    tariffLabel: '3 USD',
    amountUsd: 3,
  ),
];

enum NoteWorkflowMode { taxation, ordonnancement }

const _defaultCdfRate = AppBrandingController.defaultCdfRate;

class PerceptionNoteScreen extends StatefulWidget {
  const PerceptionNoteScreen({
    super.key,
    required this.profile,
    this.mode = NoteWorkflowMode.ordonnancement,
    this.embedded = false,
  });

  final UserProfile profile;
  final NoteWorkflowMode mode;
  final bool embedded;

  @override
  State<PerceptionNoteScreen> createState() => _PerceptionNoteScreenState();
}

class _FormSectionHeader extends StatelessWidget {
  const _FormSectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.primary, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConfirmationRow extends StatelessWidget {
  const _ConfirmationRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayValue = value.trim().isEmpty ? '-' : value.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              displayValue,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PerceptionNoteScreenState extends State<PerceptionNoteScreen> {
  final _amountCtrl = TextEditingController();
  final _paymentDelayCtrl = TextEditingController(text: '8');
  final _taxpayerIdCtrl = TextEditingController();
  final _taxpayerNameCtrl = TextEditingController();
  final _taxpayerPhoneCtrl = TextEditingController();
  final _taxpayerEmailCtrl = TextEditingController();
  final _taxpayerAddressCtrl = TextEditingController();
  final _taxpayerNipCtrl = TextEditingController();
  final _taxpayerCommentCtrl = TextEditingController();
  final _bankNameCtrl = TextEditingController();
  final _receiverAccountCtrl = TextEditingController();
  final _declarantNameCtrl = TextEditingController();
  final _declarantPhoneCtrl = TextEditingController();
  final _declarantEmailCtrl = TextEditingController();
  final _cdfRateCtrl = TextEditingController(
    text: _defaultCdfRate.toStringAsFixed(0),
  );

  List<({String id, String name})> _communes = [];
  List<OfficialTariff> _tariffs = [];
  String? _communeId;
  String? _tariffId;
  String? _pmeActType;
  String _receiptType = _noteReceiptTypes.first;
  String _activitySector = _activitySectors.first;
  String _channel = 'Banque';
  bool _showTaxationDetails = false;
  bool _loading = true;
  bool _exporting = false;
  String? _error;
  PerceptionNoteData? _savedNote;
  Uint8List? _savedNotePdfBytes;
  bool _showFinalPdfPreview = false;
  bool _ordonnancementValidated = false;
  bool _taxpayerIsDeclarant = false;
  bool _cdfRateInitialized = false;

  bool get _isTaxationMode => widget.mode == NoteWorkflowMode.taxation;

  String get _screenTitle => _isTaxationMode ? 'Taxation' : 'Ordonnancement';

  String get _screenSubtitle => _isTaxationMode
      ? 'Enregistrer l assujetti, identifier la taxe, calculer le montant et generer la note de taxation.'
      : 'Valider la taxation, choisir le canal de paiement et generer la note de perception.';

  String get _submitLabel =>
      _isTaxationMode ? 'Valider' : 'Etablir la note de perception';

  String get _savingLabel =>
      _isTaxationMode ? 'Taxation...' : 'Etablissement...';

  String get _savedLabel => _isTaxationMode
      ? 'Note de taxation enregistree.'
      : 'Note de perception enregistree.';

  String get _noteStatus =>
      _isTaxationMode ? 'taxation_creee' : 'note_perception_generee';

  bool get _isPmeActivity => _activitySector == _pmeActivitySector;
  bool get _isPmeTaxation => _isTaxationMode && _isPmeActivity;

  List<OfficialTariff> get _currentTariffs {
    if (_isTaxationMode && _isPmeActivity) {
      return _receiptType == RevenueReceiptType.taxe
          ? _pmeActType == null
                ? const <OfficialTariff>[]
                : _pmeArticleTariffs
          : const <OfficialTariff>[];
    }

    return _tariffs
        .where((tariff) => tariff.receiptType == _receiptType)
        .toList(growable: false);
  }

  OfficialTariff? get _selectedTariff {
    final id = _tariffId;
    if (id == null) return null;
    for (final tariff in _currentTariffs) {
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cdfRateInitialized) return;
    _cdfRateInitialized = true;
    _cdfRateCtrl.text = BrandingScope.of(context).cdfRate.toStringAsFixed(0);
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
    _taxpayerNipCtrl.dispose();
    _taxpayerCommentCtrl.dispose();
    _bankNameCtrl.dispose();
    _receiverAccountCtrl.dispose();
    _declarantNameCtrl.dispose();
    _declarantPhoneCtrl.dispose();
    _declarantEmailCtrl.dispose();
    _cdfRateCtrl.dispose();
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
        _tariffId = null;
        _amountCtrl.clear();
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

  void _prefillAmount() {
    final amount = _selectedTariff?.amountUsd;
    if (amount != null) {
      _amountCtrl.text = formatUsdAmount(amount);
    } else {
      _amountCtrl.clear();
    }
  }

  void _selectReceiptType(String? value) {
    if (value == null) return;
    setState(() {
      _receiptType = value;
      _tariffId = null;
      _pmeActType = null;
      _showTaxationDetails = false;
      _prefillAmount();
    });
  }

  void _selectTariff(String? value) {
    if (value == null) return;
    setState(() {
      _tariffId = value;
      _showTaxationDetails = true;
    });
    _prefillAmount();
  }

  void _selectActivitySector(String? value) {
    if (value == null) return;
    setState(() {
      _activitySector = value;
      if (_isPmeActivity) {
        _receiptType = RevenueReceiptType.taxe;
      }
      _pmeActType = null;
      _tariffId = null;
      _amountCtrl.clear();
      _showTaxationDetails = false;
    });
  }

  void _selectPmeActType(String? value) {
    if (value == null) return;
    setState(() {
      _pmeActType = value;
      _tariffId = null;
      _amountCtrl.clear();
      _showTaxationDetails = false;
    });
  }

  double? _readAmount() {
    final amount = double.tryParse(
      _amountCtrl.text.trim().replaceAll(',', '.'),
    );
    if (amount == null || amount <= 0) return null;
    return amount;
  }

  int? _readPaymentDelayDays() {
    if (_isPmeTaxation) return 1;
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

  void _fillTaxpayer(UserProfile taxpayer) {
    setState(() {
      _taxpayerIdCtrl.text = taxpayer.taxpayerIdentifier ?? '';
      _taxpayerNameCtrl.text = taxpayer.fullName;
      if (taxpayer.communeId != null && taxpayer.communeId!.isNotEmpty) {
        _communeId = taxpayer.communeId;
      }
    });
  }

  Future<void> _showTaxpayerPicker() async {
    if (_exporting) return;
    final profilesFuture = GestiaDataService.fetchAllProfiles();
    final selected = await showDialog<UserProfile>(
      context: context,
      builder: (dialogContext) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Choisir un contribuable'),
              content: SizedBox(
                width: 520,
                height: 430,
                child: FutureBuilder<List<UserProfile>>(
                  future: profilesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Text(userFacingErrorMessage(snapshot.error!));
                    }

                    final normalizedQuery = query.trim().toLowerCase();
                    final taxpayers = (snapshot.data ?? const <UserProfile>[])
                        .where((profile) {
                          if (profile.role != AppRole.contribuable) {
                            return false;
                          }
                          if (normalizedQuery.isEmpty) return true;
                          final searchable =
                              '${profile.fullName} ${profile.taxpayerIdentifier ?? ''} ${profile.communeName ?? ''}'
                                  .toLowerCase();
                          return searchable.contains(normalizedQuery);
                        })
                        .toList(growable: false);

                    return Column(
                      children: [
                        TextField(
                          autofocus: true,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search_outlined),
                            labelText: 'Rechercher',
                          ),
                          onChanged: (value) {
                            setDialogState(() => query = value);
                          },
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: taxpayers.isEmpty
                              ? const Center(
                                  child: Text('Aucun contribuable trouvé.'),
                                )
                              : ListView.separated(
                                  itemCount: taxpayers.length,
                                  separatorBuilder: (_, _) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final taxpayer = taxpayers[index];
                                    final subtitle = [
                                      if (taxpayer.taxpayerIdentifier != null &&
                                          taxpayer
                                              .taxpayerIdentifier!
                                              .isNotEmpty)
                                        'ID ${taxpayer.taxpayerIdentifier}',
                                      if (taxpayer.communeName != null &&
                                          taxpayer.communeName!.isNotEmpty)
                                        taxpayer.communeName!,
                                    ].join(' - ');
                                    return ListTile(
                                      leading: const Icon(Icons.person_outline),
                                      title: Text(taxpayer.fullName),
                                      subtitle: subtitle.isEmpty
                                          ? null
                                          : Text(subtitle),
                                      onTap: () {
                                        Navigator.of(
                                          dialogContext,
                                        ).pop(taxpayer);
                                      },
                                    );
                                  },
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Fermer'),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected != null) {
      _fillTaxpayer(selected);
    }
  }

  Future<void> _saveNoteAndShowPreview() async {
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
        const SnackBar(content: Text('Délai de paiement invalide.')),
      );
      return;
    }

    setState(() => _exporting = true);
    try {
      final taxpayerProfile = await _lookupTaxpayerProfile();
      if (!mounted) return;
      final data = _buildNoteData(amount, taxpayerProfile, paymentDelayDays);
      await GestiaDataService.insertPerceptionNote(
        noteNumber: data.noteNumber,
        communeId: _communeId ?? widget.profile.communeId,
        amountUsd: data.amountUsd,
        taxCategory: data.articleBudgetaire,
        paymentChannel: data.paymentChannel,
        taxpayerProfileId: taxpayerProfile?.id,
        taxpayerIdentifier: data.taxpayerIdentifier,
        taxpayerName: data.taxpayerName,
        taxpayerPhone: data.taxpayerPhone,
        taxpayerEmail: data.taxpayerEmail,
        taxpayerAddress: data.taxpayerAddress,
        paymentDelayDays: paymentDelayDays,
        paymentDeadline: data.paymentDeadline,
        status: _noteStatus,
        legalReference: data.legalReference,
        tariffDetails: data.tariffDetails,
        tariffLabel: data.tariffLabel,
      );
      final pdfBytes = Uint8List.fromList(
        await PerceptionNoteExporter.buildPdfBytes(data),
      );
      if (!mounted) return;
      setState(() {
        _savedNote = data;
        _savedNotePdfBytes = pdfBytes;
        _showFinalPdfPreview = false;
        _ordonnancementValidated = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$_savedLabel Apercu disponible.')),
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

  bool _validateBeforeConfirmation() {
    final amount = _readAmount();
    if (amount == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Montant invalide.')));
      return false;
    }
    if (_communeId == null && widget.profile.communeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune commune disponible.')),
      );
      return false;
    }
    final paymentDelayDays = _readPaymentDelayDays();
    if (paymentDelayDays == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Délai de paiement invalide.')),
      );
      return false;
    }
    return true;
  }

  Future<void> _submitNote() async {
    if (!_isTaxationMode) {
      await _saveNoteAndShowPreview();
      return;
    }

    if (!_validateBeforeConfirmation()) return;
    final confirmed = await _showTaxationConfirmationDialog();
    if (confirmed == true) {
      await _saveNoteAndShowPreview();
    }
  }

  Future<void> _printSavedNote() async {
    final note = _savedNote;
    if (note == null || _exporting) return;
    setState(() => _exporting = true);
    try {
      await PerceptionNoteExporter.printPdf(note);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _downloadSavedNote() async {
    final note = _savedNote;
    if (note == null || _exporting) return;
    setState(() => _exporting = true);
    try {
      final path = await PerceptionNoteExporter.exportPdf(note);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            path == null || path.isEmpty
                ? 'Export annule.'
                : 'Fichier enregistre: $path',
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

  void _startNewNote() {
    setState(() {
      _savedNote = null;
      _savedNotePdfBytes = null;
      _showFinalPdfPreview = false;
      _ordonnancementValidated = false;
      _taxpayerIsDeclarant = false;
      _tariffId = null;
      _pmeActType = null;
      _showTaxationDetails = false;
      _amountCtrl.clear();
      _taxpayerIdCtrl.clear();
      _taxpayerNameCtrl.clear();
      _taxpayerPhoneCtrl.clear();
      _taxpayerEmailCtrl.clear();
      _taxpayerAddressCtrl.clear();
      _taxpayerNipCtrl.clear();
      _taxpayerCommentCtrl.clear();
      _bankNameCtrl.clear();
      _receiverAccountCtrl.clear();
      _declarantNameCtrl.clear();
      _declarantPhoneCtrl.clear();
      _declarantEmailCtrl.clear();
      _cdfRateCtrl.text = BrandingScope.of(context).cdfRate.toStringAsFixed(0);
    });
  }

  Future<bool?> _showTaxationConfirmationDialog() {
    final amount = _readAmount() ?? 0;
    final tariff = _selectedTariff;
    final rows = <({String label, String value})>[
      (label: 'Commune', value: _communeName()),
      (label: "Secteur d'activité", value: _activitySector),
      (label: 'Type de recette', value: _receiptType),
      if (_isPmeTaxation) (label: "Type d'acte", value: _pmeActType ?? '-'),
      (label: 'Article budgétaire', value: tariff?.label ?? _receiptType),
      (label: 'Montant', value: '${formatUsdAmount(amount)} USD'),
      (label: 'Nom', value: _taxpayerNameCtrl.text.trim()),
      (label: 'Identifiant', value: _taxpayerIdCtrl.text.trim()),
      (label: 'Téléphone', value: _taxpayerPhoneCtrl.text.trim()),
      (label: 'E-mail', value: _taxpayerEmailCtrl.text.trim()),
      (label: 'Adresse', value: _taxpayerAddressCtrl.text.trim()),
      (label: 'NIP', value: _taxpayerNipCtrl.text.trim()),
      (label: 'Commentaire', value: _taxpayerCommentCtrl.text.trim()),
      (label: 'Canal', value: _channel),
    ];

    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Vérifier la note de taxation'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final row in rows)
                    _ConfirmationRow(label: row.label, value: row.value),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Confirmer'),
            ),
          ],
        );
      },
    );
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
      serviceAssiette: _isTaxationMode
          ? _activitySector
          : _serviceAssietteFor(tariff),
      articleBudgetaire: tariff?.label ?? _receiptType,
      acteJuridique: _isTaxationMode && _isPmeActivity
          ? _pmeActType ?? _receiptType
          : _receiptType,
      legalReference: _isTaxationMode && _isPmeActivity
          ? 'Liste tarifaire PME et Artisanat.'
          : 'Liste tarifaire officielle.',
      tariffDetails: tariff?.details ?? '',
      tariffLabel: tariff?.tariffLabel ?? '${formatUsdAmount(amount)} USD',
      amountUsd: amount,
      taxpayerName: taxpayerName,
      taxpayerIdentifier: _taxpayerIdCtrl.text.trim(),
      taxpayerPhone: _taxpayerPhoneCtrl.text.trim(),
      taxpayerEmail: _taxpayerEmailCtrl.text.trim(),
      taxpayerAddress: _taxpayerAddressCtrl.text.trim(),
      taxpayerNip: _taxpayerNipCtrl.text.trim(),
      taxpayerComment: _taxpayerCommentCtrl.text.trim(),
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
      onChanged: _exporting || (_isTaxationMode && _isPmeActivity)
          ? null
          : _selectReceiptType,
      decoration: _fieldDecoration(
        label: 'Type de recette',
        icon: Icons.category_outlined,
      ),
    );
  }

  Widget _buildTariffDropdown() {
    final items = _currentTariffs;
    final selectedId = items.any((tariff) => tariff.id == _tariffId)
        ? _tariffId
        : null;

    return DropdownButtonFormField<String>(
      key: ValueKey('note-tariff-$_receiptType-$_pmeActType-$selectedId'),
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
      decoration: _fieldDecoration(
        label: 'Article budgétaire',
        icon: Icons.receipt_long_outlined,
      ),
    );
  }

  Widget _buildPmeActTypeDropdown() {
    return DropdownButtonFormField<String>(
      key: ValueKey('pme-act-type-$_pmeActType'),
      initialValue: _pmeActType,
      isExpanded: true,
      items: [
        for (final actType in _pmeActTypes)
          DropdownMenuItem(
            value: actType,
            child: Text(actType, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: _exporting ? null : _selectPmeActType,
      decoration: _fieldDecoration(
        label: "Type d'acte",
        icon: Icons.assignment_outlined,
      ),
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
          : (value) {
              setState(() {
                _communeId = value;
                if (_isTaxationMode) {
                  _pmeActType = null;
                  _tariffId = null;
                  _amountCtrl.clear();
                  _showTaxationDetails = false;
                }
              });
            },
      decoration: _fieldDecoration(
        label: 'Point de taxation',
        icon: Icons.location_city_outlined,
      ),
    );
  }

  Widget _buildActivitySectorDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _activitySector,
      isExpanded: true,
      items: [
        for (final sector in _activitySectors)
          DropdownMenuItem(
            value: sector,
            child: Text(sector, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: _exporting ? null : _selectActivitySector,
      decoration: _fieldDecoration(
        label: 'Secteur d\'activité',
        icon: Icons.apartment_outlined,
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    String? hintText,
    String? suffixText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      suffixText: suffixText,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Theme.of(context).colorScheme.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.border.withValues(alpha: 0.9)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.primary, width: 1.4),
      ),
    );
  }

  Widget _buildTariffInfo(OfficialTariff tariff) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_outlined, color: AppColors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tariff.amountHelper,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tariff.source,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelChip(String channel, IconData icon) {
    final selected = _channel == channel;
    return ChoiceChip(
      avatar: Icon(
        icon,
        size: 18,
        color: selected ? Colors.white : AppColors.primary,
      ),
      label: Text(channel),
      selected: selected,
      onSelected: _exporting ? null : (_) => setState(() => _channel = channel),
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(
        color: selected ? Colors.white : null,
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide(color: AppColors.primary.withValues(alpha: 0.24)),
      showCheckmark: false,
    );
  }

  Widget _buildPdfPreviewFrame(PerceptionNoteData note) {
    final bytes = _savedNotePdfBytes;
    if (bytes == null || bytes.isEmpty) {
      return const Center(child: Text('Apercu PDF indisponible.'));
    }
    return PdfDocumentPreview(
      bytes: bytes,
      fileName: 'note_perception_${note.noteNumber}.pdf',
    );
  }

  double _readCdfRate() {
    return double.tryParse(_cdfRateCtrl.text.trim().replaceAll(',', '.')) ??
        _defaultCdfRate;
  }

  String _formatCdf(double value) {
    final raw = value.round().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      if (i > 0 && (raw.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(raw[i]);
    }
    return '$buffer CDF';
  }

  String _amountPreviewLabel(PerceptionNoteData note) {
    final rate = note.cdfRate > 0 ? note.cdfRate : _readCdfRate();
    return '${formatUsdAmount(note.amountUsd)} USD / '
        '${_formatCdf(note.amountUsd * rate)}';
  }

  Widget _buildPreviewRow(String label, String value) {
    return _ConfirmationRow(label: label, value: value);
  }

  Widget _buildWebNotePreview(PerceptionNoteData note) {
    final theme = Theme.of(context);
    final hasOrdonnancement =
        _ordonnancementValidated || note.bankName.trim().isNotEmpty;
    return Card(
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.border.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  Text(
                    'NOTE DE PERCEPTION',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    note.noteNumber,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const Divider(height: 28),
            _buildPreviewRow('Service d assiette', note.serviceAssiette),
            _buildPreviewRow('Article budgetaire', note.articleBudgetaire),
            _buildPreviewRow('Acte juridique', note.acteJuridique),
            _buildPreviewRow('Montant', _amountPreviewLabel(note)),
            _buildPreviewRow('Assujetti', note.taxpayerName),
            _buildPreviewRow('Identifiant', note.taxpayerIdentifier),
            _buildPreviewRow('Telephone', note.taxpayerPhone),
            _buildPreviewRow('E-mail', note.taxpayerEmail),
            _buildPreviewRow('Adresse', note.taxpayerAddress),
            _buildPreviewRow('Point de taxation', note.pointTaxation),
            _buildPreviewRow('Canal', note.paymentChannel),
            if (hasOrdonnancement) ...[
              const Divider(height: 28),
              Text(
                'Ordonnancement',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              _buildPreviewRow('Banque', note.bankName),
              _buildPreviewRow('Compte receveur', note.receiverAccount),
              _buildPreviewRow('Declarant', note.declarantName),
              _buildPreviewRow('Telephone declarant', note.declarantPhone),
              _buildPreviewRow('E-mail declarant', note.declarantEmail),
              _buildPreviewRow(
                'Taux applique',
                '${formatUsdAmount(note.cdfRate)} CDF / USD',
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _fillDeclarantFromTaxpayer() {
    _declarantNameCtrl.text = _taxpayerNameCtrl.text.trim();
    _declarantPhoneCtrl.text = _taxpayerPhoneCtrl.text.trim();
    _declarantEmailCtrl.text = _taxpayerEmailCtrl.text.trim();
  }

  Future<void> _openOrdonnancementSheet() async {
    final note = _savedNote;
    if (note == null || _exporting) return;
    if (_taxpayerIsDeclarant) _fillDeclarantFromTaxpayer();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                6,
                20,
                MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Ordonnancer la note',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TwoFieldsLayout(
                      firstLabel: 'Banque',
                      secondLabel: 'Compte receveur',
                      firstChild: TextField(
                        controller: _bankNameCtrl,
                        decoration: _fieldDecoration(
                          label: 'Nom de la banque',
                          icon: Icons.account_balance_outlined,
                        ),
                      ),
                      secondChild: TextField(
                        controller: _receiverAccountCtrl,
                        decoration: _fieldDecoration(
                          label: 'Compte receveur',
                          icon: Icons.numbers_outlined,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      value: _taxpayerIsDeclarant,
                      onChanged: (value) {
                        setSheetState(() {
                          _taxpayerIsDeclarant = value ?? false;
                          if (_taxpayerIsDeclarant) {
                            _fillDeclarantFromTaxpayer();
                          }
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                      title: const Text("L'assujetti est-il declarant ?"),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    const SizedBox(height: 12),
                    TwoFieldsLayout(
                      firstLabel: 'Declarant',
                      secondLabel: 'Telephone',
                      firstChild: TextField(
                        controller: _declarantNameCtrl,
                        enabled: !_taxpayerIsDeclarant,
                        decoration: _fieldDecoration(
                          label: 'Nom du declarant',
                          icon: Icons.person_outline,
                        ),
                      ),
                      secondChild: TextField(
                        controller: _declarantPhoneCtrl,
                        enabled: !_taxpayerIsDeclarant,
                        keyboardType: TextInputType.phone,
                        decoration: _fieldDecoration(
                          label: 'Telephone du declarant',
                          icon: Icons.phone_outlined,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _declarantEmailCtrl,
                      enabled: !_taxpayerIsDeclarant,
                      keyboardType: TextInputType.emailAddress,
                      decoration: _fieldDecoration(
                        label: 'Mail du declarant',
                        icon: Icons.mail_outline,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          if (_validateOrdonnancementFields(sheetContext)) {
                            Navigator.of(sheetContext).pop();
                            _validateOrdonnancementPreview();
                          }
                        },
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Valider'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  bool _validateOrdonnancementFields(BuildContext targetContext) {
    final required = <String, TextEditingController>{
      'Nom de la banque': _bankNameCtrl,
      'Compte receveur': _receiverAccountCtrl,
      'Nom du declarant': _declarantNameCtrl,
      'Telephone du declarant': _declarantPhoneCtrl,
      'Mail du declarant': _declarantEmailCtrl,
    };
    for (final entry in required.entries) {
      if (entry.value.text.trim().isEmpty) {
        ScaffoldMessenger.of(
          targetContext,
        ).showSnackBar(SnackBar(content: Text('${entry.key} requis.')));
        return false;
      }
    }
    return true;
  }

  void _validateOrdonnancementPreview() {
    final note = _savedNote;
    if (note == null) return;
    setState(() {
      _savedNote = note.copyWith(
        bankName: _bankNameCtrl.text.trim(),
        receiverAccount: _receiverAccountCtrl.text.trim(),
        declarantName: _declarantNameCtrl.text.trim(),
        declarantPhone: _declarantPhoneCtrl.text.trim(),
        declarantEmail: _declarantEmailCtrl.text.trim(),
        cdfRate: _readCdfRate(),
      );
      _savedNotePdfBytes = null;
      _showFinalPdfPreview = false;
      _ordonnancementValidated = true;
    });
  }

  Future<void> _confirmFinalPdfPreview() async {
    final note = _savedNote;
    if (note == null || _exporting) return;
    setState(() => _exporting = true);
    try {
      final pdfBytes = Uint8List.fromList(
        await PerceptionNoteExporter.buildPdfBytes(note),
      );
      if (!mounted) return;
      setState(() {
        _savedNotePdfBytes = pdfBytes;
        _showFinalPdfPreview = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _buildSavedNotePreview(PerceptionNoteData note) {
    final theme = Theme.of(context);
    final content = Padding(
      padding: EdgeInsets.all(widget.embedded ? 0 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Apercu de la note de perception',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _showFinalPdfPreview
                          ? 'La note ordonnancee est prete pour impression.'
                          : _ordonnancementValidated
                          ? 'Verifiez les informations d ordonnancement avant de confirmer le PDF.'
                          : _isTaxationMode
                          ? 'La taxation est enregistree. Elle apparaitra dans Ordonnancement pour verification et validation.'
                          : 'La note est enregistree. Vous pouvez ordonnancer ou demarrer une nouvelle taxation.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (_showFinalPdfPreview)
                FilledButton.icon(
                  onPressed: _exporting ? null : _printSavedNote,
                  icon: _exporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.print_outlined),
                  label: Text(_exporting ? 'Preparation...' : 'Imprimer'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_showFinalPdfPreview)
            Card(
              elevation: 1,
              shadowColor: Colors.black.withValues(alpha: 0.06),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: AppColors.border.withValues(alpha: 0.7),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  height: 760,
                  child: _buildPdfPreviewFrame(note),
                ),
              ),
            )
          else
            _buildWebNotePreview(note),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (_showFinalPdfPreview)
                OutlinedButton.icon(
                  onPressed: _exporting ? null : _downloadSavedNote,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Enregistrer PDF'),
                )
              else if (_ordonnancementValidated)
                FilledButton.icon(
                  onPressed: _exporting ? null : _confirmFinalPdfPreview,
                  icon: _exporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_outlined),
                  label: Text(_exporting ? 'Preparation...' : 'Confirmer'),
                )
              else if (!_isTaxationMode)
                FilledButton.icon(
                  onPressed: _exporting ? null : _openOrdonnancementSheet,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Ordonancer'),
                ),
              TextButton.icon(
                onPressed: _exporting ? null : _startNewNote,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Nouvelle taxation'),
              ),
            ],
          ),
        ],
      ),
    );

    if (widget.embedded) return content;
    return SingleChildScrollView(child: content);
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

    final savedNote = _savedNote;
    if (savedNote != null) {
      return _buildSavedNotePreview(savedNote);
    }

    final tariff = _selectedTariff;
    final showDetails = !_isTaxationMode || _showTaxationDetails;
    final content = Padding(
      padding: EdgeInsets.all(widget.embedded ? 0 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _screenTitle,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            _screenSubtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 1,
            shadowColor: Colors.black.withValues(alpha: 0.06),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppColors.border.withValues(alpha: 0.7)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _FormSectionHeader(
                    icon: Icons.tune_outlined,
                    title: 'Paramètres de taxation',
                    subtitle:
                        'Définissez le périmètre, le secteur et l article tarifaire.',
                  ),
                  const SizedBox(height: 16),
                  TwoFieldsLayout(
                    firstLabel: 'Commune',
                    secondLabel: 'Type',
                    firstChild: _buildCommuneDropdown(),
                    secondChild: _buildReceiptTypeDropdown(),
                  ),
                  if (_isTaxationMode) ...[
                    const SizedBox(height: 12),
                    _buildActivitySectorDropdown(),
                  ],
                  if (_isTaxationMode && _isPmeActivity) ...[
                    const SizedBox(height: 12),
                    _buildPmeActTypeDropdown(),
                  ],
                  if (!_isTaxationMode ||
                      !_isPmeActivity ||
                      _pmeActType != null) ...[
                    const SizedBox(height: 12),
                    _buildTariffDropdown(),
                  ],
                  if (showDetails && tariff != null) ...[
                    const SizedBox(height: 8),
                    _buildTariffInfo(tariff),
                  ],
                  if (showDetails) ...[
                    const SizedBox(height: 12),
                    if (_isPmeTaxation)
                      TextField(
                        controller: _amountCtrl,
                        enabled: !_exporting,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: _fieldDecoration(
                          label: 'Montant',
                          icon: Icons.attach_money_outlined,
                          suffixText: 'USD',
                        ),
                      )
                    else
                      TwoFieldsLayout(
                        firstLabel: 'Montant',
                        secondLabel: 'Delai de paiement',
                        firstChild: TextField(
                          controller: _amountCtrl,
                          enabled: !_exporting,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: _fieldDecoration(
                            label: 'Montant',
                            icon: Icons.attach_money_outlined,
                            suffixText: 'USD',
                          ),
                        ),
                        secondChild: TextField(
                          controller: _paymentDelayCtrl,
                          enabled: !_exporting,
                          keyboardType: TextInputType.number,
                          decoration: _fieldDecoration(
                            label: 'Délai de paiement',
                            icon: Icons.event_available_outlined,
                            hintText: 'Ex: 8',
                            suffixText: 'jours',
                          ),
                        ),
                      ),
                    const Divider(height: 28),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Expanded(
                          child: _FormSectionHeader(
                            icon: Icons.person_search_outlined,
                            title: 'Identité de l\'assujetti',
                            subtitle:
                                'Renseignez ou retrouvez le contribuable concerné par la taxation.',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: 'Afficher les contribuables',
                          child: IconButton.filledTonal(
                            onPressed: _exporting ? null : _showTaxpayerPicker,
                            icon: const Icon(Icons.group_add_outlined),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TwoFieldsLayout(
                      firstLabel: 'Identifiant',
                      secondLabel: 'Nom',
                      firstChild: TextField(
                        controller: _taxpayerIdCtrl,
                        enabled: !_exporting,
                        decoration: _fieldDecoration(
                          label: 'Identifiant contribuable',
                          icon: Icons.badge_outlined,
                          hintText: 'Ex: CTB-0001',
                        ),
                      ),
                      secondChild: TextField(
                        controller: _taxpayerNameCtrl,
                        enabled: !_exporting,
                        decoration: _fieldDecoration(
                          label: 'Nom complet',
                          icon: Icons.person_outline,
                          hintText: 'Nom',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TwoFieldsLayout(
                      firstLabel: 'Téléphone',
                      secondLabel: 'E-mail',
                      firstChild: TextField(
                        controller: _taxpayerPhoneCtrl,
                        enabled: !_exporting,
                        keyboardType: TextInputType.phone,
                        decoration: _fieldDecoration(
                          label: 'Téléphone',
                          icon: Icons.phone_outlined,
                          hintText: '+243 ...',
                        ),
                      ),
                      secondChild: TextField(
                        controller: _taxpayerEmailCtrl,
                        enabled: !_exporting,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _fieldDecoration(
                          label: 'E-mail',
                          icon: Icons.mail_outline,
                          hintText: 'email@exemple.cd',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _taxpayerAddressCtrl,
                      enabled: !_exporting,
                      decoration: _fieldDecoration(
                        label: 'Adresse',
                        icon: Icons.home_work_outlined,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TwoFieldsLayout(
                      firstLabel: 'NIP',
                      secondLabel: 'Commentaire',
                      firstChild: TextField(
                        controller: _taxpayerNipCtrl,
                        enabled: !_exporting,
                        decoration: _fieldDecoration(
                          label: 'NIP',
                          icon: Icons.pin_outlined,
                        ),
                      ),
                      secondChild: TextField(
                        controller: _taxpayerCommentCtrl,
                        enabled: !_exporting,
                        decoration: _fieldDecoration(
                          label: 'Commentaire',
                          icon: Icons.notes_outlined,
                        ),
                      ),
                    ),
                    const Divider(height: 28),
                    const _FormSectionHeader(
                      icon: Icons.payments_outlined,
                      title: 'Canal et génération',
                      subtitle:
                          'Choisissez le canal prévu puis générez la note officielle.',
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildChannelChip('Banque', Icons.account_balance),
                        _buildChannelChip('Mobile Money', Icons.phone_android),
                        _buildChannelChip('Caisse', Icons.point_of_sale),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _exporting ? null : _submitNote,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: _exporting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.description_outlined),
                        label: Text(_exporting ? _savingLabel : _submitLabel),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (widget.embedded) return content;
    return SingleChildScrollView(child: content);
  }
}
