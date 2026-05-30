import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:printing/printing.dart';
import 'package:qr/qr.dart';

import 'gestia_qr_payload.dart';

class CpiData {
  const CpiData({
    required this.provinceName,
    required this.cpiNumber,
    required this.generatedAt,
    required this.perceptionNoteNumber,
    required this.taxpayerName,
    required this.taxpayerDenomination,
    required this.taxpayerIdentifier,
    required this.verificationIdentifier,
    required this.taxpayerPhone,
    required this.taxpayerEmail,
    required this.taxpayerAddress,
    required this.communeName,
    required this.natureActe,
    required this.exercise,
    required this.actName,
    required this.periodicity,
    required this.actCount,
    required this.rateUsd,
    required this.amountUsd,
    required this.paymentMode,
    required this.agency,
    required this.agentName,
  });

  final String provinceName;
  final String cpiNumber;
  final DateTime generatedAt;
  final String perceptionNoteNumber;
  final String taxpayerName;
  final String taxpayerDenomination;
  final String taxpayerIdentifier;
  final String verificationIdentifier;
  final String taxpayerPhone;
  final String taxpayerEmail;
  final String taxpayerAddress;
  final String communeName;
  final String natureActe;
  final int exercise;
  final String actName;
  final String periodicity;
  final int actCount;
  final double rateUsd;
  final double amountUsd;
  final String paymentMode;
  final String agency;
  final String agentName;
}

class _PdfImage {
  const _PdfImage({
    required this.width,
    required this.height,
    required this.bytes,
  });

  final int width;
  final int height;
  final Uint8List bytes;
}

class CpiExporter {
  CpiExporter._();

  static Future<String?> exportPdf(CpiData data) async {
    return FilePicker.saveFile(
      dialogTitle: 'Imprimer le CPI',
      fileName: 'cpi_${_sanitizeFilePart(data.cpiNumber)}.pdf',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      bytes: Uint8List.fromList(await _buildPdfBytes(data)),
    );
  }

  static Future<void> printPdf(CpiData data) async {
    final bytes = Uint8List.fromList(await _buildPdfBytes(data));
    await Printing.layoutPdf(
      name: 'cpi_${_sanitizeFilePart(data.cpiNumber)}.pdf',
      onLayout: (_) async => bytes,
    );
  }

  static Future<List<int>> buildPdfBytes(CpiData data) {
    return _buildPdfBytes(data);
  }

  static Future<List<int>> _buildPdfBytes(CpiData data) async {
    final logo = await _loadLogoImage();
    final objects = <int, List<int>>{};
    objects[1] = utf8.encode('<< /Type /Catalog /Pages 2 0 R >>');
    objects[2] = utf8.encode('<< /Type /Pages /Count 1 /Kids [4 0 R] >>');
    objects[3] = utf8.encode(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    );
    objects[6] = utf8.encode(
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>',
    );
    if (logo != null) {
      objects[7] = _buildImageObject(logo);
    }

    final content = _buildPdfPageContent(data, hasLogoImage: logo != null);
    final contentBytes = utf8.encode(content);
    final xObject = logo == null ? '' : ' /XObject << /I1 7 0 R >>';
    objects[4] = utf8.encode(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
      '/Resources << /Font << /F1 3 0 R /F2 6 0 R >>$xObject >> '
      '/Contents 5 0 R >>',
    );
    objects[5] = utf8.encode(
      '<< /Length ${contentBytes.length} >>\nstream\n$content\nendstream',
    );

    return _assemblePdf(objects);
  }

