import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

class ReportExportMetric {
  const ReportExportMetric({required this.label, required this.value});

  final String label;
  final String value;
}

class ReportExportRow {
  const ReportExportRow({
    required this.collectedAt,
    required this.communeName,
    required this.taxCategory,
    required this.amountUsd,
  });

  final DateTime collectedAt;
  final String communeName;
  final String taxCategory;
  final double amountUsd;
}

class ReportExportData {
  const ReportExportData({
    required this.title,
    required this.scopeLabel,
    required this.generatedAt,
    required this.metrics,
    required this.rows,
  });

  final String title;
  final String scopeLabel;
  final DateTime generatedAt;
  final List<ReportExportMetric> metrics;
  final List<ReportExportRow> rows;
}

class ReportExporter {
  ReportExporter._();

  static Future<String?> exportPdf(ReportExportData data) async {
    final fileName = _buildFileName(extension: 'pdf');
    final bytes = Uint8List.fromList(_buildPdfBytes(data));
    return _saveBytes(
      bytes: bytes,
      dialogTitle: 'Enregistrer le rapport PDF',
      fileName: fileName,
      extensions: const ['pdf'],
    );
  }

  static Future<String?> exportExcel(ReportExportData data) async {
    final workbook = Excel.createExcel();
    final fileName = _buildFileName(extension: 'xlsx');
    final defaultSheet = workbook.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != 'Résumé') {
      workbook.rename(defaultSheet, 'Résumé');
    }

    final summarySheet = workbook['Résumé'];
    summarySheet.appendRow([
      TextCellValue('Rapport'),
      TextCellValue(data.title),
    ]);
    summarySheet.appendRow([
      TextCellValue('Portée'),
      TextCellValue(data.scopeLabel),
    ]);
    summarySheet.appendRow([
      TextCellValue('Généré le'),
      TextCellValue(_formatDateTime(data.generatedAt)),
    ]);
    summarySheet.appendRow([TextCellValue(''), TextCellValue('')]);
    summarySheet.appendRow([
      TextCellValue('Indicateur'),
      TextCellValue('Valeur'),
    ]);
    for (final metric in data.metrics) {
      summarySheet.appendRow([
        TextCellValue(metric.label),
        TextCellValue(metric.value),
      ]);
    }

    final transactionsSheet = workbook['Transactions'];
    transactionsSheet.appendRow([
      TextCellValue('Date'),
      TextCellValue('Mairie'),
      TextCellValue('Taxe'),
      TextCellValue('Montant FC'),
    ]);
    for (final row in data.rows) {
      transactionsSheet.appendRow([
        TextCellValue(_formatDateTime(row.collectedAt)),
        TextCellValue(row.communeName),
        TextCellValue(row.taxCategory),
        DoubleCellValue(row.amountUsd),
      ]);
    }

