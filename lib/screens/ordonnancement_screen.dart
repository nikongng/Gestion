import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../branding/branding_scope.dart';
import '../models/user_profile.dart';
import '../services/gestia_data_service.dart';
import '../theme/app_colors.dart';
import '../utils/error_messages.dart';
import '../utils/perception_note_exporter.dart';
import '../utils/report_exporter.dart';
import '../widgets/pdf_document_preview.dart';

enum _OrdonnancementPeriod { today, sevenDays, thirtyDays, thisMonth, all }

class _OrdonnancementStats {
  const _OrdonnancementStats({
    required this.pending,
    required this.ordered,
    required this.rejected,
    required this.orderedAmount,
  });

  final int pending;
  final int ordered;
  final int rejected;
  final double orderedAmount;

  static const empty = _OrdonnancementStats(
    pending: 0,
    ordered: 0,
    rejected: 0,
    orderedAmount: 0,
  );
}

class OrdonnancementScreen extends StatefulWidget {
  const OrdonnancementScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<OrdonnancementScreen> createState() => _OrdonnancementScreenState();
}

class _OrdonnancementScreenState extends State<OrdonnancementScreen> {
  final _bankNameCtrl = TextEditingController();
  final _receiverAccountCtrl = TextEditingController();
  final _declarantNameCtrl = TextEditingController();
  final _declarantPhoneCtrl = TextEditingController();
  final _declarantEmailCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _pending = [];
  bool _loading = true;
  String? _error;
  String? _updatingId;
  bool _exporting = false;
  String _paymentMode = 'Banque';
  String? _taxFilter;
  String? _communeFilter;
  String? _statusFilter = 'taxation_creee';
  Map<String, String> _ordonnateurNames = {};
  bool _taxpayerIsDeclarant = false;
  PerceptionNoteData? _generatedNote;
  Uint8List? _generatedPdfBytes;
  _OrdonnancementPeriod _period = _OrdonnancementPeriod.thirtyDays;
  _OrdonnancementStats _stats = _OrdonnancementStats.empty;
  bool _statsLoading = true;

  String? get _scope =>
      widget.profile.role.isGlobalSupervisor ? null : widget.profile.communeId;

  @override
  void initState() {
    super.initState();
    _loadPending();
    _loadStats();
  }