  static String _buildPdfPageContent(
    CpiData data, {
    required bool hasLogoImage,
  }) {
    final province = _ascii(
      data.provinceName.trim().isEmpty ? 'Kinshasa' : data.provinceName.trim(),
    ).toUpperCase();
    final city = province.contains('KINSHASA')
        ? 'VILLE DE KINSHASA'
        : 'PROVINCE DE $province';
    final place = province.contains('KINSHASA') ? 'Kinshasa' : province;
    final buffer = StringBuffer();

    _setStrokeColor(buffer, 0.10, 0.10, 0.10);
    if (hasLogoImage) {
      _image(buffer, 'I1', 36, 746, 62, 62);
    } else {
      _fallbackLogo(buffer, 36, 746, 62);
    }
    _drawQrPanel(buffer, 468, 727, 96, data);

    _centerText(buffer, 297.5, 806, 'REPUBLIQUE DEMOCRATIQUE DU CONGO', 12);
    _centerText(buffer, 297.5, 784, city, 11);
    _centerText(buffer, 297.5, 766, 'GOUVERNEMENT PROVINCIAL', 9.5, bold: true);
    _centerText(
      buffer,
      297.5,
      750,
      'MINISTERE DES FINANCES, ECONOMIE ET NUMERIQUE',
      9,
      bold: true,
    );

    _centerText(
      buffer,
      297.5,
      692,
      'CERTIFICAT DE PAIEMENT INFORMATISE - ${data.cpiNumber}',
      15,
    );
    _line(buffer, 125, 685, 470, 685);
    _rightText(
      buffer,
      558,
      642,
      '$place, le ${_formatDateTime(data.generatedAt)}',
      8.5,
    );

    _identitySections(buffer, data);
    _rightsSection(buffer, data);
    _paymentReferences(buffer, data);
    _certification(buffer, data);

    _text(
      buffer,
      28,
      18,
      "Vous pouvez vérifier l'authenticité de cette Quittance sur WWW.AU-VERIF.ONE en indiquant le numéro de l'avis.",
      7.5,
    );
    return buffer.toString();
  }

  static void _identitySections(StringBuffer buffer, CpiData data) {
    _rect(buffer, 28, 474, 539, 148);
    _line(buffer, 297.5, 474, 297.5, 622);
    _text(buffer, 38, 594, "I. RENSEIGNEMENT SUR L'ASSUJETTI", 11);
    _text(buffer, 309, 594, 'II. INFORMATIONS COMPLEMENTAIRE', 11);

    _field(
      buffer,
      38,
      558,
      246,
      'DENOMINATION',
      _fallback(data.taxpayerDenomination),
      labelWidth: 90,
      maxLines: 2,
    );
    _field(
      buffer,
      38,
      536,
      246,
      'NIF',
      _fallback(data.taxpayerIdentifier),
      labelWidth: 90,
    );
    _field(
      buffer,
      38,
      514,
      246,
      'TELEPHONE',
      _fallback(data.taxpayerPhone),
      labelWidth: 90,
    );
    _field(
      buffer,
      38,
      492,
      246,
      'ADRESSE',
      _fallback(data.taxpayerAddress),
      labelWidth: 90,
      maxLines: 2,
    );

    _field(
      buffer,
      309,
      558,
      238,
      'NOTE DE PERCEPTION',
      _fallback(data.perceptionNoteNumber),
      labelWidth: 115,
    );
    _field(
      buffer,
      309,
      536,
      238,
      'NOM COMPLET DU PAYEUR',
      _fallback(data.taxpayerName),
      labelWidth: 115,
      maxLines: 2,
    );
    _field(
      buffer,
      309,
      514,
      238,
      'TELEPHONE',
      _fallback(data.taxpayerPhone),
      labelWidth: 115,
    );
    _field(
      buffer,
      309,
      492,
      238,
      'ADRESSE DU PAYEUR',
      _fallback(data.taxpayerAddress),
      labelWidth: 115,
      maxLines: 2,
    );
  }

