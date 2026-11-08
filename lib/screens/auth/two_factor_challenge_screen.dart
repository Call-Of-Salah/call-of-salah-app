import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/auth/account_api_client.dart';
import '../../services/auth/auth_service.dart';
import '../../widgets/app_feedback.dart';
import '../settings/settings_glass.dart';
import 'widgets/auth_error_banner.dart';
import 'widgets/auth_page_scaffold.dart';
import 'widgets/auth_sheet.dart';
import 'widgets/backup_code_input_formatter.dart';
import 'widgets/code_field.dart';

/// Why the challenge is being shown - decides what "done" and "cancel"
/// mean:
/// - [signIn]: after password sign-in; success pops to the first route,
///   cancel signs the user out.
/// - [passwordReset]: mid forgot-password flow; pops `true`/`false` for
///   the caller to act on.
/// - [reauth]: mid delete-account flow; same pop semantics.
/// - [passwordChange]: Settings -> Change password; same pop semantics.
enum TwoFactorChallengeMode { signIn, passwordReset, reauth, passwordChange }

/// Test seam for [TwoFactorChallengeScreen]: the handful of auth calls
/// the screen makes. The default implementation delegates to
/// [AuthService]; widget tests inject a fake so no Supabase is needed.
abstract class TwoFactorAuth {
  Future<void> verifyTotp(String code);
  Future<void> sendEmailCode();
  Future<void> verifyEmailCode(String code);
  Future<int> verifyBackupCode(String code);
  Future<void> resetTotpWithBackupCode(String code);
  Future<void> signOut();
}

class _AuthServiceTwoFactorAuth implements TwoFactorAuth {
  const _AuthServiceTwoFactorAuth();

  @override
  Future<void> verifyTotp(String code) =>
      AuthService.instance.verifyTotp(code);

  @override
  Future<void> sendEmailCode() =>
      AuthService.instance.sendEmail2faCode(Email2faPurpose.signIn);

  @override
  Future<void> verifyEmailCode(String code) => AuthService.instance
      .verifyEmail2faCode(Email2faPurpose.signIn, code);

  @override
  Future<int> verifyBackupCode(String code) =>
      AuthService.instance.verifyBackupCode(code);

  @override
  Future<void> resetTotpWithBackupCode(String code) =>
      AuthService.instance.resetTotpWithBackupCode(code);

  @override
  Future<void> signOut() => AuthService.instance.signOut();
}

/// The post-password second-factor screen with the email-code factor.
/// Starts in authenticator mode when [requirement.totp] is set,
/// otherwise email mode (auto-sending the code); the user can switch
/// between the two when both are enabled.
class TwoFactorChallengeScreen extends StatefulWidget {
  const TwoFactorChallengeScreen({
    super.key,
    required this.requirement,
    required this.maskedEmail,
    required this.mode,
    this.auth,
  });

  final SecondFactorRequirement requirement;
  final String maskedEmail;
  final TwoFactorChallengeMode mode;

  /// Auth calls backend - defaults to [AuthService]; tests inject a fake.
  final TwoFactorAuth? auth;

  @override
  State<TwoFactorChallengeScreen> createState() =>
      _TwoFactorChallengeScreenState();
}

class _TwoFactorChallengeScreenState extends State<TwoFactorChallengeScreen> {
  static const int _resendCooldownSeconds = 60;

  late final TwoFactorAuth _auth = widget.auth ?? const _AuthServiceTwoFactorAuth();

  final TextEditingController _codeController = TextEditingController();
  final FocusNode _codeFocus = FocusNode();

