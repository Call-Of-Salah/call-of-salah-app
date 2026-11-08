import 'package:flutter/material.dart';

import '../../theme/brand_colors.dart';

/// Shared colors and small building blocks for sheets and cards -
/// sourcing every color from this app's own [ThemeData]/[ColorScheme]
/// so it follows whatever brand color the app is themed with.

/// Brand colour.
Color settingsBrandColor(BuildContext context) {
  return BrandColors.primary;
}

/// Brand colour for text/icons drawn ON a surface (not on a brand fill):
/// white in dark mode, the brand colour in light mode.
Color settingsAccentColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : settingsBrandColor(context);

Color settingsSecondaryTextColor(BuildContext context) {
  final theme = Theme.of(context);
  return theme.brightness == Brightness.dark
      ? const Color(0xFFB9C3D9)
      : Colors.grey.shade600;
}

/// Fill shared by cards and the header's round buttons - one subtle
/// tone off the sheet in both modes, so groups read as surfaces without
/// outlines.
Color settingsGroupColor(BuildContext context) {
  final theme = Theme.of(context);
  return theme.colorScheme.surfaceContainer;
}

/// Card decoration: a filled, rounded surface in [settingsGroupColor]
/// with no border or shadow.
BoxDecoration settingsCardDecoration(BuildContext context) {
  return BoxDecoration(
    color: settingsGroupColor(context),
    borderRadius: BorderRadius.circular(20),
  );
}

/// Round, filled icon button used in sheet headers (close, back).
class SettingsHeaderButton extends StatelessWidget {
  const SettingsHeaderButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        backgroundColor: settingsGroupColor(context),
        foregroundColor: settingsSecondaryTextColor(context),
        fixedSize: const Size(36, 36),
        minimumSize: const Size(36, 36),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

/// Card title text style - explicit (rather than derived from
/// `theme.textTheme`) so it doesn't pick up Material 3's default
/// letter-spacing.
TextStyle settingsCardTitleStyle(BuildContext context) {
  return TextStyle(
    fontFamily: 'GoogleSans',
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: Theme.of(context).colorScheme.onSurface,
  );
}