  static void _rightsSection(StringBuffer buffer, CpiData data) {
    _line(buffer, 28, 474, 567, 474);
    _text(
      buffer,
      33,
      444,
      'III. RENSEIGNEMENT SUR LE(S) DROIT(S) PERCU(S)',
      11,
    );

    const tableX = 34.0;
    const tableY = 326.0;
    const tableW = 523.0;
    const headerH = 42.0;
    const rowH = 58.0;

    _rect(buffer, tableX, tableY, tableW, headerH + rowH);
    final cols = <double>[0, 166, 202, 366, 410, 447, 470, 505, tableW];
    for (final offset in cols.skip(1).take(cols.length - 2)) {
      _line(buffer, tableX + offset, tableY, tableX + offset, tableY + 100);
    }
    _line(buffer, tableX, tableY + rowH, tableX + tableW, tableY + rowH);

    _tableLabel(buffer, tableX + 5, tableY + 78, "Nature d'actes");
    _tableLabel(buffer, tableX + 171, tableY + 78, 'Exercice');
    _tableLabel(buffer, tableX + 207, tableY + 78, "Nom de l'acte");
    _tableLabel(buffer, tableX + 371, tableY + 78, 'Periodicite');
    _tableLabel(buffer, tableX + 415, tableY + 82, 'Nbre');
    _tableLabel(buffer, tableX + 415, tableY + 68, "d'actes");
    _tableLabel(buffer, tableX + 452, tableY + 78, 'Taux');
    _tableLabel(buffer, tableX + 475, tableY + 78, 'Montant');
    _tableLabel(buffer, tableX + 510, tableY + 78, 'Devise');

    _wrappedText(buffer, tableX + 5, tableY + 39, data.natureActe, 8, 31, 3);
    _text(buffer, tableX + 171, tableY + 39, data.exercise.toString(), 8);
    _wrappedText(buffer, tableX + 207, tableY + 39, data.actName, 8, 31, 3);
    _text(buffer, tableX + 371, tableY + 39, data.periodicity, 8);
    _centerText(buffer, tableX + 428.5, tableY + 39, '${data.actCount}', 8);
    _rightText(buffer, tableX + 464, tableY + 39, _formatRate(data.rateUsd), 8);
    _rightText(
      buffer,
      tableX + 499,
      tableY + 39,
      _formatNumber(data.amountUsd),
      8,
    );
    _text(buffer, tableX + 512, tableY + 39, 'USD', 8);

    _text(
      buffer,
      34,
      302,
      'MONTANT PAYE : ${_formatNumber(data.amountUsd)} USD',
      8.5,
    );
  }

  static void _paymentReferences(StringBuffer buffer, CpiData data) {
    _line(buffer, 28, 286, 567, 286);
    _text(buffer, 33, 264, 'III. REFERENCES DE PAIEMENTS', 11);

    _field(
      buffer,
      34,
      234,
      250,
      'Bordereau de versement',
      data.cpiNumber,
      labelWidth: 118,
    );
    _field(
      buffer,
      34,
      214,
      250,
      'Mode de paiement',
      _fallback(data.paymentMode),
      labelWidth: 118,
    );
    _field(
      buffer,
      34,
      194,
      250,
      'Date de paiement',
      _formatDateTime(data.generatedAt),
      labelWidth: 118,
    );
    _field(
      buffer,
      302,
      234,
      250,
      "Nom de l'agent",
      _fallback(data.agentName),
      labelWidth: 105,
    );
    _field(
      buffer,
      302,
      214,
      250,
      'Agence',
      _fallback(data.agency),
      labelWidth: 105,
    );
    _line(buffer, 28, 178, 567, 178);
  }

  static void _certification(StringBuffer buffer, CpiData data) {
    _dashLine(buffer, 28, 164, 567, 164);
    _wrappedText(
      buffer,
      28,
      140,
      "Le Comptable Public Principal des recettes code 0784 certifie par le present, que l'assujetti ${_fallback(_assujettiName(data))}",
      8.5,
      98,
      2,
    );
    _wrappedText(
      buffer,
      46,
      112,
      "- ADRESSE : ${_fallback(data.taxpayerAddress)}",
      8.5,
      82,
      2,
    );
    _text(buffer, 46, 88, '- A paye la somme de :', 8.5);
    _text(
      buffer,
      90,
      68,
      'En chiffres : ${_formatNumber(data.amountUsd)} USD',
      8.5,
    );
    _text(
      buffer,
      90,
      50,
      'En lettres : ${_amountInFrench(data.amountUsd)}',
      8.5,
    );
    _text(buffer, 496, 70, 'Signature', 8.5);
    _text(buffer, 490, 30, 'GESTIA-GATEWAY', 8.5);
  }

  static void _drawQrPanel(
    StringBuffer buffer,
    double x,
    double y,
    double size,
    CpiData data,
  ) {
    _rect(buffer, x, y, size, size, fillGray: 1.0);
    _drawQrCode(buffer, x + 2, y + 2, size - 4, _qrPayload(data));
  }

