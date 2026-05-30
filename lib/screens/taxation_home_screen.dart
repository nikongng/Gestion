import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/gestia_data_service.dart';
import '../theme/app_colors.dart';
import '../utils/error_messages.dart';
import 'perception_note_screen.dart';

enum _TaxationTab { identification, taxation }

enum _TaxationView { dashboard, newTaxation }

enum _IdentificationView { list, add }

class TaxationHomeScreen extends StatefulWidget {
  const TaxationHomeScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<TaxationHomeScreen> createState() => _TaxationHomeScreenState();
}

class _TaxationHomeScreenState extends State<TaxationHomeScreen> {
  final _assujettiFormKey = GlobalKey<FormState>();
  final _nomCtrl = TextEditingController();
  final _postnomCtrl = TextEditingController();
  final _prenomCtrl = TextEditingController();
  final _lieuNaissanceCtrl = TextEditingController();
  final _dateNaissanceCtrl = TextEditingController();
  final _nationaliteCtrl = TextEditingController();
  final _rueCtrl = TextEditingController();
  final _quartierCtrl = TextEditingController();
  final _numeroCtrl = TextEditingController();
  final _prefixCtrl = TextEditingController(text: '+243');
  final _telephoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _entrepriseNomCtrl = TextEditingController();
  final _idNatCtrl = TextEditingController();
  final _rccmCtrl = TextEditingController();
  final _assujettiTableScrollCtrl = ScrollController();

  _TaxationTab _tab = _TaxationTab.identification;
  _TaxationView _view = _TaxationView.dashboard;
  _IdentificationView _identificationView = _IdentificationView.list;
  String _assujettiStatus = 'Personne physique';
  String _sexe = 'Masculin';
  String? _identityFileName;
  List<int>? _identityFileBytes;
  bool _unordonnedOnly = false;
  bool _loading = true;
  bool _savingAssujetti = false;
  bool _exportingTaxations = false;
  String? _error;
  List<Map<String, dynamic>> _notes = [];
  List<Map<String, dynamic>> _assujettis = [];
  Map<String, String> _taxateurNames = {};
  List<({String id, String name})> _communes = [];
  String? _assujettiCommuneId;
  String? _editingAssujettiId;
  DateTime? _taxationDateStart;
  DateTime? _taxationDateEnd;

  String? get _scope =>
      widget.profile.isGlobalSupervisor ? null : widget.profile.communeId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _postnomCtrl.dispose();
    _prenomCtrl.dispose();
    _lieuNaissanceCtrl.dispose();
    _dateNaissanceCtrl.dispose();
    _nationaliteCtrl.dispose();
    _rueCtrl.dispose();
    _quartierCtrl.dispose();
    _numeroCtrl.dispose();
    _prefixCtrl.dispose();
    _telephoneCtrl.dispose();
    _emailCtrl.dispose();
    _entrepriseNomCtrl.dispose();
    _idNatCtrl.dispose();
    _rccmCtrl.dispose();
    _assujettiTableScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final createdFrom = _dateOnly(_taxationDateStart);
    final createdTo = _taxationDateEnd == null
        ? null
        : _dateOnly(_taxationDateEnd)!.add(const Duration(days: 1));
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final notesFuture = GestiaDataService.fetchPerceptionNotes(
        statuses: const [
          'taxation_creee',
          'note_perception_generee',
          'paiement_declare',
          'en_recouvrement',
          'apuree_cpi_genere',
          'annulee',
        ],
        communeId: _scope,
        createdFrom: createdFrom,
        createdTo: createdTo,
        limit: 1000,
      );
      final assujettisFuture = GestiaDataService.fetchAssujettis(
        communeId: _scope,
      );
      final communesFuture = GestiaDataService.fetchCommunes();
      final results = await Future.wait<dynamic>([
        notesFuture,
        assujettisFuture,
        communesFuture,
      ]);
      final notes = results[0] as List<Map<String, dynamic>>;
      final assujettis = results[1] as List<Map<String, dynamic>>;
      var communes = results[2] as List<({String id, String name})>;
      final taxateurIds = notes
          .map((row) {
            final taxateurId = row['taxateur_id']?.toString().trim();
            if (taxateurId != null && taxateurId.isNotEmpty) {
              return taxateurId;
            }
            return row['created_by']?.toString().trim();
          })
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .toSet();
      final taxateurNames = await GestiaDataService.fetchProfileNamesByIds(
        taxateurIds,
      );
      if (!widget.profile.isGlobalSupervisor) {
        final communeId = widget.profile.communeId;
        if (communeId != null && communeId.isNotEmpty) {
          final scopedCommunes = communes
              .where((commune) => commune.id == communeId)
              .toList();
          if (scopedCommunes.isNotEmpty) {
            communes = scopedCommunes;
          }
        }
      }
      final selectedCommuneId = _defaultAssujettiCommuneId(communes);

