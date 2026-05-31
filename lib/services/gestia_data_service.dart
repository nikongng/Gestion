import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_env.dart';
import '../data/chart_data.dart';
import '../models/app_alert.dart';
import '../models/app_role.dart';
import '../models/user_profile.dart';

class GestiaDataService {
  GestiaDataService._();

  static const _collectionsSelectWithScope =
      'id, commune_id, amount, tax_category, payment_channel, collection_scope, collected_at, created_by, taxpayer_profile_id, taxpayer_identifier, communes(name)';
  static const _collectionsSelectWithWorkflow =
      'id, commune_id, amount, tax_category, payment_channel, collection_scope, collected_at, created_by, taxpayer_profile_id, taxpayer_identifier, revenue_phase, workflow_status, perception_note_number, cpi_number, paid_at, apured_at, is_auto_liquidated, communes(name)';
  static const _collectionsSelectLegacy =
      'id, commune_id, amount, tax_category, payment_channel, collected_at, created_by, taxpayer_profile_id, taxpayer_identifier, communes(name)';

  static SupabaseClient get _c {
    if (!SupabaseEnv.isConfigured) {
      throw StateError('Supabase non configuré');
    }
    return Supabase.instance.client;
  }

  static Future<UserProfile?> fetchProfile(String userId) async {
    Map<String, dynamic>? map;

    // Préfère la RPC (migration `get_my_profile_rpc`) : lit `auth.uid()` côté serveur,
    // évite les cas où le SELECT direct sur `profiles` est vide à cause de RLS / JWT.
    try {
      final res = await _c.rpc('get_my_profile');
      if (res is List) {
        if (res.isEmpty) {
          map = null;
        } else {
          map = Map<String, dynamic>.from(res.first as Map);
        }
      } else if (res is Map) {
        map = Map<String, dynamic>.from(res);
      }
    } catch (_) {
      map = null;
    }

    if (map == null) {
      final row = await _c
          .from('profiles')
          .select(
            'id, full_name, role, roles, commune_id, avatar_url, taxpayer_identifier, taxpayer_email, taxpayer_phone, taxpayer_address, legal_nif, account_status, taxpayer_status',
          )
          .eq('id', userId)
          .maybeSingle();
      if (row == null) return null;
      map = Map<String, dynamic>.from(row as Map);
    }

    final profileRow = map;
    final communeId = profileRow['commune_id']?.toString();
    if (communeId != null && communeId.isNotEmpty) {
      final communeRow = await _c
          .from('communes')
          .select('name')
          .eq('id', communeId)
          .maybeSingle();
      if (communeRow != null) {
        final cm = Map<String, dynamic>.from(communeRow as Map);
        profileRow['communes'] = {'name': cm['name']};
      }
    }
    return UserProfile.fromRow(profileRow);
  }

  static Future<List<UserProfile>> fetchAllProfiles() async {
    final rows = await _c
        .from('profiles')
        .select(
          'id, full_name, role, roles, commune_id, avatar_url, taxpayer_identifier, taxpayer_email, taxpayer_phone, taxpayer_address, legal_nif, account_status, taxpayer_status, communes(name)',
        )
        .order('full_name');
    final profileRows = rows
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final lastSignIns = await _fetchUsersLastSignIn();
    for (final row in profileRows) {
      final id = row['id']?.toString();
      if (id != null && lastSignIns.containsKey(id)) {
        row['last_sign_in_at'] = lastSignIns[id];
      }
    }
    return profileRows
        .map(UserProfile.fromRow)
        .whereType<UserProfile>()
        .toList();
  }

  static Future<Map<String, String?>> _fetchUsersLastSignIn() async {
    try {
      final response = await _c.rpc('get_users_last_sign_in');
      if (response is! List) return const {};
      return {
        for (final item in response)
          if (item is Map && item['id'] != null)
            item['id'].toString(): item['last_sign_in_at']?.toString(),
      };
    } catch (_) {
      return const {};
    }
  }

  static Future<UserProfile?> fetchProfileByTaxpayerIdentifier(
    String taxpayerIdentifier,
  ) async {
    final identifier = taxpayerIdentifier.trim();
    if (identifier.isEmpty) return null;

    try {
      final res = await _c.rpc(
        'lookup_taxpayer_profile',
        params: {'p_taxpayer_identifier': identifier},
      );
      Map<String, dynamic>? map;
      if (res is List) {
        if (res.isNotEmpty) {
          map = Map<String, dynamic>.from(res.first as Map);
        }
      } else if (res is Map) {
        map = Map<String, dynamic>.from(res);
      }
      if (map != null) {
        return UserProfile.fromRow(map);
      }
    } catch (_) {
      // Fallback sur le SELECT direct si la fonction SQL n'est pas encore deployee.
    }

    final row = await _c
        .from('profiles')
        .select(
          'id, full_name, role, roles, commune_id, avatar_url, taxpayer_identifier, taxpayer_email, taxpayer_phone, taxpayer_address, legal_nif, account_status, taxpayer_status, communes(name)',
        )
        .ilike('taxpayer_identifier', identifier)
        .maybeSingle();

    if (row == null) return null;
    return UserProfile.fromRow(Map<String, dynamic>.from(row as Map));
  }

  static bool _isMissingCollectionScope(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('collection_scope') &&
        (message.contains('column') ||
            message.contains('schema cache') ||
            message.contains('could not find'));
  }

  static bool _isMissingCollectionWorkflow(Object error) {
    final message = error.toString().toLowerCase();
    const columns = [
      'revenue_phase',
      'workflow_status',
      'perception_note_number',
      'cpi_number',
      'paid_at',
      'apured_at',
      'is_auto_liquidated',
    ];
    return columns.any(message.contains) &&
        (message.contains('column') ||
            message.contains('schema cache') ||
            message.contains('could not find'));
  }

  static bool _isMissingPerceptionNotesSchema(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('perception_notes') ||
        message.contains('perception_note_number') ||
        message.contains('ordonnateur_avis') ||
        message.contains('schema cache') ||
        message.contains('could not find');
  }

  static bool _isMissingTaxpayerCommentColumn(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('taxpayer_comment') &&
        (message.contains('column') ||
            message.contains('schema cache') ||
            message.contains('could not find'));
  }

  static bool _isMissingApurementValidationColumns(Object error) {
    final message = error.toString().toLowerCase();
    return (message.contains('apurement_comment') ||
            message.contains('bank_slip_submitted')) &&
        (message.contains('column') ||
            message.contains('schema cache') ||
            message.contains('could not find'));
  }

  static bool _isMissingAssujettisSchema(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('assujettis') ||
        message.contains('assujetti-documents') ||
        message.contains('schema cache') ||
        message.contains('could not find');
  }

  static bool _isNullCommuneConstraint(Object error) {
    final message = error.toString().toLowerCase();
    final mentionsCommuneId =
        message.contains('commune_id') || message.contains('commune id');
    return mentionsCommuneId &&
        (message.contains('23502') ||
            message.contains('null value') ||
            message.contains('not-null') ||
            message.contains('not null'));
  }