  static String _qrPayload(CpiData data) {
    return GestiaQrPayload.encode(
      type: GestiaQrDocumentType.cpi,
      reference: data.cpiNumber,
      generatedAt: data.generatedAt,
      amountUsd: data.amountUsd,
      taxpayerIdentifier: data.verificationIdentifier,
      proofOfPayment: true,
      perceptionNoteNumber: data.perceptionNoteNumber,
      taxpayerName: data.taxpayerName,
      subjectLabel: data.actName,
      locationLabel: data.communeName,
      paymentChannel: data.paymentMode,
      agentName: data.agentName,
    );
  }

  static void _drawQrCode(
    StringBuffer buffer,
    double x,
    double y,
    double size,
    String payload,
  ) {
    final code = QrCode.fromData(
      data: payload,
      errorCorrectLevel: QrErrorCorrectLevel.L,
    );
    final image = QrImage(code);
    const quietZone = 4;
    final totalModules = image.moduleCount + quietZone * 2;
    final moduleSize = size / totalModules;

    buffer.writeln('q');
    buffer.writeln('0 0 0 rg');
    for (var row = 0; row < image.moduleCount; row++) {
      for (var col = 0; col < image.moduleCount; col++) {
        if (!image.isDark(row, col)) continue;
        final moduleX = x + (col + quietZone) * moduleSize;
        final moduleY = y + size - (row + quietZone + 1) * moduleSize;
        buffer.writeln(
          '${_n(moduleX)} ${_n(moduleY)} ${_n(moduleSize)} '
          '${_n(moduleSize)} re f',
        );
      }
    }
    buffer.writeln('Q');
  }

