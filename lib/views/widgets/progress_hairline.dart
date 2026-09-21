import 'package:flutter/material.dart';

/// `.sa-bar`: a 1px track (`onSurface` at 14%) with a 1.5px brass bar over it,
/// drawn slightly high.
///
/// The detail page, the history rows, and the reader's bottom edge all share
/// this one geometry — do not re-implement it per surface.
class ProgressHairline extends StatelessWidget {
  const ProgressHairline({super.key, required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 1.5,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0.25,
            height: 1,
            child: ColoredBox(color: scheme.onSurface.withValues(alpha: 0.14)),
          ),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.clamp(0.0, 1.0),
            child: ColoredBox(color: scheme.primary),
          ),
        ],
      ),
    );
  }
}
