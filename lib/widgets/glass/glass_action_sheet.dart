import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../screens/settings/settings_glass.dart';

/// Presents [builder] as a floating, backdrop-blurred action sheet - the
/// app's replacement for stock `AlertDialog`s and `showModalBottomSheet`s
/// app-wide. Lifts above the keyboard so sheets with a text field stay
/// visible. [dismissible] controls tap-outside/swipe-down dismissal;
/// [useRootNavigator] for sheets above nested navigators.
Future<T?> showGlassActionSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
  bool useRootNavigator = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    useRootNavigator: useRootNavigator,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: builder(sheetContext),
    ),
  );
}

/// Yes/no confirmation as a [GlassActionSheet]; resolves `true` only when
/// the primary action was tapped.
Future<bool> showGlassConfirm(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  required String confirmLabel,
  String? cancelLabel,
  bool destructive = false,
}) async {
  final result = await showGlassActionSheet<bool>(
    context,
    builder: (sheetContext) => GlassActionSheet(
      icon: icon,
      title: title,
      message: message,
      destructive: destructive,
      primaryLabel: confirmLabel,
      cancelLabel: cancelLabel,
      onPrimary: () => Navigator.of(sheetContext).pop(true),
      onCancel: () => Navigator.of(sheetContext).pop(false),
    ),
  );
  return result == true;
}

/// Floating glass sheet: an icon in a tinted squircle, a title, an
/// optional message and [body], then a full-width primary action over a
/// quiet Cancel. [destructive] switches the accent to the error colour;
/// [busy] shows a spinner and disables both actions.
class GlassActionSheet extends StatelessWidget {
  const GlassActionSheet({
    super.key,
    this.icon,
    required this.title,
    this.message,
    this.body,
    required this.primaryLabel,
    required this.onPrimary,
    this.onCancel,
    this.cancelLabel,
    this.destructive = false,
    this.busy = false,
    this.showClose = true,
    this.secondaryLabel,
    this.onSecondary,
    this.secondaryDestructive = false,
  });

  final IconData? icon;
  final String title;
  final String? message;
  final Widget? body;
  /// Null disables the primary button (same tint as busy, no spinner).
  final VoidCallback? onPrimary;
  final VoidCallback? onCancel;
  /// Null hides the Cancel button entirely.
  final String? cancelLabel;
  final String primaryLabel;
  final bool destructive;
  final bool busy;

  /// The round close button in the sheet's top-right corner, like the
  /// settings sheet's header X - on by default; set false to hide it.
  /// It calls [onCancel] (or just pops the sheet when there isn't one).
  final bool showClose;

  /// Optional middle action between the primary button and Cancel -
  /// rendered like Cancel but tinted [ColorScheme.error] when
  /// [secondaryDestructive], otherwise the accent colour.
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool secondaryDestructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent =
        destructive ? scheme.error : settingsBrandColor(context);
    final onAccent = destructive ? scheme.onError : Colors.white;
    final iconColor =
        destructive ? scheme.error : settingsAccentColor(context);
    final muted = scheme.onSurface.withValues(alpha: 0.62);

    return Stack(
      children: [
        GlassSheetFrame(
          children: [
        // The close button is overlaid below (not part of the frame's
        // scrollable column) - inside the scroll view its 12px nudge past
        // the frame padding was clipped off the right edge.
        SizedBox(height: showClose ? 36 : 24),
                  if (icon != null) ...[
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: accent.withValues(
                          alpha: !destructive && isDark ? 0.25 : 0.12,
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(icon, color: iconColor, size: 28),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ],
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.45,
                        color: muted,
                      ),
                    ),
                  ],
                  if (body != null) ...[
                    const SizedBox(height: 20),
                    body!,
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: busy ? null : onPrimary,
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: onAccent,
                        disabledBackgroundColor: accent.withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(
                          fontFamily: 'GoogleSans',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: busy
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: onAccent,
                              ),
                            )
                          : Text(primaryLabel),
                    ),
                  ),
                  if (secondaryLabel != null) ...[
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 48,
                      child: TextButton(
                        onPressed: busy ? null : onSecondary,
                        style: TextButton.styleFrom(
                          foregroundColor: secondaryDestructive
                              ? scheme.error
                              : settingsAccentColor(context),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontFamily: 'GoogleSans',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: Text(secondaryLabel!),
                      ),
                    ),
                  ],
                  if (cancelLabel != null) ...[
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 48,
                      child: TextButton(
                        onPressed: busy ? null : onCancel,
                        style: TextButton.styleFrom(
                          foregroundColor: muted,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontFamily: 'GoogleSans',
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        child: Text(cancelLabel!),
                      ),
                    ),
                  ],
          ],
        ),
        if (showClose)
          Positioned(
            top: 16,
            right: 24,
            child: SettingsHeaderButton(
              icon: Icons.close_rounded,
              tooltip: 'Close',
              onPressed: busy
                  ? null
                  : onCancel ?? () => Navigator.of(context).pop(),
            ),
          ),
      ],
    );
  }
}

/// The shared outer chrome of every glass sheet: the floating margins,
/// rounded blur container and handle bar. [children] go inside the
/// padded, scrollable column - use for fully custom sheets that don't
/// fit the [GlassActionSheet] icon/title/button layout.
class GlassSheetFrame extends StatelessWidget {
  const GlassSheetFrame({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(32);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.94),
              borderRadius: radius,
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.6),
                width: 0.8,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            // Clamping (not the iOS bounce default) so a downward drag
            // at the top edge reaches the sheet's dismiss gesture even
            // when the open keyboard makes the content scrollable.
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