  static Future<_PdfImage?> _loadLogoImage() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      if (!manifest.listAssets().contains('assets/logo.png')) {
        return null;
      }
      final data = await rootBundle.load('assets/logo.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final rgbaData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (rgbaData == null) return null;
      final rgba = rgbaData.buffer.asUint8List();
      final rgb = Uint8List(image.width * image.height * 3);
      var target = 0;
      for (var source = 0; source < rgba.length; source += 4) {
        final alpha = rgba[source + 3] / 255.0;
        rgb[target++] = (255 + (rgba[source] - 255) * alpha).round();
        rgb[target++] = (255 + (rgba[source + 1] - 255) * alpha).round();
        rgb[target++] = (255 + (rgba[source + 2] - 255) * alpha).round();
      }
      return _PdfImage(width: image.width, height: image.height, bytes: rgb);
    } catch (_) {
      return null;
    }
  }

  static List<int> _buildImageObject(_PdfImage image) {
    final bytes = BytesBuilder();
    bytes.add(
      utf8.encode(
        '<< /Type /XObject /Subtype /Image '
        '/Width ${image.width} /Height ${image.height} '
        '/ColorSpace /DeviceRGB /BitsPerComponent 8 '
        '/Length ${image.bytes.length} >>\nstream\n',
      ),
    );
    bytes.add(image.bytes);
    bytes.add(utf8.encode('\nendstream'));
    return bytes.toBytes();
  }

  static void _image(
    StringBuffer buffer,
    String name,
    double x,
    double y,
    double width,
    double height,
  ) {
    buffer
      ..writeln('q')
      ..writeln('${_n(width)} 0 0 ${_n(height)} ${_n(x)} ${_n(y)} cm')
      ..writeln('/$name Do')
      ..writeln('Q');
  }

  static void _fallbackLogo(
    StringBuffer buffer,
    double x,
    double y,
    double size,
  ) {
    final centerX = x + size / 2;
    final centerY = y + size / 2;
    _circle(buffer, centerX, centerY, size / 2, stroke: (0.10, 0.10, 0.10));
    _circle(buffer, centerX, centerY, size / 2 - 6, stroke: (0.10, 0.10, 0.10));
    _centerText(buffer, centerX, centerY + 4, 'RDC', 10, bold: true);
    _centerText(buffer, centerX, centerY - 10, 'GESTIA', 7, bold: true);
  }

  static void _field(
    StringBuffer buffer,
    double x,
    double y,
    double width,
    String label,
    String value, {
    double labelWidth = 100,
    int maxLines = 1,
  }) {
    _text(buffer, x, y, label, 8, bold: true);
    _text(buffer, x + labelWidth, y, ':', 8);
    final valueX = x + labelWidth + 8;
    final chars = ((width - labelWidth - 8) / 4.1).floor().clamp(8, 80).toInt();
    _wrappedText(buffer, valueX, y, _fallback(value), 8, chars, maxLines);
  }

  static void _wrappedText(
    StringBuffer buffer,
    double x,
    double y,
    String text,
    double size,
    int maxChars,
    int maxLines, {
    bool bold = false,
  }) {
    final lines = _wrapText(text, maxChars).take(maxLines).toList();
    for (var i = 0; i < lines.length; i++) {
      _text(buffer, x, y - (i * (size + 3)), lines[i], size, bold: bold);
    }
  }

  static void _tableLabel(
    StringBuffer buffer,
    double x,
    double y,
    String text,
  ) {
    _text(buffer, x, y, text, 8);
  }

  static void _text(
    StringBuffer buffer,
    double x,
    double y,
    String text,
    double size, {
    bool bold = false,
  }) {
    buffer
      ..writeln('BT')
      ..writeln('/${bold ? 'F2' : 'F1'} ${_n(size)} Tf')
      ..writeln('${_n(x)} ${_n(y)} Td')
      ..writeln('(${_pdfEscape(text)}) Tj')
      ..writeln('ET');
  }

  static void _centerText(
    StringBuffer buffer,
    double centerX,
    double y,
    String text,
    double size, {
    bool bold = false,
  }) {
    final clean = _ascii(text);
    final width = clean.length * size * (bold ? 0.53 : 0.49);
    _text(buffer, centerX - width / 2, y, clean, size, bold: bold);
  }

  static void _rightText(
    StringBuffer buffer,
    double rightX,
    double y,
    String text,
    double size, {
    bool bold = false,
  }) {
    final clean = _ascii(text);
    final width = clean.length * size * (bold ? 0.53 : 0.49);
    _text(buffer, rightX - width, y, clean, size, bold: bold);
  }

  static void _rect(
    StringBuffer buffer,
    double x,
    double y,
    double width,
    double height, {
    double? fillGray,
  }) {
    buffer.writeln('q');
    if (fillGray != null) {
      buffer
        ..writeln('${_n(fillGray)} g')
        ..writeln('${_n(x)} ${_n(y)} ${_n(width)} ${_n(height)} re f');
    } else {
      buffer.writeln('${_n(x)} ${_n(y)} ${_n(width)} ${_n(height)} re S');
    }
    buffer.writeln('Q');
  }

  static void _line(
    StringBuffer buffer,
    double x1,
    double y1,
    double x2,
    double y2,
  ) {
    buffer
      ..writeln('q')
      ..writeln('${_n(x1)} ${_n(y1)} m ${_n(x2)} ${_n(y2)} l S')
      ..writeln('Q');
  }

  static void _dashLine(
    StringBuffer buffer,
    double x1,
    double y1,
    double x2,
    double y2,
  ) {
    buffer
      ..writeln('q')
      ..writeln('[4 4] 0 d')
      ..writeln('${_n(x1)} ${_n(y1)} m ${_n(x2)} ${_n(y2)} l S')
      ..writeln('Q');
  }

  static void _setStrokeColor(
    StringBuffer buffer,
    double red,
    double green,
    double blue,
  ) {
    buffer.writeln('${_n(red)} ${_n(green)} ${_n(blue)} RG');
  }

  static void _circle(
    StringBuffer buffer,
    double centerX,
    double centerY,
    double radius, {
    (double, double, double)? stroke,
  }) {
    const kappa = 0.5522847498;
    final control = radius * kappa;
    buffer.writeln('q');
    if (stroke != null) {
      buffer.writeln('${_n(stroke.$1)} ${_n(stroke.$2)} ${_n(stroke.$3)} RG');
    }
    buffer
      ..writeln('${_n(centerX + radius)} ${_n(centerY)} m')
      ..writeln(
        '${_n(centerX + radius)} ${_n(centerY + control)} '
        '${_n(centerX + control)} ${_n(centerY + radius)} '
        '${_n(centerX)} ${_n(centerY + radius)} c',
      )
      ..writeln(
        '${_n(centerX - control)} ${_n(centerY + radius)} '
        '${_n(centerX - radius)} ${_n(centerY + control)} '
        '${_n(centerX - radius)} ${_n(centerY)} c',
      )
      ..writeln(
        '${_n(centerX - radius)} ${_n(centerY - control)} '
        '${_n(centerX - control)} ${_n(centerY - radius)} '
        '${_n(centerX)} ${_n(centerY - radius)} c',
      )
      ..writeln(
        '${_n(centerX + control)} ${_n(centerY - radius)} '
        '${_n(centerX + radius)} ${_n(centerY - control)} '
        '${_n(centerX + radius)} ${_n(centerY)} c',
      )
      ..writeln('S')
      ..writeln('Q');
  }

  static String _n(num value) => value.toStringAsFixed(2);

  static List<int> _assemblePdf(Map<int, List<int>> objects) {
    final maxObjectId = objects.keys.reduce(math.max);
    final bytes = BytesBuilder();
    final offsets = <int>[0];

    bytes.add(utf8.encode('%PDF-1.4\n'));
    for (var objectId = 1; objectId <= maxObjectId; objectId++) {
      final body = objects[objectId];
      if (body == null) throw StateError('Objet PDF manquant: $objectId');
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
        if (current.isNotEmpty) lines.add(current);
        current = word;
      }
    }
    if (current.isNotEmpty) lines.add(current);
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
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  static String _formatNumber(double value) {
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  static String _formatRate(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return _formatNumber(value);
  }

  static String _amountInFrench(double amount) {
    final rounded = amount.round().clamp(0, 999999999).toInt();
    final words = _numberToFrench(rounded);
    return '${words[0].toUpperCase()}${words.substring(1)} Dollars';
  }

  static String _numberToFrench(int value) {
    if (value == 0) return 'zero';
    if (value < 0) return 'moins ${_numberToFrench(-value)}';

    final millions = value ~/ 1000000;
    final thousands = (value % 1000000) ~/ 1000;
    final rest = value % 1000;
    final parts = <String>[];

    if (millions > 0) {
      parts.add(
        millions == 1 ? 'un million' : '${_underThousand(millions)} millions',
      );
    }
    if (thousands > 0) {
      parts.add(
        thousands == 1 ? 'mille' : '${_underThousand(thousands)} mille',
      );
    }
    if (rest > 0) parts.add(_underThousand(rest));
    return parts.join(' ');
  }

  static String _underThousand(int value) {
    final hundreds = value ~/ 100;
    final rest = value % 100;
    final parts = <String>[];
    if (hundreds > 0) {
      if (hundreds == 1) {
        parts.add('cent');
      } else {
        parts.add('${_underHundred(hundreds)} cent');
      }
    }
    if (rest > 0) parts.add(_underHundred(rest));
    return parts.join(' ');
  }

  static String _underHundred(int value) {
    const units = [
      '',
      'un',
      'deux',
      'trois',
      'quatre',
      'cinq',
      'six',
      'sept',
      'huit',
      'neuf',
      'dix',
      'onze',
      'douze',
      'treize',
      'quatorze',
      'quinze',
      'seize',
    ];
    if (value < units.length) return units[value];
    if (value < 20) return 'dix-${units[value - 10]}';
    if (value < 70) {
      final tens = value ~/ 10;
      final unit = value % 10;
      const names = {
        2: 'vingt',
        3: 'trente',
        4: 'quarante',
        5: 'cinquante',
        6: 'soixante',
      };
      if (unit == 0) return names[tens]!;
      if (unit == 1) return '${names[tens]} et un';
      return '${names[tens]}-${units[unit]}';
    }
    if (value < 80) {
      final rest = value - 60;
      return rest == 11
          ? 'soixante et onze'
          : 'soixante-${_underHundred(rest)}';
    }
    final rest = value - 80;
    if (rest == 0) return 'quatre-vingts';
    return 'quatre-vingt-${_underHundred(rest)}';
  }

  static String _sanitizeFilePart(String value) {
    final cleaned = _ascii(value)
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return cleaned.isEmpty ? 'document' : cleaned;
  }

  static String _fallback(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'Non renseigne' : trimmed;
  }

  static String _assujettiName(CpiData data) {
    final denomination = data.taxpayerDenomination.trim();
    if (denomination.isNotEmpty) return denomination;
    return data.taxpayerName;
  }
}
