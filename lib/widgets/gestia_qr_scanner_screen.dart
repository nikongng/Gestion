import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_colors.dart';
import '../utils/gestia_qr_payload.dart';

class GestiaQrScannerScreen extends StatefulWidget {
  const GestiaQrScannerScreen({super.key, required this.expectedType});

  final GestiaQrDocumentType expectedType;

  @override
  State<GestiaQrScannerScreen> createState() => _GestiaQrScannerScreenState();
}

class _GestiaQrScannerScreenState extends State<GestiaQrScannerScreen> {
  late final MobileScannerController _controller;
  bool _handled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: const [BarcodeFormat.qrCode],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDetect(BarcodeCapture capture) {
    if (_handled) return;

    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue?.trim();
      if (rawValue == null || rawValue.isEmpty) continue;

      final payload = GestiaQrPayload.tryDecode(rawValue);
      if (payload == null) {
        _showError('Code QR non reconnu par GESTIA.');
        return;
      }

      if (payload.type != widget.expectedType) {
        _showError('Ce code est un ${payload.type.label}.');
        return;
      }

      _handled = true;
      _controller.stop();
      Navigator.of(context).pop(payload);
      return;
    }
  }

  void _showError(String message) {
    if (!mounted || _error == message) return;
    setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = widget.expectedType.label;

    return Scaffold(
      appBar: AppBar(
        title: Text('Scanner $label'),
        actions: [
          IconButton(
            tooltip: 'Lampe',
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(Icons.flash_on_outlined),
          ),
          IconButton(
            tooltip: 'Camera',
            onPressed: () => _controller.switchCamera(),
            icon: const Icon(Icons.cameraswitch_outlined),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _handleDetect,
            onDetectError: (error, stackTrace) {
              _showError('Camera indisponible ou permission refusee.');
            },
          ),
          Center(
            child: Container(
              width: 248,
              height: 248,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(
                      _error == null
                          ? Icons.qr_code_scanner_outlined
                          : Icons.error_outline,
                      color: _error == null
                          ? AppColors.primary
                          : theme.colorScheme.error,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error ?? 'QR $label attendu',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