  static bool _isMairieCollectionRow(Map<String, dynamic> row) {
    final scope = row['collection_scope']?.toString().trim().toLowerCase();
    if (scope == 'mairie') return true;
    if (scope == 'commune') return false;
    final category = row['tax_category']?.toString().toLowerCase() ?? '';
    return category.contains('mairie');
  }

  static Future<Map<String, String>> fetchProfileNamesByIds(
    Iterable<String> userIds,
  ) async {
    final ids = userIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return const {};

    try {
      final response = await _c.rpc(
        'lookup_profile_names',
        params: {'p_user_ids': ids},
      );
      final rows = response as List;
      return {
        for (final raw in rows)
          Map<String, dynamic>.from(raw as Map)['id'].toString():
              (Map<String, dynamic>.from(raw)['full_name']?.toString() ??
              'Utilisateur'),
      };
    } catch (_) {
      final profiles = await fetchAllProfiles();
      return {
        for (final item in profiles)
          if (ids.contains(item.id)) item.id: item.fullName,
      };
    }
  }

  static Future<void> updateCommuneName({
    required String communeId,
    required String name,
  }) async {
    await _c.from('communes').update({'name': name.trim()}).eq('id', communeId);
  }

  static Future<void> insertCommune({required String name}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Nom de commune réquis.');
    }
    await _c.from('communes').insert({'name': trimmed});
  }

  static Future<List<({String id, String name})>> fetchCommunes() async {
    final rows =
        await _c.from('communes').select('id, name').order('name') as List;
    return rows.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return (id: m['id'] as String, name: m['name'] as String);
    }).toList();
  }

  static Future<Map<String, dynamic>> buildBackupSnapshot({
    required UserProfile profile,
  }) async {
    Future<List<Map<String, dynamic>>> rows(String table) async {
      try {
        final response = await _c.from(table).select() as List;
        return response
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
      } catch (_) {
        return const [];
      }
    }

    return {
      'metadata': {
        'generated_at': DateTime.now().toUtc().toIso8601String(),
        'generated_by': profile.id,
        'generated_by_name': profile.fullName,
        'roles': profile.roles.map((role) => role.dbValue).toList(),
      },
      'app_settings': await rows('app_settings'),
      'profiles': profile.canManageApp ? await rows('profiles') : const [],
      'communes': await rows('communes'),
      'assujettis': await rows('assujettis'),
      'perception_notes': await rows('perception_notes'),
      'collections': await rows('collections'),
    };
  }

  static bool _isMissingReceiptTypesColumn(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('receipt_types') &&
        (message.contains('column') ||
            message.contains('schema cache') ||
            message.contains('could not find'));
  }

  static Future<List<String>> fetchCustomReceiptTypes() async {
    try {
      final row = await _c
          .from('app_settings')
          .select('receipt_types')
          .eq('id', 1)
          .maybeSingle();
      if (row == null) return const [];
      final raw = Map<String, dynamic>.from(row as Map)['receipt_types'];
      if (raw is! List) return const [];
      return _cleanStringList(raw);
    } catch (e) {
      if (_isMissingReceiptTypesColumn(e)) return const [];
      rethrow;
    }
  }

  static Future<List<String>> addCustomReceiptType(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Type de recette réquis.');
    }

    final current = await fetchCustomReceiptTypes();
    final exists = current.any(
      (item) => item.toLowerCase() == trimmed.toLowerCase(),
    );
    final next = exists ? current : [...current, trimmed]
      ..sort();

    try {
      await _c
          .from('app_settings')
          .update({
            'receipt_types': next,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', 1);
    } catch (e) {
      if (_isMissingReceiptTypesColumn(e)) {
        throw StateError(
          'Migrez Supabase avec 20260527120000_add_receipt_types_to_app_settings.sql.',
        );
      }
      rethrow;
    }
    return next;
  }

  static List<String> _cleanStringList(List<Object?> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isEmpty) continue;
      final key = text.toLowerCase();
      if (seen.add(key)) result.add(text);
    }
    return result;
  }

  static Future<List<Map<String, dynamic>>> fetchCollectionsInRange({
    required DateTime from,
    required DateTime to,
    String? communeId,
    String? taxpayerProfileId,
  }) async {
    Future<List<Map<String, dynamic>>> load(String selectColumns) async {
      var q = _c
          .from('collections')
          .select(selectColumns)
          .gte('collected_at', from.toUtc().toIso8601String())
          .lte('collected_at', to.toUtc().toIso8601String());
      if (communeId != null) {
        q = q.eq('commune_id', communeId);
      }
      if (taxpayerProfileId != null) {
        q = q.eq('taxpayer_profile_id', taxpayerProfileId);
      }
      final response = await q;
      final rows = response as List;
      return rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }

    try {
      return await load(_collectionsSelectWithWorkflow);
    } catch (e) {
      if (_isMissingCollectionWorkflow(e)) {
        return load(_collectionsSelectWithScope);
      }
      if (_isMissingCollectionScope(e)) {
        return load(_collectionsSelectLegacy);
      }
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>>
  fetchCollectionsByTaxpayerIdentifier({
    required String taxpayerIdentifier,
    String? communeId,
  }) async {
    final identifier = taxpayerIdentifier.trim();
    if (identifier.isEmpty) return [];

    Future<List<Map<String, dynamic>>> load(String selectColumns) async {
      var q = _c
          .from('collections')
          .select(selectColumns)
          .ilike('taxpayer_identifier', identifier);

      if (communeId != null) {
        q = q.eq('commune_id', communeId);
      }

      final response = await q.order('collected_at', ascending: false);
      final rows = response as List;
      return rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }

    try {
      return await load(_collectionsSelectWithWorkflow);
    } catch (e) {
      if (_isMissingCollectionWorkflow(e)) {
        return load(_collectionsSelectWithScope);
      }
      if (_isMissingCollectionScope(e)) {
        return load(_collectionsSelectLegacy);
      }
      rethrow;
    }
  }

  static Future<TaxpayerVerificationResult> verifyTaxPaymentByIdentifier({
    required String taxpayerIdentifier,
    String? communeId,
  }) async {
    final identifier = taxpayerIdentifier.trim();
    if (identifier.isEmpty) {
      throw ArgumentError('Identifiant réquis.');
    }

    final profile = await fetchProfileByTaxpayerIdentifier(identifier);
    final collections = await fetchCollectionsByTaxpayerIdentifier(
      taxpayerIdentifier: identifier,
      communeId: communeId,
    );

    final creatorIds = collections
        .map((row) => row['created_by']?.toString())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet();
    final collectorNames = await fetchProfileNamesByIds(creatorIds);

    return TaxpayerVerificationResult(
      taxpayerIdentifier: profile?.taxpayerIdentifier?.trim().isNotEmpty == true
          ? profile!.taxpayerIdentifier!.trim()
          : identifier,
      profile: profile,
      collections: collections,
      collectorNames: collectorNames,
    );
  }

  /// Lignes pour le tableau des communes (recettes du jour, bourgmestre si visible en RLS).
  static Future<List<CommuneOverviewRow>> fetchCommunesOverview({
    String? filterCommuneId,
    String? taxpayerProfileId,
  }) async {
    var communes = await fetchCommunes();
    if (filterCommuneId != null) {
      communes = communes.where((c) => c.id == filterCommuneId).toList();
    }
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final txs = await fetchCollectionsInRange(
      from: dayStart,
      to: dayEnd,
      communeId: filterCommuneId,
      taxpayerProfileId: taxpayerProfileId,
    );
    final sumByCommune = <String, double>{};
    final countByCommune = <String, int>{};
    for (final t in txs) {
      if (_isMairieCollectionRow(t)) continue;
      final id = t['commune_id']?.toString();
      if (id == null || id.isEmpty) continue;
      sumByCommune[id] =
          (sumByCommune[id] ?? 0) + (t['amount'] as num).toDouble();
      countByCommune[id] = (countByCommune[id] ?? 0) + 1;
    }

    final bmRows = await _c
        .from('profiles')
        .select('full_name, commune_id')
        .eq('role', 'bourgmestre');
    final bmList = (bmRows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final bmName = <String, String>{};
    for (final m in bmList) {
      final cid = m['commune_id'] as String?;
      if (cid != null) {
        bmName[cid] = m['full_name'] as String? ?? '—';
      }
    }

    final agentRows = await _c
        .from('profiles')
        .select('full_name, commune_id')
        .inFilter('role', ['agent', 'taxateur', 'ordonnateur', 'apureur']);
    final agentList = (agentRows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final agentNames = <String, List<String>>{};
    for (final m in agentList) {
      final cid = m['commune_id']?.toString();
      final name = m['full_name']?.toString().trim();
      if (cid == null || cid.isEmpty || name == null || name.isEmpty) {
        continue;
      }
      agentNames.putIfAbsent(cid, () => <String>[]).add(name);
    }
    for (final list in agentNames.values) {
      list.sort();
    }

    return [
      for (final c in communes)
        CommuneOverviewRow(
          communeId: c.id,
          name: c.name,
          agentNames: List.unmodifiable(agentNames[c.id] ?? const <String>[]),
          bourgmestreName: bmName[c.id] ?? 'de',
          revenueToday: sumByCommune[c.id] ?? 0,
          transactionsToday: countByCommune[c.id] ?? 0,
        ),
    ];
  }

  static Future<double> sumToday({
    String? communeId,
    String? taxpayerProfileId,
  }) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    final rows = await fetchCollectionsInRange(
      from: start,
      to: end,
      communeId: communeId,
      taxpayerProfileId: taxpayerProfileId,
    );
    var t = 0.0;
    for (final r in rows) {
      t += (r['amount'] as num).toDouble();
    }
    return t;
  }

  static Future<List<CommuneRevenue>> revenueByCommuneLast30Days({
    String? communeId,
    String? taxpayerProfileId,
  }) async {
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 30));
    final rows = await fetchCollectionsInRange(
      from: from,
      to: now,
      communeId: communeId,
      taxpayerProfileId: taxpayerProfileId,
    );
    final map = <String, double>{};
    for (final r in rows) {
      if (_isMairieCollectionRow(r)) continue;
      if (r['commune_id'] == null) continue;
      final commune = r['communes'] as Map<String, dynamic>?;
      final name = commune?['name'] as String? ?? '—';
      final amt = (r['amount'] as num).toDouble();
      map[name] = (map[name] ?? 0) + amt;
    }
    if (map.isEmpty) return [];
    final list = map.entries.map((e) => CommuneRevenue(e.key, e.value)).toList()
      ..sort((a, b) => b.amountUsd.compareTo(a.amountUsd));
    return list;
  }

  static Future<List<TaxSlice>> taxBreakdownLast30Days({
    String? communeId,
    String? taxpayerProfileId,
  }) async {
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 30));
    final rows = await fetchCollectionsInRange(
      from: from,
      to: now,
      communeId: communeId,
      taxpayerProfileId: taxpayerProfileId,
    );
    final map = <String, double>{};
    for (final r in rows) {
      final cat = r['tax_category'] as String? ?? 'Autres';
      final amt = (r['amount'] as num).toDouble();
      map[cat] = (map[cat] ?? 0) + amt;
    }
    if (map.isEmpty) return [];
    final total = map.values.fold<double>(0, (a, b) => a + b);
    const colors = [0xFF1366FF, 0xFF0FC2A5, 0xFFFF9F43, 0xFFE74C3C, 0xFF7C3AED];
    var i = 0;
    return map.entries.map((e) {
      final pct = total > 0 ? (e.value / total) * 100 : 0.0;
      final color = colors[i % colors.length];
      i++;
      return TaxSlice(e.key, pct, color);
    }).toList();
  }

  static Future<List<DailyRevenue>> last7DaysRevenue({
    String? communeId,
    String? taxpayerProfileId,
  }) async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final rangeStart = todayStart.subtract(const Duration(days: 6));
    final rangeEnd = todayStart.add(const Duration(days: 1));
    final rows = await fetchCollectionsInRange(
      from: rangeStart,
      to: rangeEnd,
      communeId: communeId,
      taxpayerProfileId: taxpayerProfileId,
    );
    const labels = ['Dim', 'Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam'];
    final byDay = <String, double>{};
    for (final r in rows) {
      final ts = DateTime.parse(r['collected_at'] as String).toLocal();
      final key = '${ts.year}-${ts.month}-${ts.day}';
      byDay[key] = (byDay[key] ?? 0) + (r['amount'] as num).toDouble();
    }
    final out = <DailyRevenue>[];
    for (var offset = 6; offset >= 0; offset--) {
      final d = todayStart.subtract(Duration(days: offset));
      final key = '${d.year}-${d.month}-${d.day}';
      final sum = byDay[key] ?? 0;
      final weekday = d.weekday % 7;
      out.add(DailyRevenue(labels[weekday], sum));
    }
    return out;
  }

  static const _monthFr = [
    'Jan',
    'Fév',
    'Mar',
    'Avr',
    'Mai',
    'Juin',
    'Juil',
    'Août',
    'Sep',
    'Oct',
    'Nov',
    'Déc',
  ];

  /// Réalisé par mois sur les 6 derniers mois ; objectif = réalisé × 1,05 (placeholder jusqu’à table d’objectifs).
  static Future<List<MonthGoalVsActual>> goalVsActualLast6Months({
    String? communeId,
    String? taxpayerProfileId,
  }) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 5, 1);
    final end = DateTime(now.year, now.month + 1, 1);
    final rows = await fetchCollectionsInRange(
      from: start,
      to: end,
      communeId: communeId,
      taxpayerProfileId: taxpayerProfileId,
    );
    final byMonth = <String, double>{};
    for (final r in rows) {
      final ts = DateTime.parse(r['collected_at'] as String).toLocal();
      final key = '${ts.year}-${ts.month}';
      byMonth[key] = (byMonth[key] ?? 0) + (r['amount'] as num).toDouble();
    }
    final out = <MonthGoalVsActual>[];
    for (var i = 0; i < 6; i++) {
      final ref = DateTime(start.year, start.month + i, 1);
      final key = '${ref.year}-${ref.month}';
      final actual = byMonth[key] ?? 0;
      final actualK = actual / 1000;
      final goalK = actualK > 0 ? actualK * 1.05 : 8.0;
      final label = _monthFr[ref.month - 1];
      out.add(MonthGoalVsActual(label, goalK, actualK));
    }
    return out;
  }

  static Future<void> insertCollection({
    String? communeId,
    required double amountUsd,
    required String taxCategory,
    String? paymentChannel,
    String collectionScope = 'commune',
    String? taxpayerProfileId,
    String? taxpayerIdentifier,
    String? perceptionNoteNumber,
    String? cpiNumber,
    String revenuePhase = 'apurement',
    String workflowStatus = 'apuree_cpi_genere',
    DateTime? paidAt,
    DateTime? apuredAt,
    bool isAutoLiquidated = false,
  }) async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) throw StateError('Non connecté');
    final normalizedScope = collectionScope.trim().toLowerCase();
    final isMairieCollection = normalizedScope == 'mairie';
    final now = DateTime.now().toUtc();
    final payload = <String, dynamic>{
      'amount': amountUsd,
      'tax_category': taxCategory,
      'payment_channel': paymentChannel,
      'collection_scope': isMairieCollection ? 'mairie' : 'commune',
      'created_by': uid,
      'taxpayer_profile_id': taxpayerProfileId,
      'taxpayer_identifier': taxpayerIdentifier,
      'perception_note_number': perceptionNoteNumber,
      'cpi_number': cpiNumber,
      'revenue_phase': revenuePhase,
      'workflow_status': workflowStatus,
      'paid_at': (paidAt ?? now).toUtc().toIso8601String(),
      'apured_at': (apuredAt ?? now).toUtc().toIso8601String(),
      'is_auto_liquidated': isAutoLiquidated,
    };
    if (communeId != null) {
      payload['commune_id'] = communeId;
    }

    try {
      await _c.from('collections').insert(payload);
    } catch (e) {
      if (_isMissingCollectionWorkflow(e)) {
        throw StateError(
          'Migrez Supabase avec 20260527130000_revenue_workflow_phases.sql.',
        );
      }
      if (isMairieCollection &&
          communeId == null &&
          _isNullCommuneConstraint(e)) {
        await _insertLegacyMairieCollection(payload);
        return;
      }
      if (!_isMissingCollectionScope(e)) rethrow;
      payload.remove('collection_scope');
      if (isMairieCollection && communeId == null) {
        await _insertLegacyMairieCollection(payload);
        return;
      }
      await _c.from('collections').insert(payload);
    }
  }

  static Future<void> deleteCollection(String collectionId) async {
    final id = collectionId.trim();
    if (id.isEmpty) return;
    await _c.from('collections').delete().eq('id', id);
  }

  static Future<void> insertPerceptionNote({
    required String noteNumber,
    String? communeId,
    String collectionScope = 'commune',
    required double amountUsd,
    required String taxCategory,
    String? paymentChannel,
    String? taxpayerProfileId,
    String? taxpayerIdentifier,
    String? taxpayerName,
    String? taxpayerPhone,
    String? taxpayerEmail,
    String? taxpayerAddress,
    String? taxpayerComment,
    required int paymentDelayDays,
    required DateTime paymentDeadline,
    String status = 'note_perception_generee',
    String? legalReference,
    String? tariffDetails,
    String? tariffLabel,
  }) async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) throw StateError('Non connecté');
    final normalizedScope = collectionScope.trim().toLowerCase();
    final isMairieNote = normalizedScope == 'mairie';
    final trimmedNoteNumber = noteNumber.trim();
    if (trimmedNoteNumber.isEmpty) {
      throw ArgumentError('Numéro de note requis.');
    }

    final payload = <String, dynamic>{
      'note_number': trimmedNoteNumber,
      'collection_scope': isMairieNote ? 'mairie' : 'commune',
      'amount': amountUsd,
      'tax_category': taxCategory,
      'payment_channel': paymentChannel,
      'taxpayer_profile_id': taxpayerProfileId,
      'taxpayer_identifier': taxpayerIdentifier,
      'taxpayer_name': taxpayerName,
      'taxpayer_phone': taxpayerPhone,
      'taxpayer_email': taxpayerEmail,
      'taxpayer_address': taxpayerAddress,
      'payment_delay_days': paymentDelayDays,
      'payment_deadline': paymentDeadline.toUtc().toIso8601String(),
      'status': status,
      'created_by': uid,
      'legal_reference': legalReference,
      'tariff_details': tariffDetails,
      'tariff_label': tariffLabel,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final normalizedComment = taxpayerComment?.trim();
    if (normalizedComment != null && normalizedComment.isNotEmpty) {
      payload['taxpayer_comment'] = normalizedComment;
    }
    if (communeId != null) {
      payload['commune_id'] = communeId;
    }
    if (status == 'taxation_creee') {
      payload['taxateur_id'] = uid;
    } else {
      payload['ordonnateur_id'] = uid;
    }

    try {
      await _c.from('perception_notes').insert(payload);
    } catch (e) {
      if (_isMissingTaxpayerCommentColumn(e) &&
          payload.remove('taxpayer_comment') != null) {
        await _c.from('perception_notes').insert(payload);
        return;
      }
      if (_isMissingPerceptionNotesSchema(e)) {
        throw StateError(
          'Migrez Supabase avec 20260527130000_revenue_workflow_phases.sql.',
        );
      }
      rethrow;
    }
  }

  static Future<void> markPerceptionNoteApured({
    required String noteNumber,
    required String cpiNumber,
    required DateTime paidAt,
  }) async {
    final trimmedNoteNumber = noteNumber.trim();
    if (trimmedNoteNumber.isEmpty) return;

    try {
      await _c
          .from('perception_notes')
          .update({
            'status': 'apuree_cpi_genere',
            'cpi_number': cpiNumber.trim(),
            'paid_at': paidAt.toUtc().toIso8601String(),
            'apured_at': DateTime.now().toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('note_number', trimmedNoteNumber);
    } catch (e) {
      if (_isMissingPerceptionNotesSchema(e)) {
        throw StateError(
          'Migrez Supabase avec 20260527130000_revenue_workflow_phases.sql.',
        );
      }
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> fetchPerceptionNotes({
    List<String>? statuses,
    String? communeId,
    bool overdueOnly = false,
    DateTime? createdFrom,
    DateTime? createdTo,
    int limit = 80,
  }) async {
    Future<List<Map<String, dynamic>>> load({
      required bool includeTaxpayerComment,
    }) async {
      var q = _c
          .from('perception_notes')
          .select(
            'id, note_number, commune_id, collection_scope, amount, tax_category, '
            'payment_channel, taxpayer_profile_id, taxpayer_identifier, taxpayer_name, taxpayer_phone, '
            'taxpayer_email, taxpayer_address, ${includeTaxpayerComment ? 'taxpayer_comment, ' : ''}payment_deadline, status, cpi_number, '
            'paid_at, apured_at, created_at, updated_at, taxateur_id, ordonnateur_id, created_by, ordonnateur_avis, legal_reference, tariff_details, tariff_label, '
            'bank_name, receiver_account, declarant_name, declarant_phone, declarant_email, cdf_rate, '
            'communes(name)',
          );

      if (statuses != null && statuses.isNotEmpty) {
        q = q.inFilter('status', statuses);
      }
      if (communeId != null) {
        q = q.eq('commune_id', communeId);
      }
      if (overdueOnly) {
        q = q.lt('payment_deadline', DateTime.now().toUtc().toIso8601String());
      }
      if (createdFrom != null) {
        q = q.gte('created_at', createdFrom.toUtc().toIso8601String());
      }
      if (createdTo != null) {
        q = q.lt('created_at', createdTo.toUtc().toIso8601String());
      }

      final response = await q
          .order('payment_deadline', ascending: true)
          .limit(limit);
      final rows = response as List;
      return rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }

    try {
      return await load(includeTaxpayerComment: true);
    } catch (e) {
      if (_isMissingTaxpayerCommentColumn(e)) {
        return load(includeTaxpayerComment: false);
      }
      if (_isMissingPerceptionNotesSchema(e)) {
        throw StateError(
          'Migrez Supabase avec 20260527130000_revenue_workflow_phases.sql.',
        );
      }
      rethrow;
    }
  }

  static Future<int> markOverdueTaxationsForRecovery() async {
    try {
      final response = await _c.rpc('mark_overdue_taxations_for_recovery');
      if (response is int) return response;
      return int.tryParse(response?.toString() ?? '') ?? 0;
    } catch (e) {
      final message = e.toString().toLowerCase();
      if (message.contains('mark_overdue_taxations_for_recovery') ||
          message.contains('schema cache') ||
          message.contains('could not find')) {
        throw StateError(
          'Migrez Supabase avec 20260529110000_overdue_taxations_to_recouvrement.sql.',
        );
      }
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> fetchAssujettis({
    String? communeId,
    int limit = 200,
  }) async {
    try {
      var q = _c
          .from('assujettis')
          .select(
            'id, commune_id, status, nom, postnom, prenom, lieu_naissance, date_naissance, '
            'nationalite, sexe, adresse_commune, adresse_rue, adresse_quartier, adresse_numero, '
            'contact_prefix, contact_telephone, contact_email, entreprise_nom, id_nat, rccm, '
            'identity_document_name, identity_document_path, created_at, communes(name)',
          );
      if (communeId != null) {
        q = q.eq('commune_id', communeId);
      }
      final response = await q
          .order('created_at', ascending: false)
          .limit(limit);
      final rows = response as List;
      return rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      if (_isMissingAssujettisSchema(e)) {
        throw StateError(
          'Migrez Supabase avec 20260529100000_create_assujettis.sql.',
        );
      }
      rethrow;
    }
  }

  static Future<void> insertAssujetti({
    required Map<String, dynamic> payload,
    List<int>? identityDocumentBytes,
    String? identityDocumentName,
  }) async {
    try {
      final uid = _c.auth.currentUser?.id;
      if (uid == null || uid.isEmpty) {
        throw StateError('Session expirée. Reconnectez-vous.');
      }
      final insertPayload = <String, dynamic>{...payload, 'created_by': uid};
      final inserted = await _c
          .from('assujettis')
          .insert(insertPayload)
          .select('id, commune_id')
          .single();
      final row = Map<String, dynamic>.from(inserted as Map);
      final id = row['id']?.toString();
      final communeId = row['commune_id']?.toString();

      if (identityDocumentBytes == null ||
          identityDocumentBytes.isEmpty ||
          identityDocumentName == null ||
          identityDocumentName.trim().isEmpty ||
          id == null) {
        return;
      }

      final rawExt = identityDocumentName.split('.').last.toLowerCase();
      final ext = rawExt == 'jpeg' ? 'jpg' : rawExt;
      const allowed = {'pdf', 'jpg', 'png'};
      if (!allowed.contains(ext)) {
        throw ArgumentError('Formats acceptés : PDF, JPG, PNG.');
      }
      final contentType = switch (ext) {
        'pdf' => 'application/pdf',
        'jpg' => 'image/jpeg',
        'png' => 'image/png',
        _ => 'application/octet-stream',
      };
      final storageFolder = communeId ?? 'mairie';
      final path = '$storageFolder/$id/piece-identite.$ext';
      await _c.storage
          .from('assujetti-documents')
          .uploadBinary(
            path,
            Uint8List.fromList(identityDocumentBytes),
            fileOptions: FileOptions(contentType: contentType, upsert: true),
          );
      await _c
          .from('assujettis')
          .update({
            'identity_document_name': identityDocumentName.trim(),
            'identity_document_path': path,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id);
    } catch (e) {
      if (_isMissingAssujettisSchema(e)) {
        throw StateError(
          'Migrez Supabase avec 20260529100000_create_assujettis.sql.',
        );
      }
      rethrow;
    }
  }

  static Future<void> updateAssujetti({
    required String assujettiId,
    required Map<String, dynamic> payload,
    List<int>? identityDocumentBytes,
    String? identityDocumentName,
  }) async {
    try {
      final updatePayload = <String, dynamic>{
        ...payload,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      final updated = await _c
          .from('assujettis')
          .update(updatePayload)
          .eq('id', assujettiId)
          .select('id, commune_id')
          .single();
      final row = Map<String, dynamic>.from(updated as Map);
      final communeId = row['commune_id']?.toString();

      if (identityDocumentBytes == null ||
          identityDocumentBytes.isEmpty ||
          identityDocumentName == null ||
          identityDocumentName.trim().isEmpty) {
        return;
      }

      final rawExt = identityDocumentName.split('.').last.toLowerCase();
      final ext = rawExt == 'jpeg' ? 'jpg' : rawExt;
      const allowed = {'pdf', 'jpg', 'png'};
      if (!allowed.contains(ext)) {
        throw ArgumentError('Formats acceptés : PDF, JPG, PNG.');
      }
      final contentType = switch (ext) {
        'pdf' => 'application/pdf',
        'jpg' => 'image/jpeg',
        'png' => 'image/png',
        _ => 'application/octet-stream',
      };
      final storageFolder = communeId ?? 'mairie';
      final path = '$storageFolder/$assujettiId/piece-identite.$ext';
      await _c.storage
          .from('assujetti-documents')
          .uploadBinary(
            path,
            Uint8List.fromList(identityDocumentBytes),
            fileOptions: FileOptions(contentType: contentType, upsert: true),
          );
      await _c
          .from('assujettis')
          .update({
            'identity_document_name': identityDocumentName.trim(),
            'identity_document_path': path,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', assujettiId);
    } catch (e) {
      if (_isMissingAssujettisSchema(e)) {
        throw StateError(
          'Migrez Supabase avec 20260529100000_create_assujettis.sql.',
        );
      }
      rethrow;
    }
  }

  static Future<void> deleteAssujetti({
    required String assujettiId,
    String? identityDocumentPath,
  }) async {
    try {
      final path = identityDocumentPath?.trim();
      if (path != null && path.isNotEmpty) {
        await _c.storage.from('assujetti-documents').remove([path]);
      }
      await _c.from('assujettis').delete().eq('id', assujettiId);
    } catch (e) {
      if (_isMissingAssujettisSchema(e)) {
        throw StateError(
          'Migrez Supabase avec 20260529100000_create_assujettis.sql.',
        );
      }
      rethrow;
    }
  }

  static Future<void> updatePerceptionNoteStatus({
    required String noteId,
    required String status,
    String? cpiNumber,
    DateTime? paidAt,
    DateTime? apuredAt,
    String? paymentChannel,
    String? bankName,
    String? receiverAccount,
    String? declarantName,
    String? declarantPhone,
    String? declarantEmail,
    String? ordonnateurAvis,
    String? apurementComment,
    bool? bankSlipSubmitted,
    double? cdfRate,
    bool markOrdonnateur = false,
  }) async {
    final payload = <String, dynamic>{
      'status': status,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (markOrdonnateur) {
      final uid = _c.auth.currentUser?.id;
      if (uid != null) payload['ordonnateur_id'] = uid;
    }
    if (cpiNumber != null) payload['cpi_number'] = cpiNumber.trim();
    if (paymentChannel != null) {
      payload['payment_channel'] = paymentChannel.trim();
    }
    if (bankName != null) payload['bank_name'] = bankName.trim();
    if (receiverAccount != null) {
      payload['receiver_account'] = receiverAccount.trim();
    }
    if (declarantName != null) payload['declarant_name'] = declarantName.trim();
    if (declarantPhone != null) {
      payload['declarant_phone'] = declarantPhone.trim();
    }
    if (declarantEmail != null) {
      payload['declarant_email'] = declarantEmail.trim();
    }
    if (ordonnateurAvis != null) {
      payload['ordonnateur_avis'] = ordonnateurAvis.trim();
    }
    if (apurementComment != null) {
      payload['apurement_comment'] = apurementComment.trim();
    }
    if (bankSlipSubmitted != null) {
      payload['bank_slip_submitted'] = bankSlipSubmitted;
    }
    if (cdfRate != null) payload['cdf_rate'] = cdfRate;
    if (paidAt != null) payload['paid_at'] = paidAt.toUtc().toIso8601String();
    if (apuredAt != null) {
      payload['apured_at'] = apuredAt.toUtc().toIso8601String();
    }

    try {
      await _c.from('perception_notes').update(payload).eq('id', noteId);
    } catch (e) {
      if (_isMissingApurementValidationColumns(e)) {
        final removedComment = payload.remove('apurement_comment') != null;
        final removedSlip = payload.remove('bank_slip_submitted') != null;
        if (removedComment || removedSlip) {
          await _c.from('perception_notes').update(payload).eq('id', noteId);
          return;
        }
      }
      if (_isMissingPerceptionNotesSchema(e)) {
        throw StateError(
          'Migrez Supabase avec 20260527130000_revenue_workflow_phases.sql.',
        );
      }
      rethrow;
    }
  }

  static Future<void> _insertLegacyMairieCollection(
    Map<String, dynamic> payload,
  ) async {
    final fallbackCommuneId = await _firstCommuneId();
    if (fallbackCommuneId == null) {
      throw StateError(
        'La base doit autoriser les recettes Mairie sans commune.',
      );
    }
    await _c.from('collections').insert({
      ...payload,
      'commune_id': fallbackCommuneId,
    });
  }

  static Future<String?> _firstCommuneId() async {
    final rows = await _c.from('communes').select('id').order('name').limit(1);
    if (rows.isEmpty) return null;
    final row = Map<String, dynamic>.from(rows.first as Map);
    final id = row['id']?.toString().trim();
    return id == null || id.isEmpty ? null : id;
  }

  /// Admin provincial uniquement (Edge Function `create-staff-user`).
  /// Meilleure commune aujourd’hui (montant total).
  static Future<({String name, double amount})?> topCommuneToday({
    String? scopeCommuneId,
    String? taxpayerProfileId,
  }) async {
    final rows = await fetchCommunesOverview(
      filterCommuneId: scopeCommuneId,
      taxpayerProfileId: taxpayerProfileId,
    );
    if (rows.isEmpty) return null;
    var best = rows.first;
    for (var i = 1; i < rows.length; i++) {
      if (rows[i].revenueToday > best.revenueToday) best = rows[i];
    }
    if (best.revenueToday <= 0) return null;
    return (name: best.name, amount: best.revenueToday);
  }

  static Future<void> createStaffUserViaEdgeFunction({
    required String email,
    required String password,
    required String fullName,
    required AppRole role,
    List<AppRole> roles = const [],
    String? communeId,
  }) async {
    const allowedStaffRoles = {
      AppRole.taxateur,
      AppRole.ordonnateur,
      AppRole.apureur,
      AppRole.agent,
    };
    if (!allowedStaffRoles.contains(role) ||
        roles.any((item) => !allowedStaffRoles.contains(item))) {
      throw ArgumentError(
        'Seuls les rôles Taxateur, Liquidateur, Apureur et Agent de recouvrement sont autorisés.',
      );
    }
    if (role == AppRole.adminProvincial) {
      throw ArgumentError(
        'Impossible de créer un admin provincial depuis l\'app',
      );
    }
    await _c.auth.refreshSession();
    final session = _c.auth.currentSession;
    final accessToken = session?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Session expirée. Reconnectez-vous.');
    }
    try {
      final res = await _c.functions.invoke(
        'create-staff-user',
        headers: {
          'Authorization': 'Bearer $accessToken',
          'x-user-access-token': accessToken,
        },
        body: {
          'email': email,
          'password': password,
          'full_name': fullName,
          'role': role.dbValue,
          'roles': [
            for (final item in <AppRole>{role, ...roles}) item.dbValue,
          ],
          'commune_id': null,
        },
      );
      if (res.status != 200) {
        var msg = 'Erreur ${res.status}';
        final d = res.data;
        if (d is Map && d['error'] != null) {
          msg = '${d['error']}';
        } else if (d != null) {
          msg = d.toString();
        }
        throw Exception(msg);
      }
    } catch (e) {
      final message = '$e';
      if (message.contains('Failed to fetch')) {
        throw Exception(
          "Impossible de joindre la fonction create-staff-user. Vérifiez qu'elle est deployée sur Supabase et que CORS est autorisé.",
        );
      }
      rethrow;
    }
  }

  static Future<void> updateProfileRoles({
    required String userId,
    required AppRole primaryRole,
    required List<AppRole> roles,
    String? communeId,
  }) async {
    final normalized = <AppRole>{primaryRole, ...roles}.toList();
    const allowedStaffRoles = {
      AppRole.taxateur,
      AppRole.ordonnateur,
      AppRole.apureur,
      AppRole.agent,
    };
    if (normalized.any((role) => !allowedStaffRoles.contains(role))) {
      throw ArgumentError(
        'Seuls les rôles Taxateur, Liquidateur, Apureur et Agent de recouvrement sont modifiables ici.',
      );
    }
    if (normalized.any(
      (role) => role == AppRole.adminProvincial || role == AppRole.contribuable,
    )) {
      throw ArgumentError(
        'Les rôles admin provincial et contribuable ne sont pas modifiables ici.',
      );
    }
    await _c
        .from('profiles')
        .update({
          'role': primaryRole.dbValue,
          'roles': normalized.map((role) => role.dbValue).toList(),
          'commune_id': null,
        })
        .eq('id', userId);
  }

  static Future<void> updateProfileAccountStatus({
    required String userId,
    required bool active,
  }) async {
    final id = userId.trim();
    if (id.isEmpty) throw ArgumentError('Utilisateur invalide.');

    final status = active ? 'actif' : 'inactif';
    await _c
        .from('profiles')
        .update({'account_status': status, 'taxpayer_status': status})
        .eq('id', id);
  }

  static Future<ContribuableRegistrationResult> registerContribuable({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required String address,
    required bool isLegalEntity,
    String? legalDenomination,
    String? legalNif,
  }) async {
    final trimmedEmail = email.trim();
    final trimmedName = fullName.trim();
    final trimmedPhone = phone.trim();
    final trimmedAddress = address.trim();
    final trimmedLegalDenomination = legalDenomination?.trim() ?? '';
    final trimmedLegalNif = legalNif?.trim() ?? '';
    if (trimmedEmail.isEmpty ||
        trimmedName.isEmpty ||
        trimmedPhone.isEmpty ||
        trimmedAddress.isEmpty ||
        password.isEmpty) {
      throw ArgumentError(
        'Nom complet, e-mail, telephone, adresse et mot de passe requis.',
      );
    }
    if (password.length < 6) {
      throw ArgumentError(
        'Le mot de passe doit contenir au moins 6 caractères.',
      );
    }

    if (isLegalEntity &&
        (trimmedLegalDenomination.isEmpty || trimmedLegalNif.isEmpty)) {
      throw ArgumentError(
        'Denomination et NIF requis pour une personne morale.',
      );
    }

    try {
      final res = await _c.functions.invoke(
        'register-contribuable',
        body: {
          'email': trimmedEmail,
          'password': password,
          'full_name': trimmedName,
          'taxpayer_email': trimmedEmail,
          'taxpayer_phone': trimmedPhone,
          'taxpayer_address': trimmedAddress,
          'is_legal_entity': isLegalEntity,
          'legal_denomination': trimmedLegalDenomination,
          'legal_nif': trimmedLegalNif,
        },
      );
      if (res.status != 200) {
        var msg = 'Erreur ${res.status}';
        final d = res.data;
        if (d is Map && d['error'] != null) {
          msg = '${d['error']}';
        } else if (d != null) {
          msg = d.toString();
        }
        throw Exception(msg);
      }

      final data = Map<String, dynamic>.from(res.data as Map);
      final taxpayerIdentifier = data['taxpayer_identifier']?.toString();
      final userId = data['user_id']?.toString();
      if (taxpayerIdentifier == null ||
          taxpayerIdentifier.isEmpty ||
          userId == null ||
          userId.isEmpty) {
        throw Exception(
          'Reponse incomplete de la fonction register-contribuable.',
        );
      }

      await _c.auth.signInWithPassword(email: trimmedEmail, password: password);

      return ContribuableRegistrationResult(
        userId: userId,
        email: trimmedEmail,
        taxpayerIdentifier: taxpayerIdentifier,
      );
    } catch (e) {
      final message = '$e';
      if (message.contains('Failed to fetch')) {
        throw Exception(
          "Impossible de joindre la fonction register-contribuable. Vérifiez qu'elle est deployée sur Supabase et que CORS est autorisé.",
        );
      }
      rethrow;
    }
  }

  static Future<ContribuableRegistrationResult>
  createContribuableViaEdgeFunction({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required String address,
    required bool isLegalEntity,
    required String identificationType,
    required String identificationNumber,
    required String locationLabel,
    required String activity,
    required String status,
    String? communeId,
    String? legalDenomination,
    String? legalNif,
  }) async {
    await _c.auth.refreshSession();
    final session = _c.auth.currentSession;
    final accessToken = session?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Session expirée. Reconnectez-vous.');
    }
    final trimmedEmail = email.trim().toLowerCase();
    final trimmedName = fullName.trim();
    final trimmedPhone = phone.trim();
    final trimmedAddress = address.trim();
    if (trimmedEmail.isEmpty ||
        password.isEmpty ||
        trimmedName.isEmpty ||
        trimmedPhone.isEmpty ||
        trimmedAddress.isEmpty ||
        identificationType.trim().isEmpty ||
        identificationNumber.trim().isEmpty ||
        locationLabel.trim().isEmpty ||
        activity.trim().isEmpty) {
      throw ArgumentError('Tous les champs contribuable sont requis.');
    }
    try {
      final res = await _c.functions.invoke(
        'register-contribuable',
        headers: {
          'Authorization': 'Bearer $accessToken',
          'x-user-access-token': accessToken,
        },
        body: {
          'email': trimmedEmail,
          'password': password,
          'full_name': trimmedName,
          'taxpayer_email': trimmedEmail,
          'taxpayer_phone': trimmedPhone,
          'taxpayer_address': trimmedAddress,
          'is_legal_entity': isLegalEntity,
          'legal_denomination': legalDenomination?.trim() ?? '',
          'legal_nif': legalNif?.trim() ?? '',
          'commune_id': communeId,
          'taxpayer_id_type': identificationType.trim(),
          'taxpayer_id_number': identificationNumber.trim(),
          'taxpayer_location_label': locationLabel.trim(),
          'taxpayer_activity': activity.trim(),
          'taxpayer_status': status.trim().isEmpty ? 'actif' : status.trim(),
        },
      );
      if (res.status != 200) {
        var msg = 'Erreur ${res.status}';
        final d = res.data;
        if (d is Map && d['error'] != null) {
          msg = '${d['error']}';
        } else if (d != null) {
          msg = d.toString();
        }
        throw Exception(msg);
      }
      final data = Map<String, dynamic>.from(res.data as Map);
      return ContribuableRegistrationResult(
        userId: data['user_id']?.toString() ?? '',
        email: trimmedEmail,
        taxpayerIdentifier: data['taxpayer_identifier']?.toString() ?? '',
      );
    } catch (e) {
      final message = '$e';
      if (message.contains('Failed to fetch')) {
        throw Exception(
          "Impossible de joindre la fonction register-contribuable. Vérifiez qu'elle est déployée sur Supabase et que CORS est autorisé.",
        );
      }
      rethrow;
    }
  }

  static Future<void> deleteStaffUserViaEdgeFunction({
    required String userId,
  }) async {
    await _c.auth.refreshSession();
    final session = _c.auth.currentSession;
    final accessToken = session?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Session expirée. Reconnectez-vous.');
    }
    try {
      final res = await _c.functions.invoke(
        'delete-staff-user',
        headers: {
          'Authorization': 'Bearer $accessToken',
          'x-user-access-token': accessToken,
        },
        body: {'user_id': userId},
      );
      if (res.status != 200) {
        var msg = 'Erreur ${res.status}';
        final d = res.data;
        if (d is Map && d['error'] != null) {
          msg = '${d['error']}';
        } else if (d != null) {
          msg = d.toString();
        }
        throw Exception(msg);
      }
    } catch (e) {
      final message = '$e';
      if (message.contains('Failed to fetch')) {
        throw Exception(
          "Impossible de joindre la fonction delete-staff-user. Vérifiez qu'elle est deployée sur Supabase et que CORS est autorisé.",
        );
      }
      rethrow;
    }
  }

  static const _avatarsBucket = 'avatars';

  static Future<void> updateMyDisplayName({
    required String userId,
    required String fullName,
  }) async {
    final t = fullName.trim();
    if (t.isEmpty) {
      throw ArgumentError('Le nom affiché ne peut pas être vide.');
    }
    await _c.from('profiles').update({'full_name': t}).eq('id', userId);
  }

  static Future<void> updateMyPassword({required String newPassword}) async {
    final password = newPassword.trim();
    if (password.length < 6) {
      throw ArgumentError(
        'Le mot de passe doit contenir au moins 6 caractères.',
      );
    }
    await _c.auth.updateUser(UserAttributes(password: password));
  }

  /// Supprime les fichiers du dossier Storage de l’utilisateur (avant un nouvel upload).
  static Future<void> _clearAvatarObjects(String userId) async {
    try {
      final files = await _c.storage.from(_avatarsBucket).list(path: userId);
      if (files.isEmpty) return;
      final paths = files.map((f) => '$userId/${f.name}').toList();
      await _c.storage.from(_avatarsBucket).remove(paths);
    } catch (_) {
      // dossier vide ou première utilisation
    }
  }

  /// Envoie une image dans `avatars/{userId}/` et met à jour `profiles.avatar_url`.
  /// Le nom change à chaque upload pour éviter que l’ancien avatar reste en cache.
  static Future<void> uploadMyAvatarAndSaveProfile({
    required String userId,
    required List<int> bytes,
    required String fileExtension,
  }) async {
    var ext = fileExtension.toLowerCase().replaceAll('.', '');
    if (ext == 'jpeg') ext = 'jpg';
    const allowed = {'jpg', 'png', 'webp'};
    if (!allowed.contains(ext)) {
      throw ArgumentError('Formats acceptés : JPG, PNG, WebP.');
    }
    final contentType = switch (ext) {
      'jpg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    await _clearAvatarObjects(userId);
    final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final path = '$userId/avatar_$stamp.$ext';
    await _c.storage
        .from(_avatarsBucket)
        .uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    final publicUrl = _c.storage.from(_avatarsBucket).getPublicUrl(path);
    await _c
        .from('profiles')
        .update({'avatar_url': publicUrl})
        .eq('id', userId);
  }

  static Future<void> clearMyAvatar({required String userId}) async {
    await _clearAvatarObjects(userId);
    await _c.from('profiles').update({'avatar_url': null}).eq('id', userId);
  }

  /// Alertes ouvertes pour le rôle (agents : liste vide — pas d’ écran Alertes).
  static Future<List<AppAlert>> fetchAlertsForProfile(
    UserProfile profile,
  ) async {
    if (!profile.hasAlertsAccess) return [];

    if (!SupabaseEnv.isConfigured) {
      return const [];
    }

    try {
      final rows = await _c
          .from('alerts')
          .select(
            'id, severity, category, title, body, created_at, resolved_at, commune_id, target_role, target_user_id, source_table, source_id, communes(name)',
          )
          .order('created_at', ascending: false);
      final raw = rows as List;
      final out = raw
          .map((e) => AppAlert.fromRow(Map<String, dynamic>.from(e as Map)))
          .whereType<AppAlert>()
          .toList();
      return out;
    } catch (_) {
      // Table absente, migration non appliquée, etc.
    }
    return const [];
  }

  /// Compteurs pour le tableau de bord (superviseurs uniquement).
  static Future<({int openTotal, int critiques})> fetchAlertsSummary(
    UserProfile profile,
  ) async {
    final list = await fetchAlertsForProfile(profile);
    final open = list.where((a) => a.isOpen).toList();
    final critiques = open
        .where((a) => a.severity == AlertSeverity.critique)
        .length;
    return (openTotal: open.length, critiques: critiques);
  }
}

class CommuneOverviewRow {
  const CommuneOverviewRow({
    required this.communeId,
    required this.name,
    required this.bourgmestreName,
    required this.agentNames,
    required this.revenueToday,
    required this.transactionsToday,
  });

  final String communeId;
  final String name;
  final String bourgmestreName;
  final List<String> agentNames;
  final double revenueToday;
  final int transactionsToday;
}

class ContribuableRegistrationResult {
  const ContribuableRegistrationResult({
    required this.userId,
    required this.email,
    required this.taxpayerIdentifier,
  });

  final String userId;
  final String email;
  final String taxpayerIdentifier;
}

class TaxpayerVerificationResult {
  const TaxpayerVerificationResult({
    required this.taxpayerIdentifier,
    required this.profile,
    required this.collections,
    required this.collectorNames,
  });

  final String taxpayerIdentifier;
  final UserProfile? profile;
  final List<Map<String, dynamic>> collections;
  final Map<String, String> collectorNames;

  bool get hasRegisteredPayment => collections.isNotEmpty;

  int get paymentCount => collections.length;

  double get totalAmount {
    return collections.fold<double>(
      0,
      (sum, row) => sum + ((row['amount'] as num?)?.toDouble() ?? 0),
    );
  }

  DateTime? get lastPaymentAt {
    for (final row in collections) {
      final raw = row['collected_at']?.toString();
      if (raw == null || raw.isEmpty) continue;
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed.toLocal();
    }
    return null;
  }
}
