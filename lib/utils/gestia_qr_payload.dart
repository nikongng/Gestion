import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

enum GestiaQrDocumentType { cpi, perceptionNote }

extension GestiaQrDocumentTypeLabel on GestiaQrDocumentType {
  String get label {
    switch (this) {
      case GestiaQrDocumentType.cpi:
        return 'CPI';
      case GestiaQrDocumentType.perceptionNote:
        return 'note de perception';
    }
  }
}

class GestiaQrPayloadData {
  const GestiaQrPayloadData({
    required this.type,
    required this.reference,
    required this.generatedAtLabel,
    required this.amountUsdLabel,
    required this.taxpayerIdentifier,
    required this.proofOfPayment,
    this.perceptionNoteNumber,
    this.paymentDelayLabel,
    this.signed = true,
  });

  final GestiaQrDocumentType type;
  final String reference;
  final String generatedAtLabel;
  final String amountUsdLabel;
  final String taxpayerIdentifier;
  final bool proofOfPayment;
  final String? perceptionNoteNumber;
  final String? paymentDelayLabel;
  final bool signed;
}

class GestiaQrPayload {
  GestiaQrPayload._();

  static const _prefix = 'GESTIA1';
  static final _keyBytes = utf8.encode(
    'GESTIA::QR::KINSHASA::APP-ONLY::V1::2026-05-26',
  );

  static String encode({
    required GestiaQrDocumentType type,
    required String reference,
    required DateTime generatedAt,
    required double amountUsd,
    required String taxpayerIdentifier,
    required bool proofOfPayment,
    String? perceptionNoteNumber,
    String? paymentDelayLabel,
  }) {
    final payload = <String, Object?>{
      't': type == GestiaQrDocumentType.cpi ? 'c' : 'n',
      'r': _compact(reference, 28),
      'd': _formatDate(generatedAt),
      'm': _formatAmount(amountUsd),
      'id': _compact(taxpayerIdentifier, 24),
      'p': proofOfPayment ? 1 : 0,
      if (_compact(perceptionNoteNumber ?? '', 28).isNotEmpty)
        'np': _compact(perceptionNoteNumber ?? '', 28),
      if (_compact(paymentDelayLabel ?? '', 12).isNotEmpty)
        'dl': _compact(paymentDelayLabel ?? '', 12),
    };

    final nonce = _nonce();
    final plain = utf8.encode(jsonEncode(payload));
    final cipher = _xor(plain, _stream(nonce, plain.length));
    final body = _base64NoPadding([...nonce, ...cipher]);
    return '$_prefix.$body.${_signature(body)}';
  }

  static GestiaQrPayloadData? tryDecode(String rawValue) {
    final raw = rawValue.trim();
    if (raw.isEmpty) return null;
    return _tryDecodeSigned(raw) ?? _tryDecodeLegacy(raw);
  }

  static GestiaQrPayloadData? _tryDecodeSigned(String raw) {
    try {
      final parts = raw.split('.');
      if (parts.length != 3 || parts.first != _prefix) return null;

      final body = parts[1];
      final signature = parts[2];
      if (!_constantEquals(signature, _signature(body))) return null;

      final bytes = base64Url.decode(_withBase64Padding(body));
      if (bytes.length <= 8) return null;

      final nonce = bytes.sublist(0, 8);
      final cipher = bytes.sublist(8);
      final plain = _xor(cipher, _stream(nonce, cipher.length));
      final decoded = jsonDecode(utf8.decode(plain));
      if (decoded is! Map<String, dynamic>) return null;

      return _fromCompactMap(decoded, signed: true);
    } catch (_) {
      return null;
    }
  }

