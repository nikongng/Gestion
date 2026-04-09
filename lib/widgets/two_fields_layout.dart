import 'package:flutter/material.dart';

/// Deux champs côte à côte sur large écran, empilés sur mobile.
class TwoFieldsLayout extends StatelessWidget {
  const TwoFieldsLayout({
    super.key,
    required this.firstLabel,
    required this.secondLabel,
    required this.firstChild,
    required this.secondChild,
  });

  final String firstLabel;
  final String secondLabel;
  final Widget firstChild;
  final Widget secondChild;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 700) {
          return Column(
            children: [
              Align(alignment: Alignment.centerLeft, child: Text(firstLabel)),
              const SizedBox(height: 6),
              firstChild,
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerLeft, child: Text(secondLabel)),
              const SizedBox(height: 6),
              secondChild,
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(firstLabel),
                  const SizedBox(height: 6),
                  firstChild,
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(secondLabel),
                  const SizedBox(height: 6),
                  secondChild,
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
