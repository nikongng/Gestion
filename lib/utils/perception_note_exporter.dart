import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:printing/printing.dart';
import 'package:qr/qr.dart';

import 'gestia_qr_payload.dart';

class PerceptionNoteData {
  const PerceptionNoteData({
    required this.provinceName,
    required this.noteNumber,
    required this.generatedAt,
    required this.serviceAssiette,
    required this.articleBudgetaire,
    required this.acteJuridique,
    required this.legalReference,
    required this.tariffDetails,
    required this.tariffLabel,
    required this.amountUsd,
    required this.taxpayerName,
    required this.taxpayerIdentifier,
    required this.taxpayerPhone,
    required this.taxpayerEmail,
    required this.taxpayerAddress,
    required this.taxpayerNip,
    required this.taxpayerComment,
    required this.pointTaxation,
    required this.paymentChannel,
    required this.taxateurName,
    required this.ordonnateurName,
    required this.paymentDelayLabel,
    required this.paymentDeadline,
    this.isTaxationDocument = false,
    this.bankName = '',
    this.receiverAccount = '',
    this.declarantName = '',
    this.declarantPhone = '',
    this.declarantEmail = '',
    this.cdfRate = 0,
    this.ordonnateurAvis = 'Taxation conforme',
  });

  final String provinceName;
  final String noteNumber;
  final DateTime generatedAt;
  final String serviceAssiette;
  final String articleBudgetaire;
  final String acteJuridique;
  final String legalReference;
  final String tariffDetails;
  final String tariffLabel;
  final double amountUsd;
  final String taxpayerName;
  final String taxpayerIdentifier;
  final String taxpayerPhone;
  final String taxpayerEmail;
  final String taxpayerAddress;
  final String taxpayerNip;
  final String taxpayerComment;
  final String pointTaxation;
  final String paymentChannel;
  final String taxateurName;
  final String ordonnateurName;
  final String paymentDelayLabel;
  final DateTime paymentDeadline;
  final bool isTaxationDocument;
  final String bankName;
  final String receiverAccount;
  final String declarantName;
  final String declarantPhone;
  final String declarantEmail;
  final double cdfRate;
  final String ordonnateurAvis;

  double get amountCdf => cdfRate > 0 ? amountUsd * cdfRate : 0;

  String get documentTitle =>
      isTaxationDocument ? 'NOTE DE TAXATION' : 'NOTE DE PERCEPTION';

  PerceptionNoteData copyWith({
    String? bankName,
    String? receiverAccount,
    String? declarantName,
    String? declarantPhone,
    String? declarantEmail,
    double? cdfRate,
    String? ordonnateurAvis,
  }) {
    return PerceptionNoteData(
      provinceName: provinceName,
      noteNumber: noteNumber,
      generatedAt: generatedAt,
      serviceAssiette: serviceAssiette,
      articleBudgetaire: articleBudgetaire,
      acteJuridique: acteJuridique,
      legalReference: legalReference,
      tariffDetails: tariffDetails,
      tariffLabel: tariffLabel,
      amountUsd: amountUsd,
      taxpayerName: taxpayerName,
      taxpayerIdentifier: taxpayerIdentifier,
      taxpayerPhone: taxpayerPhone,
      taxpayerEmail: taxpayerEmail,
      taxpayerAddress: taxpayerAddress,
      taxpayerNip: taxpayerNip,
      taxpayerComment: taxpayerComment,
      pointTaxation: pointTaxation,
      paymentChannel: paymentChannel,
      taxateurName: taxateurName,
      ordonnateurName: ordonnateurName,
      paymentDelayLabel: paymentDelayLabel,
      paymentDeadline: paymentDeadline,
      isTaxationDocument: isTaxationDocument,
      bankName: bankName ?? this.bankName,
      receiverAccount: receiverAccount ?? this.receiverAccount,
      declarantName: declarantName ?? this.declarantName,
      declarantPhone: declarantPhone ?? this.declarantPhone,
      declarantEmail: declarantEmail ?? this.declarantEmail,
      cdfRate: cdfRate ?? this.cdfRate,
      ordonnateurAvis: ordonnateurAvis ?? this.ordonnateurAvis,
    );
  }
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

class PerceptionNoteExporter {
  PerceptionNoteExporter._();

