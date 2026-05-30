import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

class UserDirectoryExportRow {
  const UserDirectoryExportRow({
    required this.index,
    required this.name,
    required this.identifier,
    required this.role,
    required this.service,
    required this.status,
    required this.lastConnection,
  });

  final int index;
  final String name;
  final String identifier;
  final String role;
  final String service;
  final String status;
  final String lastConnection;
}

class UserDirectoryExporter {
  UserDirectoryExporter._();

  static Future<String?> exportExcel({
    required String title,
    required List<UserDirectoryExportRow> rows,
  }) async {
    final workbook = Excel.createExcel();
    final sheetName = 'Utilisateurs';
    final defaultSheet = workbook.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != sheetName) {
      workbook.rename(defaultSheet, sheetName);
    }

    final sheet = workbook[sheetName];
    sheet.appendRow([
      TextCellValue('#'),
      TextCellValue('Nom'),
      TextCellValue('Email / Identifiant'),
      TextCellValue('Rôle'),
      TextCellValue('Service'),
      TextCellValue('Statut'),
      TextCellValue('Dernière connexion'),
    ]);
    for (final row in rows) {
      sheet.appendRow([
        IntCellValue(row.index),
        TextCellValue(row.name),
        TextCellValue(row.identifier),
        TextCellValue(row.role),
        TextCellValue(row.service),
        TextCellValue(row.status),
        TextCellValue(row.lastConnection),
      ]);
    }

    final bytes = workbook.save(fileName: _fileName('xlsx'));
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Impossible de générer le fichier Excel.');
    }

    return FilePicker.saveFile(
      dialogTitle: 'Exporter les utilisateurs Excel',
      fileName: _fileName('xlsx'),
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      bytes: Uint8List.fromList(bytes),
    );
  }

  static Future<String?> exportPdf({
    required String title,
    required List<UserDirectoryExportRow> rows,
  }) {
    final bytes = Uint8List.fromList(_buildPdfBytes(title: title, rows: rows));
    return FilePicker.saveFile(
      dialogTitle: 'Exporter les utilisateurs PDF',
      fileName: _fileName('pdf'),
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      bytes: bytes,
    );
  }

  static String _fileName(String extension) {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'utilisateurs_${now.year}-${two(now.month)}-${two(now.day)}_'
        '${two(now.hour)}-${two(now.minute)}.$extension';
  }

  static List<int> _buildPdfBytes({
    required String title,
    required List<UserDirectoryExportRow> rows,
  }) {
    const pageWidth = 842.0;
    const pageHeight = 595.0;
    const rowsPerPage = 22;
    final chunks = <List<UserDirectoryExportRow>>[];
    for (var i = 0; i < rows.length; i += rowsPerPage) {
      final end = i + rowsPerPage > rows.length ? rows.length : i + rowsPerPage;
      chunks.add(rows.sublist(i, end));
    }
    if (chunks.isEmpty) chunks.add(const []);

    final objects = <int, List<int>>{};
    final pageIds = <int>[];
    final contentIds = <int>[];
    final fontId = 3 + chunks.length * 2;

    for (var page = 0; page < chunks.length; page++) {
      final pageId = 3 + page * 2;
      final contentId = pageId + 1;
      pageIds.add(pageId);
      contentIds.add(contentId);
      objects[pageId] = ascii.encode(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $pageWidth $pageHeight] '
        '/Resources << /Font << /F1 $fontId 0 R >> >> '
        '/Contents $contentId 0 R >>',
      );
      final content = _buildPdfPageContent(
        title: title,
        page: page + 1,
        totalPages: chunks.length,
        rows: chunks[page],
      );
      objects[contentId] = ascii.encode(
        '<< /Length ${latin1.encode(content).length} >>\nstream\n'
        '$content\nendstream',
      );
    }

    objects[1] = ascii.encode('<< /Type /Catalog /Pages 2 0 R >>');
    objects[2] = ascii.encode(
      '<< /Type /Pages /Kids [${pageIds.map((id) => '$id 0 R').join(' ')}] '
      '/Count ${pageIds.length} >>',
    );
    objects[fontId] = ascii.encode(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    );

    return _assemblePdf(objects);
  }

  static String _buildPdfPageContent({
    required String title,
    required int page,
    required int totalPages,
    required List<UserDirectoryExportRow> rows,
  }) {
    final buffer = StringBuffer();

    void text(double x, double y, String value, {double size = 9}) {
      buffer.writeln(
        'BT /F1 $size Tf $x $y Td (${_escapePdfText(value)}) Tj ET',
      );
    }

    text(36, 552, title, size: 18);
    text(730, 552, 'Page $page/$totalPages', size: 9);
    text(36, 526, '#', size: 9);
    text(66, 526, 'Nom', size: 9);
    text(215, 526, 'Identifiant', size: 9);
    text(360, 526, 'Role', size: 9);
    text(485, 526, 'Service', size: 9);
    text(655, 526, 'Statut', size: 9);
    text(720, 526, 'Connexion', size: 9);

    var y = 504.0;
    for (final row in rows) {
      text(36, y, row.index.toString());
      text(66, y, _clip(row.name, 25));
      text(215, y, _clip(row.identifier, 24));
      text(360, y, _clip(row.role, 20));
      text(485, y, _clip(row.service, 25));
      text(655, y, row.status);
      text(720, y, _clip(row.lastConnection, 17));
      y -= 20;
    }

    return buffer.toString();
  }

  static String _clip(String value, int max) {
    if (value.length <= max) return value;
    return '${value.substring(0, max - 1)}.';
  }

  static String _escapePdfText(String value) {
    return value.runes
        .map((codePoint) {
          if (codePoint > 255) return '?';
          return String.fromCharCode(codePoint);
        })
        .join()
        .replaceAll(r'\', r'\\')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)');
  }

  static List<int> _assemblePdf(Map<int, List<int>> objects) {
    final bytes = <int>[];
    final offsets = <int, int>{};
    bytes.addAll(ascii.encode('%PDF-1.4\n'));

    final ids = objects.keys.toList()..sort();
    for (final id in ids) {
      offsets[id] = bytes.length;
      bytes.addAll(ascii.encode('$id 0 obj\n'));
      bytes.addAll(objects[id]!);
      bytes.addAll(ascii.encode('\nendobj\n'));
    }

    final xrefOffset = bytes.length;
    final maxId = ids.isEmpty ? 0 : ids.last;
    bytes.addAll(ascii.encode('xref\n0 ${maxId + 1}\n'));
    bytes.addAll(ascii.encode('0000000000 65535 f \n'));
    for (var id = 1; id <= maxId; id++) {
      final offset = offsets[id] ?? 0;
      bytes.addAll(
        ascii.encode('${offset.toString().padLeft(10, '0')} 00000 n \n'),
      );
    }

    bytes.addAll(
      ascii.encode(
        'trailer\n<< /Size ${maxId + 1} /Root 1 0 R >>\n'
        'startxref\n$xrefOffset\n%%EOF',
      ),
    );
    return bytes;
  }
}