    final bytes = workbook.save(fileName: fileName);
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Impossible de générer le fichier Excel.');
    }

    return _saveBytes(
      bytes: Uint8List.fromList(bytes),
      dialogTitle: 'Enregistrer le rapport Excel',
      fileName: fileName,
      extensions: const ['xlsx'],
    );
  }

  static Future<String?> _saveBytes({
    required Uint8List bytes,
    required String dialogTitle,
    required String fileName,
    required List<String> extensions,
  }) {
    return FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: extensions,
      bytes: bytes,
    );
  }

  static String _buildFileName({required String extension}) {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${now.year}-${two(now.month)}-${two(now.day)}_${two(now.hour)}-${two(now.minute)}';
    return 'rapport_collecte_$stamp.$extension';
  }

  static List<int> _buildPdfBytes(ReportExportData data) {
    final lines = <String>[
      'Résumé',
      for (final metric in data.metrics) '${metric.label}: ${metric.value}',
      '',
      'Transactions (${data.rows.length})',
      if (data.rows.isEmpty)
        'Aucune transaction sur la période.'
      else
        for (final row in data.rows)
          '${_formatDateTime(row.collectedAt)} | ${row.communeName} | ${row.taxCategory} | ${_formatMoney(row.amountUsd)}',
    ];

    final wrappedLines = <String>[];
    for (final line in lines) {
      wrappedLines.addAll(_wrapText(line, 92));
    }

    const pageBodyLineCount = 34;
    final pageCount = wrappedLines.isEmpty
        ? 1
        : ((wrappedLines.length + pageBodyLineCount - 1) ~/ pageBodyLineCount);
    final pageBodies = <List<String>>[];
    for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
      final start = pageIndex * pageBodyLineCount;
      final end = math.min(start + pageBodyLineCount, wrappedLines.length);
      pageBodies.add(
        start < wrappedLines.length
            ? wrappedLines.sublist(start, end)
            : const [],
      );
    }

    final objects = <int, List<int>>{};
    objects[1] = utf8.encode('<< /Type /Catalog /Pages 2 0 R >>');
    final pageRefs = <String>[];
    for (var i = 0; i < pageBodies.length; i++) {
      final pageId = 4 + (i * 2);
      pageRefs.add('$pageId 0 R');
    }
    objects[2] = utf8.encode(
      '<< /Type /Pages /Count ${pageBodies.length} /Kids [${pageRefs.join(' ')}] >>',
    );
    objects[3] = utf8.encode(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    );

    for (var i = 0; i < pageBodies.length; i++) {
      final pageId = 4 + (i * 2);
      final contentId = pageId + 1;
      final content = _buildPdfPageContent(
        data: data,
        bodyLines: pageBodies[i],
        pageNumber: i + 1,
        pageCount: pageBodies.length,
      );
      final contentBytes = utf8.encode(content);
      objects[pageId] = utf8.encode(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
        '/Resources << /Font << /F1 3 0 R >> >> /Contents $contentId 0 R >>',
      );
      objects[contentId] = utf8.encode(
        '<< /Length ${contentBytes.length} >>\nstream\n$content\nendstream',
      );
    }

    return _assemblePdf(objects);
  }

  static String _buildPdfPageContent({
    required ReportExportData data,
    required List<String> bodyLines,
    required int pageNumber,
    required int pageCount,
  }) {
    final buffer = StringBuffer()
      ..writeln('BT')
      ..writeln('/F1 16 Tf')
      ..writeln('40 802 Td')
      ..writeln('(${_pdfEscape(data.title)}) Tj')
      ..writeln('/F1 10 Tf')
      ..writeln('0 -18 Td')
      ..writeln(
        '(${_pdfEscape('Généré le ${_formatDateTime(data.generatedAt)}')}) Tj',
      )
      ..writeln('0 -14 Td')
      ..writeln('(${_pdfEscape('Portée: ${data.scopeLabel}')}) Tj')
      ..writeln('0 -22 Td')
      ..writeln('/F1 11 Tf')
      ..writeln('14 TL');

    for (final line in bodyLines) {
      if (line.isEmpty) {
        buffer.writeln('T*');
      } else {
        buffer.writeln('(${_pdfEscape(line)}) Tj');
        buffer.writeln('T*');
      }
    }

    buffer
      ..writeln('ET')
      ..writeln('BT')
      ..writeln('/F1 9 Tf')
      ..writeln('40 24 Td')
      ..writeln('(${_pdfEscape('Page $pageNumber / $pageCount')}) Tj')
      ..writeln('ET');

    return buffer.toString();
  }

  static List<int> _assemblePdf(Map<int, List<int>> objects) {
    final maxObjectId = objects.keys.reduce(math.max);
    final bytes = BytesBuilder();
    final offsets = <int>[0];

    bytes.add(utf8.encode('%PDF-1.4\n'));
    for (var objectId = 1; objectId <= maxObjectId; objectId++) {
      final body = objects[objectId];
      if (body == null) {
        throw StateError('Objet PDF manquant: $objectId');
      }
      offsets.add(bytes.length);
      bytes.add(utf8.encode('$objectId 0 obj\n'));
      bytes.add(body);
      bytes.addByte(0x0A);
      bytes.add(utf8.encode('endobj\n'));
    }

    final xrefOffset = bytes.length;
    bytes.add(utf8.encode('xref\n0 ${maxObjectId + 1}\n'));
    bytes.add(utf8.encode('0000000000 65535 f \n'));
    for (var objectId = 1; objectId <= maxObjectId; objectId++) {
      final offset = offsets[objectId].toString().padLeft(10, '0');
      bytes.add(utf8.encode('$offset 00000 n \n'));
    }
    bytes.add(
      utf8.encode(
        'trailer << /Size ${maxObjectId + 1} /Root 1 0 R >>\n'
        'startxref\n$xrefOffset\n%%EOF',
      ),
    );
    return bytes.toBytes();
  }

  static List<String> _wrapText(String text, int maxChars) {
    if (text.isEmpty) return const [''];
    final sanitized = _ascii(text).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (sanitized.isEmpty) return const [''];
    if (sanitized.length <= maxChars) return [sanitized];

    final words = sanitized.split(' ');
    final lines = <String>[];
    var current = '';
    for (final word in words) {
      final candidate = current.isEmpty ? word : '$current $word';
      if (candidate.length <= maxChars) {
        current = candidate;
      } else {
        if (current.isNotEmpty) {
          lines.add(current);
        }
        current = word;
      }
    }
    if (current.isNotEmpty) {
      lines.add(current);
    }
    return lines;
  }

  static String _pdfEscape(String input) {
    return _ascii(input)
        .replaceAll('\\', r'\\')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)')
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ');
  }

  static String _ascii(String input) {
    const replacements = {
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'À': 'A',
      'Â': 'A',
      'Ä': 'A',
      'ç': 'c',
      'Ç': 'C',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'É': 'E',
      'È': 'E',
      'Ê': 'E',
      'Ë': 'E',
      'î': 'i',
      'ï': 'i',
      'Î': 'I',
      'Ï': 'I',
      'ô': 'o',
      'ö': 'o',
      'Ô': 'O',
      'Ö': 'O',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'Ù': 'U',
      'Û': 'U',
      'Ü': 'U',
      'ÿ': 'y',
      'Ÿ': 'Y',
      'œ': 'oe',
      'Œ': 'OE',
      '’': "'",
      '“': '"',
      '”': '"',
      '–': '-',
      '—': '-',
      '•': '-',
      '·': '-',
    };

    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);
      if (replacements.containsKey(char)) {
        buffer.write(replacements[char]);
      } else if (rune >= 32 && rune <= 126) {
        buffer.write(char);
      } else if (rune == 10 || rune == 13) {
        buffer.write(' ');
      }
    }
    return buffer.toString();
  }

  static String _formatDateTime(DateTime date) {
    final local = date.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  static String _formatMoney(double value) {
    final amount = value.toStringAsFixed(0);
    final buffer = StringBuffer();
    for (var i = 0; i < amount.length; i++) {
      if (i > 0 && (amount.length - i) % 3 == 0) {
        buffer.write(' ');
      }
      buffer.write(amount[i]);
    }
    return '$buffer FC';
  }
}
