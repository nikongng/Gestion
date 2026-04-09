import 'package:flutter/material.dart';

/// Avatar avec initiales si pas d’URL ou erreur de chargement.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.fullName,
    this.avatarUrl,
    this.radius = 20,
    this.backgroundColor,
    this.initialsColor,
  });

  final String fullName;
  final String? avatarUrl;
  final double radius;
  /// Si non null, utilisé pour le fond (ex. barre latérale sombre).
  final Color? backgroundColor;
  /// Si non null, couleur des initiales lorsqu’il n’y a pas d’image.
  final Color? initialsColor;

  String get _initials {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .take(2);
    final s = parts.map((p) => p.isNotEmpty ? p[0].toUpperCase() : '').join();
    return s.isEmpty ? '?' : s;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = backgroundColor ?? cs.primaryContainer;
    final fg = initialsColor ?? cs.onPrimaryContainer;
    final u = avatarUrl;
    final size = radius * 2;
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: bg,
        child: u != null && u.isNotEmpty
            ? Image.network(
                u,
                fit: BoxFit.cover,
                width: size,
                height: size,
                errorBuilder: (context, error, _) => Center(
                  child: Text(
                    _initials,
                    style: TextStyle(
                      fontSize: radius * 0.75,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ),
              )
            : Center(
                child: Text(
                  _initials,
                  style: TextStyle(
                    fontSize: radius * 0.75,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ),
      ),
    );
  }
}