  @override
  void dispose() {
    _bankNameCtrl.dispose();
    _receiverAccountCtrl.dispose();
    _declarantNameCtrl.dispose();
    _declarantPhoneCtrl.dispose();
    _declarantEmailCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPending() async {
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
          'apuree_cpi_genere',
          'annulee',
        ],
        communeId: _scope,
        limit: 5000,
      );
      final ordonnateurNames = await _fetchOrdonnateurNames(rows);
      if (!mounted) return;
      setState(() {
        _pending = rows;
        _ordonnateurNames = ordonnateurNames;
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

  Future<Map<String, String>> _fetchOrdonnateurNames(
    List<Map<String, dynamic>> rows,
  ) async {
    final ids = rows
        .map((row) => row['ordonnateur_id']?.toString() ?? '')
        .where((id) => id.trim().isNotEmpty)
        .toSet();
    if (ids.isEmpty) return const {};
    try {
      return await GestiaDataService.fetchProfileNamesByIds(ids);
    } catch (_) {
      return const {};
    }
  }

  Future<void> _loadStats() async {
    setState(() => _statsLoading = true);
    try {
      final range = _periodRange(_period);
      final rows = await GestiaDataService.fetchPerceptionNotes(
        statuses: const [
          'taxation_creee',
          'ordonnee',
          'note_perception_generee',
          'paiement_declare',
          'en_recouvrement',
          'apuree_cpi_genere',
          'annulee',
        ],
        communeId: _scope,
        createdFrom: range?.start,
        createdTo: range?.end,
        limit: 5000,
      );
      if (!mounted) return;
      setState(() {
        _stats = _statsFromRows(rows);
        _statsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stats = _OrdonnancementStats.empty;
        _statsLoading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(e))));
    }
  }

  _OrdonnancementStats _statsFromRows(List<Map<String, dynamic>> rows) {
    const orderedStatuses = {
      'ordonnee',
      'note_perception_generee',
      'paiement_declare',
      'en_recouvrement',
      'apuree_cpi_genere',
    };
    var pending = 0;
    var ordered = 0;
    var rejected = 0;
    var orderedAmount = 0.0;

    for (final row in rows) {
      final status = row['status']?.toString() ?? '';
      final amount = (row['amount'] as num?)?.toDouble() ?? 0;
      if (status == 'taxation_creee') {
        pending++;
      } else if (status == 'annulee') {
        rejected++;
      } else if (orderedStatuses.contains(status)) {
        ordered++;
        orderedAmount += amount;
      }
    }

    return _OrdonnancementStats(
      pending: pending,
      ordered: ordered,
      rejected: rejected,
      orderedAmount: orderedAmount,
    );
  }

  DateTimeRange? _periodRange(_OrdonnancementPeriod period) {
    if (period == _OrdonnancementPeriod.all) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (period) {
      _OrdonnancementPeriod.today => DateTimeRange(
        start: today,
        end: today.add(const Duration(days: 1)),
      ),
      _OrdonnancementPeriod.sevenDays => DateTimeRange(
        start: today.subtract(const Duration(days: 6)),
        end: today.add(const Duration(days: 1)),
      ),
      _OrdonnancementPeriod.thirtyDays => DateTimeRange(
        start: today.subtract(const Duration(days: 29)),
        end: today.add(const Duration(days: 1)),
      ),
      _OrdonnancementPeriod.thisMonth => DateTimeRange(
        start: DateTime(today.year, today.month),
        end: DateTime(today.year, today.month + 1),
      ),
      _OrdonnancementPeriod.all => null,
    };
  }

  String _periodLabel(_OrdonnancementPeriod period) {
    return switch (period) {
      _OrdonnancementPeriod.today => 'Aujourd hui',
      _OrdonnancementPeriod.sevenDays => '7 derniers jours',
      _OrdonnancementPeriod.thirtyDays => '30 derniers jours',
      _OrdonnancementPeriod.thisMonth => 'Mois en cours',
      _OrdonnancementPeriod.all => 'Toutes les periodes',
    };
  }

  String _formatAmount(double amount) => '${amount.toStringAsFixed(2)} USD';

  List<Map<String, dynamic>> get _filteredRows {
    final query = _searchCtrl.text.trim().toLowerCase();
    return _pending.where((row) {
      final tax = row['tax_category']?.toString() ?? '';
      final commune = _communeName(row);
      final status = row['status']?.toString() ?? '';
      if (_taxFilter != null && tax != _taxFilter) return false;
      if (_communeFilter != null && commune != _communeFilter) return false;
      if (_statusFilter != null && status != _statusFilter) return false;
      if (query.isEmpty) return true;
      final searchable = [
        row['note_number'],
        row['taxpayer_name'],
        row['taxpayer_identifier'],
        row['tax_category'],
        commune,
        status,
      ].whereType<Object>().map((value) => value.toString().toLowerCase());
      return searchable.any((value) => value.contains(query));
    }).toList();
  }

  List<Map<String, dynamic>> get _historyRows {
    final rows = _pending
        .where((row) => row['status']?.toString() != 'taxation_creee')
        .toList();
    rows.sort((a, b) {
      final aDate = _rowDateTime(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = _rowDateTime(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return rows;
  }

  List<String> _distinctValues(String Function(Map<String, dynamic>) read) {
    final values = _pending
        .map(read)
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    values.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  String _statusLabel(String? status) {
    return switch (status) {
      null => 'Tous les statuts',
      'taxation_creee' => 'A ordonnancer',
      'ordonnee' => 'Ordonnee',
      'note_perception_generee' => 'Note generee',
      'paiement_declare' => 'Paiement declare',
      'en_recouvrement' => 'En recouvrement',
      'apuree_cpi_genere' => 'Apuree',
      'annulee' => 'Rejetee',
      _ => status,
    };
  }

  DateTime? _rowDateTime(Map<String, dynamic> row) {
    return DateTime.tryParse(row['updated_at']?.toString() ?? '')?.toLocal() ??
        DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal();
  }

  String _dateTimeLabel(DateTime? date) {
    if (date == null) return '-';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
  }

  String _bankLabel(Map<String, dynamic> row) {
    final bank = row['bank_name']?.toString().trim() ?? '';
    final account = row['receiver_account']?.toString().trim() ?? '';
    if (bank.isEmpty && account.isEmpty) return '-';
    if (bank.isEmpty) return account;
    if (account.isEmpty) return bank;
    return '$bank / $account';
  }

  String _ordonnateurName(Map<String, dynamic> row) {
    final id = row['ordonnateur_id']?.toString();
    if (id != null && id.isNotEmpty) {
      final name = _ordonnateurNames[id];
      if (name != null && name.trim().isNotEmpty) return name;
    }
    return '-';
  }

  Future<void> _exportFilteredRows() async {
    if (_exporting) return;
    final rows = _filteredRows;
    setState(() => _exporting = true);
    try {
      final total = rows.fold<double>(
        0,
        (sum, row) => sum + ((row['amount'] as num?)?.toDouble() ?? 0),
      );
      final path = await ReportExporter.exportExcel(
        ReportExportData(
          title: 'Ordonnancement - ${_statusLabel(_statusFilter)}',
          scopeLabel: _periodLabel(_period),
          generatedAt: DateTime.now(),
          metrics: [
            ReportExportMetric(
              label: 'Notes exportees',
              value: '${rows.length}',
            ),
            ReportExportMetric(
              label: 'Montant total',
              value: _formatAmount(total),
            ),
          ],
          rows: [
            for (final row in rows)
              ReportExportRow(
                collectedAt:
                    DateTime.tryParse(
                      row['created_at']?.toString() ?? '',
                    )?.toLocal() ??
                    DateTime.now(),
                communeName: _communeName(row),
                taxCategory:
                    '${row['note_number'] ?? '-'} - ${row['tax_category'] ?? '-'} - ${_statusLabel(row['status']?.toString())}',
                amountUsd: (row['amount'] as num?)?.toDouble() ?? 0,
              ),
          ],
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            path == null || path.isEmpty
                ? 'Export annule.'
                : 'Export Excel genere. Fichier: $path',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingErrorMessage(e, prefix: 'Echec de l export')),
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _openOrdonnancementDialog(Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty || _updatingId != null) return;
    _prefillDeclarant(row);
    var taxpayerChecked = true;
    var taxTypeChecked = true;
    var amountChecked = true;
    var rateChecked = true;
    var nomenclatureChecked = true;
    var legalChecked = true;
    var fraudChecked = true;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final canValidate =
                taxpayerChecked &&
                taxTypeChecked &&
                amountChecked &&
                rateChecked &&
                nomenclatureChecked &&
                legalChecked &&
                fraudChecked &&
                _bankNameCtrl.text.trim().isNotEmpty &&
                _receiverAccountCtrl.text.trim().isNotEmpty &&
                _declarantNameCtrl.text.trim().isNotEmpty &&
                _declarantPhoneCtrl.text.trim().isNotEmpty &&
                _declarantEmailCtrl.text.trim().isNotEmpty;

            return AlertDialog(
              title: const Text('Ordonnancer la taxation'),
              content: SizedBox(
                width: 720,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTaxationSummary(row),
                      const SizedBox(height: 16),
                      Text(
                        '1. Verification de la taxation',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      _checkTile(
                        value: taxpayerChecked,
                        label: 'Nom du contribuable controle',
                        onChanged: (v) =>
                            setDialogState(() => taxpayerChecked = v),
                      ),
                      _checkTile(
                        value: taxTypeChecked,
                        label: 'Type de taxe controle',
                        onChanged: (v) =>
                            setDialogState(() => taxTypeChecked = v),
                      ),
                      _checkTile(
                        value: amountChecked,
                        label: 'Montant controle',
                        onChanged: (v) =>
                            setDialogState(() => amountChecked = v),
                      ),
                      _checkTile(
                        value: rateChecked,
                        label: 'Taux applique controle',
                        onChanged: (v) => setDialogState(() => rateChecked = v),
                      ),
                      _checkTile(
                        value: nomenclatureChecked,
                        label: 'Conformite avec la nomenclature fiscale',
                        onChanged: (v) =>
                            setDialogState(() => nomenclatureChecked = v),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '2. Validation administrative',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      _checkTile(
                        value: legalChecked,
                        label: 'La taxe existe legalement',
                        onChanged: (v) =>
                            setDialogState(() => legalChecked = v),
                      ),
                      _checkTile(
                        value: fraudChecked,
                        label: 'Aucun element frauduleux detecte',
                        onChanged: (v) =>
                            setDialogState(() => fraudChecked = v),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '3. Compte bancaire et declarant',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _bankNameCtrl,
                        onChanged: (_) => setDialogState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Banque partenaire',
                          prefixIcon: Icon(Icons.account_balance_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _receiverAccountCtrl,
                        onChanged: (_) => setDialogState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Compte officiel de la province',
                          prefixIcon: Icon(Icons.numbers_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _modeChip(
                            'Banque',
                            Icons.account_balance,
                            setDialogState,
                          ),
                          _modeChip(
                            'Mobile Money',
                            Icons.phone_android,
                            setDialogState,
                          ),
                          _modeChip(
                            'Carte Visa',
                            Icons.credit_card,
                            setDialogState,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      CheckboxListTile(
                        value: _taxpayerIsDeclarant,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text("L'assujetti est-il declarant ?"),
                        onChanged: (value) {
                          setDialogState(() {
                            _taxpayerIsDeclarant = value ?? false;
                            if (_taxpayerIsDeclarant) _prefillDeclarant(row);
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _declarantNameCtrl,
                        enabled: !_taxpayerIsDeclarant,
                        onChanged: (_) => setDialogState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Nom du declarant',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _declarantPhoneCtrl,
                        enabled: !_taxpayerIsDeclarant,
                        onChanged: (_) => setDialogState(() {}),
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Telephone du declarant',
                          prefixIcon: Icon(Icons.phone_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _declarantEmailCtrl,
                        enabled: !_taxpayerIsDeclarant,
                        onChanged: (_) => setDialogState(() {}),
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Mail du declarant',
                          prefixIcon: Icon(Icons.mail_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Annuler'),
                ),
                FilledButton.icon(
                  onPressed: canValidate
                      ? () async {
                          Navigator.of(dialogContext).pop();
                          await _generatePerceptionNote(row);
                        }
                      : null,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Generer la note'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _checkTile({
    required bool value,
    required String label,
    required ValueChanged<bool> onChanged,
  }) {
    return CheckboxListTile(
      value: value,
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(label),
      onChanged: (v) => onChanged(v ?? false),
    );
  }

  Widget _modeChip(
    String label,
    IconData icon,
    void Function(void Function()) setDialogState,
  ) {
    final selected = _paymentMode == label;
    return ChoiceChip(
      avatar: Icon(
        icon,
        size: 18,
        color: selected ? Colors.white : AppColors.primary,
      ),
      label: Text(label),
      selected: selected,
      selectedColor: AppColors.primary,
      showCheckmark: false,
      labelStyle: TextStyle(
        color: selected ? Colors.white : null,
        fontWeight: FontWeight.w700,
      ),
      onSelected: (_) => setDialogState(() => _paymentMode = label),
    );
  }

  void _prefillDeclarant(Map<String, dynamic> row) {
    _taxpayerIsDeclarant = true;
    _declarantNameCtrl.text = row['taxpayer_name']?.toString() ?? '';
    _declarantPhoneCtrl.text = row['taxpayer_phone']?.toString() ?? '';
    _declarantEmailCtrl.text = row['taxpayer_email']?.toString() ?? '';
  }

  Future<void> _generatePerceptionNote(Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() => _updatingId = id);
    try {
      final note = _noteDataFromRow(row);
      final pdfBytes = Uint8List.fromList(
        await PerceptionNoteExporter.buildPdfBytes(note),
      );
      await GestiaDataService.updatePerceptionNoteStatus(
        noteId: id,
        status: 'note_perception_generee',
        paymentChannel: _paymentMode,
        bankName: _bankNameCtrl.text.trim(),
        receiverAccount: _receiverAccountCtrl.text.trim(),
        declarantName: _declarantNameCtrl.text.trim(),
        declarantPhone: _declarantPhoneCtrl.text.trim(),
        declarantEmail: _declarantEmailCtrl.text.trim(),
        cdfRate: BrandingScope.of(context).cdfRate,
        markOrdonnateur: true,
      );
      await _loadPending();
      await _loadStats();
      if (!mounted) return;
      setState(() {
        _generatedNote = note;
        _generatedPdfBytes = pdfBytes;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note de perception generee.')),
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

  PerceptionNoteData _noteDataFromRow(Map<String, dynamic> row) {
    final amount = (row['amount'] as num?)?.toDouble() ?? 0;
    final deadlineText = row['payment_deadline']?.toString();
    final deadline = DateTime.tryParse(deadlineText ?? '') ?? DateTime.now();
    return PerceptionNoteData(
      provinceName: BrandingScope.of(context).provinceName,
      noteNumber: row['note_number']?.toString() ?? '',
      generatedAt: DateTime.now(),
      serviceAssiette: row['tax_category']?.toString() ?? 'GESTIA RECETTES',
      articleBudgetaire: row['tax_category']?.toString() ?? '',
      acteJuridique: row['tax_category']?.toString() ?? '',
      legalReference:
          row['legal_reference']?.toString() ?? 'Liste tarifaire officielle.',
      tariffDetails: row['tariff_details']?.toString() ?? '',
      tariffLabel: row['tariff_label']?.toString() ?? '${_money(row)}',
      amountUsd: amount,
      taxpayerName: row['taxpayer_name']?.toString() ?? '',
      taxpayerIdentifier: row['taxpayer_identifier']?.toString() ?? '',
      taxpayerPhone: row['taxpayer_phone']?.toString() ?? '',
      taxpayerEmail: row['taxpayer_email']?.toString() ?? '',
      taxpayerAddress: row['taxpayer_address']?.toString() ?? '',
      taxpayerNip: '',
      taxpayerComment: '',
      pointTaxation: 'GESTIA - ${_communeName(row)}',
      paymentChannel: _paymentMode,
      taxateurName: row['taxateur_name']?.toString() ?? '',
      ordonnateurName: widget.profile.fullName,
      paymentDelayLabel: _paymentDelayLabel(deadline),
      paymentDeadline: deadline,
      bankName: _bankNameCtrl.text.trim(),
      receiverAccount: _receiverAccountCtrl.text.trim(),
      declarantName: _declarantNameCtrl.text.trim(),
      declarantPhone: _declarantPhoneCtrl.text.trim(),
      declarantEmail: _declarantEmailCtrl.text.trim(),
      cdfRate: BrandingScope.of(context).cdfRate,
    );
  }

  String _paymentDelayLabel(DateTime deadline) {
    final today = DateTime.now();
    final cleanToday = DateTime(today.year, today.month, today.day);
    final cleanDeadline = DateTime(deadline.year, deadline.month, deadline.day);
    final days = cleanDeadline.difference(cleanToday).inDays;
    if (days <= 1) return '1 jour';
    return '$days jours';
  }

  Future<void> _printGeneratedNote() async {
    final note = _generatedNote;
    if (note == null) return;
    await PerceptionNoteExporter.printPdf(note);
  }

  Future<void> _saveGeneratedNote() async {
    final note = _generatedNote;
    if (note == null) return;
    await PerceptionNoteExporter.exportPdf(note);
  }

  Widget _buildTaxationSummary(Map<String, dynamic> row) {
    final theme = Theme.of(context);
    final rate = BrandingScope.of(context).cdfRate;
    final amount = (row['amount'] as num?)?.toDouble() ?? 0;
    final cdf = (amount * rate).round().toString();
    final lines = <({String label, String value})>[
      (label: 'Contribuable', value: row['taxpayer_name']?.toString() ?? '-'),
      (label: 'Type de taxe', value: row['tax_category']?.toString() ?? '-'),
      (label: 'Montant', value: '${_money(row)} / $cdf CDF'),
      (label: 'Taux applique', value: '${rate.toStringAsFixed(0)} CDF / USD'),
      (
        label: 'Nomenclature',
        value: row['tariff_label']?.toString() ?? 'Nomenclature officielle',
      ),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row['note_number']?.toString() ?? 'Taxation',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      line.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      line.value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGeneratedNotePanel(BuildContext context) {
    final note = _generatedNote;
    final bytes = _generatedPdfBytes;
    if (note == null || bytes == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long_outlined, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Note de perception generee',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _saveGeneratedNote,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Enregistrer'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _printGeneratedNote,
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Imprimer'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 720,
              child: PdfDocumentPreview(
                bytes: bytes,
                fileName: 'note_perception_${note.noteNumber}.pdf',
              ),
            ),
          ],
        ),
      ),
    );
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

  int _metricColumns(double width) {
    if (width >= 1100) return 4;
    if (width >= 700) return 2;
    return 1;
  }

  Widget _buildMetricGrid(double width, List<Widget> cards) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _metricColumns(width),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: 104,
      ),
      itemBuilder: (context, index) => cards[index],
    );
  }

  Widget _buildPeriodSelector() {
    return SizedBox(
      width: 240,
      child: DropdownButtonFormField<_OrdonnancementPeriod>(
        isExpanded: true,
        initialValue: _period,
        decoration: const InputDecoration(
          labelText: 'Periode',
          prefixIcon: Icon(Icons.date_range_outlined),
          border: OutlineInputBorder(),
        ),
        items: [
          for (final period in _OrdonnancementPeriod.values)
            DropdownMenuItem(value: period, child: Text(_periodLabel(period))),
        ],
        onChanged: (value) async {
          if (value == null || value == _period) return;
          setState(() => _period = value);
          await _loadStats();
        },
      ),
    );
  }

  Widget _buildStatsPanel(BuildContext context) {
    final theme = Theme.of(context);
    final stats = _stats;
    final cards = <Widget>[
      _OrdonnancementKpiCard(
        title: 'A ordonnancer',
        value: _statsLoading ? '...' : '${stats.pending}',
        subtitle: 'Montant total',
        detail: _periodLabel(_period),
        icon: Icons.pending_actions_outlined,
        accent: AppColors.chartBlue,
      ),
      _OrdonnancementKpiCard(
        title: 'Ordonnancees',
        value: _statsLoading ? '...' : '${stats.ordered}',
        subtitle: 'Montant total',
        detail: 'Notes validees',
        icon: Icons.fact_check_outlined,
        accent: AppColors.chartOrange,
      ),
      _OrdonnancementKpiCard(
        title: 'Rejetees',
        value: _statsLoading ? '...' : '${stats.rejected}',
        subtitle: 'Montant total',
        detail: 'Taxations annulees',
        icon: Icons.block_outlined,
        accent: AppColors.chartTeal,
      ),
      _OrdonnancementKpiCard(
        title: 'Montant ordonnance',
        value: _statsLoading ? '...' : _formatAmount(stats.orderedAmount),
        subtitle: 'Total sur la periode',
        detail: 'Ordonnancements',
        icon: Icons.payments_outlined,
        accent: AppColors.chartPurple,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: constraints.maxWidth < 520
                      ? constraints.maxWidth
                      : constraints.maxWidth - 252,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Synthese ordonnancement',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (_statsLoading)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                ),
                _buildPeriodSelector(),
              ],
            ),
            const SizedBox(height: 12),
            _buildMetricGrid(constraints.maxWidth, cards),
          ],
        );
      },
    );
  }

  Widget _buildFiltersPanel(BuildContext context) {
    final taxOptions = _distinctValues(
      (row) => row['tax_category']?.toString() ?? '',
    );
    final communeOptions = _distinctValues(_communeName);
    const statusOptions = [
      'taxation_creee',
      'ordonnee',
      'note_perception_generee',
      'paiement_declare',
      'en_recouvrement',
      'apuree_cpi_genere',
      'annulee',
    ];

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 300,
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Recherche',
                  hintText: 'N note, contribuable, taxe...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _taxFilter,
                decoration: const InputDecoration(
                  labelText: 'Type de taxe',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Toutes les taxes'),
                  ),
                  for (final tax in taxOptions)
                    DropdownMenuItem(value: tax, child: Text(tax)),
                ],
                onChanged: (value) => setState(() => _taxFilter = value),
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _communeFilter,
                decoration: const InputDecoration(
                  labelText: 'Commune',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Toutes les communes'),
                  ),
                  for (final commune in communeOptions)
                    DropdownMenuItem(value: commune, child: Text(commune)),
                ],
                onChanged: (value) => setState(() => _communeFilter = value),
              ),
            ),
            SizedBox(
              width: 210,
              child: DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _statusFilter,
                decoration: const InputDecoration(
                  labelText: 'Statut',
                  border: OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(_statusLabel(null)),
                  ),
                  for (final status in statusOptions)
                    DropdownMenuItem(
                      value: status,
                      child: Text(_statusLabel(status)),
                    ),
                ],
                onChanged: (value) => setState(() => _statusFilter = value),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () {
                _searchCtrl.clear();
                setState(() {
                  _taxFilter = null;
                  _communeFilter = null;
                  _statusFilter = 'taxation_creee';
                });
              },
              icon: const Icon(Icons.restart_alt_outlined),
              label: const Text('Reinitialiser'),
            ),
            FilledButton.icon(
              onPressed: _exporting ? null : _exportFilteredRows,
              icon: _exporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
              label: const Text('Exporter'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingPanel(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _filteredRows;
    if (_loading) return const Center(child: CircularProgressIndicator());
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
            Row(
              children: [
                Icon(Icons.fact_check_outlined, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Taxations a valider',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Actualiser',
                  onPressed: _loadPending,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              Text(
                'Aucune note ne correspond aux filtres.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final row in rows) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined),
                  title: Text(row['note_number']?.toString() ?? 'Note'),
                  subtitle: Text(
                    '${_communeName(row)} - ${row['taxpayer_name'] ?? 'Assujetti'} - ${_statusLabel(row['status']?.toString())}',
                  ),
                  trailing: Wrap(
                    spacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _money(row),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      FilledButton.icon(
                        onPressed:
                            _updatingId == row['id'] ||
                                row['status'] != 'taxation_creee'
                            ? null
                            : () => _openOrdonnancementDialog(row),
                        icon: _updatingId == row['id']
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check),
                        label: const Text('Verifier'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryPanel(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _historyRows;
    if (_loading || _error != null) return const SizedBox.shrink();

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history_outlined, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Historique des ordonnancements',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              Text(
                'Aucun ordonnancement dans votre perimetre.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('N note perception')),
                    DataColumn(label: Text('Contribuable')),
                    DataColumn(label: Text('Montant')),
                    DataColumn(label: Text('Banque')),
                    DataColumn(label: Text('Date')),
                    DataColumn(label: Text('Statut')),
                    DataColumn(label: Text('Ordonnateur')),
                  ],
                  rows: [
                    for (final row in rows)
                      DataRow(
                        cells: [
                          DataCell(Text(row['note_number']?.toString() ?? '-')),
                          DataCell(
                            Text(row['taxpayer_name']?.toString() ?? '-'),
                          ),
                          DataCell(Text(_money(row))),
                          DataCell(Text(_bankLabel(row))),
                          DataCell(Text(_dateTimeLabel(_rowDateTime(row)))),
                          DataCell(
                            Text(_statusLabel(row['status']?.toString())),
                          ),
                          DataCell(Text(_ordonnateurName(row))),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatsPanel(context),
          const SizedBox(height: 16),
          _buildFiltersPanel(context),
          const SizedBox(height: 16),
          _buildGeneratedNotePanel(context),
          if (_generatedNote != null) const SizedBox(height: 16),
          _buildPendingPanel(context),
          const SizedBox(height: 16),
          _buildHistoryPanel(context),
        ],
      ),
    );
  }
}

class _OrdonnancementKpiCard extends StatelessWidget {
  const _OrdonnancementKpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.detail,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String value;
  final String subtitle;
  final String detail;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = theme.colorScheme.surface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? surface : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.58)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.14 : 0.045),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.18 : 0.13),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 25),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.mutedText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
