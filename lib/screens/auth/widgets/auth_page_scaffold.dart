import 'package:flutter/material.dart';

import '../../../widgets/app_safe_area.dart';
import '../../settings/settings_glass.dart';
import 'auth_sheet.dart';

/// Page frame shared by every auth screen. Outside the auth sheet it is
/// the classic Scaffold + AppBar; inside it renders the settings-style
/// sheet header (round back button when there is somewhere to go back
/// to, title, round close button) with an opaque surface so pages don't
/// show through each other during slide transitions.
///
/// The [body] is what each screen used to wrap in `AppSafeArea`; it is
/// wrapped in one here in both modes.
class AuthPageScaffold extends StatelessWidget {
  const AuthPageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.onBack,
    this.backEnabled = true,
    this.showBack = true,
    this.closable = true,
    this.actions = const [],
  });

  final String title;
  final Widget body;

  /// Custom back action (e.g. a confirm/sign-out step). When null the
  /// back button just pops the current route.
  final VoidCallback? onBack;

  /// Whether the back button is enabled (disabled while an action is
  /// in-flight).
  final bool backEnabled;

  /// Outside the sheet: whether the AppBar shows a back arrow at all
  /// (`automaticallyImplyLeading`). Inside: whether the header may show
  /// a back button.
  final bool showBack;

  /// Inside the sheet only: whether the header shows the close (X)
  /// button. False on mandatory screens (2FA setup, fresh backup codes)
  /// where leaving must go through the screen's own flow.
  final bool closable;

  /// Extra header buttons, right-aligned before the close button (AppBar
  /// actions outside the sheet) - e.g. Sign In's "Create account" icon.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final inSheet = AuthSheetScope.maybeOf(context) != null;
    if (!inSheet) {
      return Scaffold(
        appBar: AppBar(
          title: Text(title),
          automaticallyImplyLeading: showBack,
          leading: onBack == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: backEnabled ? onBack : null,
                ),
          actions: actions,
        ),
        body: AppSafeArea(child: body),
      );
    }

    final canPop = Navigator.of(context).canPop();
    final hasBack = showBack && (onBack != null || canPop);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Column(
        children: [
          Padding(
            // 20px top breathing room above the header row.
            padding: EdgeInsets.fromLTRB(hasBack ? 12 : 20, 20, 12, 12),
            child: Row(
              children: [
                if (hasBack) ...[
                  SettingsHeaderButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onPressed: backEnabled
                        ? (onBack ?? () => Navigator.of(context).maybePop())
                        : null,
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'GoogleSans',
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
                for (final action in actions) ...[
                  action,
                  const SizedBox(width: 8),
                ],
                if (closable)
                  SettingsHeaderButton(
                    icon: Icons.close_rounded,
                    tooltip: 'Close',
                    onPressed: () =>
                        AuthSheetScope.maybeOf(context)!.close(null),
                  ),
              ],
            ),
          ),
          Expanded(child: AppSafeArea(child: body)),
        ],
      ),
    );
  }
}
