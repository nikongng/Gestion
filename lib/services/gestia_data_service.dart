import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_env.dart';
import '../data/sample_chart_data.dart';
import '../data/sample_alerts.dart';
import '../models/app_alert.dart';
import '../models/app_role.dart';
import '../models/user_profile.dart';

class GestiaDataService {
  GestiaDataService._();

  static SupabaseClient get _c {
    if (!SupabaseEnv.isConfigured) {
      throw StateError('Supabase non configurÃ©');
    }
    return Supabase.instance.client;
  }

  static Future<UserProfile?> fetchProfile(String userId) async {
    Map<String, dynamic>? map;

    // PrÃ©fÃ¨re la RPC (migration `get_my_profile_rpc`) : lit `auth.uid()` cÃ´tÃ© serveur,
    // Ã©vite les cas oÃ¹ le SELECT direct sur `profiles` est vide Ã  cause de RLS / JWT.
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
          .select('id, full_name, role, commune_id, avatar_url')
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
        .select('id, full_name, role, commune_id, avatar_url, communes(name)')
        .order('full_name');
    return rows
        .map((e) => UserProfile.fromRow(Map<String, dynamic>.from(e)))
        .whereType<UserProfile>()
        .toList();
  }

  static Future<void> updateCommuneName({
    required String communeId,
    required String name,
  }) async {
    await _c.from('communes').update({'name': name.trim()}).eq('id', communeId);
  }

