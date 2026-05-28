import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

Widget buildPdfDocumentPreview(
  BuildContext context,
  Uint8List bytes,
  String fileName,
) {
  return _WebPdfDocumentPreview(bytes: bytes, fileName: fileName);
}

class _WebPdfDocumentPreview extends StatefulWidget {
  const _WebPdfDocumentPreview({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;

  @override
  State<_WebPdfDocumentPreview> createState() => _WebPdfDocumentPreviewState();
}

class _WebPdfDocumentPreviewState extends State<_WebPdfDocumentPreview> {
  late String _viewType;
  String? _objectUrl;

  @override
  void initState() {
    super.initState();
    _viewType = 'gestia-pdf-preview-${DateTime.now().microsecondsSinceEpoch}';
    _registerView();
  }

  @override
  void didUpdateWidget(covariant _WebPdfDocumentPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bytes != widget.bytes ||
        oldWidget.fileName != widget.fileName) {
      _revokeObjectUrl();
      _registerView();
    }
  }

  @override
  void dispose() {
    _revokeObjectUrl();
    super.dispose();
  }

  void _registerView() {
    _viewType = 'gestia-pdf-preview-${DateTime.now().microsecondsSinceEpoch}';
    final blob = html.Blob([widget.bytes], 'application/pdf');
    _objectUrl = html.Url.createObjectUrlFromBlob(blob);
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      return html.IFrameElement()
        ..src = _objectUrl!
        ..title = widget.fileName
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%';
    });
  }

  void _revokeObjectUrl() {
    final url = _objectUrl;
    if (url == null) return;
    html.Url.revokeObjectUrl(url);
    _objectUrl = null;
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
