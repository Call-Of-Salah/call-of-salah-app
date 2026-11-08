import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'content_width.dart';

/// The app's standard screen-level [SafeArea].
///
/// Omits the bottom system-UI inset on iOS - the home-indicator/gesture-bar
/// strip is safe for our non-interactive, scrollable screen content to sit
/// under, and reserving space for it there just adds unwanted extra bottom
/// padding. Android's bottom inset is kept as-is.
///
/// Use this instead of a raw [SafeArea] when building a screen's top-level
/// `Scaffold.body` so this behavior stays consistent across the app.
class AppSafeArea extends StatelessWidget {
  const AppSafeArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: defaultTargetPlatform != TargetPlatform.iOS,
      child: ContentWidth(child: child),
    );
  }
}
