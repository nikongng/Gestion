import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 40,
    this.radius = 12,
    this.padding = 3,
    this.backgroundColor = Colors.transparent,
    this.border,
    this.boxShadow,
  });

  static const assetPath = 'assets/logo/LG.png';
  static const webPath = 'logo/LG.png';

  final double size;
  final double radius;
  final double padding;
  final Color backgroundColor;
  final BoxBorder? border;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    final innerRadius = radius > padding ? radius - padding : 0.0;

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(radius),
        border: border,
        boxShadow: boxShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(innerRadius),
        child: kIsWeb
            ? Image.network(
                webPath,
                fit: BoxFit.contain,
                errorBuilder: _fallbackLogo,
              )
            : Image.asset(
                assetPath,
                fit: BoxFit.contain,
                errorBuilder: _fallbackLogo,
              ),
      ),
    );
  }

  Widget _fallbackLogo(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) {
    return const Icon(Icons.apartment_rounded, color: Color(0xFF15569A));
  }
}
