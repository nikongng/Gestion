import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

Widget buildPdfDocumentPreview(
  BuildContext context,
  Uint8List bytes,
  String fileName,
) {
  return PdfPreview(
    build: (_) async => bytes,
    allowPrinting: false,
    allowSharing: false,
    canChangeOrientation: false,
    canChangePageFormat: false,
    canDebug: false,
    pdfFileName: fileName,
  );
}