      if (!mounted) return;
      setState(() {
        _notes = notes;
        _assujettis = assujettis;
        _taxateurNames = taxateurNames;
        _communes = communes;
        _assujettiCommuneId = selectedCommuneId;
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

  void _openTaxationList({required bool unordonnedOnly}) {
    setState(() {
      _tab = _TaxationTab.taxation;
      _view = _TaxationView.dashboard;
      _unordonnedOnly = unordonnedOnly;
    });
  }

  DateTime? _dateOnly(DateTime? value) {
    if (value == null) return null;
    return DateTime(value.year, value.month, value.day);
  }

  DateTime? _noteTaxationDate(Map<String, dynamic> row) {
    return DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal();
  }

  bool _isInTaxationDateRange(Map<String, dynamic> row) {
    final date = _noteTaxationDate(row);
    if (date == null) return true;
    final cleanDate = _dateOnly(date)!;
    final start = _dateOnly(_taxationDateStart);
    final end = _dateOnly(_taxationDateEnd);
    if (start != null && cleanDate.isBefore(start)) return false;
    if (end != null && cleanDate.isAfter(end)) return false;
    return true;
  }

  bool _isUnvalidatedByOrdonnateur(Map<String, dynamic> row) {
    final status = row['status']?.toString();
    final ordonnateurId = row['ordonnateur_id']?.toString().trim();
    return status == 'annulee' ||
        (status == 'taxation_creee' &&
            (ordonnateurId == null || ordonnateurId.isEmpty));
  }

  String _dateFilterLabel(DateTime? date, String fallback) {
    if (date == null) return fallback;
    String two(int item) => item.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year}';
  }

  Future<void> _pickTaxationDate({required bool start}) async {
    final now = DateTime.now();
    final current = start ? _taxationDateStart : _taxationDateEnd;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _taxationDateStart = picked;
        if (_taxationDateEnd != null && _taxationDateEnd!.isBefore(picked)) {
          _taxationDateEnd = picked;
        }
      } else {
        _taxationDateEnd = picked;
        if (_taxationDateStart != null && _taxationDateStart!.isAfter(picked)) {
          _taxationDateStart = picked;
        }
      }
    });
    await _load();
  }

  Future<void> _resetTaxationDateFilter() async {
    if (_taxationDateStart == null && _taxationDateEnd == null) return;
    setState(() {
      _taxationDateStart = null;
      _taxationDateEnd = null;
    });
    await _load();
  }

  void _showIdentificationList() {
    setState(() => _identificationView = _IdentificationView.list);
  }

  void _showAddAssujetti() {
    _clearAssujettiForm();
    setState(() => _identificationView = _IdentificationView.add);
  }

  String? _defaultAssujettiCommuneId([
    List<({String id, String name})>? source,
  ]) {
    final communes = source ?? _communes;
    final current = _assujettiCommuneId;
    if (current != null && communes.any((commune) => commune.id == current)) {
      return current;
    }
    final profileCommuneId = widget.profile.communeId;
    if (profileCommuneId != null &&
        communes.any((commune) => commune.id == profileCommuneId)) {
      return profileCommuneId;
    }
    return communes.isNotEmpty ? communes.first.id : null;
  }

  String? _selectedAssujettiCommuneName() {
    final id = _assujettiCommuneId;
    if (id == null) return null;
    for (final commune in _communes) {
      if (commune.id == id) return commune.name;
    }
    return null;
  }

  Future<void> _pickIdentityFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    setState(() {
      _identityFileName = file.name;
      _identityFileBytes = file.bytes;
    });
  }

  void _clearAssujettiForm() {
    _assujettiFormKey.currentState?.reset();
    _nomCtrl.clear();
    _postnomCtrl.clear();
    _prenomCtrl.clear();
    _lieuNaissanceCtrl.clear();
    _dateNaissanceCtrl.clear();
    _nationaliteCtrl.clear();
    _rueCtrl.clear();
    _quartierCtrl.clear();
    _numeroCtrl.clear();
    _prefixCtrl.text = '+243';
    _telephoneCtrl.clear();
    _emailCtrl.clear();
    _entrepriseNomCtrl.clear();
    _idNatCtrl.clear();
    _rccmCtrl.clear();
    setState(() {
      _assujettiStatus = 'Personne physique';
      _sexe = 'Masculin';
      _assujettiCommuneId = _defaultAssujettiCommuneId();
      _editingAssujettiId = null;
      _identityFileName = null;
      _identityFileBytes = null;
    });
  }

  void _cancelAssujettiForm() {
    _clearAssujettiForm();
    _showIdentificationList();
  }

  DateTime? _readBirthDate() {
    final parts = _dateNaissanceCtrl.text.trim().split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day);
  }

  String _assujettiStatusDb() {
    return _assujettiStatus == 'Personne morale'
        ? 'personne_morale'
        : 'personne_physique';
  }

  String _fieldValue(Map<String, dynamic> row, String key) =>
      row[key]?.toString().trim() ?? '';

  String _formatDateInput(String raw) {
    if (raw.isEmpty) return '';
    final date = DateTime.tryParse(raw);
    if (date == null) return raw;
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year}';
  }

  String _formatDateDisplay(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return '-';
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    String two(int item) => item.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year}';
  }

  String _formatDateTimeDisplay(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return '-';
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return value;
    String two(int item) => item.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  void _editAssujetti(Map<String, dynamic> assujetti) {
    setState(() {
      _editingAssujettiId = assujetti['id']?.toString();
      _assujettiStatus = _assujettiStatusLabel(assujetti);
      _sexe = _fieldValue(assujetti, 'sexe').isEmpty
          ? 'Masculin'
          : _fieldValue(assujetti, 'sexe');
      _assujettiCommuneId = _fieldValue(assujetti, 'commune_id').isEmpty
          ? _defaultAssujettiCommuneId()
          : _fieldValue(assujetti, 'commune_id');
      _nomCtrl.text = _fieldValue(assujetti, 'nom');
      _postnomCtrl.text = _fieldValue(assujetti, 'postnom');
      _prenomCtrl.text = _fieldValue(assujetti, 'prenom');
      _lieuNaissanceCtrl.text = _fieldValue(assujetti, 'lieu_naissance');
      _dateNaissanceCtrl.text = _formatDateInput(
        _fieldValue(assujetti, 'date_naissance'),
      );
      _nationaliteCtrl.text = _fieldValue(assujetti, 'nationalite');
      _rueCtrl.text = _fieldValue(assujetti, 'adresse_rue');
      _quartierCtrl.text = _fieldValue(assujetti, 'adresse_quartier');
      _numeroCtrl.text = _fieldValue(assujetti, 'adresse_numero');
      _prefixCtrl.text = _fieldValue(assujetti, 'contact_prefix').isEmpty
          ? '+243'
          : _fieldValue(assujetti, 'contact_prefix');
      _telephoneCtrl.text = _fieldValue(assujetti, 'contact_telephone');
      _emailCtrl.text = _fieldValue(assujetti, 'contact_email');
      _entrepriseNomCtrl.text = _fieldValue(assujetti, 'entreprise_nom');
      _idNatCtrl.text = _fieldValue(assujetti, 'id_nat');
      _rccmCtrl.text = _fieldValue(assujetti, 'rccm');
      _identityFileName =
          _fieldValue(assujetti, 'identity_document_name').isEmpty
          ? null
          : _fieldValue(assujetti, 'identity_document_name');
      _identityFileBytes = null;
      _identificationView = _IdentificationView.add;
    });
  }

  Future<void> _deleteAssujetti(Map<String, dynamic> assujetti) async {
    final id = assujetti['id']?.toString();
    if (id == null || id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer l’assujetti'),
        content: Text(
          'Voulez-vous supprimer définitivement ${_assujettiName(assujetti)} ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await GestiaDataService.deleteAssujetti(
        assujettiId: id,
        identityDocumentPath: assujetti['identity_document_path']?.toString(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Assujetti supprimé.')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(e))));
    }
  }

  Future<void> _validateAssujettiForm() async {
    if (!_assujettiFormKey.currentState!.validate()) return;
    final birthDate = _readBirthDate();
    if (birthDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Date de naissance invalide.')),
      );
      return;
    }
    final communeName = _selectedAssujettiCommuneName();
    final confirmed = await _showAssujettiPreviewDialog(
      communeName: communeName,
    );
    if (!confirmed || !mounted) return;

    setState(() => _savingAssujetti = true);
    try {
      final payload = _buildAssujettiPayload(birthDate, communeName);
      final editingId = _editingAssujettiId;
      if (editingId == null) {
        await GestiaDataService.insertAssujetti(
          payload: payload,
          identityDocumentBytes: _identityFileBytes,
          identityDocumentName: _identityFileName,
        );
      } else {
        await GestiaDataService.updateAssujetti(
          assujettiId: editingId,
          payload: payload,
          identityDocumentBytes: _identityFileBytes,
          identityDocumentName: _identityFileBytes == null
              ? null
              : _identityFileName,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            editingId == null ? 'Assujetti enregistré.' : 'Assujetti modifié.',
          ),
        ),
      );
      _clearAssujettiForm();
      _showIdentificationList();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _savingAssujetti = false);
    }
  }

  Map<String, dynamic> _buildAssujettiPayload(
    DateTime birthDate,
    String? communeName,
  ) {
    String? optional(String value) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    return {
      'commune_id': _assujettiCommuneId,
      'status': _assujettiStatusDb(),
      'nom': _nomCtrl.text.trim(),
      'postnom': _postnomCtrl.text.trim(),
      'prenom': _prenomCtrl.text.trim(),
      'lieu_naissance': _lieuNaissanceCtrl.text.trim(),
      'date_naissance': birthDate.toIso8601String().substring(0, 10),
      'nationalite': _nationaliteCtrl.text.trim(),
      'sexe': _sexe,
      'adresse_commune': communeName,
      'adresse_rue': _rueCtrl.text.trim(),
      'adresse_quartier': _quartierCtrl.text.trim(),
      'adresse_numero': _numeroCtrl.text.trim(),
      'contact_prefix': _prefixCtrl.text.trim(),
      'contact_telephone': _telephoneCtrl.text.trim(),
      'contact_email': optional(_emailCtrl.text),
      'entreprise_nom': optional(_entrepriseNomCtrl.text),
      'id_nat': optional(_idNatCtrl.text),
      'rccm': optional(_rccmCtrl.text),
    };
  }

  Future<bool> _showAssujettiPreviewDialog({
    required String? communeName,
  }) async {
    String valueOrDash(String? value) {
      final text = value?.trim() ?? '';
      return text.isEmpty ? '-' : text;
    }

    final isPersonneMorale = _assujettiStatus == 'Personne morale';
    final rows = <({String label, String value})>[
      (label: 'Statut', value: _assujettiStatus),
      (label: 'Nom', value: valueOrDash(_nomCtrl.text)),
      (label: 'Postnom', value: valueOrDash(_postnomCtrl.text)),
      (label: 'Prénom', value: valueOrDash(_prenomCtrl.text)),
      (label: 'Lieu de naissance', value: valueOrDash(_lieuNaissanceCtrl.text)),
      (label: 'Date de naissance', value: valueOrDash(_dateNaissanceCtrl.text)),
      (label: 'Nationalité', value: valueOrDash(_nationaliteCtrl.text)),
      (label: 'Sexe', value: _sexe),
      (label: 'Commune', value: valueOrDash(communeName)),
      (label: 'Rue', value: valueOrDash(_rueCtrl.text)),
      (label: 'Quartier', value: valueOrDash(_quartierCtrl.text)),
      (label: 'Numéro', value: valueOrDash(_numeroCtrl.text)),
      (
        label: 'Téléphone',
        value:
            '${valueOrDash(_prefixCtrl.text)} ${valueOrDash(_telephoneCtrl.text)}',
      ),
      (label: 'Email', value: valueOrDash(_emailCtrl.text)),
      if (isPersonneMorale) ...[
        (
          label: "Nom de l'entreprise",
          value: valueOrDash(_entrepriseNomCtrl.text),
        ),
        (label: 'N° ID nat', value: valueOrDash(_idNatCtrl.text)),
        (label: 'RCCM', value: valueOrDash(_rccmCtrl.text)),
      ],
      (
        label: "Pièce d'identité",
        value: _identityFileName == null ? 'Non jointe' : _identityFileName!,
      ),
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Aperçu de l’assujetti'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final row in rows)
                    _AssujettiPreviewRow(label: row.label, value: row.value),
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
              label: const Text('Valider l’enregistrement'),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  List<Map<String, dynamic>> get _visibleNotes {
    final rows = _notes.where(_isInTaxationDateRange).where((row) {
      if (!_unordonnedOnly) return true;
      return _isUnvalidatedByOrdonnateur(row);
    }).toList();
    rows.sort((a, b) {
      final ad = _noteTaxationDate(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = _noteTaxationDate(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    return rows;
  }

  double get _totalAmount => _visibleNotes.fold<double>(
    0,
    (total, row) => total + ((row['amount'] as num?)?.toDouble() ?? 0),
  );

  String _communeName(Map<String, dynamic> row) {
    final commune = row['communes'];
    if (commune is Map) {
      final name = commune['name']?.toString().trim();
      if (name != null && name.isNotEmpty) return name;
    }
    return row['collection_scope'] == 'mairie' ? 'Mairie' : 'Commune';
  }

  String _pointTaxation(Map<String, dynamic> row) {
    final communeName = _communeName(row).trim();
    final fallback = widget.profile.communeName?.trim();
    if (communeName.isEmpty ||
        communeName == '-' ||
        communeName.toLowerCase() == 'commune' ||
        communeName.toLowerCase() == 'mairie') {
      return fallback == null || fallback.isEmpty
          ? 'Mairie'
          : 'Mairie de $fallback';
    }
    return communeName.toLowerCase().startsWith('mairie')
        ? communeName
        : 'Mairie de $communeName';
  }

  String _taxateurName(Map<String, dynamic> row) {
    final taxateurId = row['taxateur_id']?.toString().trim();
    final createdBy = row['created_by']?.toString().trim();
    final id = taxateurId != null && taxateurId.isNotEmpty
        ? taxateurId
        : createdBy;
    if (id == null || id.isEmpty) return '-';
    return _taxateurNames[id] ?? '-';
  }

  String _noteNature(Map<String, dynamic> row) {
    final category = row['tax_category']?.toString().trim();
    if (category != null && category.isNotEmpty) return category;
    final tariff = row['tariff_label']?.toString().trim();
    if (tariff != null && tariff.isNotEmpty) return tariff;
    final reference = row['legal_reference']?.toString().trim();
    return reference == null || reference.isEmpty ? '-' : reference;
  }

  Future<void> _showNoteDetails(Map<String, dynamic> row) async {
    final details = <({String label, String value})>[
      (
        label: 'Date de taxation',
        value: _formatDateTimeDisplay(row['created_at']?.toString()),
      ),
      (label: 'N° note', value: row['note_number']?.toString() ?? '-'),
      (label: 'Payeur', value: row['taxpayer_name']?.toString() ?? '-'),
      (label: "Nature d’acte", value: _noteNature(row)),
      (
        label: 'Montant',
        value: _money((row['amount'] as num?)?.toDouble() ?? 0),
      ),
      (label: 'Point de taxation', value: _pointTaxation(row)),
      (label: 'Taxateur', value: _taxateurName(row)),
      (label: 'Statut', value: _statusLabel(row['status']?.toString())),
      (
        label: "Avis de l'ordonnateur",
        value: row['ordonnateur_avis']?.toString() ?? '-',
      ),
    ];

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Détail de la note de taxation'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final item in details)
                  _AssujettiPreviewRow(label: item.label, value: item.value),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  String _taxationExportFileName() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'taxations_${now.year}-${two(now.month)}-${two(now.day)}_'
        '${two(now.hour)}-${two(now.minute)}.xlsx';
  }

  Future<void> _exportTaxationRows(List<Map<String, dynamic>> rows) async {
    if (_exportingTaxations) return;
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune taxation à exporter.')),
      );
      return;
    }

    setState(() => _exportingTaxations = true);
    try {
      final workbook = Excel.createExcel();
      const sheetName = 'Taxations';
      final defaultSheet = workbook.getDefaultSheet();
      if (defaultSheet != null && defaultSheet != sheetName) {
        workbook.rename(defaultSheet, sheetName);
      }
      final sheet = workbook[sheetName];
      sheet.appendRow([
        TextCellValue('N°'),
        TextCellValue('Date de taxation'),
        TextCellValue('N° note'),
        TextCellValue('Payeur'),
        TextCellValue("Nature d’acte"),
        TextCellValue('Montant'),
        TextCellValue('Point de taxation'),
        TextCellValue('Taxateur'),
        TextCellValue('Statut'),
      ]);
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        sheet.appendRow([
          IntCellValue(i + 1),
          TextCellValue(_formatDateTimeDisplay(row['created_at']?.toString())),
          TextCellValue(row['note_number']?.toString() ?? '-'),
          TextCellValue(row['taxpayer_name']?.toString() ?? '-'),
          TextCellValue(_noteNature(row)),
          DoubleCellValue((row['amount'] as num?)?.toDouble() ?? 0),
          TextCellValue(_pointTaxation(row)),
          TextCellValue(_taxateurName(row)),
          TextCellValue(_statusLabel(row['status']?.toString())),
        ]);
      }

      final fileName = _taxationExportFileName();
      final bytes = workbook.save(fileName: fileName);
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Impossible de générer le fichier Excel.');
      }

      final path = await FilePicker.saveFile(
        dialogTitle: 'Exporter les taxations',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: Uint8List.fromList(bytes),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            path == null || path.isEmpty
                ? 'Export annulé.'
                : 'Export Excel généré.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userFacingErrorMessage(e, prefix: 'Échec de l’export')),
        ),
      );
    } finally {
      if (mounted) setState(() => _exportingTaxations = false);
    }
  }

  Widget _buildTaxationListToolbar(List<Map<String, dynamic>> rows) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _loading ? null : () => _pickTaxationDate(start: true),
              icon: const Icon(Icons.event_outlined),
              label: Text(_dateFilterLabel(_taxationDateStart, 'Date début')),
            ),
            OutlinedButton.icon(
              onPressed: _loading
                  ? null
                  : () => _pickTaxationDate(start: false),
              icon: const Icon(Icons.event_available_outlined),
              label: Text(_dateFilterLabel(_taxationDateEnd, 'Date fin')),
            ),
            if (_taxationDateStart != null || _taxationDateEnd != null)
              TextButton.icon(
                onPressed: _loading ? null : _resetTaxationDateFilter,
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Réinitialiser'),
              ),
            FilledButton.icon(
              onPressed: _exportingTaxations
                  ? null
                  : () => _exportTaxationRows(rows),
              icon: _exportingTaxations
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_download_outlined),
              label: Text(_exportingTaxations ? 'Export...' : 'Exporter'),
            ),
          ],
        ),
      ),
    );
  }

  String _money(num amount) => '${amount.toStringAsFixed(2)} USD';

  String _statusLabel(String? status) {
    switch (status) {
      case 'taxation_creee':
        return 'Non conforme';
      case 'note_perception_generee':
        return 'Note de perception';
      case 'paiement_declare':
        return 'Paiement déclaré';
      case 'en_recouvrement':
        return 'En recouvrement';
      case 'apuree_cpi_genere':
        return 'Apurée';
      case 'annulee':
        return 'Non conforme';
      default:
        return status ?? '-';
    }
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.person_add_alt_1_outlined, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Identification et Taxation',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Actualiser',
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SegmentedButton<_TaxationTab>(
          segments: const [
            ButtonSegment(
              value: _TaxationTab.identification,
              icon: Icon(Icons.badge_outlined),
              label: Text('Identification'),
            ),
            ButtonSegment(
              value: _TaxationTab.taxation,
              icon: Icon(Icons.receipt_long_outlined),
              label: Text('Taxation'),
            ),
          ],
          selected: {_tab},
          onSelectionChanged: (selection) {
            setState(() {
              _tab = selection.first;
              _view = _TaxationView.dashboard;
            });
          },
        ),
      ],
    );
  }

  Widget _buildIdentification() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _ActionCard(
              icon: Icons.people_alt_outlined,
              title: 'Liste des assujettis',
              subtitle: 'Consulter les assujettis enregistres.',
              onTap: _showIdentificationList,
            ),
            _ActionCard(
              icon: Icons.person_add_alt_1_outlined,
              title: 'Ajouter assujetti',
              subtitle: 'Identifier une personne physique ou morale.',
              onTap: _showAddAssujetti,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _identificationView == _IdentificationView.add
            ? _buildAssujettiForm()
            : _buildAssujettiList(),
      ],
    );
  }

  Widget _buildAssujettiList() {
    if (_assujettis.isEmpty) {
      return _EmptyPanel(
        icon: Icons.badge_outlined,
        message: 'Aucun assujetti enregistré dans votre périmètre.',
      );
    }

    return Card(
      elevation: 0,
      child: RawScrollbar(
        controller: _assujettiTableScrollCtrl,
        thumbVisibility: true,
        trackVisibility: true,
        notificationPredicate: (notification) => notification.depth == 0,
        thickness: 8,
        radius: const Radius.circular(999),
        child: SingleChildScrollView(
          controller: _assujettiTableScrollCtrl,
          scrollDirection: Axis.horizontal,
          primary: false,
          padding: const EdgeInsets.only(bottom: 12),
          child: DataTable(
            columns: const [
              DataColumn(label: Text('N°')),
              DataColumn(label: Text('NIP')),
              DataColumn(label: Text('Nom')),
              DataColumn(label: Text('Prénom')),
              DataColumn(label: Text("Nom de l'entreprise")),
              DataColumn(label: Text('RCCM')),
              DataColumn(label: Text('ID nat')),
              DataColumn(label: Text('Statut')),
              DataColumn(label: Text('Email')),
              DataColumn(label: Text('Téléphone')),
              DataColumn(label: Text('Adresse')),
              DataColumn(label: Text('Genre')),
              DataColumn(label: Text("Date d'ajout")),
              DataColumn(label: Text('Action')),
            ],
            rows: [
              for (var i = 0; i < _assujettis.length; i++)
                DataRow(
                  cells: [
                    DataCell(Text('${i + 1}')),
                    DataCell(Text(_assujettiNip(_assujettis[i]))),
                    DataCell(Text(_fieldOrDash(_assujettis[i], 'nom'))),
                    DataCell(Text(_fieldOrDash(_assujettis[i], 'prenom'))),
                    DataCell(
                      Text(_fieldOrDash(_assujettis[i], 'entreprise_nom')),
                    ),
                    DataCell(Text(_fieldOrDash(_assujettis[i], 'rccm'))),
                    DataCell(Text(_fieldOrDash(_assujettis[i], 'id_nat'))),
                    DataCell(Text(_assujettiStatusLabel(_assujettis[i]))),
                    DataCell(
                      Text(_fieldOrDash(_assujettis[i], 'contact_email')),
                    ),
                    DataCell(Text(_assujettiPhone(_assujettis[i]))),
                    DataCell(
                      SizedBox(
                        width: 240,
                        child: Text(
                          _assujettiAddress(_assujettis[i]),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(Text(_assujettiGenre(_assujettis[i]))),
                    DataCell(
                      Text(
                        _formatDateDisplay(
                          _assujettis[i]['created_at']?.toString(),
                        ),
                      ),
                    ),
                    DataCell(_assujettiActions(_assujettis[i])),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _fieldOrDash(Map<String, dynamic> row, String key) {
    final value = row[key]?.toString().trim() ?? '';
    return value.isEmpty ? '-' : value;
  }

  String _assujettiNip(Map<String, dynamic> assujetti) {
    final id = _fieldValue(assujetti, 'id');
    if (id.isEmpty) return '-';
    final compact = id.replaceAll('-', '');
    final length = compact.length < 8 ? compact.length : 8;
    return 'ASJ-${compact.substring(0, length).toUpperCase()}';
  }

  String _assujettiName(Map<String, dynamic> assujetti) {
    return [
      assujetti['nom']?.toString() ?? '',
      assujetti['postnom']?.toString() ?? '',
      assujetti['prenom']?.toString() ?? '',
    ].where((part) => part.trim().isNotEmpty).join(' ');
  }

  String _assujettiCommune(Map<String, dynamic> assujetti) {
    final commune = assujetti['communes'];
    if (commune is Map) {
      final name = commune['name']?.toString().trim();
      if (name != null && name.isNotEmpty) return name;
    }
    return assujetti['adresse_commune']?.toString() ?? '-';
  }

  String _assujettiAddress(Map<String, dynamic> assujetti) {
    final parts = [
      _assujettiCommune(assujetti),
      _fieldValue(assujetti, 'adresse_quartier'),
      _fieldValue(assujetti, 'adresse_rue'),
      _fieldValue(assujetti, 'adresse_numero'),
    ].where((part) => part.trim().isNotEmpty && part != '-').toList();
    return parts.isEmpty ? '-' : parts.join(', ');
  }

  String _assujettiPhone(Map<String, dynamic> assujetti) {
    final prefix = _fieldValue(assujetti, 'contact_prefix');
    final phone = _fieldValue(assujetti, 'contact_telephone');
    final text = [prefix, phone].where((part) => part.isNotEmpty).join(' ');
    return text.isEmpty ? '-' : text;
  }

  String _assujettiGenre(Map<String, dynamic> assujetti) {
    final sexe = _fieldValue(assujetti, 'sexe');
    if (sexe == 'Feminin') return 'Féminin';
    return sexe.isEmpty ? '-' : sexe;
  }

  String _assujettiStatusLabel(Map<String, dynamic> assujetti) {
    return assujetti['status']?.toString() == 'personne_morale'
        ? 'Personne morale'
        : 'Personne physique';
  }

  Widget _assujettiActions(Map<String, dynamic> assujetti) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Modifier',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => _editAssujetti(assujetti),
        ),
        IconButton(
          tooltip: 'Supprimer',
          icon: const Icon(Icons.delete_outline),
          color: Theme.of(context).colorScheme.error,
          onPressed: () => _deleteAssujetti(assujetti),
        ),
      ],
    );
  }

  Widget _buildAssujettiForm() {
    final isPersonneMorale = _assujettiStatus == 'Personne morale';
    final editing = _editingAssujettiId != null;
    return Form(
      key: _assujettiFormKey,
      child: Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      editing ? 'Modifier assujetti' : 'Ajouter assujetti',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Annuler',
                    onPressed: _savingAssujetti ? null : _cancelAssujettiForm,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _assujettiStatus,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: 'Personne physique',
                    child: Text('Personne physique'),
                  ),
                  DropdownMenuItem(
                    value: 'Personne morale',
                    child: Text('Personne morale'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _assujettiStatus = value);
                },
                decoration: _inputDecoration(
                  label: 'Statut',
                  icon: Icons.account_circle_outlined,
                  isRequired: true,
                ),
              ),
              const SizedBox(height: 16),
              _FormTitle(icon: Icons.person_outline, title: 'Identité'),
              const SizedBox(height: 12),
              _ResponsiveFields(
                children: [
                  _textField(_nomCtrl, 'Nom', Icons.person_outline),
                  _textField(_postnomCtrl, 'Postnom', Icons.person_outline),
                  _textField(_prenomCtrl, 'Prénom', Icons.person_outline),
                ],
              ),
              const SizedBox(height: 12),
              _ResponsiveFields(
                children: [
                  _textField(
                    _lieuNaissanceCtrl,
                    'Lieu de naissance',
                    Icons.place_outlined,
                  ),
                  _dateField(),
                  _textField(
                    _nationaliteCtrl,
                    'Nationalité',
                    Icons.flag_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _sexe,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'Masculin', child: Text('Masculin')),
                  DropdownMenuItem(value: 'Feminin', child: Text('Féminin')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _sexe = value);
                },
                decoration: _inputDecoration(
                  label: 'Sexe',
                  icon: Icons.wc,
                  isRequired: true,
                ),
              ),
              const Divider(height: 30),
              _FormTitle(icon: Icons.home_work_outlined, title: 'Adresse'),
              const SizedBox(height: 12),
              _ResponsiveFields(
                children: [
                  _buildAssujettiCommuneDropdown(),
                  _textField(_rueCtrl, 'Rue', Icons.signpost_outlined),
                  _textField(_quartierCtrl, 'Quartier', Icons.map_outlined),
                  _textField(_numeroCtrl, 'Numéro', Icons.numbers_outlined),
                ],
              ),
              const Divider(height: 30),
              _FormTitle(icon: Icons.contact_phone_outlined, title: 'Contact'),
              const SizedBox(height: 12),
              _ResponsiveFields(
                children: [
                  _textField(_prefixCtrl, 'Préfixe', Icons.add_call),
                  _textField(
                    _telephoneCtrl,
                    'Téléphone',
                    Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                  ),
                  _textField(
                    _emailCtrl,
                    'Email',
                    Icons.mail_outline,
                    isRequired: false,
                    keyboardType: TextInputType.emailAddress,
                  ),
                ],
              ),
              if (isPersonneMorale) ...[
                const Divider(height: 30),
                _FormTitle(
                  icon: Icons.apartment_outlined,
                  title: "Information de l'entreprise",
                ),
                const SizedBox(height: 12),
                _ResponsiveFields(
                  children: [
                    _textField(
                      _entrepriseNomCtrl,
                      "Nom de l'entreprise",
                      Icons.business_outlined,
                    ),
                    _textField(
                      _idNatCtrl,
                      'N° ID nat',
                      Icons.badge_outlined,
                      isRequired: false,
                    ),
                    _textField(
                      _rccmCtrl,
                      'RCCM',
                      Icons.description_outlined,
                      isRequired: false,
                    ),
                  ],
                ),
              ],
              const Divider(height: 30),
              _FormTitle(
                icon: Icons.file_present_outlined,
                title: "Pièce d'identité",
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _savingAssujetti ? null : _pickIdentityFile,
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(
                  _identityFileName == null
                      ? 'Importer un fichier'
                      : _identityFileName!,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: _savingAssujetti ? null : _validateAssujettiForm,
                    icon: _savingAssujetti
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(
                      _savingAssujetti
                          ? 'Enregistrement...'
                          : editing
                          ? 'Modifier'
                          : 'Valider',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _savingAssujetti ? null : _cancelAssujettiForm,
                    icon: const Icon(Icons.close),
                    label: const Text('Annuler'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? hintText,
    bool isRequired = false,
  }) {
    return InputDecoration(
      labelText: isRequired ? '$label *' : label,
      hintText: hintText,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Theme.of(context).colorScheme.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.border.withValues(alpha: 0.9)),
      ),
    );
  }

  DropdownButtonFormField<String> _buildAssujettiCommuneDropdown() {
    final selected =
        _communes.any((commune) => commune.id == _assujettiCommuneId)
        ? _assujettiCommuneId
        : null;
    return DropdownButtonFormField<String>(
      initialValue: selected,
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
      onChanged: _savingAssujetti
          ? null
          : (value) => setState(() => _assujettiCommuneId = value),
      validator: (value) =>
          value == null || value.isEmpty ? 'Champ requis' : null,
      decoration: _inputDecoration(
        label: 'Commune',
        icon: Icons.location_city_outlined,
        hintText: _communes.isEmpty ? 'Aucune commune disponible' : null,
        isRequired: true,
      ),
    );
  }

  TextFormField _textField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool isRequired = true,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: isRequired
          ? (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Champ requis';
              }
              return null;
            }
          : null,
      decoration: _inputDecoration(
        label: label,
        icon: icon,
        isRequired: isRequired,
      ),
    );
  }

  TextFormField _dateField() {
    return TextFormField(
      controller: _dateNaissanceCtrl,
      readOnly: true,
      validator: (value) {
        if (value == null || value.trim().isEmpty) return 'Champ requis';
        return null;
      },
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime(now.year - 18, now.month, now.day),
          firstDate: DateTime(1900),
          lastDate: now,
        );
        if (picked == null) return;
        _dateNaissanceCtrl.text =
            '${picked.day.toString().padLeft(2, '0')}/'
            '${picked.month.toString().padLeft(2, '0')}/${picked.year}';
      },
      decoration: _inputDecoration(
        label: 'Date de naissance',
        icon: Icons.calendar_month_outlined,
        isRequired: true,
      ),
    );
  }

  Widget _buildTaxationDashboard(BuildContext context) {
    final visibleNotes = _visibleNotes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _ActionCard(
              icon: Icons.add_circle_outline,
              title: 'Nouvelle taxation',
              subtitle: 'Créer une note de taxation.',
              onTap: () => setState(() => _view = _TaxationView.newTaxation),
            ),
            _ActionCard(
              icon: Icons.format_list_bulleted_outlined,
              title: 'Liste des taxations',
              subtitle: 'Afficher toutes les taxations.',
              onTap: () => _openTaxationList(unordonnedOnly: false),
            ),
            _ActionCard(
              icon: Icons.pending_actions_outlined,
              title: 'Notes non conformes',
              subtitle: "Voir les taxations non validées par l'ordonnateur.",
              onTap: () => _openTaxationList(unordonnedOnly: true),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = constraints.maxWidth >= 720
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: _MetricCard(
                    label: _unordonnedOnly
                        ? 'Total des notes non validées'
                        : 'Total des notes',
                    value: visibleNotes.length.toString(),
                    icon: Icons.receipt_long_outlined,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _MetricCard(
                    label: 'Montant total',
                    value: _money(_totalAmount),
                    icon: Icons.payments_outlined,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _buildTaxationListToolbar(visibleNotes),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                _unordonnedOnly
                    ? "Liste des notes non conformes non validées par l'ordonnateur"
                    : 'Toutes les taxations effectuées',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            if (_unordonnedOnly)
              TextButton.icon(
                onPressed: () => _openTaxationList(unordonnedOnly: false),
                icon: const Icon(Icons.format_list_bulleted_outlined),
                label: const Text('Tout afficher'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _buildNotesTable(visibleNotes),
      ],
    );
  }

  Widget _buildNotesTable(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return _EmptyPanel(
        icon: Icons.receipt_long_outlined,
        message: _unordonnedOnly
            ? "Aucune note de taxation non validée par l'ordonnateur dans votre périmètre."
            : 'Aucune taxation effectuée dans votre périmètre.',
      );
    }

    return Card(
      elevation: 0,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('N°')),
            DataColumn(label: Text('Date de taxation')),
            DataColumn(label: Text('N° note')),
            DataColumn(label: Text('Payeur')),
            DataColumn(label: Text("Nature d’acte")),
            DataColumn(label: Text('Montant')),
            DataColumn(label: Text('Point de taxation')),
            DataColumn(label: Text('Taxateur')),
            DataColumn(label: Text('Statut')),
            DataColumn(label: Text('Action')),
          ],
          rows: [
            for (var i = 0; i < rows.length; i++)
              DataRow(
                cells: [
                  DataCell(Text('${i + 1}')),
                  DataCell(
                    Text(
                      _formatDateTimeDisplay(rows[i]['created_at']?.toString()),
                    ),
                  ),
                  DataCell(Text(rows[i]['note_number']?.toString() ?? '-')),
                  DataCell(
                    SizedBox(
                      width: 180,
                      child: Text(
                        rows[i]['taxpayer_name']?.toString() ?? '-',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 260,
                      child: Text(
                        _noteNature(rows[i]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(_money((rows[i]['amount'] as num?)?.toDouble() ?? 0)),
                  ),
                  DataCell(Text(_pointTaxation(rows[i]))),
                  DataCell(Text(_taxateurName(rows[i]))),
                  DataCell(Text(_statusLabel(rows[i]['status']?.toString()))),
                  DataCell(
                    IconButton(
                      tooltip: 'Voir',
                      icon: const Icon(Icons.visibility_outlined),
                      onPressed: () => _showNoteDetails(rows[i]),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Card(
        elevation: 0,
        child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
      );
    }
    if (_view == _TaxationView.newTaxation) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: () {
              setState(() => _view = _TaxationView.dashboard);
              _load();
            },
            icon: const Icon(Icons.arrow_back),
            label: const Text('Retour'),
          ),
          const SizedBox(height: 8),
          PerceptionNoteScreen(
            profile: widget.profile,
            mode: NoteWorkflowMode.taxation,
            embedded: true,
          ),
        ],
      );
    }
    return _tab == _TaxationTab.identification
        ? _buildIdentification()
        : _buildTaxationDashboard(context);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 18),
          _buildContent(context),
        ],
      ),
    );
  }
}

class _AssujettiPreviewRow extends StatelessWidget {
  const _AssujettiPreviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
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

class _ResponsiveFields extends StatelessWidget {
  const _ResponsiveFields({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980
            ? 3
            : constraints.maxWidth >= 640
            ? 2
            : 1;
        final width = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - (12 * (columns - 1))) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _FormTitle extends StatelessWidget {
  const _FormTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 260,
      child: Card(
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(icon, color: AppColors.chartTeal),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
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
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(icon, color: AppColors.mutedText),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
