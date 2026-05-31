import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/gestia_data_service.dart';
import '../theme/app_colors.dart';
import '../utils/error_messages.dart';
import '../utils/gestia_qr_payload.dart';
import '../widgets/gestia_qr_scanner_screen.dart';

enum _RecoveryStatusFilter { all, normal, reminder, late, veryLate, recovery }

enum _RecoveryScanTarget { cpi, perceptionNote }

class _RecoveryActionLog {
  const _RecoveryActionLog({
    required this.noteId,
    required this.label,
    required this.createdAt,
    this.observation,
  });

  final String noteId;
  final String label;
  final DateTime createdAt;
  final String? observation;
}

class RecouvrementScreen extends StatefulWidget {
  const RecouvrementScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<RecouvrementScreen> createState() => _RecouvrementScreenState();
}

class _RecouvrementScreenState extends State<RecouvrementScreen> {
  final _nameCtrl = TextEditingController();
  final _identifierCtrl = TextEditingController();
  final _minAmountCtrl = TextEditingController();
  final _maxAmountCtrl = TextEditingController();
  final _observationCtrl = TextEditingController();

  List<Map<String, dynamic>> _notes = [];
  Map<String, String> _taxateurNames = {};
  List<_RecoveryActionLog> _actionLogs = [];
  bool _loading = true;
  bool _exporting = false;
  String? _error;
  String? _updatingId;
  String? _selectedId;
  String? _communeFilter;
  String? _taxateurFilter;
  _RecoveryStatusFilter _statusFilter = _RecoveryStatusFilter.all;
  DateTimeRange? _deadlineRange;

  String? get _scope =>
      widget.profile.isGlobalSupervisor ? null : widget.profile.communeId;

  Map<String, dynamic>? get _selectedNote {
    if (_selectedId == null) return _filteredNotes.firstOrNull;
    for (final note in _filteredNotes) {
      if (note['id']?.toString() == _selectedId) return note;
    }
    return _filteredNotes.firstOrNull;
  }

  List<Map<String, dynamic>> get _recoveryNotes {
    final rows = _notes.where((row) {
      if (_isPaid(row)) return false;
      return _delayDays(row) > 0 ||
          row['status']?.toString() == 'en_recouvrement';
    }).toList();
    rows.sort((a, b) {
      final delayCompare = _delayDays(b).compareTo(_delayDays(a));
      if (delayCompare != 0) return delayCompare;
      return _deadline(a).compareTo(_deadline(b));
    });
    return rows;
  }

  List<Map<String, dynamic>> get _filteredNotes {
    final nameQuery = _nameCtrl.text.trim().toLowerCase();
    final identifierQuery = _identifierCtrl.text.trim().toLowerCase();
    final minAmount = double.tryParse(
      _minAmountCtrl.text.trim().replaceAll(',', '.'),
    );
    final maxAmount = double.tryParse(
      _maxAmountCtrl.text.trim().replaceAll(',', '.'),
    );

    return _recoveryNotes.where((row) {
      if (_communeFilter != null &&
          _taxpayerCommuneName(row) != _communeFilter) {
        return false;
      }
      if (_taxateurFilter != null && _taxateurId(row) != _taxateurFilter) {
        return false;
      }
      if (_deadlineRange != null) {
        final deadline = _deadline(row);
        final start = DateTime(
          _deadlineRange!.start.year,
          _deadlineRange!.start.month,
          _deadlineRange!.start.day,
        );
        final end = DateTime(
          _deadlineRange!.end.year,
          _deadlineRange!.end.month,
          _deadlineRange!.end.day,
          23,
          59,
          59,
        );
        if (deadline.isBefore(start) || deadline.isAfter(end)) return false;
      }
      if (_statusFilter != _RecoveryStatusFilter.all &&
          _statusFilter != _statusBucket(row)) {
        return false;
      }
      final amount = _amount(row);
      if (minAmount != null && amount < minAmount) return false;
      if (maxAmount != null && amount > maxAmount) return false;
      if (nameQuery.isNotEmpty &&
          !(row['taxpayer_name']?.toString().toLowerCase() ?? '').contains(
            nameQuery,
          )) {
        return false;
      }
      if (identifierQuery.isNotEmpty) {
        final haystack = [
          row['taxpayer_identifier'],
          row['note_number'],
          row['cpi_number'],
        ].map((value) => value?.toString().toLowerCase() ?? '').join(' ');
        if (!haystack.contains(identifierQuery)) return false;
      }
      return true;
    }).toList();
  }

