import 'package:flutter/material.dart';

import '../branding/branding_scope.dart';

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

  static const assetPath = 'assets/logo/gestia.png';

  final double size;
  final double radius;
  final double padding;
  final Color backgroundColor;
  final BoxBorder? border;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    final innerRadius = radius > padding ? radius - padding : 0.0;
    final logoUrl = BrandingScope.of(context).logoUrl;

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
        child: logoUrl == null || logoUrl.isEmpty
            ? Image.asset(
                assetPath,
                fit: BoxFit.contain,
                errorBuilder: _fallbackLogo,
              )
            : Image.network(
                logoUrl,
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