  static Future<List<({String id, String name})>> fetchCommunes() async {
    final rows =
        await _c.from('communes').select('id, name').order('name') as List;
    return rows
        .map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return (id: m['id'] as String, name: m['name'] as String);
        })
        .toList();
  }

  static Future<List<Map<String, dynamic>>> fetchCollectionsInRange({
    required DateTime from,
    required DateTime to,
    String? communeId,
  }) async {
    var q = _c
        .from('collections')
        .select(
          'id, commune_id, amount, tax_category, collected_at, communes(name)',
        )
        .gte('collected_at', from.toUtc().toIso8601String())
        .lte('collected_at', to.toUtc().toIso8601String());
    if (communeId != null) {
      q = q.eq('commune_id', communeId);
    }
    final response = await q;
    final rows = response as List;
    return rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Lignes pour le tableau des communes (recettes du jour, bourgmestre si visible en RLS).
  static Future<List<CommuneOverviewRow>> fetchCommunesOverview({
    String? filterCommuneId,
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
    );
    final sumByCommune = <String, double>{};
    final countByCommune = <String, int>{};
    for (final t in txs) {
      final id = t['commune_id'] as String;
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
        bmName[cid] = m['full_name'] as String? ?? 'â€”';
      }
    }

    return [
      for (final c in communes)
        CommuneOverviewRow(
          communeId: c.id,
          name: c.name,
          bourgmestreName: bmName[c.id] ?? 'â€”',
          revenueToday: sumByCommune[c.id] ?? 0,
          transactionsToday: countByCommune[c.id] ?? 0,
        ),
    ];
  }

  static Future<double> sumToday({String? communeId}) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    final rows = await fetchCollectionsInRange(from: start, to: end, communeId: communeId);
    var t = 0.0;
    for (final r in rows) {
      t += (r['amount'] as num).toDouble();
    }
    return t;
  }

  static Future<List<CommuneRevenue>> revenueByCommuneLast30Days({
    String? communeId,
  }) async {
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 30));
    final rows = await fetchCollectionsInRange(
      from: from,
      to: now,
      communeId: communeId,
    );
    final map = <String, double>{};
    for (final r in rows) {
      final commune = r['communes'] as Map<String, dynamic>?;
      final name = commune?['name'] as String? ?? 'â€”';
      final amt = (r['amount'] as num).toDouble();
      map[name] = (map[name] ?? 0) + amt;
    }
    if (map.isEmpty) return [];
    final list = map.entries
        .map((e) => CommuneRevenue(e.key, e.value))
        .toList()
      ..sort((a, b) => b.amountUsd.compareTo(a.amountUsd));
    return list;
  }

  static Future<List<TaxSlice>> taxBreakdownLast30Days({String? communeId}) async {
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 30));
    final rows = await fetchCollectionsInRange(from: from, to: now, communeId: communeId);
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

  static Future<List<DailyRevenue>> last7DaysRevenue({String? communeId}) async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final rangeStart = todayStart.subtract(const Duration(days: 6));
    final rangeEnd = todayStart.add(const Duration(days: 1));
    final rows = await fetchCollectionsInRange(
      from: rangeStart,
      to: rangeEnd,
      communeId: communeId,
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
    'FÃ©v',
    'Mar',
    'Avr',
    'Mai',
    'Juin',
    'Juil',
    'AoÃ»t',
    'Sep',
    'Oct',
    'Nov',
    'DÃ©c',
  ];

  /// RÃ©alisÃ© par mois sur les 6 derniers mois ; objectif = rÃ©alisÃ© Ã— 1,05 (placeholder jusquâ€™Ã  table dâ€™objectifs).
  static Future<List<MonthGoalVsActual>> goalVsActualLast6Months({
    String? communeId,
  }) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 5, 1);
    final end = DateTime(now.year, now.month + 1, 1);
    final rows =
        await fetchCollectionsInRange(from: start, to: end, communeId: communeId);
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
    required String communeId,
    required double amountUsd,
    required String taxCategory,
    String? paymentChannel,
  }) async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) throw StateError('Non connectÃ©');
    await _c.from('collections').insert({
      'commune_id': communeId,
      'amount': amountUsd,
      'tax_category': taxCategory,
      'payment_channel': ?paymentChannel,
      'created_by': uid,
    });
  }

  /// Admin provincial uniquement (Edge Function `create-staff-user`).
  /// Meilleure commune aujourdâ€™hui (montant total).
  static Future<({String name, double amount})?> topCommuneToday({
    String? scopeCommuneId,
  }) async {
    final rows = await fetchCommunesOverview(filterCommuneId: scopeCommuneId);
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
    String? communeId,
  }) async {
    if (role == AppRole.adminProvincial) {
      throw ArgumentError('Impossible de crÃ©er un admin provincial depuis lâ€™app');
    }
    final session = _c.auth.currentSession;
    if (session == null) {
      throw StateError('Session expirÃ©e. Reconnectez-vous.');
    }
    final res = await _c.functions.invoke(
      'create-staff-user',
      headers: {
        'Authorization': 'Bearer ${session.accessToken}',
      },
      body: {
        'email': email,
        'password': password,
        'full_name': fullName,
        'role': role.dbValue,
        'commune_id': communeId,
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
  }

  static const _avatarsBucket = 'avatars';

  static Future<void> updateMyDisplayName({
    required String userId,
    required String fullName,
  }) async {
    final t = fullName.trim();
    if (t.isEmpty) {
      throw ArgumentError('Le nom affichÃ© ne peut pas Ãªtre vide.');
    }
    await _c.from('profiles').update({'full_name': t}).eq('id', userId);
  }

  /// Supprime les fichiers du dossier Storage de lâ€™utilisateur (avant un nouvel upload).
  static Future<void> _clearAvatarObjects(String userId) async {
    try {
      final files =
          await _c.storage.from(_avatarsBucket).list(path: userId);
      if (files.isEmpty) return;
      final paths = files.map((f) => '$userId/${f.name}').toList();
      await _c.storage.from(_avatarsBucket).remove(paths);
    } catch (_) {
      // dossier vide ou premiÃ¨re utilisation
    }
  }

  /// Envoie une image dans `avatars/{userId}/` et met Ã  jour `profiles.avatar_url`.
  static Future<void> uploadMyAvatarAndSaveProfile({
    required String userId,
    required List<int> bytes,
    required String fileExtension,
  }) async {
    var ext = fileExtension.toLowerCase().replaceAll('.', '');
    if (ext == 'jpeg') ext = 'jpg';
    const allowed = {'jpg', 'png', 'webp'};
    if (!allowed.contains(ext)) {
      throw ArgumentError('Formats acceptÃ©s : JPG, PNG, WebP.');
    }
    final contentType = switch (ext) {
      'jpg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    await _clearAvatarObjects(userId);
    final path = '$userId/avatar.$ext';
    await _c.storage.from(_avatarsBucket).uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: true,
          ),
        );
    final publicUrl = _c.storage.from(_avatarsBucket).getPublicUrl(path);
    await _c.from('profiles').update({'avatar_url': publicUrl}).eq('id', userId);
  }

  static Future<void> clearMyAvatar({
    required String userId,
  }) async {
    await _clearAvatarObjects(userId);
    await _c.from('profiles').update({'avatar_url': null}).eq('id', userId);
  }

  /// Alertes ouvertes pour le rÃ´le (agents : liste vide â€” pas dâ€™Ã©cran Alertes).
  static Future<List<AppAlert>> fetchAlertsForProfile(UserProfile profile) async {
    final role = profile.role;
    if (role == AppRole.agent) return [];

    if (!SupabaseEnv.isConfigured) {
      return sampleAlertsFallback(role, profile.communeId);
    }

    try {
      if (role.isGlobalSupervisor) {
        final rows = await _c
            .from('alerts')
            .select(
              'id, severity, category, title, body, created_at, resolved_at, commune_id, communes(name)',
            )
            .order('created_at', ascending: false);
        final raw = rows as List;
        final out = raw
            .map((e) => AppAlert.fromRow(Map<String, dynamic>.from(e as Map)))
            .whereType<AppAlert>()
            .toList();
        if (out.isEmpty) {
          return sampleAlertsFallback(role, profile.communeId);
        }
        return out;
      }
      final cid = profile.communeId;
      if (role == AppRole.bourgmestre && cid != null) {
        final rows = await _c
            .from('alerts')
            .select(
              'id, severity, category, title, body, created_at, resolved_at, commune_id, communes(name)',
            )
            .eq('commune_id', cid)
            .order('created_at', ascending: false);
        final raw = rows as List;
        final out = raw
            .map((e) => AppAlert.fromRow(Map<String, dynamic>.from(e as Map)))
            .whereType<AppAlert>()
            .toList();
        if (out.isEmpty) {
          return sampleAlertsFallback(role, profile.communeId);
        }
        return out;
      }
    } catch (_) {
      // Table absente, migration non appliquÃ©e, etc.
    }
    return sampleAlertsFallback(role, profile.communeId);
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
    required this.revenueToday,
    required this.transactionsToday,
  });

  final String communeId;
  final String name;
  final String bourgmestreName;
  final double revenueToday;
  final int transactionsToday;
}




