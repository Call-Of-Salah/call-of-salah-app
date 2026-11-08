import 'package:flutter/material.dart';

/// App logo mark shown at the top of the auth screens. Placeholder: a
/// branded circle with an icon until real artwork exists.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.nightlight_round,
        size: size * 0.5,
        color: theme.colorScheme.onPrimaryContainer,
      ),
    );
  }
}
