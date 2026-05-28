import 'package:flutter/material.dart';

import '../branding/branding_scope.dart';
import '../data/sample_chart_data.dart';
import '../models/app_role.dart';
import '../models/user_profile.dart';
import '../services/collections_live_listener.dart';
import '../services/gestia_data_service.dart';
import '../theme/app_colors.dart';
import '../utils/cpi_exporter.dart';
import '../utils/error_messages.dart';
import '../utils/gestia_qr_payload.dart';
import '../widgets/gestia_qr_scanner_screen.dart';
import '../widgets/modern_section_panel.dart';

enum _TransactionRange { today, last7Days, last30Days, all }

enum _RecoveryScanTarget { cpi, perceptionNote }

enum _ApurementDecision { conforme, partiel, surpaiement, rejet }

enum _ApurementListView { ordered, paid, apured, toPay }

class _ApurementStats {
  const _ApurementStats({
    required this.pending,
    required this.apured,
    required this.recovery,
    required this.apuredAmount,
  });

  final int pending;
  final int apured;
  final int recovery;
  final double apuredAmount;
}

class CollecteScreen extends StatefulWidget {
  const CollecteScreen({
    super.key,
    required this.profile,
    this.focusRecoveryControlOnOpen = false,
    this.onRecoveryControlOpened,
  });

  final UserProfile profile;
  final bool focusRecoveryControlOnOpen;
  final VoidCallback? onRecoveryControlOpened;

  @override
  State<CollecteScreen> createState() => _CollecteScreenState();
}

class _CollecteScreenState extends State<CollecteScreen> {
  late CollectionsLiveListener _collectionsLiveListener;
  final _transactionSearchCtrl = TextEditingController();
  final _verificationIdCtrl = TextEditingController();
  final _verificationPanelKey = GlobalKey();

  List<TaxSlice> _slices = [];
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _apurementNotes = [];
  bool _loadingPie = true;
  bool _loadingTransactions = true;
  bool _loadingApurementStats = true;
  _ApurementListView? _selectedApurementList;
  String? _transactionsError;
  TaxpayerVerificationResult? _verificationResult;
  bool _loadingVerification = false;
  bool _addingReceiptType = false;
  String? _verificationError;
  int _paymentFormVersion = 0;

  _TransactionRange _range = _TransactionRange.all;
  String? _categoryFilter;
  String? _channelFilter;
  String? _communeFilter;

  String? get _scope =>
      widget.profile.role.isGlobalSupervisor ? null : widget.profile.communeId;
  String? get _taxpayerScope =>
      widget.profile.role == AppRole.contribuable ? widget.profile.id : null;
  bool get _showVerificationPanel =>
      widget.profile.role != AppRole.contribuable;

  List<Map<String, dynamic>> get _filteredTransactions {
    final query = _transactionSearchCtrl.text.trim().toLowerCase();

    final list =
        _transactions.where((row) {
            final matchesCategory =
                _categoryFilter == null ||
                _transactionCategory(row) == _categoryFilter;
            final matchesChannel =
                _channelFilter == null ||
                _transactionChannel(row) == _channelFilter;
            final matchesCommune =
                _communeFilter == null ||
                row['commune_id']?.toString() == _communeFilter;

            final matchesQuery =
                query.isEmpty ||
                [
                      _transactionCommuneName(row),
                      _transactionCategory(row),
                      _transactionChannel(row),
                      _transactionPerceptionNote(row),
                      _transactionCpiNumber(row),
                      _transactionTaxpayerId(row),
                      _formatMoney(_transactionAmount(row)),
                    ]
                    .map((value) => value.toLowerCase())
                    .any((value) => value.contains(query));

            return matchesCategory &&
                matchesChannel &&
                matchesCommune &&
                matchesQuery;
          }).toList()
          ..sort((a, b) => _transactionDate(b).compareTo(_transactionDate(a)));

    return list;
  }

  List<String> get _availableCategories {
    final values =
        _transactions
            .map(_transactionCategory)
            .where((value) => value.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return values;
  }

  List<String> get _availableChannels {
    final values =
        _transactions
            .map(_transactionChannel)
            .where((value) => value.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return values;
  }

  List<({String id, String name})> get _availableCommunes {
    final map = <String, String>{};
    for (final row in _transactions) {
      final id = row['commune_id']?.toString();
      if (id == null || id.isEmpty) continue;
      map[id] = _transactionCommuneName(row);
    }
    final list =
        map.entries.map((entry) => (id: entry.key, name: entry.value)).toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    return list;
  }

  _ApurementStats get _apurementStats {
    final pending = _apurementNotes.where((row) {
      final status = row['status']?.toString();
      return status == 'note_perception_generee' ||
          status == 'paiement_declare';
    }).length;
    final recovery = _apurementNotes
        .where((row) => row['status']?.toString() == 'en_recouvrement')
        .length;
    final apuredAmount = _transactions.fold<double>(
      0,
      (sum, row) => sum + _transactionAmount(row),
    );

    return _ApurementStats(
      pending: pending,
      apured: _transactions.length,
      recovery: recovery,
      apuredAmount: apuredAmount,
    );
  }

  List<Map<String, dynamic>> get _apurementPendingRows {
    final rows = _apurementRowsFor(_selectedApurementList).toList();
    rows.sort((a, b) => _noteDeadline(a).compareTo(_noteDeadline(b)));
    return rows;
  }

  Iterable<Map<String, dynamic>> _apurementRowsFor(_ApurementListView? view) {
    if (view == null) return const Iterable.empty();
    if (view == _ApurementListView.apured) {
      return _apurementNotes.where((row) {
        final status = row['status']?.toString();
        return status == 'apuree_cpi_genere';
      });
    }
    return _apurementNotes.where((row) {
      final status = row['status']?.toString();
      return switch (view) {
        _ApurementListView.ordered =>
          status == 'ordonnee' || status == 'note_perception_generee',
        _ApurementListView.paid => status == 'paiement_declare',
        _ApurementListView.toPay => status == 'note_perception_generee',
        _ApurementListView.apured => false,
        null => false,
      };
    });
  }

  @override
  void initState() {
    super.initState();
    _transactionSearchCtrl.addListener(_handleFilterChanged);
    _verificationIdCtrl.addListener(_handleFilterChanged);
    _startLiveUpdates();
    _loadPie();
    _loadTransactions();
    _loadApurementStats();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusRecoveryControlIfRequested();
    });
  }

