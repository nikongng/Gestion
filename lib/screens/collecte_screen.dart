import 'package:flutter/material.dart';

import '../data/sample_chart_data.dart';
import '../models/app_role.dart';
import '../models/user_profile.dart';
import '../services/collections_live_listener.dart';
import '../services/gestia_data_service.dart';
import '../theme/app_colors.dart';
import '../utils/error_messages.dart';
import '../utils/gestia_qr_payload.dart';
import '../widgets/charts/tax_breakdown_pie_card.dart';
import '../widgets/gestia_qr_scanner_screen.dart';
import '../widgets/modern_section_panel.dart';
import '../widgets/payment_form_card.dart';
import '../widgets/responsive_two_cards.dart';

enum _TransactionRange { today, last7Days, last30Days, all }

enum _RecoveryScanTarget { cpi, perceptionNote }

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
  bool _loadingPie = true;
  bool _loadingTransactions = true;
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

  @override
  void initState() {
    super.initState();
    _transactionSearchCtrl.addListener(_handleFilterChanged);
    _verificationIdCtrl.addListener(_handleFilterChanged);
    _startLiveUpdates();
    _loadPie();
    _loadTransactions();
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
          constraints: const BoxConstraints(minWidth: 980),
          child: DataTable(
            columnSpacing: 22,
            dataRowMinHeight: 66,
            dataRowMaxHeight: 78,
            headingRowHeight: 54,
            columns: const [
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Commune')),
              DataColumn(label: Text('Categorie')),
              DataColumn(label: Text('Canal')),
              DataColumn(label: Text('ID contribuable')),
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
                      : 'Saisie des recettes',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (widget.profile.role.canManageApp)
                Tooltip(
                  message: 'Ajouter un type de recette',
                  child: IconButton.filledTonal(
                    onPressed: _addingReceiptType
                        ? null
                        : _showAddReceiptTypeDialog,
                    icon: _addingReceiptType
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          ResponsiveTwoCards(
            left: PaymentFormCard(
              key: ValueKey('payment-form-$_paymentFormVersion'),
              profile: widget.profile,
              onSaved: _handlePaymentSaved,
            ),
            right: Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.profile.role == AppRole.contribuable
                          ? 'Contribuable connecté'
                          : 'Utilisateur connecté',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.profile.fullName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      widget.profile.displayLine,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Divider(height: 24),
                    if (_loadingPie)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else
                      TaxBreakdownPieCard(
                        title: widget.profile.role == AppRole.contribuable
                            ? 'Mes paiements (30 j.)'
                            : 'Recettes (30 j.)',
                        compact: true,
                        slices: _slices,
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (_showVerificationPanel) ...[
            const SizedBox(height: 20),
            KeyedSubtree(
              key: _verificationPanelKey,
              child: _buildVerificationPanel(context),
            ),
          ],
          const SizedBox(height: 20),
          ModernSectionPanel(
            title: widget.profile.role == AppRole.contribuable
                ? 'Historique de mes transactions'
                : 'Historique des transactions',
            subtitle:
                'Consultez toutes les recettes enregistrées, filtrez par période, catégorie, canal ou commune, et retrouvez rapidement une transaction.',
            eyebrow: 'Tableau',
            accentColor: AppColors.primary,
            action: OutlinedButton.icon(
              onPressed: _loadingTransactions ? null : _loadTransactions,
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
                      label: 'Transactions',
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
