import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class RevenueReceiptType {
  const RevenueReceiptType._();

  static const impot = 'Imp\u00f4t';
  static const taxe = 'Taxe';
  static const redevance = 'Redevance';

  static const values = <String>[impot, taxe, redevance];
}

class OfficialTariff {
  const OfficialTariff({
    required this.id,
    required this.receiptType,
    required this.label,
    required this.source,
    required this.details,
    required this.tariffLabel,
    this.amountUsd,
  });

  factory OfficialTariff.fromJson(Map<String, dynamic> json) {
    return OfficialTariff(
      id: _readString(json, 'id'),
      receiptType: _readString(json, 'receiptType'),
      label: _readString(json, 'label'),
      source: _readString(json, 'source'),
      details: _readString(json, 'details'),
      tariffLabel: _readString(json, 'tariffLabel'),
      amountUsd: _readNumber(json['amountUsd']),
    );
  }

  final String id;
  final String receiptType;
  final String label;
  final String source;
  final String details;
  final String tariffLabel;
  final double? amountUsd;

  String get searchText =>
      '$receiptType $label $source $details $tariffLabel'.toLowerCase();

  String get amountHelper {
    final amount = amountUsd;
    if (amount != null) {
      return 'Montant officiel: ${formatUsdAmount(amount)} USD';
    }
    return 'Tarif officiel: $tariffLabel';
  }
}

String formatUsdAmount(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
}

class OfficialTariffCatalog {
  OfficialTariffCatalog._();

  static const assetPath = 'assets/tariffs/official_tariffs.json';
  static List<OfficialTariff>? _cache;

  static Future<List<OfficialTariff>> load() async {
    final cached = _cache;
    if (cached != null) return cached;

    try {
      final data = await rootBundle.load(assetPath);
      final rawJson = utf8.decode(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      final decoded = jsonDecode(rawJson);
      if (decoded is! List) {
        throw const FormatException('Catalogue tarifaire invalide.');
      }

      final tariffs = decoded
          .whereType<Map>()
          .map(
            (item) => OfficialTariff.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((tariff) => tariff.id.isNotEmpty && tariff.label.isNotEmpty)
          .toList(growable: false);
      if (tariffs.isEmpty) {
        throw const FormatException('Catalogue tarifaire vide.');
      }

      return _cache = List.unmodifiable(tariffs);
    } catch (_) {
      throw StateError(
        'Impossible de charger la liste tarifaire officielle. '
        'Vérifiez le fichier des tarifs.',
      );
    }
  }
}

String _readString(Map<String, dynamic> json, String key) {
  return json[key]?.toString().trim() ?? '';
}

double? _readNumber(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.replaceAll(',', '.'));
  return null;
}