  @override
  void didUpdateWidget(covariant CollecteScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final profileChanged =
        oldWidget.profile.id != widget.profile.id ||
        oldWidget.profile.role != widget.profile.role ||
        oldWidget.profile.communeId != widget.profile.communeId;
    if (profileChanged) {
      _collectionsLiveListener.dispose();
      _communeFilter = null;
      _verificationResult = null;
      _verificationError = null;
      _verificationIdCtrl.clear();
      _startLiveUpdates();
      _loadPie();
      _loadTransactions();
      _loadApurementStats();
    }
    if (!oldWidget.focusRecoveryControlOnOpen &&
        widget.focusRecoveryControlOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusRecoveryControlIfRequested();
      });
    }
  }

  @override
  void dispose() {
    _transactionSearchCtrl.removeListener(_handleFilterChanged);
    _verificationIdCtrl.removeListener(_handleFilterChanged);
    _transactionSearchCtrl.dispose();
    _verificationIdCtrl.dispose();
    _collectionsLiveListener.dispose();
    super.dispose();
  }

  void _startLiveUpdates() {
    _collectionsLiveListener = CollectionsLiveListener(
      profile: widget.profile,
      onCollectionInserted: () async {
        await _loadPie(silent: true);
        await _loadTransactions(silent: true);
        await _loadApurementStats(silent: true);
      },
    )..start();
  }

  void _handleFilterChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _handlePaymentSaved() {
    _loadPie();
    _loadTransactions();
    _loadApurementStats();
    if (_showVerificationPanel && _verificationIdCtrl.text.trim().isNotEmpty) {
      _runVerification(silent: true);
    }
  }

  Future<void> _showAddReceiptTypeDialog() async {
    if (!widget.profile.role.canManageApp || _addingReceiptType) return;

    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Ajouter un type de recette'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Type de recette',
              hintText: 'Ex: Amende administrative',
            ),
            onSubmitted: (text) => Navigator.of(dialogContext).pop(text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    final receiptType = value?.trim();
    if (receiptType == null || receiptType.isEmpty || !mounted) return;

    setState(() => _addingReceiptType = true);
    try {
      await GestiaDataService.addCustomReceiptType(receiptType);
      if (!mounted) return;
      setState(() => _paymentFormVersion++);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Type de recette ajoute: $receiptType')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _addingReceiptType = false);
    }
  }

  Future<void> _focusRecoveryControlIfRequested() async {
    if (!mounted || !widget.focusRecoveryControlOnOpen) return;
    if (!_showVerificationPanel) {
      widget.onRecoveryControlOpened?.call();
      return;
    }

    final targetContext = _verificationPanelKey.currentContext;
    if (targetContext != null) {
      await Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        alignment: 0.04,
      );
    }

    if (mounted) {
      widget.onRecoveryControlOpened?.call();
    }
  }

  Future<void> _runVerification({bool silent = false}) async {
    final identifier = _verificationIdCtrl.text.trim();
    if (identifier.isEmpty) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Entrez un identifiant à vérifier.')),
        );
      }
      return;
    }

    setState(() {
      _loadingVerification = true;
      _verificationError = null;
      if (!silent) {
        _verificationResult = null;
      }
    });

    try {
      final result = await GestiaDataService.verifyTaxPaymentByIdentifier(
        taxpayerIdentifier: identifier,
        communeId: _scope,
      );
      if (!mounted) return;
      setState(() {
        _verificationResult = result;
        _loadingVerification = false;
        _verificationError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingVerification = false;
        _verificationError = userFacingErrorMessage(e);
      });
    }
  }

  Future<void> _openRecoveryScannerMenu() async {
    final target = await showModalBottomSheet<_RecoveryScanTarget>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Scanner',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('Scanner CPI'),
                  onTap: () {
                    Navigator.of(sheetContext).pop(_RecoveryScanTarget.cpi);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Scanner note de perception'),
                  subtitle: const Text('Ce document n\'est pas une preuve.'),
                  onTap: () {
                    Navigator.of(
                      sheetContext,
                    ).pop(_RecoveryScanTarget.perceptionNote);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || target == null) return;
    await _scanRecoveryDocument(target);
  }

  Future<void> _scanRecoveryDocument(_RecoveryScanTarget target) async {
    final expectedType = target == _RecoveryScanTarget.cpi
        ? GestiaQrDocumentType.cpi
        : GestiaQrDocumentType.perceptionNote;
    final payload = await Navigator.of(context).push<GestiaQrPayloadData>(
      MaterialPageRoute(
        builder: (_) => GestiaQrScannerScreen(expectedType: expectedType),
      ),
    );

    if (!mounted || payload == null) return;

    final identifier = _qrControlIdentifier(payload);
    if (identifier.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'QR valide, mais il manque une reference exploitable. Regenerez le document.',
          ),
        ),
      );
      return;
    }

    await _showScannedDocumentDetails(payload);
  }

  String _qrControlIdentifier(GestiaQrPayloadData payload) {
    for (final value in [
      payload.taxpayerIdentifier,
      payload.perceptionNoteNumber ?? '',
      payload.reference,
    ]) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  Future<void> _showScannedDocumentDetails(GestiaQrPayloadData payload) async {
    final theme = Theme.of(context);
    final isCpi = payload.type == GestiaQrDocumentType.cpi;
    final isNote = payload.type == GestiaQrDocumentType.perceptionNote;
    final title = isCpi ? 'Informations du CPI' : 'Informations de la note';
    final rows = <({String label, String value, IconData icon})>[
      (
        label: 'Document',
        value: isCpi
            ? 'Certificat de paiement informatise'
            : 'Note de perception',
        icon: isCpi ? Icons.receipt_long_outlined : Icons.description_outlined,
      ),
      (
        label: isCpi ? 'Numero CPI' : 'Numero de note',
        value: payload.reference,
        icon: Icons.confirmation_number_outlined,
      ),
      (
        label: 'Date',
        value: _formatScannedDate(payload.generatedAtLabel),
        icon: Icons.event_outlined,
      ),
      (
        label: 'Montant',
        value: _formatScannedAmount(payload.amountUsdLabel),
        icon: Icons.payments_outlined,
      ),
      (
        label: 'Statut',
        value: payload.proofOfPayment
            ? 'Preuve de paiement'
            : 'Pas une preuve de paiement',
        icon: payload.proofOfPayment
            ? Icons.verified_outlined
            : Icons.info_outline,
      ),
      (
        label: 'Reference controle',
        value: _qrControlIdentifier(payload),
        icon: Icons.qr_code_2_outlined,
      ),
      if ((payload.perceptionNoteNumber ?? '').trim().isNotEmpty)
        (
          label: 'Note de perception',
          value: payload.perceptionNoteNumber!.trim(),
          icon: Icons.description_outlined,
        ),
      if ((payload.taxpayerName ?? '').trim().isNotEmpty)
        (
          label: 'Assujetti',
          value: payload.taxpayerName!.trim(),
          icon: Icons.person_outline,
        ),
      if (payload.taxpayerIdentifier.trim().isNotEmpty)
        (
          label: 'Identifiant',
          value: payload.taxpayerIdentifier.trim(),
          icon: Icons.badge_outlined,
        ),
      if ((payload.subjectLabel ?? '').trim().isNotEmpty)
        (
          label: isNote ? 'Acte juridique' : 'Acte / taxe',
          value: payload.subjectLabel!.trim(),
          icon: Icons.article_outlined,
        ),
      if ((payload.locationLabel ?? '').trim().isNotEmpty)
        (
          label: 'Lieu',
          value: payload.locationLabel!.trim(),
          icon: Icons.location_on_outlined,
        ),
      if ((payload.paymentChannel ?? '').trim().isNotEmpty)
        (
          label: 'Canal',
          value: payload.paymentChannel!.trim(),
          icon: Icons.account_balance_wallet_outlined,
        ),
      if ((payload.agentName ?? '').trim().isNotEmpty)
        (
          label: isNote ? 'Taxateur' : 'Agent',
          value: payload.agentName!.trim(),
          icon: Icons.work_outline,
        ),
      if ((payload.paymentDelayLabel ?? '').trim().isNotEmpty)
        (
          label: 'Delai de paiement',
          value: payload.paymentDelayLabel!.trim(),
          icon: Icons.timer_outlined,
        ),
      if ((payload.deadlineLabel ?? '').trim().isNotEmpty)
        (
          label: 'Echeance',
          value: payload.deadlineLabel!.trim(),
          icon: Icons.event_available_outlined,
        ),
      (
        label: 'Verification',
        value: payload.signed ? 'QR signe GESTIA' : 'Ancien format GESTIA',
        icon: Icons.security_outlined,
      ),
    ].where((row) => row.value.trim().isNotEmpty).toList(growable: false);

    final detailRows = rows
        .where(
          (row) =>
              !{'Document', 'Date', 'Montant', 'Statut'}.contains(row.label),
        )
        .toList(growable: false);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.78,
          minChildSize: 0.44,
          maxChildSize: 0.94,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                20 + MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              children: [
                _buildScannedDocumentHeader(
                  context,
                  title: title,
                  payload: payload,
                  isCpi: isCpi,
                ),
                const SizedBox(height: 16),
                _buildScannedDocumentSummary(context, payload),
                if (!payload.proofOfPayment) ...[
                  const SizedBox(height: 12),
                  _buildScannedWarning(context),
                ],
                const SizedBox(height: 18),
                Text(
                  'Details',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 620;
                    final halfWidth = (constraints.maxWidth - 12) / 2;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final row in detailRows)
                          _buildScannedInfoTile(
                            context,
                            row: row,
                            width: narrow || _shouldSpanScannedTile(row)
                                ? constraints.maxWidth
                                : halfWidth,
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: const Icon(Icons.check),
                    label: const Text('Fermer'),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildScannedDocumentHeader(
    BuildContext context, {
    required String title,
    required GestiaQrPayloadData payload,
    required bool isCpi,
  }) {
    final theme = Theme.of(context);
    final statusColor = payload.proofOfPayment
        ? AppColors.chartTeal
        : AppColors.chartOrange;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            isCpi ? Icons.receipt_long_outlined : Icons.description_outlined,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildScannedChip(
                    context,
                    label: payload.signed ? 'QR signe GESTIA' : 'Ancien QR',
                    icon: Icons.security_outlined,
                    color: AppColors.primary,
                  ),
                  _buildScannedChip(
                    context,
                    label: payload.proofOfPayment ? 'Paiement' : 'Non paiement',
                    icon: payload.proofOfPayment
                        ? Icons.verified_outlined
                        : Icons.info_outline,
                    color: statusColor,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildScannedDocumentSummary(
    BuildContext context,
    GestiaQrPayloadData payload,
  ) {
    final theme = Theme.of(context);
    final amount = _formatScannedAmount(payload.amountUsdLabel);
    final date = _formatScannedDate(payload.generatedAtLabel);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            payload.reference,
            softWrap: true,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildScannedMetric(
                context,
                label: 'Montant',
                value: amount,
                icon: Icons.payments_outlined,
              ),
              _buildScannedMetric(
                context,
                label: 'Date',
                value: date,
                icon: Icons.event_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScannedMetric(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 260),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value.isEmpty ? 'Non renseigne' : value,
              softWrap: true,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScannedWarning(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.chartOrange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.chartOrange.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: AppColors.chartOrange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Ce document n est pas une preuve de paiement.',
              softWrap: true,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannedInfoTile(
    BuildContext context, {
    required ({String label, String value, IconData icon}) row,
    required double width,
  }) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.34,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(row.icon, size: 20, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    row.value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScannedChip(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  bool _shouldSpanScannedTile(
    ({String label, String value, IconData icon}) row,
  ) {
    return row.value.length > 44 ||
        row.label == 'Acte / taxe' ||
        row.label == 'Acte juridique' ||
        row.label == 'Lieu' ||
        row.label == 'Reference controle';
  }

  String _formatScannedAmount(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return '';
    if (clean.toLowerCase().contains('usd')) return clean;
    return '$clean USD';
  }

  String _formatScannedDate(String value) {
    final clean = value.trim();
    if (RegExp(r'^\d{10}$').hasMatch(clean)) {
      return '${clean.substring(0, 2)}/${clean.substring(2, 4)}/20${clean.substring(4, 6)} '
          '${clean.substring(6, 8)}:${clean.substring(8, 10)}';
    }
    if (RegExp(r'^\d{12}$').hasMatch(clean)) {
      return '${clean.substring(6, 8)}/${clean.substring(4, 6)}/${clean.substring(0, 4)} '
          '${clean.substring(8, 10)}:${clean.substring(10, 12)}';
    }
    return clean;
  }

  ({DateTime from, DateTime to}) _rangeBounds() {
    final now = DateTime.now();
    switch (_range) {
      case _TransactionRange.today:
        final start = DateTime(now.year, now.month, now.day);
        return (from: start, to: now);
      case _TransactionRange.last7Days:
        return (from: now.subtract(const Duration(days: 7)), to: now);
      case _TransactionRange.last30Days:
        return (from: now.subtract(const Duration(days: 30)), to: now);
      case _TransactionRange.all:
        return (from: DateTime(2000), to: now);
    }
  }

  String _rangeLabel(_TransactionRange range) {
    switch (range) {
      case _TransactionRange.today:
        return 'Aujourd hui';
      case _TransactionRange.last7Days:
        return '7 jours';
      case _TransactionRange.last30Days:
        return '30 jours';
      case _TransactionRange.all:
        return 'Tout';
    }
  }

  Widget _dropdownLabel(String value) {
    return Text(value, maxLines: 1, overflow: TextOverflow.ellipsis);
  }

  Future<void> _loadPie({bool silent = false}) async {
    if (!silent) {
      setState(() => _loadingPie = true);
    }
    try {
      final tax = await GestiaDataService.taxBreakdownLast30Days(
        communeId: _scope,
        taxpayerProfileId: _taxpayerScope,
      );
      if (!mounted) return;
      setState(() {
        _slices = tax;
        _loadingPie = false;
      });
    } catch (_) {
      if (!mounted || silent) return;
      setState(() => _loadingPie = false);
    }
  }

  Future<void> _loadTransactions({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loadingTransactions = true;
        _transactionsError = null;
      });
    }

    try {
      final bounds = _rangeBounds();
      final rows = await GestiaDataService.fetchCollectionsInRange(
        from: bounds.from,
        to: bounds.to,
        communeId: _scope,
        taxpayerProfileId: _taxpayerScope,
      );
      if (!mounted) return;
      setState(() {
        _transactions = rows;
        _loadingTransactions = false;
        _transactionsError = null;

        if (_categoryFilter != null &&
            !_availableCategories.contains(_categoryFilter)) {
          _categoryFilter = null;
        }
        if (_channelFilter != null &&
            !_availableChannels.contains(_channelFilter)) {
          _channelFilter = null;
        }
        if (_communeFilter != null &&
            !_availableCommunes.any(
              (commune) => commune.id == _communeFilter,
            )) {
          _communeFilter = null;
        }
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _loadingTransactions = false;
        _transactionsError = userFacingErrorMessage(e);
      });
    }
  }

  Future<void> _loadApurementStats({bool silent = false}) async {
    if (!silent) {
      setState(() => _loadingApurementStats = true);
    }

    try {
      final bounds = _rangeBounds();
      final rows = await GestiaDataService.fetchPerceptionNotes(
        statuses: const [
          'ordonnee',
          'note_perception_generee',
          'paiement_declare',
          'en_recouvrement',
          'apuree_cpi_genere',
        ],
        communeId: _scope,
        createdFrom: _range == _TransactionRange.all ? null : bounds.from,
        createdTo: _range == _TransactionRange.all ? null : bounds.to,
        limit: 5000,
      );
      final scopedRows = _taxpayerScope == null
          ? rows
          : rows
                .where(
                  (row) =>
                      row['taxpayer_profile_id']?.toString() == _taxpayerScope,
                )
                .toList();
      if (!mounted) return;
      setState(() {
        _apurementNotes = scopedRows;
        _loadingApurementStats = false;
      });
    } catch (_) {
      if (!mounted || silent) return;
      setState(() => _loadingApurementStats = false);
    }
  }

  String _transactionCommuneName(Map<String, dynamic> row) {
    final scope = row['collection_scope']?.toString().trim().toLowerCase();
    if (scope == 'mairie') {
      return 'Mairie';
    }
    final commune = row['communes'];
    if (commune is Map && commune['name'] != null) {
      return commune['name'].toString();
    }
    return 'Sans commune';
  }

  String _transactionCategory(Map<String, dynamic> row) {
    final value = row['tax_category']?.toString().trim();
    return value == null || value.isEmpty ? 'Autres' : value;
  }

  String _transactionChannel(Map<String, dynamic> row) {
    final value = row['payment_channel']?.toString().trim();
    return value == null || value.isEmpty ? 'Non precisé' : value;
  }

  String _transactionTaxpayerId(Map<String, dynamic> row) {
    final value = row['taxpayer_identifier']?.toString().trim();
    return value == null || value.isEmpty ? '-' : value;
  }

  String _transactionPerceptionNote(Map<String, dynamic> row) {
    final value = row['perception_note_number']?.toString().trim();
    return value == null || value.isEmpty ? '-' : value;
  }

  String _transactionCpiNumber(Map<String, dynamic> row) {
    final value = row['cpi_number']?.toString().trim();
    return value == null || value.isEmpty ? '-' : value;
  }

  String _transactionStatusLabel(Map<String, dynamic> row) {
    final value = row['workflow_status']?.toString().trim();
    return switch (value) {
      'apuree_cpi_genere' => 'Apuree',
      'paiement_declare' => 'Paiement declare',
      'en_recouvrement' => 'En recouvrement',
      'ordonnee' => 'Ordonnee',
      'taxation_creee' => 'A ordonnancer',
      null || '' => '-',
      _ => value,
    };
  }

  DateTime _noteDeadline(Map<String, dynamic> row) {
    final raw = row['payment_deadline']?.toString();
    if (raw == null || raw.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.tryParse(raw)?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _noteCommuneName(Map<String, dynamic> row) {
    final scope = row['collection_scope']?.toString().trim().toLowerCase();
    if (scope == 'mairie') return 'Mairie';
    final commune = row['communes'];
    if (commune is Map && commune['name'] != null) {
      return commune['name'].toString();
    }
    return 'Sans commune';
  }

  String _noteStatusLabel(String? status) {
    return switch (status) {
      'note_perception_generee' => 'A apurer',
      'paiement_declare' => 'Paiement declare',
      'en_recouvrement' => 'En recouvrement',
      'apuree_cpi_genere' => 'Apuree',
      _ => status ?? '-',
    };
  }

  String _apurementDecisionLabel(_ApurementDecision decision) {
    return switch (decision) {
      _ApurementDecision.conforme => 'Paiement conforme',
      _ApurementDecision.partiel => 'Paiement partiel',
      _ApurementDecision.surpaiement => 'Surpaiement',
      _ApurementDecision.rejet => 'Rejet',
    };
  }

  String _agencyFromChannel(String channel) {
    final lower = channel.toLowerCase();
    if (lower.contains('mobile')) return 'Operateur mobile money';
    if (lower.contains('carte') || lower.contains('visa')) {
      return 'Paiement par carte';
    }
    return 'Banque partenaire';
  }

  String _generateApurementCpiNumber(DateTime date) {
    final stamp =
        '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    final millis = date.millisecondsSinceEpoch.toString();
    return 'CPI-$stamp-${millis.substring(millis.length - 5)}';
  }

  String _firstNotEmpty(List<String> values) {
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  String _ordonnancementPaymentChannel(Map<String, dynamic> row) {
    final value = row['payment_channel']?.toString().trim() ?? '';
    return value.isEmpty ? 'Non precise' : value;
  }

  String _ordonnancementPaymentReference(Map<String, dynamic> row) {
    return _firstNotEmpty([
      row['receiver_account']?.toString() ?? '',
      row['bank_name']?.toString() ?? '',
      row['note_number']?.toString() ?? '',
    ]);
  }

  double _transactionAmount(Map<String, dynamic> row) {
    return (row['amount'] as num?)?.toDouble() ?? 0;
  }

  DateTime _transactionDate(Map<String, dynamic> row) {
    final raw = row['collected_at']?.toString();
    if (raw == null || raw.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.parse(raw).toLocal();
  }

  String _formatMoney(double value) {
    final source = value.toStringAsFixed(0);
    final buffer = StringBuffer();
    for (var i = 0; i < source.length; i++) {
      if (i > 0 && (source.length - i) % 3 == 0) {
        buffer.write(' ');
      }
      buffer.write(source[i]);
    }
    return '$buffer \$';
  }

  String _formatDateTime(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month/$year - $hour:$minute';
  }

  Color _categoryColor(String category) {
    final lower = category.toLowerCase();
    if (lower.contains('march')) return AppColors.chartTeal;
    if (lower.contains('permis') || lower.contains('licence')) {
      return AppColors.chartPurple;
    }
    if (lower.contains('station')) return AppColors.chartOrange;
    return AppColors.primary;
  }

  Widget _buildTableBadge(BuildContext context, String label, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  int _apurementMetricColumns(double width) {
    if (width >= 1100) return 4;
    if (width >= 700) return 2;
    return 1;
  }

  Widget _buildApurementMetricGrid(double width, List<Widget> cards) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _apurementMetricColumns(width),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: 104,
      ),
      itemBuilder: (context, index) => cards[index],
    );
  }

  Widget _buildApurementStatsPanel(BuildContext context) {
    final orderedCount = _apurementRowsFor(_ApurementListView.ordered).length;
    final paidCount = _apurementRowsFor(_ApurementListView.paid).length;
    final apuredCount = _apurementRowsFor(_ApurementListView.apured).length;
    final toPayCount = _apurementRowsFor(_ApurementListView.toPay).length;
    final cards = <Widget>[
      _ApurementKpiCard(
        title: 'Notes ordonnancees',
        value: _loadingApurementStats ? '...' : '$orderedCount',
        subtitle: 'Liste des notes',
        detail: _rangeLabel(_range),
        icon: Icons.pending_actions_outlined,
        accent: AppColors.chartBlue,
        selected: _selectedApurementList == _ApurementListView.ordered,
        onTap: () => _toggleApurementList(_ApurementListView.ordered),
      ),
      _ApurementKpiCard(
        title: 'Notes payees',
        value: _loadingApurementStats ? '...' : '$paidCount',
        subtitle: 'Paiements declares',
        detail: _rangeLabel(_range),
        icon: Icons.payments_outlined,
        accent: AppColors.chartTeal,
        selected: _selectedApurementList == _ApurementListView.paid,
        onTap: () => _toggleApurementList(_ApurementListView.paid),
      ),
      _ApurementKpiCard(
        title: 'Notes apurees',
        value: _loadingApurementStats ? '...' : '$apuredCount',
        subtitle: 'CPI generes',
        detail: _rangeLabel(_range),
        icon: Icons.fact_check_outlined,
        accent: AppColors.chartOrange,
        selected: _selectedApurementList == _ApurementListView.apured,
        onTap: () => _toggleApurementList(_ApurementListView.apured),
      ),
      _ApurementKpiCard(
        title: 'Notes a payer',
        value: _loadingApurementStats ? '...' : '$toPayCount',
        subtitle: 'Pas encore payees',
        detail: _rangeLabel(_range),
        icon: Icons.receipt_long_outlined,
        accent: AppColors.chartPurple,
        selected: _selectedApurementList == _ApurementListView.toPay,
        onTap: () => _toggleApurementList(_ApurementListView.toPay),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        return _buildApurementMetricGrid(constraints.maxWidth, cards);
      },
    );
  }

  void _toggleApurementList(_ApurementListView view) {
    setState(() {
      _selectedApurementList = _selectedApurementList == view ? null : view;
    });
  }

  Widget _buildApurementPendingPanel(BuildContext context) {
    final theme = Theme.of(context);
    final selectedList = _selectedApurementList;
    if (selectedList == null) {
      return const SizedBox.shrink();
    }
    final rows = _apurementPendingRows;

    if (_loadingApurementStats) {
      return const Center(child: CircularProgressIndicator());
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
                    _apurementListTitle(selectedList),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Actualiser',
                  onPressed: _loadApurementStats,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              Text(
                _apurementListEmptyLabel(selectedList),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final row in rows) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(row['note_number']?.toString() ?? 'Note'),
                  subtitle: Text(
                    '${_noteCommuneName(row)} - ${row['taxpayer_name'] ?? 'Assujetti'} - ${_noteStatusLabel(row['status']?.toString())}',
                  ),
                  trailing: Wrap(
                    spacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _formatMoney((row['amount'] as num?)?.toDouble() ?? 0),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: selectedList == _ApurementListView.apured
                            ? null
                            : () => _openApurementDialog(row),
                        icon: const Icon(Icons.payments_outlined),
                        label: Text(
                          selectedList == _ApurementListView.apured
                              ? 'Apuree'
                              : 'Apurer',
                        ),
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

  String _apurementListTitle(_ApurementListView view) {
    return switch (view) {
      _ApurementListView.ordered => 'Liste des notes ordonnancees',
      _ApurementListView.paid => 'Liste des notes payees',
      _ApurementListView.apured => 'Liste des notes apurees',
      _ApurementListView.toPay => 'Liste des notes a payer',
    };
  }

  String _apurementListEmptyLabel(_ApurementListView view) {
    return switch (view) {
      _ApurementListView.ordered => 'Aucune note ordonnancee dans ce perimetre.',
      _ApurementListView.paid => 'Aucune note payee en attente.',
      _ApurementListView.apured => 'Aucune note apuree pour cette periode.',
      _ApurementListView.toPay => 'Aucune note a payer dans ce perimetre.',
    };
  }

  Future<void> _openApurementDialog(Map<String, dynamic> row) async {
    final expected = (row['amount'] as num?)?.toDouble() ?? 0;
    final amountCtrl = TextEditingController(text: expected.toStringAsFixed(2));
    final channel = _ordonnancementPaymentChannel(row);
    final paymentReference = _ordonnancementPaymentReference(row);
    var paidAt = DateTime.now();
    var decision = _ApurementDecision.conforme;
    var submitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final amountReceived =
                double.tryParse(amountCtrl.text.trim().replaceAll(',', '.')) ??
                0;
            final isRejected = decision == _ApurementDecision.rejet;
            final canSubmit = !submitting && (isRejected || amountReceived > 0);

            return AlertDialog(
              title: const Text('Detail de l ordonnancement'),
              content: SizedBox(
                width: 760,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildApurementDetailSummary(row, amountReceived, paidAt),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: 220,
                            child: TextField(
                              controller: amountCtrl,
                              enabled: !isRejected,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              onChanged: (_) => setDialogState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'Montant recu',
                                suffixText: 'USD',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Ref. paiement',
                                prefixIcon: Icon(Icons.numbers_outlined),
                                border: OutlineInputBorder(),
                              ),
                              child: Text(
                                paymentReference.isEmpty
                                    ? '-'
                                    : paymentReference,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Canal',
                                prefixIcon: Icon(Icons.payments_outlined),
                                border: OutlineInputBorder(),
                              ),
                              child: Text(channel),
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: OutlinedButton.icon(
                              onPressed: isRejected
                                  ? null
                                  : () async {
                                      final selected = await showDatePicker(
                                        context: context,
                                        initialDate: paidAt,
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime.now().add(
                                          const Duration(days: 1),
                                        ),
                                      );
                                      if (selected == null) return;
                                      setDialogState(() {
                                        paidAt = DateTime(
                                          selected.year,
                                          selected.month,
                                          selected.day,
                                          paidAt.hour,
                                          paidAt.minute,
                                        );
                                      });
                                    },
                              icon: const Icon(Icons.event_outlined),
                              label: Text(_formatDateTime(paidAt)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Option d apurement',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final option in _ApurementDecision.values)
                            ChoiceChip(
                              label: Text(_apurementDecisionLabel(option)),
                              selected: decision == option,
                              onSelected: (_) {
                                setDialogState(() => decision = option);
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Annuler'),
                ),
                FilledButton.icon(
                  onPressed: canSubmit
                      ? () async {
                          setDialogState(() => submitting = true);
                          final ok = await _submitApurement(
                            row: row,
                            amountReceived: amountReceived,
                            paymentReference: paymentReference,
                            channel: channel,
                            paidAt: paidAt,
                            decision: decision,
                          );
                          if (!context.mounted) return;
                          if (ok) {
                            Navigator.of(dialogContext).pop();
                          } else {
                            setDialogState(() => submitting = false);
                          }
                        }
                      : null,
                  icon: submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.receipt_long_outlined),
                  label: Text(
                    decision == _ApurementDecision.rejet
                        ? 'Rejeter'
                        : 'Generer le justificatif',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    amountCtrl.dispose();
  }

  Widget _buildApurementDetailSummary(
    Map<String, dynamic> row,
    double amountReceived,
    DateTime paidAt,
  ) {
    final expected = (row['amount'] as num?)?.toDouble() ?? 0;
    final paymentReference = _ordonnancementPaymentReference(row);
    final lines = <({String label, String value})>[
      (
        label: 'N note de perception',
        value: row['note_number']?.toString() ?? '-',
      ),
      (label: 'Contribuable', value: row['taxpayer_name']?.toString() ?? '-'),
      (
        label: 'Ref. paiement',
        value: paymentReference.isEmpty ? '-' : paymentReference,
      ),
      (label: 'Canal', value: _ordonnancementPaymentChannel(row)),
      (label: 'Montant attendu', value: _formatMoney(expected)),
      (label: 'Montant recu', value: _formatMoney(amountReceived)),
      (label: 'Date de paiement', value: _formatDateTime(paidAt)),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(
                      line.label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      line.value,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
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

  Future<bool> _submitApurement({
    required Map<String, dynamic> row,
    required double amountReceived,
    required String paymentReference,
    required String channel,
    required DateTime paidAt,
    required _ApurementDecision decision,
  }) async {
    final id = row['id']?.toString();
    final noteNumber = row['note_number']?.toString().trim() ?? '';
    if (id == null || id.isEmpty || noteNumber.isEmpty) return false;

    try {
      if (decision == _ApurementDecision.rejet) {
        await GestiaDataService.updatePerceptionNoteStatus(
          noteId: id,
          status: 'annulee',
        );
        await _loadApurementStats();
        await _loadTransactions();
        if (!mounted) return true;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ordonnancement rejete.')));
        return true;
      }

      final cpiNumber = _generateApurementCpiNumber(paidAt);
      final fullPayment =
          decision == _ApurementDecision.conforme ||
          decision == _ApurementDecision.surpaiement;
      final workflowStatus = fullPayment
          ? 'apuree_cpi_genere'
          : 'paiement_declare';
      final noteStatus = fullPayment ? 'apuree_cpi_genere' : 'paiement_declare';
      final taxpayerIdentifier =
          row['taxpayer_identifier']?.toString().trim() ?? '';
      final verificationIdentifier = _firstNotEmpty([
        paymentReference,
        taxpayerIdentifier,
        noteNumber,
        cpiNumber,
      ]);

      await GestiaDataService.insertCollection(
        communeId: row['commune_id']?.toString(),
        amountUsd: amountReceived,
        taxCategory: row['tax_category']?.toString() ?? 'Apurement',
        paymentChannel: channel,
        collectionScope: row['collection_scope']?.toString() ?? 'commune',
        taxpayerProfileId: row['taxpayer_profile_id']?.toString(),
        taxpayerIdentifier: taxpayerIdentifier.isNotEmpty
            ? taxpayerIdentifier
            : verificationIdentifier,
        perceptionNoteNumber: noteNumber,
        cpiNumber: cpiNumber,
        revenuePhase: 'apurement',
        workflowStatus: workflowStatus,
        paidAt: paidAt,
        apuredAt: fullPayment ? DateTime.now() : null,
        isAutoLiquidated: false,
      );

      await GestiaDataService.updatePerceptionNoteStatus(
        noteId: id,
        status: noteStatus,
        cpiNumber: cpiNumber,
        paidAt: paidAt,
        apuredAt: fullPayment ? DateTime.now() : null,
        paymentChannel: channel,
      );

      final cpi = _buildApurementCpiData(
        row: row,
        amountReceived: amountReceived,
        cpiNumber: cpiNumber,
        paidAt: paidAt,
        channel: channel,
        verificationIdentifier: verificationIdentifier,
      );
      final path = await CpiExporter.exportPdf(cpi);

      await _loadApurementStats();
      await _loadTransactions();
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            path == null || path.isEmpty
                ? 'Apurement enregistre. Export annule.'
                : fullPayment
                ? 'CPI genere: $path'
                : 'Quittance generee: $path',
          ),
        ),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(e))));
      return false;
    }
  }

  CpiData _buildApurementCpiData({
    required Map<String, dynamic> row,
    required double amountReceived,
    required String cpiNumber,
    required DateTime paidAt,
    required String channel,
    required String verificationIdentifier,
  }) {
    final branding = BrandingScope.of(context);
    final taxpayerName = row['taxpayer_name']?.toString().trim() ?? '';
    final taxpayerIdentifier =
        row['taxpayer_identifier']?.toString().trim() ?? '';
    final taxpayerAddress = row['taxpayer_address']?.toString().trim() ?? '';
    final taxpayerPhone = row['taxpayer_phone']?.toString().trim() ?? '';
    final actLabel = row['tax_category']?.toString().trim() ?? 'Apurement';

    return CpiData(
      provinceName: branding.provinceName,
      cpiNumber: cpiNumber,
      generatedAt: paidAt,
      perceptionNoteNumber: row['note_number']?.toString() ?? '',
      taxpayerName: taxpayerName.isEmpty ? 'Contribuable' : taxpayerName,
      taxpayerDenomination: taxpayerName.isEmpty
          ? 'Contribuable'
          : taxpayerName,
      taxpayerIdentifier: taxpayerIdentifier,
      verificationIdentifier: verificationIdentifier,
      taxpayerPhone: taxpayerPhone,
      taxpayerEmail: row['taxpayer_email']?.toString() ?? '',
      taxpayerAddress: taxpayerAddress,
      communeName: _noteCommuneName(row),
      natureActe: actLabel,
      exercise: paidAt.year,
      actName: actLabel,
      periodicity: 'Ponctuel',
      actCount: 1,
      rateUsd: amountReceived,
      amountUsd: amountReceived,
      paymentMode: channel,
      agency: _agencyFromChannel(channel),
      agentName: widget.profile.fullName,
    );
  }

  Widget _buildTransactionsTable(
    BuildContext context,
    List<Map<String, dynamic>> rows,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: theme.colorScheme.surface.withValues(
          alpha: isDark ? 0.92 : 0.98,
        ),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 1180),
          child: DataTable(
            columnSpacing: 22,
            dataRowMinHeight: 66,
            dataRowMaxHeight: 78,
            headingRowHeight: 54,
            columns: const [
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('N note perception')),
              DataColumn(label: Text('CPI')),
              DataColumn(label: Text('Commune')),
              DataColumn(label: Text('Categorie')),
              DataColumn(label: Text('Canal')),
              DataColumn(label: Text('ID contribuable')),
              DataColumn(label: Text('Statut')),
              DataColumn(
                label: Align(
                  alignment: Alignment.centerRight,
                  child: Text('Montant'),
                ),
                numeric: true,
              ),
            ],
            rows: [
              for (final row in rows)
                DataRow(
                  cells: [
                    DataCell(
                      Text(
                        _formatDateTime(_transactionDate(row)),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    DataCell(Text(_transactionPerceptionNote(row))),
                    DataCell(Text(_transactionCpiNumber(row))),
                    DataCell(
                      Text(
                        _transactionCommuneName(row),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    DataCell(
                      _buildTableBadge(
                        context,
                        _transactionCategory(row),
                        _categoryColor(_transactionCategory(row)),
                      ),
                    ),
                    DataCell(
                      _buildTableBadge(
                        context,
                        _transactionChannel(row),
                        AppColors.chartOrange,
                      ),
                    ),
                    DataCell(
                      Text(
                        _transactionTaxpayerId(row),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    DataCell(
                      _buildTableBadge(
                        context,
                        _transactionStatusLabel(row),
                        AppColors.chartTeal,
                      ),
                    ),
                    DataCell(
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          _formatMoney(_transactionAmount(row)),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _verificationScopeLabel() {
    if (_scope == null) return 'Toutes les communes';
    return widget.profile.communeName ?? 'Commune courante';
  }

  String _collectorName(
    Map<String, dynamic> row,
    TaxpayerVerificationResult result,
  ) {
    final createdBy = row['created_by']?.toString().trim();
    if (createdBy != null && createdBy.isNotEmpty) {
      final mappedName = result.collectorNames[createdBy]?.trim();
      if (mappedName != null && mappedName.isNotEmpty) {
        return mappedName;
      }

      if (createdBy == widget.profile.id) {
        return widget.profile.fullName;
      }

      final taxpayerProfileId = row['taxpayer_profile_id']?.toString().trim();
      if (result.profile != null &&
          taxpayerProfileId != null &&
          taxpayerProfileId.isNotEmpty &&
          taxpayerProfileId == createdBy &&
          result.profile!.id == createdBy) {
        return result.profile!.fullName;
      }
    }

    return 'Non disponible';
  }

  Widget _buildVerificationInfoTile(
    BuildContext context, {
    required String label,
    required String value,
    IconData? icon,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      constraints: const BoxConstraints(minWidth: 180),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: cs.surface.withValues(alpha: isDark ? 0.88 : 0.96),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.42)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationTable(
    BuildContext context,
    TaxpayerVerificationResult result,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: theme.colorScheme.surface.withValues(
          alpha: isDark ? 0.92 : 0.98,
        ),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 1180),
          child: DataTable(
            columnSpacing: 22,
            dataRowMinHeight: 66,
            dataRowMaxHeight: 78,
            headingRowHeight: 54,
            columns: const [
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Commune')),
              DataColumn(label: Text('Taxe')),
              DataColumn(label: Text('Canal')),
              DataColumn(label: Text('Encaisse par')),
              DataColumn(
                label: Align(
                  alignment: Alignment.centerRight,
                  child: Text('Montant'),
                ),
                numeric: true,
              ),
            ],
            rows: [
              for (final row in result.collections)
                DataRow(
                  cells: [
                    DataCell(
                      Text(
                        _formatDateTime(_transactionDate(row)),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        _transactionCommuneName(row),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    DataCell(
                      _buildTableBadge(
                        context,
                        _transactionCategory(row),
                        _categoryColor(_transactionCategory(row)),
                      ),
                    ),
                    DataCell(
                      _buildTableBadge(
                        context,
                        _transactionChannel(row),
                        AppColors.chartOrange,
                      ),
                    ),
                    DataCell(
                      Text(
                        _collectorName(row, result),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    DataCell(
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          _formatMoney(_transactionAmount(row)),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVerificationPanel(BuildContext context) {
    final result = _verificationResult;
    final theme = Theme.of(context);
    final statusColor = result?.hasRegisteredPayment == true
        ? AppColors.chartTeal
        : AppColors.chartRed;
    final profile = result?.profile;
    final lastPaymentLabel = result?.lastPaymentAt != null
        ? _formatDateTime(result!.lastPaymentAt!)
        : 'Aucun';

    return ModernSectionPanel(
      title: 'Controle de recouvrement',
      subtitle:
          'Saisissez un identifiant contribuable pour vérifier si un paiement est enregistré et afficher les informations disponibles.',
      eyebrow: 'Vérification',
      accentColor: AppColors.chartOrange,
      action: FilledButton.tonalIcon(
        onPressed: _loadingVerification ? null : () => _runVerification(),
        icon: const Icon(Icons.search),
        label: const Text('Vérifier'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ModernInfoPill(
                label: 'Perimetre',
                value: _verificationScopeLabel(),
                icon: Icons.location_on_outlined,
                color: AppColors.chartOrange,
              ),
              if (result != null)
                ModernInfoPill(
                  label: 'Statut',
                  value: result.hasRegisteredPayment
                      ? 'Paiement enregistré'
                      : 'Aucun paiement',
                  icon: result.hasRegisteredPayment
                      ? Icons.verified_outlined
                      : Icons.error_outline,
                  color: statusColor,
                ),
              if (result != null)
                ModernInfoPill(
                  label: 'Transactions',
                  value: '${result.paymentCount}',
                  icon: Icons.receipt_long_outlined,
                  color: AppColors.primary,
                ),
              if (result != null)
                ModernInfoPill(
                  label: 'Total visible',
                  value: _formatMoney(result.totalAmount),
                  icon: Icons.payments_outlined,
                  color: AppColors.chartTeal,
                ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 760;
              final field = TextField(
                controller: _verificationIdCtrl,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _runVerification(),
                decoration: InputDecoration(
                  labelText: 'Identifiant contribuable',
                  hintText: 'Ex: CTB-0001',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.badge_outlined),
                  suffixIcon: _verificationIdCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _verificationIdCtrl.clear();
                            setState(() {
                              _verificationResult = null;
                              _verificationError = null;
                            });
                          },
                          icon: const Icon(Icons.close),
                        ),
                ),
              );
              final button = SizedBox(
                height: 56,
                child: FilledButton.icon(
                  onPressed: _loadingVerification
                      ? null
                      : () => _runVerification(),
                  icon: _loadingVerification
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: Text(
                    _loadingVerification
                        ? 'Vérification...'
                        : 'Lancer le controle',
                  ),
                ),
              );
              final scannerButton = SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _loadingVerification
                      ? null
                      : _openRecoveryScannerMenu,
                  icon: const Icon(Icons.qr_code_scanner_outlined),
                  label: const Text('Scanner'),
                ),
              );
              final actions = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [scannerButton, const SizedBox(height: 8), button],
              );

              if (stacked) {
                return Column(
                  children: [
                    field,
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity, child: actions),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: field),
                  const SizedBox(width: 12),
                  SizedBox(width: 224, child: actions),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          if (_loadingVerification)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_verificationError != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.58),
              ),
              child: Text(_verificationError!),
            )
          else if (result == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.32,
                ),
              ),
              child: Text(
                'Entrez un identifiant pour verifier rapidement le statut de paiement et retrouver toutes les informations du contribuable.',
                style: theme.textTheme.bodyMedium,
              ),
            )
          else ...[
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildVerificationInfoTile(
                  context,
                  label: 'Identifiant',
                  value: result.taxpayerIdentifier,
                  icon: Icons.badge_outlined,
                ),
                _buildVerificationInfoTile(
                  context,
                  label: 'Nom complet',
                  value: profile?.fullName ?? 'Profil non retrouvé',
                  icon: Icons.person_outline,
                ),
                _buildVerificationInfoTile(
                  context,
                  label: 'Rôle',
                  value: profile?.role.shortLabel ?? 'Non renseigné',
                  icon: Icons.work_outline,
                ),
                _buildVerificationInfoTile(
                  context,
                  label: 'Commune',
                  value: profile?.communeName ?? _verificationScopeLabel(),
                  icon: Icons.location_city_outlined,
                ),
                _buildVerificationInfoTile(
                  context,
                  label: 'Dernier paiement visible',
                  value: lastPaymentLabel,
                  icon: Icons.event_outlined,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!result.hasRegisteredPayment)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: AppColors.chartRed.withValues(alpha: 0.08),
                  border: Border.all(
                    color: AppColors.chartRed.withValues(alpha: 0.18),
                  ),
                ),
                child: Text(
                  profile != null
                      ? 'Aucun paiement enregistré pour cet identifiant dans le périmètre courant.'
                      : 'Aucune information de paiement ou de profil n\'a été trouvée pour cet identifiant dans le périmètre courant.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else ...[
              Text(
                'Historique des paiements retrouvés',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              _buildVerificationTable(context, result),
            ],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleTransactions = _filteredTransactions;
    final totalVisible = visibleTransactions.fold<double>(
      0,
      (sum, row) => sum + _transactionAmount(row),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  widget.profile.role == AppRole.contribuable
                      ? 'Paiement de mes taxes'
                      : 'Apurement',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildApurementStatsPanel(context),
          if (_selectedApurementList != null) ...[
            const SizedBox(height: 16),
            _buildApurementPendingPanel(context),
          ],
          const SizedBox(height: 20),
          ModernSectionPanel(
            title: widget.profile.role == AppRole.contribuable
                ? 'Historique de mes apurements'
                : 'Historique des apurements',
            subtitle:
                'Consultez toutes les recettes enregistrées, filtrez par période, catégorie, canal ou commune, et retrouvez rapidement une transaction.',
            eyebrow: 'Tableau',
            accentColor: AppColors.primary,
            action: OutlinedButton.icon(
              onPressed: _loadingTransactions
                  ? null
                  : () async {
                      await _loadTransactions();
                      await _loadApurementStats();
                    },
              icon: const Icon(Icons.refresh_outlined),
              label: const Text('Actualiser'),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ModernInfoPill(
                      label: 'Apurements',
                      value: '${visibleTransactions.length}',
                      icon: Icons.receipt_long_outlined,
                      color: AppColors.primary,
                    ),
                    ModernInfoPill(
                      label: 'Montant visible',
                      value: _formatMoney(totalVisible),
                      icon: Icons.payments_outlined,
                      color: AppColors.chartTeal,
                    ),
                    ModernInfoPill(
                      label: 'Periode',
                      value: _rangeLabel(_range),
                      icon: Icons.date_range_outlined,
                      color: AppColors.chartOrange,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _transactionSearchCtrl,
                  decoration: InputDecoration(
                    labelText: 'Recherche',
                    hintText: 'Commune, catégorie, canal, identifiant...',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _transactionSearchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () => _transactionSearchCtrl.clear(),
                            icon: const Icon(Icons.close),
                          ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Periode',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final range in _TransactionRange.values)
                      ChoiceChip(
                        label: Text(_rangeLabel(range)),
                        selected: _range == range,
                        onSelected: (selected) async {
                          if (!selected) return;
                          setState(() => _range = range);
                          await _loadTransactions();
                          await _loadApurementStats();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String?>(
                        key: ValueKey(_categoryFilter ?? 'all-categories'),
                        isExpanded: true,
                        initialValue: _categoryFilter,
                        decoration: const InputDecoration(
                          labelText: 'Catégorie',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: _dropdownLabel('Toutes les catégories'),
                          ),
                          for (final category in _availableCategories)
                            DropdownMenuItem<String?>(
                              value: category,
                              child: _dropdownLabel(category),
                            ),
                        ],
                        onChanged: (value) {
                          setState(() => _categoryFilter = value);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String?>(
                        key: ValueKey(_channelFilter ?? 'all-channels'),
                        isExpanded: true,
                        initialValue: _channelFilter,
                        decoration: const InputDecoration(
                          labelText: 'Canal',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: _dropdownLabel('Tous les canaux'),
                          ),
                          for (final channel in _availableChannels)
                            DropdownMenuItem<String?>(
                              value: channel,
                              child: _dropdownLabel(channel),
                            ),
                        ],
                        onChanged: (value) {
                          setState(() => _channelFilter = value);
                        },
                      ),
                    ),
                    if (_scope == null)
                      SizedBox(
                        width: 240,
                        child: DropdownButtonFormField<String?>(
                          key: ValueKey(_communeFilter ?? 'all-communes'),
                          isExpanded: true,
                          initialValue: _communeFilter,
                          decoration: const InputDecoration(
                            labelText: 'Commune',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: _dropdownLabel('Toutes les communes'),
                            ),
                            for (final commune in _availableCommunes)
                              DropdownMenuItem<String?>(
                                value: commune.id,
                                child: _dropdownLabel(commune.name),
                              ),
                          ],
                          onChanged: (value) {
                            setState(() => _communeFilter = value);
                          },
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_loadingTransactions)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_transactionsError != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: Theme.of(
                        context,
                      ).colorScheme.errorContainer.withValues(alpha: 0.58),
                    ),
                    child: Text(_transactionsError!),
                  )
                else if (visibleTransactions.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.35),
                    ),
                    child: Text(
                      'Aucune transaction ne correspond aux filtres actuels.',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  )
                else
                  _buildTransactionsTable(context, visibleTransactions),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ApurementKpiCard extends StatelessWidget {
  const _ApurementKpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.detail,
    required this.icon,
    required this.accent,
    this.selected = false,
    this.onTap,
  });

  final String title;
  final String value;
  final String subtitle;
  final String detail;
  final IconData icon;
  final Color accent;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: isDark ? 0.18 : 0.09)
                : isDark
                ? theme.colorScheme.surface
                : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.72)
                  : AppColors.border.withValues(alpha: 0.58),
            ),
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
        ),
      ),
    );
  }
}