  List<String> get _communes {
    final values = _recoveryNotes.map(_taxpayerCommuneName).toSet().toList()
      ..sort();
    return values;
  }

  List<({String id, String name})> get _taxateurs {
    final values = <String, String>{};
    for (final row in _recoveryNotes) {
      final id = _taxateurId(row);
      if (id == null || id.isEmpty) continue;
      values[id] = _taxateurName(row);
    }
    final list =
        values.entries
            .map((entry) => (id: entry.key, name: entry.value))
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    return list;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _identifierCtrl.dispose();
    _minAmountCtrl.dispose();
    _maxAmountCtrl.dispose();
    _observationCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await GestiaDataService.markOverdueTaxationsForRecovery();
      final rows = await GestiaDataService.fetchPerceptionNotes(
        statuses: const [
          'ordonnee',
          'note_perception_generee',
          'paiement_declare',
          'en_recouvrement',
        ],
        communeId: _scope,
        limit: 5000,
      );
      final taxateurIds = rows
          .map(_taxateurId)
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();
      final taxateurNames = await GestiaDataService.fetchProfileNamesByIds(
        taxateurIds,
      );
      if (!mounted) return;
      setState(() {
        _notes = rows;
        _taxateurNames = taxateurNames;
        if (_selectedId != null &&
            !_recoveryNotes.any(
              (row) => row['id']?.toString() == _selectedId,
            )) {
          _selectedId = null;
        }
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

  Future<void> _pickDeadlineRange() async {
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _deadlineRange,
    );
    if (selected == null) return;
    setState(() => _deadlineRange = selected);
  }

  void _clearFilters() {
    _nameCtrl.clear();
    _identifierCtrl.clear();
    _minAmountCtrl.clear();
    _maxAmountCtrl.clear();
    setState(() {
      _communeFilter = null;
      _taxateurFilter = null;
      _statusFilter = _RecoveryStatusFilter.all;
      _deadlineRange = null;
    });
  }

  Future<void> _openScannerPicker() async {
    final target = await showModalBottomSheet<_RecoveryScanTarget>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                  child: Text(
                    'Scanner un document',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('Scanner CPI'),
                  subtitle: const Text('Certificat de paiement informatisé'),
                  onTap: () {
                    Navigator.of(sheetContext).pop(_RecoveryScanTarget.cpi);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Scanner note de perception'),
                  subtitle: const Text('Contrôle de la note à recouvrer'),
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

    final matchedNote = _findScannedNote(payload);
    if (matchedNote != null) {
      _focusScannedNote(matchedNote);
    }
    await _showScannedResult(payload, matchedNote);
  }

  void _focusScannedNote(Map<String, dynamic> row) {
    _nameCtrl.clear();
    _identifierCtrl.text = row['taxpayer_identifier']?.toString() ?? '';
    _minAmountCtrl.clear();
    _maxAmountCtrl.clear();
    setState(() {
      _selectedId = row['id']?.toString();
      _communeFilter = null;
      _taxateurFilter = null;
      _statusFilter = _RecoveryStatusFilter.all;
      _deadlineRange = null;
    });
  }

  Map<String, dynamic>? _findScannedNote(GestiaQrPayloadData payload) {
    final referenceKeys = <String>{
      _scanKey(payload.reference),
      _scanKey(payload.perceptionNoteNumber ?? ''),
    }..remove('');

    for (final row in _notes) {
      final rowKeys = <String>{
        _scanKey(row['note_number']),
        _scanKey(row['cpi_number']),
      }..remove('');
      if (rowKeys.any(referenceKeys.contains)) return row;
    }

    final taxpayerKey = _scanKey(payload.taxpayerIdentifier);
    if (taxpayerKey.isEmpty) return null;

    final amount = _scanAmount(payload.amountUsdLabel);
    final candidates = _recoveryNotes
        .where((row) {
          final sameTaxpayer =
              _scanKey(row['taxpayer_identifier']) == taxpayerKey;
          if (!sameTaxpayer) return false;
          return amount == null || (_amount(row) - amount).abs() < 0.01;
        })
        .toList(growable: false);
    if (candidates.length == 1) return candidates.first;
    return null;
  }

  String _scanKey(Object? value) {
    return value?.toString().trim().toLowerCase().replaceAll(
          RegExp(r'[\s\-_/]+'),
          '',
        ) ??
        '';
  }

  double? _scanAmount(String value) {
    final cleaned = value
        .toUpperCase()
        .replaceAll('USD', '')
        .replaceAll('FC', '')
        .replaceAll('CDF', '')
        .replaceAll(' ', '')
        .replaceAll(',', '.')
        .trim();
    return double.tryParse(cleaned);
  }

  String _qrAmountLabel(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return '-';
    if (cleaned.toUpperCase().contains('USD')) return cleaned;
    return '$cleaned USD';
  }

  Future<void> _showScannedResult(
    GestiaQrPayloadData payload,
    Map<String, dynamic>? matchedNote,
  ) async {
    final theme = Theme.of(context);
    final isCpi = payload.type == GestiaQrDocumentType.cpi;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            20 + MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    matchedNote == null
                        ? Icons.warning_amber_outlined
                        : Icons.verified_outlined,
                    color: matchedNote == null
                        ? AppColors.chartOrange
                        : AppColors.chartTeal,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      matchedNote == null
                          ? 'QR valide, note introuvable'
                          : 'Document retrouvé',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                matchedNote == null
                    ? 'Le QR est bien lisible, mais aucune note en recouvrement ne correspond aux références du document.'
                    : 'La note correspondante est sélectionnée dans le tableau.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _detailLine('Document', isCpi ? 'CPI' : 'Note de perception'),
              _detailLine('Référence', payload.reference),
              if ((payload.perceptionNoteNumber ?? '').trim().isNotEmpty)
                _detailLine(
                  'Note perception',
                  payload.perceptionNoteNumber!.trim(),
                ),
              if (payload.taxpayerIdentifier.trim().isNotEmpty)
                _detailLine('Identifiant', payload.taxpayerIdentifier.trim()),
              if ((payload.taxpayerName ?? '').trim().isNotEmpty)
                _detailLine('Assujetti', payload.taxpayerName!.trim()),
              _detailLine('Montant', _qrAmountLabel(payload.amountUsdLabel)),
              _detailLine(
                'Statut QR',
                payload.proofOfPayment
                    ? 'Preuve de paiement'
                    : 'Pas une preuve de paiement',
              ),
              if (matchedNote != null) ...[
                const Divider(height: 24),
                _detailLine(
                  'Note trouvée',
                  matchedNote['note_number']?.toString() ?? '-',
                ),
                _detailLine(
                  'Assujetti',
                  matchedNote['taxpayer_name']?.toString() ?? '-',
                ),
                _detailLine(
                  'Taxe',
                  matchedNote['tax_category']?.toString() ?? '-',
                ),
                _detailLine(
                  'Total à recouvrer',
                  _formatMoney(_totalDue(matchedNote)),
                ),
                _detailLine('Statut', _statusLabel(matchedNote)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  icon: const Icon(Icons.check),
                  label: const Text('Fermer'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _exportUnpaidNotes() async {
    if (_exporting) return;
    final rows = _filteredNotes;
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune note impayée à exporter.')),
      );
      return;
    }

    setState(() => _exporting = true);
    try {
      final workbook = xls.Excel.createExcel();
      final defaultSheet = workbook.getDefaultSheet();
      if (defaultSheet != null && defaultSheet != 'Notes impayées') {
        workbook.rename(defaultSheet, 'Notes impayées');
      }
      final sheet = workbook['Notes impayées'];
      sheet.appendRow([
        xls.TextCellValue('N°'),
        xls.TextCellValue('N° note'),
        xls.TextCellValue('Nom'),
        xls.TextCellValue('Identifiant'),
        xls.TextCellValue('Commune de l’assujetti'),
        xls.TextCellValue('Nature / taxe'),
        xls.TextCellValue('Montant'),
        xls.TextCellValue('Pénalité'),
        xls.TextCellValue('Total à recouvrer'),
        xls.TextCellValue('Date d’échéance'),
        xls.TextCellValue('Jours de retard'),
        xls.TextCellValue('Statut'),
        xls.TextCellValue('Agent taxateur'),
      ]);
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        sheet.appendRow([
          xls.IntCellValue(i + 1),
          xls.TextCellValue(row['note_number']?.toString() ?? '-'),
          xls.TextCellValue(row['taxpayer_name']?.toString() ?? '-'),
          xls.TextCellValue(row['taxpayer_identifier']?.toString() ?? '-'),
          xls.TextCellValue(_taxpayerCommuneName(row)),
          xls.TextCellValue(row['tax_category']?.toString() ?? '-'),
          xls.DoubleCellValue(_amount(row)),
          xls.DoubleCellValue(_penalty(row)),
          xls.DoubleCellValue(_totalDue(row)),
          xls.TextCellValue(_formatDate(_deadline(row))),
          xls.IntCellValue(_delayDays(row)),
          xls.TextCellValue(_statusLabel(row)),
          xls.TextCellValue(_taxateurName(row)),
        ]);
      }

      final fileName = 'notes_impayees_${_fileStamp(DateTime.now())}.xlsx';
      final bytes = workbook.save(fileName: fileName);
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Impossible de générer le fichier Excel.');
      }
      final path = await FilePicker.saveFile(
        dialogTitle: 'Exporter la liste des notes impayées',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: Uint8List.fromList(bytes),
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export enregistré : $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _fileStamp(DateTime value) {
    String two(int input) => input.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}_'
        '${two(value.hour)}-${two(value.minute)}';
  }

  Future<void> _sendReminder(Map<String, dynamic> row) async {
    _addHistory(row, 'Rappel envoyé');
    final phone = row['taxpayer_phone']?.toString().trim();
    final target = phone == null || phone.isEmpty ? 'notification' : 'SMS';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Rappel $target préparé pour cette note.')),
    );
  }

  Future<void> _applyPenalty(Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() => _updatingId = id);
    try {
      await GestiaDataService.updatePerceptionNoteStatus(
        noteId: id,
        status: 'en_recouvrement',
      );
      _addHistory(row, 'Pénalité appliquée');
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Pénalité calculée : ${_formatMoney(_penalty(row))}.'),
        ),
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

  Future<void> _markRecovered(Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() => _updatingId = id);
    try {
      await GestiaDataService.updatePerceptionNoteStatus(
        noteId: id,
        status: 'apuree_cpi_genere',
        paidAt: DateTime.now(),
        apuredAt: DateTime.now(),
      );
      _addHistory(row, 'Note marquée comme recouvrée');
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note marquée comme recouvrée.')),
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

  void _addHistory(Map<String, dynamic> row, String label) {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() {
      _actionLogs = [
        _RecoveryActionLog(
          noteId: id,
          label: label,
          createdAt: DateTime.now(),
          observation: _observationCtrl.text.trim().isEmpty
              ? null
              : _observationCtrl.text.trim(),
        ),
        ..._actionLogs,
      ];
    });
  }

  bool _isPaid(Map<String, dynamic> row) {
    final status = row['status']?.toString();
    return status == 'apuree_cpi_genere' ||
        row['apured_at'] != null ||
        row['cpi_number']?.toString().trim().isNotEmpty == true;
  }

  double _amount(Map<String, dynamic> row) {
    return (row['amount'] as num?)?.toDouble() ?? 0;
  }

  DateTime _deadline(Map<String, dynamic> row) {
    final parsed = DateTime.tryParse(row['payment_deadline']?.toString() ?? '');
    return parsed?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  DateTime _createdAt(Map<String, dynamic> row) {
    final parsed = DateTime.tryParse(row['created_at']?.toString() ?? '');
    return parsed?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  int _delayDays(Map<String, dynamic> row) {
    final deadline = _deadline(row);
    if (deadline.millisecondsSinceEpoch == 0) return 0;
    final today = DateTime.now();
    final cleanToday = DateTime(today.year, today.month, today.day);
    final cleanDeadline = DateTime(deadline.year, deadline.month, deadline.day);
    return cleanToday.difference(cleanDeadline).inDays.clamp(0, 9999).toInt();
  }

  double _penaltyRate(Map<String, dynamic> row) {
    final days = _delayDays(row);
    if (days <= 8) return 0;
    if (days <= 30) return 0.05;
    if (days <= 60) return 0.10;
    return 0.15;
  }

  double _penalty(Map<String, dynamic> row) {
    return _amount(row) * _penaltyRate(row);
  }

  double _totalDue(Map<String, dynamic> row) {
    return _amount(row) + _penalty(row);
  }

  _RecoveryStatusFilter _statusBucket(Map<String, dynamic> row) {
    if (row['status']?.toString() == 'en_recouvrement') {
      return _RecoveryStatusFilter.recovery;
    }
    final days = _delayDays(row);
    if (days <= 8) return _RecoveryStatusFilter.normal;
    if (days <= 15) return _RecoveryStatusFilter.reminder;
    if (days <= 30) return _RecoveryStatusFilter.late;
    return _RecoveryStatusFilter.veryLate;
  }

  String _statusLabel(Map<String, dynamic> row) {
    if (row['status']?.toString() == 'en_recouvrement') {
      final ordonnateurId = row['ordonnateur_id']?.toString().trim();
      if (ordonnateurId == null || ordonnateurId.isEmpty) {
        return 'Non ordonnée - recouvrement';
      }
      return 'En recouvrement';
    }
    return switch (_statusBucket(row)) {
      _RecoveryStatusFilter.normal => 'Note normale',
      _RecoveryStatusFilter.reminder => 'À rappeler',
      _RecoveryStatusFilter.late => 'En retard',
      _RecoveryStatusFilter.veryLate => 'Très en retard',
      _RecoveryStatusFilter.recovery => 'En recouvrement',
      _RecoveryStatusFilter.all => '-',
    };
  }

  String _statusFilterLabel(_RecoveryStatusFilter value) {
    return switch (value) {
      _RecoveryStatusFilter.all => 'Tous les statuts',
      _RecoveryStatusFilter.normal => 'Note normale',
      _RecoveryStatusFilter.reminder => 'À rappeler',
      _RecoveryStatusFilter.late => 'En retard',
      _RecoveryStatusFilter.veryLate => 'Très en retard',
      _RecoveryStatusFilter.recovery => 'En recouvrement',
    };
  }

  Color _statusColor(Map<String, dynamic> row) {
    return switch (_statusBucket(row)) {
      _RecoveryStatusFilter.normal => AppColors.chartBlue,
      _RecoveryStatusFilter.reminder => AppColors.chartYellow,
      _RecoveryStatusFilter.late => AppColors.chartOrange,
      _RecoveryStatusFilter.veryLate => AppColors.chartRed,
      _RecoveryStatusFilter.recovery => AppColors.chartPurple,
      _RecoveryStatusFilter.all => AppColors.primary,
    };
  }

  String _communeName(Map<String, dynamic> row) {
    final scope = row['collection_scope']?.toString().trim().toLowerCase();
    if (scope == 'mairie') return 'Mairie';
    final commune = row['communes'];
    if (commune is Map) {
      final name = commune['name']?.toString().trim();
      if (name != null && name.isNotEmpty) return name;
    }
    return 'Commune';
  }

  String _taxpayerCommuneName(Map<String, dynamic> row) {
    final address = row['taxpayer_address']?.toString().trim() ?? '';
    if (address.isNotEmpty) {
      final firstPart = address.split(',').first.trim();
      if (firstPart.isNotEmpty) return firstPart;
    }
    return 'Non renseignée';
  }

  String? _taxateurId(Map<String, dynamic> row) {
    final taxateurId = row['taxateur_id']?.toString().trim();
    if (taxateurId != null && taxateurId.isNotEmpty) return taxateurId;
    final createdBy = row['created_by']?.toString().trim();
    if (createdBy != null && createdBy.isNotEmpty) return createdBy;
    return null;
  }

  String _taxateurName(Map<String, dynamic> row) {
    final id = _taxateurId(row);
    if (id == null || id.isEmpty) return 'Non renseigné';
    return _taxateurNames[id] ?? 'Utilisateur';
  }

  String _formatMoney(double value) {
    return '${value.toStringAsFixed(2)} USD';
  }

  String _formatDate(DateTime value) {
    if (value.millisecondsSinceEpoch == 0) return '-';
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  String _formatDateTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${_formatDate(value)} $hour:$minute';
  }

  Widget _metricCard({
    required BuildContext context,
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetrics(BuildContext context) {
    final suffering = _recoveryNotes.where((row) => _delayDays(row) > 8).length;
    final overdue = _recoveryNotes.length;
    final penalties = _recoveryNotes.fold<double>(
      0,
      (sum, row) => sum + _penalty(row),
    );
    final recovered = _notes
        .where(_isPaid)
        .fold<double>(0, (sum, row) => sum + _amount(row));
    final base = _notes.fold<double>(0, (sum, row) => sum + _amount(row));
    final rate = base <= 0 ? 0 : (recovered / base * 100).clamp(0, 100);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1100
            ? 5
            : width >= 760
            ? 3
            : 1;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: columns == 1 ? 4.2 : 2.2,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _metricCard(
              context: context,
              label: 'Notes en souffrance',
              value: '$suffering',
              icon: Icons.warning_amber_outlined,
              color: AppColors.chartOrange,
            ),
            _metricCard(
              context: context,
              label: 'Notes dépassées',
              value: '$overdue',
              icon: Icons.schedule_outlined,
              color: AppColors.chartRed,
            ),
            _metricCard(
              context: context,
              label: 'Total pénalités',
              value: _formatMoney(penalties),
              icon: Icons.price_change_outlined,
              color: AppColors.chartPurple,
            ),
            _metricCard(
              context: context,
              label: 'Total recouvré',
              value: _formatMoney(recovered),
              icon: Icons.verified_outlined,
              color: AppColors.chartTeal,
            ),
            _metricCard(
              context: context,
              label: 'Taux recouvrement',
              value: '${rate.toStringAsFixed(1)}%',
              icon: Icons.trending_up_outlined,
              color: AppColors.primary,
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilters(BuildContext context) {
    final rangeLabel = _deadlineRange == null
        ? 'Date d’échéance'
        : '${_formatDate(_deadlineRange!.start)} - ${_formatDate(_deadlineRange!.end)}';

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 220,
              child: TextField(
                controller: _nameCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Nom',
                  hintText: 'Nom de l’assujetti',
                  prefixIcon: Icon(Icons.person_search_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            SizedBox(
              width: 190,
              child: TextField(
                controller: _identifierCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Identifiant',
                  hintText: 'NIP, note, CPI...',
                  prefixIcon: Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String?>(
                initialValue: _communeFilter,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Commune de l’assujetti',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Toutes'),
                  ),
                  for (final commune in _communes)
                    DropdownMenuItem<String?>(
                      value: commune,
                      child: Text(commune),
                    ),
                ],
                onChanged: (value) => setState(() => _communeFilter = value),
              ),
            ),
            SizedBox(
              width: 210,
              child: DropdownButtonFormField<_RecoveryStatusFilter>(
                initialValue: _statusFilter,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Statut',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final status in _RecoveryStatusFilter.values)
                    DropdownMenuItem(
                      value: status,
                      child: Text(_statusFilterLabel(status)),
                    ),
                ],
                onChanged: (value) => setState(
                  () => _statusFilter = value ?? _RecoveryStatusFilter.all,
                ),
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String?>(
                initialValue: _taxateurFilter,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Agent taxateur',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Tous les taxateurs'),
                  ),
                  for (final taxateur in _taxateurs)
                    DropdownMenuItem<String?>(
                      value: taxateur.id,
                      child: Text(taxateur.name),
                    ),
                ],
                onChanged: (value) => setState(() => _taxateurFilter = value),
              ),
            ),
            SizedBox(
              width: 150,
              child: TextField(
                controller: _minAmountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Montant min',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            SizedBox(
              width: 150,
              child: TextField(
                controller: _maxAmountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Montant max',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _pickDeadlineRange,
              icon: const Icon(Icons.date_range_outlined),
              label: Text(rangeLabel),
            ),
            IconButton.filledTonal(
              tooltip: 'Réinitialiser',
              onPressed: _clearFilters,
              icon: const Icon(Icons.filter_alt_off_outlined),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildTable(BuildContext context) {
    final rows = _filteredNotes;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Card(
        elevation: 0,
        child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
      );
    }
    if (rows.isEmpty) {
      return Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            'Aucune note impayée ne correspond aux filtres.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 1580),
          child: DataTable(
            showCheckboxColumn: false,
            columns: const [
              DataColumn(label: Text('N° note')),
              DataColumn(label: Text('Contribuable')),
              DataColumn(label: Text('Commune assujetti')),
              DataColumn(label: Text('Identifiant')),
              DataColumn(label: Text('Taxe')),
              DataColumn(label: Text('Montant')),
              DataColumn(label: Text('Date émission')),
              DataColumn(label: Text('Date échéance')),
              DataColumn(label: Text('Jours de retard')),
              DataColumn(label: Text('Pénalité')),
              DataColumn(label: Text('Statut')),
              DataColumn(label: Text('Agent taxateur')),
              DataColumn(label: Text('Actions')),
            ],
            rows: [
              for (final row in rows)
                DataRow(
                  selected:
                      row['id']?.toString() == _selectedNote?['id']?.toString(),
                  onSelectChanged: (_) =>
                      setState(() => _selectedId = row['id']?.toString()),
                  cells: [
                    DataCell(Text(row['note_number']?.toString() ?? '-')),
                    DataCell(Text(row['taxpayer_name']?.toString() ?? '-')),
                    DataCell(Text(_taxpayerCommuneName(row))),
                    DataCell(
                      Text(row['taxpayer_identifier']?.toString() ?? '-'),
                    ),
                    DataCell(Text(row['tax_category']?.toString() ?? '-')),
                    DataCell(Text(_formatMoney(_amount(row)))),
                    DataCell(Text(_formatDate(_createdAt(row)))),
                    DataCell(Text(_formatDate(_deadline(row)))),
                    DataCell(Text('${_delayDays(row)} j')),
                    DataCell(Text(_formatMoney(_penalty(row)))),
                    DataCell(
                      _badge(context, _statusLabel(row), _statusColor(row)),
                    ),
                    DataCell(Text(_taxateurName(row))),
                    DataCell(
                      Wrap(
                        spacing: 6,
                        children: [
                          IconButton(
                            tooltip: 'Envoyer rappel',
                            onPressed: () => _sendReminder(row),
                            icon: const Icon(Icons.sms_outlined),
                          ),
                          IconButton(
                            tooltip: 'Appliquer pénalité',
                            onPressed: _updatingId == row['id']?.toString()
                                ? null
                                : () => _applyPenalty(row),
                            icon: const Icon(Icons.price_change_outlined),
                          ),
                          IconButton(
                            tooltip: 'Marquer comme recouvrée',
                            onPressed: _updatingId == row['id']?.toString()
                                ? null
                                : () => _markRecovered(row),
                            icon: const Icon(Icons.verified_outlined),
                          ),
                        ],
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

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildDetailPanel(BuildContext context) {
    final row = _selectedNote;
    final theme = Theme.of(context);
    if (row == null) {
      return Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Selectionnez une note pour voir le detail.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }
    final logs = _actionLogs
        .where((log) => log.noteId == row['id']?.toString())
        .toList();

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.assignment_outlined, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    row['note_number']?.toString() ?? 'Note',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _badge(context, _statusLabel(row), _statusColor(row)),
              ],
            ),
            const SizedBox(height: 12),
            _detailLine(
              'Contribuable',
              row['taxpayer_name']?.toString() ?? '-',
            ),
            _detailLine('Commune assujetti', _taxpayerCommuneName(row)),
            _detailLine('Point de taxation', _communeName(row)),
            _detailLine('Agent taxateur', _taxateurName(row)),
            _detailLine('Montant initial', _formatMoney(_amount(row))),
            _detailLine('Pénalité', _formatMoney(_penalty(row))),
            _detailLine('Total actualisé', _formatMoney(_totalDue(row))),
            _detailLine('Émission', _formatDate(_createdAt(row))),
            _detailLine('Échéance', _formatDate(_deadline(row))),
            _detailLine('Retard', '${_delayDays(row)} jours'),
            const SizedBox(height: 14),
            TextField(
              controller: _observationCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Observations',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => _sendReminder(row),
                  icon: const Icon(Icons.sms_outlined),
                  label: const Text('Envoyer rappel'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _updatingId == row['id']?.toString()
                      ? null
                      : () => _applyPenalty(row),
                  icon: const Icon(Icons.price_change_outlined),
                  label: const Text('Appliquer pénalité'),
                ),
                FilledButton.icon(
                  onPressed: _updatingId == row['id']?.toString()
                      ? null
                      : () => _markRecovered(row),
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('Marquer recouvrée'),
                ),
              ],
            ),
            const Divider(height: 28),
            Text(
              'Historique des actions',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            if (logs.isEmpty)
              Text(
                'Aucune action enregistrée dans cette session.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final log in logs)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history_outlined),
                  title: Text(log.label),
                  subtitle: Text(
                    [
                      _formatDateTime(log.createdAt),
                      if (log.observation != null) log.observation!,
                    ].join(' - '),
                  ),
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
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 640;
              final title = Row(
                children: [
                  Icon(
                    Icons.notification_important_outlined,
                    color: AppColors.chartOrange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Recouvrement',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              );
              final actions = Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _exporting ? null : _exportUnpaidNotes,
                    icon: _exporting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_outlined),
                    label: Text(_exporting ? 'Export...' : 'Exporter'),
                  ),
                  FilledButton.icon(
                    onPressed: _openScannerPicker,
                    icon: const Icon(Icons.qr_code_scanner_outlined),
                    label: const Text('Scanner'),
                  ),
                  IconButton(
                    tooltip: 'Actualiser',
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, const SizedBox(height: 12), actions],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  actions,
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          Text(
            'Liste des assujettis non en ordre : notes non ordonnées après 8 jours, impayés, pénalités et suivi des actions du receveur.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _buildMetrics(context),
          const SizedBox(height: 16),
          _buildFilters(context),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 980) {
                return Column(
                  children: [
                    _buildTable(context),
                    const SizedBox(height: 16),
                    _buildDetailPanel(context),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: _buildTable(context)),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: _buildDetailPanel(context)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