  static Future<String?> exportPdf(PerceptionNoteData data) async {
    final fileName =
        '${_documentFilePrefix(data)}_${_sanitizeFilePart(data.noteNumber)}.pdf';
    return FilePicker.saveFile(
      dialogTitle: data.isTaxationDocument
          ? 'Enregistrer la note de taxation'
          : 'Enregistrer la note de perception',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      bytes: Uint8List.fromList(await buildPdfBytes(data)),
    );
  }

  static Future<void> printPdf(PerceptionNoteData data) async {
    await Printing.layoutPdf(
      name:
          '${_documentFilePrefix(data)}_${_sanitizeFilePart(data.noteNumber)}.pdf',
      onLayout: (_) async => Uint8List.fromList(await buildPdfBytes(data)),
    );
  }

  static String _documentFilePrefix(PerceptionNoteData data) {
    return data.isTaxationDocument ? 'note_taxation' : 'note_perception';
  }

  static Future<List<int>> buildPdfBytes(PerceptionNoteData data) async {
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
    PerceptionNoteData data, {
    required bool hasLogoImage,
  }) {
    final province = _ascii(
      data.provinceName.trim().isEmpty ? 'Kinshasa' : data.provinceName.trim(),
    ).toUpperCase();
    final city = province.contains('KINSHASA')
        ? 'VILLE DE KINSHASA'
        : 'VILLE / PROVINCE DE $province';
    final government = province.contains('KINSHASA')
        ? 'GOUVERNEMENT PROVINCIAL DE KINSHASA'
        : 'GOUVERNEMENT PROVINCIAL';
    final buffer = StringBuffer();

    _setStrokeColor(buffer, 0.12, 0.12, 0.12);
    _rect(buffer, 34, 34, 527, 774);
    _rect(buffer, 40, 40, 515, 762);

    _centerText(
      buffer,
      297.5,
      786,
      'REPUBLIQUE DEMOCRATIQUE DU CONGO',
      11,
      bold: true,
    );
    _centerText(buffer, 297.5, 770, city, 10, bold: true);
    _centerText(buffer, 297.5, 755, government, 10, bold: true);
    _centerText(
      buffer,
      297.5,
      740,
      'MINISTERE DES FINANCES, ECONOMIE ET NUMERIQUE',
      9,
      bold: true,
    );

    if (hasLogoImage) {
      _image(buffer, 'I1', 44, 708, 78, 74);
    } else {
      _provinceLogo(buffer, 44, 710, 76);
    }
    _verificationBox(buffer, 447, 700, data);
    _rect(buffer, 142, 704, 311, 44, fillGray: 0.93);
    _centerText(buffer, 297.5, 727, data.documentTitle, 18, bold: true);
    _centerText(buffer, 297.5, 710, data.noteNumber, 10, bold: true);
    _centerText(
      buffer,
      297.5,
      696,
      'Date : ${_formatDateTime(data.generatedAt)}',
      8,
      bold: true,
    );

    _watermark(buffer);

    _section(buffer, 44, 638, 507, 48, 'I. SERVICE TAXATEUR');
    _field(buffer, 58, 657, 430, 'Service d’assiette', data.serviceAssiette);

    _section(buffer, 44, 442, 507, 180, 'II. ARTICLES BUDGETAIRES');
    _field(
      buffer,
      58,
      596,
      455,
      'Article budgetaire',
      data.articleBudgetaire,
      maxLines: 2,
    );
    _field(buffer, 58, 568, 455, 'Acte juridique', data.acteJuridique);
    _field(
      buffer,
      58,
      548,
      455,
      'Reference legale',
      data.legalReference,
      maxLines: 2,
    );
    _field(buffer, 58, 512, 455, 'Tarif officiel', data.tariffLabel);
    _field(
      buffer,
      58,
      492,
      455,
      'Montant taxe',
      _formatMoney(data),
      boldValue: true,
    );
    _field(
      buffer,
      58,
      472,
      455,
      'Date de taxation',
      _formatDateTime(data.generatedAt),
    );
    _field(
      buffer,
      315,
      472,
      200,
      'Periodicite',
      _periodicityFrom(data.tariffDetails),
    );

    _section(buffer, 44, 272, 250, 152, 'III. IDENTITÉ DE L’ASSUJETTI');
    _field(buffer, 56, 398, 210, 'Nom', _fallback(data.taxpayerName));
    _field(
      buffer,
      56,
      378,
      210,
      'Identifiant',
      _fallback(data.taxpayerIdentifier),
    );
    _field(buffer, 56, 358, 210, 'Tel', _fallback(data.taxpayerPhone));
    _field(buffer, 56, 338, 210, 'E-mail', _fallback(data.taxpayerEmail));
    _field(
      buffer,
      56,
      318,
      210,
      'Adresse',
      _fallback(data.taxpayerAddress),
      maxLines: 2,
    );
    _field(buffer, 56, 300, 210, 'NIP', _fallback(data.taxpayerNip));
    _field(
      buffer,
      56,
      282,
      210,
      'Commentaire',
      _fallback(data.taxpayerComment),
      maxLines: 2,
    );

    _section(buffer, 305, 272, 246, 152, 'IV. INFORMATIONS SUPPLEMENTAIRES');
    _field(
      buffer,
      317,
      398,
      205,
      'Point de taxation',
      data.pointTaxation,
      maxLines: 2,
    );
    if (!data.isTaxationDocument) {
      _field(buffer, 317, 362, 205, 'Canal indicatif', data.paymentChannel);
      _field(buffer, 317, 342, 205, 'Banque', _fallback(data.bankName));
      _field(
        buffer,
        317,
        322,
        205,
        'Compte receveur',
        _fallback(data.receiverAccount),
      );
      _field(buffer, 317, 302, 205, 'Declarant', _fallback(data.declarantName));
      _field(buffer, 317, 282, 205, 'Contact', _declarantContact(data));

      _section(buffer, 44, 104, 507, 168, 'V. SERVICE ORDONNATEUR');
      _field(
        buffer,
        58,
        246,
        455,
        'Avis de l’ordonnateur',
        _fallback(data.ordonnateurAvis),
      );
      _field(
        buffer,
        58,
        226,
        455,
        'Montant ordonnance en chiffres',
        _formatMoney(data),
        boldValue: true,
      );
      _field(
        buffer,
        58,
        206,
        455,
        'Montant ordonnance en lettres',
        _amountInFrench(data.amountUsd),
        maxLines: 2,
      );
      _field(
        buffer,
        58,
        172,
        455,
        'Date ordonnancement',
        _formatDateTime(data.generatedAt),
      );
      _field(
        buffer,
        58,
        152,
        455,
        'Nom de l’ordonnateur',
        data.ordonnateurName,
      );
      _field(
        buffer,
        58,
        132,
        455,
        'Delai de paiement',
        '${_fallback(data.paymentDelayLabel)}, au plus tard le ${_formatDate(data.paymentDeadline)} sous peine de penalite.',
        maxLines: 2,
      );
    } else {
      _section(buffer, 44, 104, 507, 168, 'V. VALIDATION DE TAXATION');
      _field(
        buffer,
        58,
        246,
        455,
        'Statut',
        'Taxation enregistree, en attente d’ordonnancement',
      );
      _field(
        buffer,
        58,
        226,
        455,
        'Montant taxe en chiffres',
        _formatMoney(data),
        boldValue: true,
      );
      _field(
        buffer,
        58,
        206,
        455,
        'Montant taxe en lettres',
        _amountInFrench(data.amountUsd),
        maxLines: 2,
      );
      _field(
        buffer,
        58,
        172,
        455,
        'Date de taxation',
        _formatDateTime(data.generatedAt),
      );
      _field(buffer, 58, 152, 455, 'Nom du taxateur', data.taxateurName);
      _field(
        buffer,
        58,
        132,
        455,
        'Suite du dossier',
        'A valider par l’ordonnateur.',
        maxLines: 2,
      );
    }

    _rect(buffer, 44, 72, 507, 22, fillGray: 0.88);
    _centerText(
      buffer,
      297.5,
      79,
      'CECI N’EST PAS UNE PREUVE DE PAIEMENT',
      11,
      bold: true,
    );

    _line(buffer, 72, 54, 210, 54);
    _line(buffer, 385, 54, 523, 54);
    _centerText(
      buffer,
      141,
      43,
      data.isTaxationDocument ? 'Signature taxateur' : 'Signature ordonnateur',
      8,
    );
    _centerText(buffer, 454, 43, 'Signature assujetti', 8);
    return buffer.toString();
  }

