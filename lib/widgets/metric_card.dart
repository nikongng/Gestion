import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
    this.width = 250,
    this.minHeight = 132,
    this.icon,
    this.accentColor,
    this.badge,
    this.highlighted = false,
    this.numericValue,
    this.animatedFormatter,
  });

  final String title;
  final String value;
  final String subtitle;
  final double? width;
  final double minHeight;
  final IconData? icon;
  final Color? accentColor;
  final String? badge;
  final bool highlighted;
  final double? numericValue;
  final String Function(double value)? animatedFormatter;

  @override
  Widget build(BuildContext context) {
    final card = LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final cs = theme.colorScheme;
        final screenWidth = MediaQuery.sizeOf(context).width;
        final compact =
            constraints.maxHeight > 0 && constraints.maxHeight <= 170;
        final ultraCompact = screenWidth < 420;
        final accent = accentColor ?? AppColors.primary;

        final padding = compact ? 14.0 : 16.0;
        final iconBoxSize = compact ? 36.0 : 40.0;
        final iconSize = compact ? 18.0 : 20.0;

        final titleStyle = theme.textTheme.labelLarge?.copyWith(
          fontSize: compact ? 12 : 12.5,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.2,
        );

        final valueStyle = theme.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w900,
          fontSize: compact ? 22 : (ultraCompact ? 24 : 28),
          height: 0.96,
          letterSpacing: -0.8,
          color: theme.colorScheme.onSurface,
        );

        final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
          color: AppColors.mutedText,
          fontSize: compact ? 11 : 12,
          height: 1.2,
          fontWeight: FontWeight.w500,
        );

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                isDark
                    ? Color.alphaBlend(
                        accent.withValues(alpha: highlighted ? 0.10 : 0.06),
                        cs.surface,
                      )
                    : Colors.white,
                isDark
                    ? Color.alphaBlend(
                        accent.withValues(alpha: highlighted ? 0.18 : 0.10),
                        cs.surface.withValues(alpha: 0.98),
                      )
                    : accent.withValues(alpha: highlighted ? 0.12 : 0.07),
              ],
            ),
            border: Border.all(
              color: accent.withValues(alpha: highlighted ? 0.24 : 0.12),
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: highlighted ? 0.14 : 0.08),
                blurRadius: highlighted ? 34 : 24,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.04),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Stack(
              children: [
                Positioned(
                  top: -28,
                  right: -18,
                  child: Container(
                    width: compact ? 84 : 104,
                    height: compact ? 84 : 104,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(
                        alpha: highlighted ? 0.20 : 0.12,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -46,
                  left: -28,
                  child: Container(
                    width: compact ? 108 : 132,
                    height: compact ? 108 : 132,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [accent, accent.withValues(alpha: 0.35)],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(padding),
                  child: compact
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (icon != null) ...[
                              _MetricIconShell(
                                accent: accent,
                                icon: icon!,
                                size: iconBoxSize,
                                iconSize: iconSize,
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          title,
                                          style: titleStyle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (badge != null) ...[
                                        const SizedBox(width: 8),
                                        _MetricBadge(
                                          label: badge!,
                                          accent: accent,
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: _AnimatedMetricValue(
                                      staticValue: value,
                                      numericValue: numericValue,
                                      formatter: animatedFormatter,
                                      style: valueStyle,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    subtitle,
                                    style: subtitleStyle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : ConstrainedBox(
                          constraints: BoxConstraints(minHeight: minHeight),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (icon != null)
                                    _MetricIconShell(
                                      accent: accent,
                                      icon: icon!,
                                      size: iconBoxSize,
                                      iconSize: iconSize,
                                    ),
                                  const Spacer(),
                                  if (badge != null)
                                    _MetricBadge(label: badge!, accent: accent),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                title,
                                style: titleStyle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: _AnimatedMetricValue(
                                  staticValue: value,
                                  numericValue: numericValue,
                                  formatter: animatedFormatter,
                                  style: valueStyle,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                subtitle,
                                style: subtitleStyle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (width == null) return card;
    return SizedBox(width: width, child: card);
  }
}

class _MetricIconShell extends StatelessWidget {
  const _MetricIconShell({
    required this.accent,
    required this.icon,
    required this.size,
    required this.iconSize,
  });

  final Color accent;
  final IconData icon;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.18),
            accent.withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
      ),
      child: Icon(icon, color: accent, size: iconSize),
    );
  }
}

class _MetricBadge extends StatelessWidget {
  const _MetricBadge({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: accent.withValues(alpha: 0.10),
        border: Border.all(color: accent.withValues(alpha: 0.14)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: accent,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _AnimatedMetricValue extends StatelessWidget {
  const _AnimatedMetricValue({
    required this.staticValue,
    required this.numericValue,
    required this.formatter,
    required this.style,
  });

  final String staticValue;
  final double? numericValue;
  final String Function(double value)? formatter;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (numericValue == null) {
      return Text(
        staticValue,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: numericValue),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) {
        final text =
            formatter?.call(animatedValue) ?? animatedValue.round().toString();
        return Text(
          text,
          style: style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}
