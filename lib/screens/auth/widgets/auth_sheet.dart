import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/auth/auth_service.dart';
import '../../../widgets/app_feedback.dart';
import '../login_screen.dart';

/// Auth pages presented as a modal bottom sheet covering the screen
/// below the status bar / app bar area. [show] starts the sign-in flow
/// (Sign In, Sign Up, Forgot Password, the 2FA/setup/backup-codes
/// follow-ons); [open] starts on any single auth page (Settings'
/// authenticator setup/replace, the re-auth challenge). Everything
/// renders inside a nested [Navigator], so pages slide between each
/// other within the sheet instead of covering the whole screen.
///
/// Screens inside the sheet build their header via `AuthPageScaffold`
/// (sheet-style header inside, AppBar outside), finish via
/// [finishAuthFlow] (closes the sheet with an optional message the
/// caller turns into a toast), and leave via [popAuthRoute] (pops the
/// nested route, or closes the sheet from the root page).
class AuthSheet {
  /// Opens the sign-in flow over [context] as a modal bottom sheet
  /// (uses the root navigator so it stacks above the current route).
  /// Resolves with the message passed to [finishAuthFlow], or
  /// null when the user closes the sheet without finishing.
  ///
  /// Closing mid-flow (e.g. during a 2FA challenge) abandons a
  /// half-authenticated session: when the result is null but a session
  /// exists without a published user, the user is signed back out.
  static Future<String?> show(BuildContext context) async {
    final result = await open<String>(context, const LoginScreen());
    if (result == null &&
        AuthService.instance.currentUser.value == null &&
        AuthService.instance.hasSession) {
      // Half-authenticated session (e.g. closed mid 2FA challenge) -
      // drop it so the user isn't left signed in at aal1.
      await AuthService.instance.signOut();
    }
    return result;
  }

  /// Opens the sheet with [page] as its nested navigator's root - for
  /// Settings-launched auth pages that aren't the sign-in flow (TOTP
  /// enrollment/replacement, the re-auth 2FA challenge). Resolves with
  /// whatever the page left via [popAuthRoute] or the scope's close,
  /// or null when the user closes the sheet. Unlike [show] there is no
  /// session cleanup - the caller owns that decision.
  static Future<T?> open<T>(BuildContext context, Widget page) {
    // Sheet top sits just below the status bar / toolbar area.
    final height = MediaQuery.of(context).size.height -
        MediaQuery.of(context).padding.top -
        kToolbarHeight;
    return showModalBottomSheet<Object?>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      isDismissible: false,
      enableDrag: false,
      // No glass panel: its translucent top strip and hairline border met
      // the pages' opaque background in a visible seam above the header.
      // Each page paints the opaque surface right up to the rounded edge.
      builder: (_) => SizedBox(
        height: height,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: _AuthSheetBody(root: page),
        ),
      ),
    ).then((result) => result as T?);
  }
}

/// The sheet's body: a nested navigator owning the auth flow's page
/// stack. Stateful to hold the navigator's key.
class _AuthSheetBody extends StatefulWidget {
  const _AuthSheetBody({required this.root});

  /// The nested navigator's initial page.
  final Widget root;

  @override
  State<_AuthSheetBody> createState() => _AuthSheetBodyState();
}

class _AuthSheetBodyState extends State<_AuthSheetBody> {
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return AuthSheetScope(
      close: (result) => Navigator.of(context).pop(result),
      // Snackbars inside the nested navigator need a ScaffoldMessenger
      // below the sheet's own Scaffold pages.
      child: ScaffoldMessenger(
        // System back pops the nested route first (each page's PopScope
        // still applies); when only Sign In is left the sheet route
        // itself pops - closing the sheet.
        child: NavigatorPopHandler<Object?>(
          onPopWithResult: (_) => _navKey.currentState!.maybePop(),
          child: Navigator(
            key: _navKey,
            onGenerateRoute: (_) =>
                MaterialPageRoute(builder: (_) => widget.root),
          ),
        ),
      ),
    );
  }
}

/// How widgets inside the sheet reach its close action - [close] pops
/// the whole sheet with an optional result.
class AuthSheetScope extends InheritedWidget {
  const AuthSheetScope({
    super.key,
    required this.close,
    required super.child,
  });

  final void Function(Object? result) close;

  static AuthSheetScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AuthSheetScope>();

  @override
  bool updateShouldNotify(AuthSheetScope oldWidget) => false;
}

/// Ends the auth flow. Inside the sheet this closes the whole sheet with
/// [message] (the caller decides how to surface it, e.g. as a toast);
/// outside it pops to the first route and shows a snackbar.
void finishAuthFlow(BuildContext context, {String? message}) {
  TextInput.finishAutofillContext();
  final scope = AuthSheetScope.maybeOf(context);
  if (scope != null) {
    scope.close(message);
    return;
  }
  Navigator.of(context).popUntil((route) => route.isFirst);
  if (message != null) {
    AppFeedback.showSnackBar(context, message, isError: false);
  }
}

/// Leaves the current auth page. Inside the sheet a page's self-pop is
/// the nested navigator's `pop` - except on the root page, where
/// popping the only route would leave the navigator empty, so the whole
/// sheet closes with [result] instead. Outside the sheet this is a
/// plain pop.
void popAuthRoute<T>(BuildContext context, [T? result]) {
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop(result);
    return;
  }
  final scope = AuthSheetScope.maybeOf(context);
  if (scope != null) {
    scope.close(result);
    return;
  }
  navigator.pop(result);
}