  static GestiaQrPayloadData? _tryDecodeLegacy(String raw) {
    if (!raw.startsWith('GESTIA-CPI|') && !raw.startsWith('GESTIA-NP|')) {
      return null;
    }

    final segments = raw.split('|');
    final values = <String, String>{};
    for (final segment in segments.skip(1)) {
      final separator = segment.indexOf(':');
      if (separator <= 0) continue;
      values[segment.substring(0, separator)] = segment.substring(
        separator + 1,
      );
    }

    final type = raw.startsWith('GESTIA-CPI|')
        ? GestiaQrDocumentType.cpi
        : GestiaQrDocumentType.perceptionNote;
    return GestiaQrPayloadData(
      type: type,
      reference: values['REF'] ?? '',
      generatedAtLabel: values['D'] ?? '',
      amountUsdLabel: (values['M'] ?? '').replaceAll('USD', ''),
      taxpayerIdentifier: values['ID'] ?? '',
      proofOfPayment: type == GestiaQrDocumentType.cpi,
      perceptionNoteNumber: values['NP'],
      paymentDelayLabel: values['DL'],
      signed: false,
    );
  }

  static GestiaQrPayloadData? _fromCompactMap(
    Map<String, dynamic> map, {
    required bool signed,
  }) {
    final typeCode = _readString(map, 't');
    final type = switch (typeCode) {
      'c' => GestiaQrDocumentType.cpi,
      'n' => GestiaQrDocumentType.perceptionNote,
      _ => null,
    };
    if (type == null) return null;

    return GestiaQrPayloadData(
      type: type,
      reference: _readString(map, 'r'),
      generatedAtLabel: _readString(map, 'd'),
      amountUsdLabel: _readString(map, 'm'),
      taxpayerIdentifier: _readString(map, 'id'),
      proofOfPayment: _readInt(map, 'p') == 1,
      perceptionNoteNumber: _nullableString(map, 'np'),
      paymentDelayLabel: _nullableString(map, 'dl'),
      signed: signed,
    );
  }

  static List<int> _nonce() {
    try {
      final secure = math.Random.secure();
      return List<int>.generate(8, (_) => secure.nextInt(256));
    } catch (_) {
      final seed = DateTime.now().microsecondsSinceEpoch;
      final fallback = math.Random(seed);
      return List<int>.generate(8, (_) => fallback.nextInt(256));
    }
  }

  static List<int> _stream(List<int> nonce, int length) {
    final bytes = <int>[];
    var counter = 0;
    while (bytes.length < length) {
      final seed = <int>[
        ...nonce,
        counter & 0xff,
        (counter >> 8) & 0xff,
        (counter >> 16) & 0xff,
        (counter >> 24) & 0xff,
      ];
      bytes.addAll(Hmac(sha256, _keyBytes).convert(seed).bytes);
      counter++;
    }
    return bytes.take(length).toList(growable: false);
  }

  static List<int> _xor(List<int> source, List<int> stream) {
    return List<int>.generate(
      source.length,
      (index) => source[index] ^ stream[index],
      growable: false,
    );
  }

  static String _signature(String body) {
    final digest = Hmac(sha256, _keyBytes).convert(utf8.encode(body)).bytes;
    return _base64NoPadding(digest.take(12).toList(growable: false));
  }

  static String _base64NoPadding(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _withBase64Padding(String value) {
    final missing = value.length % 4;
    return missing == 0
        ? value
        : value.padRight(value.length + 4 - missing, '=');
  }

  static bool _constantEquals(String left, String right) {
    if (left.length != right.length) return false;
    var diff = 0;
    for (var i = 0; i < left.length; i++) {
      diff |= left.codeUnitAt(i) ^ right.codeUnitAt(i);
    }
    return diff == 0;
  }

  static String _formatDate(DateTime date) {
    final local = date.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}${two(local.month)}${local.year.toString().substring(2)}'
        '${two(local.hour)}${two(local.minute)}';
  }

  static String _formatAmount(double amount) {
    final fixed = amount.toStringAsFixed(2);
    return fixed.endsWith('.00') ? fixed.substring(0, fixed.length - 3) : fixed;
  }

  static String _compact(String value, int maxLength) {
    final clean = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.length <= maxLength) return clean;
    return clean.substring(0, maxLength);
  }

  static String _readString(Map<String, dynamic> map, String key) {
    return map[key]?.toString().trim() ?? '';
  }

  static String? _nullableString(Map<String, dynamic> map, String key) {
    final value = _readString(map, key);
    return value.isEmpty ? null : value;
  }

  static int _readInt(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
