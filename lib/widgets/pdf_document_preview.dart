import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'pdf_document_preview_stub.dart'
    if (dart.library.html) 'pdf_document_preview_web.dart';

class PdfDocumentPreview extends StatelessWidget {
  const PdfDocumentPreview({
    super.key,
    required this.bytes,
    required this.fileName,
  });

  final Uint8List bytes;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    return buildPdfDocumentPreview(context, bytes, fileName);
  }
}
