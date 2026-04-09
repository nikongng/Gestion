import 'package:flutter/material.dart';

import '../theme/theme_scope.dart';

/// Bouton menu pour choisir clair / sombre / système.
class ThemeModeMenuButton extends StatelessWidget {
  const ThemeModeMenuButton({super.key, this.iconColor});

  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final controller = ThemeScope.of(context);
    final cs = Theme.of(context).colorScheme;

    return PopupMenuButton<ThemeMode>(
      tooltip: 'Thème d\'affichage',
      initialValue: controller.mode,
      onSelected: controller.setMode,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(controller.modeIcon, color: iconColor ?? cs.onSurface),
      ),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: ThemeMode.system,
          child: _MenuRow(
            icon: Icons.brightness_auto_rounded,
            label: 'Comme le système',
            selected: controller.mode == ThemeMode.system,
          ),
        ),
        PopupMenuItem(
          value: ThemeMode.light,
          child: _MenuRow(
            icon: Icons.light_mode_rounded,
            label: 'Clair',
            selected: controller.mode == ThemeMode.light,
          ),
        ),
        PopupMenuItem(
          value: ThemeMode.dark,
          child: _MenuRow(
            icon: Icons.dark_mode_rounded,
            label: 'Sombre',
            selected: controller.mode == ThemeMode.dark,
          ),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 22, color: selected ? cs.primary : cs.onSurface),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
        if (selected) Icon(Icons.check, size: 20, color: cs.primary),
      ],
    );
  }
}
