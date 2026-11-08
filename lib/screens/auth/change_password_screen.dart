import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../../services/auth/auth_service.dart';
import '../../utils/auth_validation.dart';
import 'two_factor_challenge_screen.dart';
import 'widgets/auth_error_banner.dart';
import 'widgets/auth_page_scaffold.dart';
import 'widgets/auth_sheet.dart';
import 'widgets/password_requirements.dart';

/// Test seam for [ChangePasswordScreen] - the default delegates to
/// [AuthService]; widget tests inject a fake so no Supabase is needed.
abstract class ChangePasswordAuth {
  Future<SecondFactorRequirement> reauthenticate(String password);
  bool get isTotpEnabled;
  String get maskedEmail;
  Future<void> updatePassword(String newPassword);
  Future<void> completeReauth();
  Future<void> abandonReauth();
}

class _AuthServiceChangePasswordAuth implements ChangePasswordAuth {
  const _AuthServiceChangePasswordAuth();

  @override
  Future<SecondFactorRequirement> reauthenticate(String password) =>
      AuthService.instance.reauthenticate(password);

  @override
  bool get isTotpEnabled => AuthService.instance.isTotpEnabled;

  @override
  String get maskedEmail => AuthService.maskEmail(
        AuthService.instance.currentUser.value?.email ?? '',
      );

  @override
  Future<void> updatePassword(String newPassword) =>
      AuthService.instance.updatePassword(newPassword);

  @override
  Future<void> completeReauth() => AuthService.instance.completeReauth();

  @override
  Future<void> abandonReauth() => AuthService.instance.abandonReauth();
}

/// Settings -> Account -> Change password. Same proof as signing in
/// again: the current password (a fresh password sign-in), then the
/// second step - the authenticator code when one is set up (Supabase
/// only lets an `aal2` session change the password then; a backup code
/// works too but removes the authenticator), otherwise an email code.
/// After saving, every other device is signed out
/// ([AuthService.updatePassword]).
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, this.auth, this.challengeBuilder});

  /// Auth calls backend - defaults to [AuthService]; tests inject a fake.
  final ChangePasswordAuth? auth;

  /// Test seam for the second-step page; defaults to
  /// [TwoFactorChallengeScreen].
  final Widget Function(SecondFactorRequirement requirement, String maskedEmail)?
      challengeBuilder;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  late final ChangePasswordAuth _auth =
      widget.auth ?? const _AuthServiceChangePasswordAuth();

  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscure = true;
  bool _busy = false;
  String? _error;

  /// The current password re-signed in (the session was swapped).
  bool _reauthed = false;

  /// The second step passed too - a failed save can be retried with a
  /// different new password without proving it again.
  bool _verified = false;

  /// The flow ended (saved or signed out) - nothing left to clean up.
  bool _finished = false;

  @override
  void dispose() {
    // Closed mid-flow: a re-signed-in session that never passed its
    // second step can't be trusted (same rule as the delete-account
    // re-auth), otherwise just release the re-auth hold.
    if (!_finished) {
      unawaited(_reauthed && !_verified
          ? _auth.abandonReauth()
          : _auth.completeReauth());
    }
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    if (!_verified) {
      final SecondFactorRequirement requirement;
      try {
        requirement = await _auth.reauthenticate(_currentController.text);
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = error is AuthException && error.code == 'invalid_credentials'
              ? 'Your current password is incorrect.'
              : AuthService.messageFor(error);
        });
        return;
      }
      _reauthed = true;

      // An authenticator means only its code (aal2) can unlock the
      // change - an email code can't, so it isn't offered.
      final challenge = _auth.isTotpEnabled
          ? const SecondFactorRequirement(totp: true)
          : requirement;
      if (challenge.isRequired) {
        if (!mounted) return;
        final passed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) =>
                widget.challengeBuilder?.call(challenge, _auth.maskedEmail) ??
                TwoFactorChallengeScreen(
                  requirement: challenge,
                  maskedEmail: _auth.maskedEmail,
                  mode: TwoFactorChallengeMode.passwordChange,
                ),
          ),
        );
        if (passed != true) {
          _finished = true;
          await _auth.abandonReauth();
          if (!mounted) return;
          finishAuthFlow(
            context,
            message: "For your security you've been signed out",
          );
          return;
        }
      }
      _verified = true;
    }

    try {
      await _auth.updatePassword(_newController.text);
      _finished = true;
      await _auth.completeReauth();
      if (!mounted) return;
      finishAuthFlow(
        context,
        message: 'Password changed - other devices were signed out',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AuthService.messageFor(error);
      });
    }
  }

  InputDecoration _decoration(String label, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: suffix,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return AuthPageScaffold(
      title: 'Change Password',
      backEnabled: !_busy,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: AutofillGroup(
            onDisposeAction: AutofillContextAction.cancel,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _auth.isTotpEnabled
                        ? 'Enter your current password, then a code from your '
                            'authenticator app. Other devices are signed out '
                            'afterwards.'
                        : 'Enter your current password, then the code we email '
                            'you. Other devices are signed out afterwards.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: subtitleColor,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_error != null) AuthErrorBanner(message: _error!),
                  TextFormField(
                    controller: _currentController,
                    obscureText: _obscure,
                    readOnly: _busy || _verified,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.next,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: _decoration(
                      'Current password',
                      Icons.lock_outline,
                    ),
                    validator: AuthValidation.validateLoginPassword,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _newController,
                    obscureText: _obscure,
                    readOnly: _busy,
                    keyboardType: TextInputType.visiblePassword,
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.next,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: _decoration(
                      'New password',
                      Icons.lock,
                      suffix: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (value) {
                      final invalid =
                          AuthValidation.validateSignupPassword(value);
                      if (invalid != null) return invalid;
                      return value == _currentController.text
                          ? 'Choose a password different from your current one'
                          : null;
                    },
                  ),
                  const SizedBox(height: 8),
                  PasswordRequirements(controller: _newController),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmController,
                    obscureText: _obscure,
                    readOnly: _busy,
                    keyboardType: TextInputType.visiblePassword,
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.done,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: _decoration(
                      'Confirm new password',
                      Icons.lock_outline,
                    ),
                    validator: (value) => AuthValidation.validateConfirmPassword(
                      value,
                      _newController.text,
                    ),
                    onFieldSubmitted: (_) => _busy ? null : _submit(),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _busy ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'Change password',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