  late bool _emailMode = !widget.requirement.totp;
  bool _backupMode = false;
  final TextEditingController _backupController = TextEditingController();
  final FocusNode _backupFocus = FocusNode();
  bool _isVerifying = false;
  bool _isSending = false;
  String? _errorMessage;
  int _resendCountdown = 0;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    if (_emailMode) {
      unawaited(_sendEmailCode());
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _codeFocus.dispose();
    _backupController.dispose();
    _backupFocus.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendCountdown = _resendCooldownSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown <= 1) {
        timer.cancel();
        setState(() => _resendCountdown = 0);
      } else {
        setState(() => _resendCountdown--);
      }
    });
  }

  Future<void> _sendEmailCode() async {
    if (_isSending) return;
    setState(() {
      _isSending = true;
      _errorMessage = null;
    });
    try {
      await _auth.sendEmailCode();
      if (!mounted) return;
      _startCooldown();
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = AuthService.messageFor(error));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _switchToEmail() {
    setState(() {
      _emailMode = true;
      _errorMessage = null;
      _codeController.clear();
    });
    unawaited(_sendEmailCode());
  }

  void _switchToAuthenticator() {
    setState(() {
      _emailMode = false;
      _errorMessage = null;
      _codeController.clear();
    });
  }

  void _switchToBackup() {
    setState(() {
      _backupMode = true;
      _errorMessage = null;
    });
  }

  void _switchFromBackup() {
    setState(() {
      _backupMode = false;
      _errorMessage = null;
      _backupController.clear();
    });
  }

  Future<void> _verify() async {
    if (_backupMode) {
      if (_backupController.text.trim().isEmpty) {
        setState(() => _errorMessage = 'Please enter a backup code.');
        return;
      }
    } else if (_codeController.text.trim().length != 6) {
      setState(() => _errorMessage = 'Please enter the 6-digit code.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      int? backupRemaining;
      if (_backupMode && _removesAuthenticator) {
        await _auth.resetTotpWithBackupCode(_backupController.text.trim());
      } else if (_backupMode) {
        backupRemaining =
            await _auth.verifyBackupCode(_backupController.text.trim());
      } else if (_emailMode) {
        await _auth.verifyEmailCode(_codeController.text.trim());
      } else {
        await _auth.verifyTotp(_codeController.text.trim());
      }
      if (!mounted) return;
      _onSuccess(backupRemaining: backupRemaining);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _errorMessage = AuthService.messageFor(error);
        _codeController.clear();
        _backupController.clear();
      });
    }
  }

  /// A password reset/change with an authenticator can only continue
  /// with the authenticator code, or a backup code that also removes the
  /// authenticator (a backup code leaves the session `aal1`, and
  /// Supabase only lets `aal2` change the password while one is set up).
  bool get _removesAuthenticator =>
      (widget.mode == TwoFactorChallengeMode.passwordReset ||
          widget.mode == TwoFactorChallengeMode.passwordChange) &&
      widget.requirement.totp;

  void _onSuccess({int? backupRemaining}) {
    final warning = backupRemaining != null && backupRemaining <= 3
        ? 'You have $backupRemaining backup code${backupRemaining == 1 ? '' : 's'} '
            'left - generate new ones in Settings > Account'
        : null;
    if (widget.mode == TwoFactorChallengeMode.signIn) {
      // Pushed on top of Sign In (or inside the auth sheet) - finishing
      // returns home/closes the sheet with the toast message.
      finishAuthFlow(context, message: warning ?? 'Signed in');
    } else {
      popAuthRoute(context, true);
      if (warning != null) {
        AppFeedback.showSnackBar(context, warning, isError: false);
      }
    }
  }

  Future<void> _onCancel() async {
    if (widget.mode == TwoFactorChallengeMode.signIn) {
      // Cancelling the sign-in challenge abandons the half-authenticated
      // (password-only) session.
      await _auth.signOut();
      if (!mounted) return;
      popAuthRoute(context);
    } else {
      popAuthRoute(context, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_onCancel());
      },
      child: AuthPageScaffold(
        title: '2-Step Verification',
        onBack: () => unawaited(_onCancel()),
        backEnabled: !_isVerifying,
        body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => FocusScope.of(context).unfocus(),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.shield_outlined,
                      size: 38,
                      color: settingsAccentColor(context),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Verification Required',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _backupMode
                        ? _removesAuthenticator
                            ? 'Enter one of your backup codes. This also removes '
                                'your authenticator app - you can set it up again '
                                'in Settings > Account.'
                            : 'Enter one of your backup codes. Each code works once.'
                        : _emailMode
                        ? 'We sent a 6-digit code to\n${widget.maskedEmail}'
                        : 'Enter the 6-digit code from your authenticator app to continue.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: subtitleColor,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 36),
                  if (_backupMode)
                    TextFormField(
                      controller: _backupController,
                      focusNode: _backupFocus,
                      enabled: !_isVerifying,
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      enableSuggestions: false,
                      inputFormatters: [BackupCodeInputFormatter()],
                      decoration: InputDecoration(
                        hintText: 'XXXXX-XXXXX',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                      onFieldSubmitted: (_) => _verify(),
                      onChanged: (_) {
                        if (_errorMessage != null) {
                          setState(() => _errorMessage = null);
                        }
                      },
                    )
                  else
                  CodeField(
                    controller: _codeController,
                    focusNode: _codeFocus,
                    enabled: !_isVerifying,
                    onSubmitted: (_) => _verify(),
                    onChanged: (_) {
                      if (_errorMessage != null) {
                        setState(() => _errorMessage = null);
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  if (_errorMessage != null)
                    AuthErrorBanner(message: _errorMessage!),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isVerifying ? null : _verify,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _isVerifying
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text(
                              'Verify',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!_backupMode)
                    if (_emailMode) ...[
                    Text(
                      'Check your inbox and spam folder for the code.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: subtitleColor,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _resendCountdown > 0 || _isSending
                          ? null
                          : _sendEmailCode,
                      child: Text(
                        _resendCountdown > 0
                            ? 'Resend code (${_resendCountdown}s)'
                            : 'Resend code',
                        style: TextStyle(
                          color: _resendCountdown > 0
                              ? subtitleColor
                              : theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    if (widget.requirement.totp)
                      TextButton(
                        onPressed:
                            _isVerifying ? null : _switchToAuthenticator,
                        child: Text(
                          'Use authenticator app instead',
                          style: TextStyle(color: theme.colorScheme.primary),
                        ),
                      ),
                  ] else ...[
                    Text(
                      'Open your authenticator app or password manager to '
                      'find the current code for this account.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: subtitleColor,
                        height: 1.5,
                      ),
                    ),
                    if (widget.requirement.email)
                      TextButton(
                        onPressed: _isVerifying ? null : _switchToEmail,
                        child: Text(
                          'Send a code to my email instead',
                          style: TextStyle(color: theme.colorScheme.primary),
                        ),
                      ),
                  ],
                  if (_backupMode) ...[
                    if (widget.requirement.totp)
                      TextButton(
                        onPressed: _isVerifying
                            ? null
                            : () {
                                _switchFromBackup();
                                setState(() => _emailMode = false);
                              },
                        child: Text(
                          'Use authenticator app instead',
                          style: TextStyle(color: theme.colorScheme.primary),
                        ),
                      ),
                    if (widget.requirement.email)
                      TextButton(
                        onPressed: _isVerifying
                            ? null
                            : () {
                                _switchFromBackup();
                                _switchToEmail();
                              },
                        child: Text(
                          'Email me a code instead',
                          style: TextStyle(color: theme.colorScheme.primary),
                        ),
                      ),
                  ] else
                    TextButton(
                      onPressed: _isVerifying ? null : _switchToBackup,
                      child: Text(
                        'Use a backup code',
                        style: TextStyle(color: theme.colorScheme.primary),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
    );
  }
}