  static void _verificationBox(
    StringBuffer buffer,
    double x,
    double y,
    PerceptionNoteData data,
  ) {
    const size = 104.0;
    _rect(buffer, x, y, size, size, fillGray: 1.0);
    _rect(buffer, x, y, size, size);
    _drawQrCode(buffer, x + 4, y + 4, size - 8, _qrPayload(data));
    _centerText(buffer, x + size / 2, y - 10, 'AU-VERIF.ONE', 7, bold: true);
    _centerText(buffer, x + size / 2, y - 20, data.noteNumber, 5.5);
  }

  static String _qrPayload(PerceptionNoteData data) {
    final controlIdentifier = data.taxpayerIdentifier.trim().isNotEmpty
        ? data.taxpayerIdentifier
        : data.noteNumber;
    return GestiaQrPayload.encode(
      type: GestiaQrDocumentType.perceptionNote,
      reference: data.noteNumber,
      generatedAt: data.generatedAt,
      amountUsd: data.amountUsd,
      taxpayerIdentifier: controlIdentifier,
      proofOfPayment: false,
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

  static void _provinceLogo(
    StringBuffer buffer,
    double x,
    double y,
    double size,
  ) {
    final centerX = x + size / 2;
    final centerY = y + size / 2;
    final outer = size / 2;
    final middle = outer - 3;
    final inner = outer - 8;

    _circle(buffer, centerX, centerY, outer, fill: (0.04, 0.20, 0.48));
    _circle(buffer, centerX, centerY, middle, fill: (1.0, 1.0, 1.0));
    _circle(buffer, centerX, centerY, inner, fill: (0.02, 0.03, 0.05));
    _circle(buffer, centerX, centerY, outer, stroke: (0.02, 0.10, 0.30));

    _centerText(buffer, centerX, y + size - 15, 'RDC', 7, bold: true);
    _centerText(buffer, centerX, y + 7, 'PROVINCE DU LUALABA', 5.7, bold: true);

    _setFillColor(buffer, 0.10, 0.34, 0.80);
    buffer
      ..writeln('q')
      ..writeln('${_n(centerX - 16)} ${_n(centerY - 7)} m')
      ..writeln('${_n(centerX - 3)} ${_n(centerY + 14)} l')
      ..writeln('${_n(centerX + 13)} ${_n(centerY + 8)} l')
      ..writeln('${_n(centerX + 10)} ${_n(centerY - 12)} l')
      ..writeln('${_n(centerX - 10)} ${_n(centerY - 16)} l')
      ..writeln('h f')
      ..writeln('Q');

    _setStrokeColor(buffer, 0.86, 0.86, 0.86);
    _line(buffer, centerX + 12, centerY - 10, centerX + 28, centerY + 12);
    _line(buffer, centerX + 28, centerY - 10, centerX + 12, centerY + 12);
    _setStrokeColor(buffer, 0.12, 0.12, 0.12);

    _setStrokeColor(buffer, 0.10, 0.55, 0.18);
    for (var i = 0; i < 7; i++) {
      final dy = i * 5.0;
      _line(
        buffer,
        centerX - 24,
        centerY - 17 + dy,
        centerX - 12,
        centerY - 9 + dy,
      );
      _line(
        buffer,
        centerX + 24,
        centerY - 17 + dy,
        centerX + 12,
        centerY - 9 + dy,
      );
    }
    _setStrokeColor(buffer, 0.12, 0.12, 0.12);
  }

  static void _watermark(StringBuffer buffer) {
    buffer
      ..writeln('q')
      ..writeln('0.86 0.86 0.86 rg')
      ..writeln('BT')
      ..writeln('/F2 28 Tf')
      ..writeln('0.90 0.42 -0.42 0.90 105 365 Tm')
      ..writeln('(${_pdfEscape('CECI N’EST PAS UNE PREUVE DE PAIEMENT')}) Tj')
      ..writeln('ET')
      ..writeln('Q');
  }

  static void _section(
    StringBuffer buffer,
    double x,
    double y,
    double width,
    double height,
    String title,
  ) {
    _rect(buffer, x, y, width, height);
    _rect(buffer, x, y + height - 18, width, 18, fillGray: 0.90);
    _text(buffer, x + 8, y + height - 13, title, 9, bold: true);
  }

  static void _field(
    StringBuffer buffer,
    double x,
    double y,
    double width,
    String label,
    String value, {
    int maxLines = 1,
    bool boldValue = false,
  }) {
    final labelText = '${_ascii(label)} :';
    _text(buffer, x, y, labelText, 8, bold: true);
    final valueX = x + 118;
    final lines = _wrapText(
      _fallback(value),
      ((width - 118) / 4.5).floor(),
    ).take(maxLines).toList();
    for (var i = 0; i < lines.length; i++) {
      _text(buffer, valueX, y - (i * 10), lines[i], 8, bold: boldValue);
    }
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

  static void _setStrokeColor(
    StringBuffer buffer,
    double red,
    double green,
    double blue,
  ) {
    buffer.writeln('${_n(red)} ${_n(green)} ${_n(blue)} RG');
  }

  static void _setFillColor(
    StringBuffer buffer,
    double red,
    double green,
    double blue,
  ) {
    buffer.writeln('${_n(red)} ${_n(green)} ${_n(blue)} rg');
  }

  static void _circle(
    StringBuffer buffer,
    double centerX,
    double centerY,
    double radius, {
    (double, double, double)? fill,
    (double, double, double)? stroke,
  }) {
    const kappa = 0.5522847498;
    final control = radius * kappa;
    buffer.writeln('q');
    if (fill != null) {
      buffer.writeln('${_n(fill.$1)} ${_n(fill.$2)} ${_n(fill.$3)} rg');
    }
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
      ..writeln(fill != null ? 'f' : 'S')
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
    var normalized = input;
    const sequenceReplacements = {
      '\u00c3\u00a0': 'a',
      '\u00c3\u00a2': 'a',
      '\u00c3\u00a4': 'a',
      '\u00c3\u0080': 'A',
      '\u00c3\u0082': 'A',
      '\u00c3\u0084': 'A',
      '\u00c3\u00a7': 'c',
      '\u00c3\u0087': 'C',
      '\u00c3\u00a9': 'e',
      '\u00c3\u00a8': 'e',
      '\u00c3\u00aa': 'e',
      '\u00c3\u00ab': 'e',
      '\u00c3\u0089': 'E',
      '\u00c3\u0088': 'E',
      '\u00c3\u008a': 'E',
      '\u00c3\u008b': 'E',
      '\u00c3\u00ae': 'i',
      '\u00c3\u00af': 'i',
      '\u00c3\u008e': 'I',
      '\u00c3\u008f': 'I',
      '\u00c3\u00b4': 'o',
      '\u00c3\u00b6': 'o',
      '\u00c3\u0094': 'O',
      '\u00c3\u0096': 'O',
      '\u00c3\u00b9': 'u',
      '\u00c3\u00bb': 'u',
      '\u00c3\u00bc': 'u',
      '\u00c3\u0099': 'U',
      '\u00c3\u009b': 'U',
      '\u00c3\u009c': 'U',
      '\u00c3\u00bf': 'y',
      '\u00c5\u00b8': 'Y',
      '\u00c5\u0093': 'oe',
      '\u00c5\u0092': 'OE',
      '\u00e2\u20ac\u2122': "'",
      '\u00e2\u20ac\u0153': '"',
      '\u00e2\u20ac\u009d': '"',
      '\u00e2\u20ac\u201c': '-',
      '\u00e2\u20ac\u201d': '-',
      '\u00e2\u20ac\u00a2': '-',
      '\u00c2\u00b7': '-',
    };
    for (final entry in sequenceReplacements.entries) {
      normalized = normalized.replaceAll(entry.key, entry.value);
    }

    const replacements = {
      '\u00e0': 'a',
      '\u00e2': 'a',
      '\u00e4': 'a',
      '\u00c0': 'A',
      '\u00c2': 'A',
      '\u00c4': 'A',
      '\u00e7': 'c',
      '\u00c7': 'C',
      '\u00e9': 'e',
      '\u00e8': 'e',
      '\u00ea': 'e',
      '\u00eb': 'e',
      '\u00c9': 'E',
      '\u00c8': 'E',
      '\u00ca': 'E',
      '\u00cb': 'E',
      '\u00ee': 'i',
      '\u00ef': 'i',
      '\u00ce': 'I',
      '\u00cf': 'I',
      '\u00f4': 'o',
      '\u00f6': 'o',
      '\u00d4': 'O',
      '\u00d6': 'O',
      '\u00f9': 'u',
      '\u00fb': 'u',
      '\u00fc': 'u',
      '\u00d9': 'U',
      '\u00db': 'U',
      '\u00dc': 'U',
      '\u00ff': 'y',
      '\u0178': 'Y',
      '\u0153': 'oe',
      '\u0152': 'OE',
      '\u2019': "'",
      '\u201c': '"',
      '\u201d': '"',
      '\u2013': '-',
      '\u2014': '-',
      '\u2022': '-',
      '\u00b7': '-',
    };

    final buffer = StringBuffer();
    for (final rune in normalized.runes) {
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

  static String _formatDate(DateTime date) {
    final local = date.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year}';
  }

  static String _formatDateTime(DateTime date) {
    final local = date.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${_formatDate(local)} ${two(local.hour)}:${two(local.minute)}';
  }

  static String _formatMoney(PerceptionNoteData data) {
    final usd = data.amountUsd.toStringAsFixed(2).replaceAll('.', ',');
    if (data.amountCdf <= 0) {
      return '$usd USD';
    }
    final cdf = _formatCdf(data.amountCdf);
    return '$usd USD / $cdf CDF';
  }

  static String _amountInFrench(double amount) {
    final rounded = amount.round().clamp(0, 999999999).toInt();
    final words = _numberToFrench(rounded);
    return '$words dollars americains'.toUpperCase();
  }

  static String _formatCdf(double value) {
    final fixed = value.round().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < fixed.length; i++) {
      if (i > 0 && (fixed.length - i) % 3 == 0) {
        buffer.write(' ');
      }
      buffer.write(fixed[i]);
    }
    return buffer.toString();
  }

  static String _declarantContact(PerceptionNoteData data) {
    final parts = <String>[
      if (data.declarantPhone.trim().isNotEmpty) data.declarantPhone.trim(),
      if (data.declarantEmail.trim().isNotEmpty) data.declarantEmail.trim(),
    ];
    return parts.join(' / ');
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

  static String _periodicityFrom(String details) {
    final marker = RegExp(
      r'Periodicite:\s*([^-\n]+)',
      caseSensitive: false,
    ).firstMatch(_ascii(details));
    return marker?.group(1)?.trim().toUpperCase() ?? 'PONCTUELLE';
  }

  static String _fallback(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'Non renseigne' : trimmed;
  }

  static String _sanitizeFilePart(String value) {
    return _ascii(value)
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }
}
