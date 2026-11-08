import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/auth/auth_service.dart';
import '../settings/settings_glass.dart';
import 'two_factor_challenge_screen.dart';
import 'two_factor_setup_screen.dart';
import 'widgets/auth_error_banner.dart';
import 'widgets/auth_page_scaffold.dart';
import 'widgets/auth_sheet.dart';
import 'widgets/code_field.dart';

/// "We sent a 6-digit code to `email`" confirmation step after sign up
/// (or when sign-in reports `email_not_confirmed`). Verifying signs the
/// user in and proves the inbox for its always-on email factor.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({
    super.key,
    required this.email,
    this.codeAlreadySent = false,
  });

  final String email;

  /// True when a code is already on its way (sign-up just happened, or a
  /// resend already fired) - starts the resend cooldown immediately.
  final bool codeAlreadySent;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  static const int _resendCooldownSeconds = 60;

  final TextEditingController _codeController = TextEditingController();
  final FocusNode _codeFocus = FocusNode();

  bool _isVerifying = false;
  bool _isResending = false;
  String? _errorMessage;
  int _resendCountdown = 0;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    if (widget.codeAlreadySent) _startCooldown();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _codeFocus.dispose();
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

  Future<void> _verify() async {
    if (_codeController.text.trim().length != 6) {
      setState(() => _errorMessage = 'Please enter the 6-digit code.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      final result = await AuthService.instance.verifySignupCode(
        widget.email,
        _codeController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _isVerifying = false);

      switch (result) {
        case SignInSuccess():
          finishAuthFlow(
            context,
            message: "Email confirmed - you're signed in",
          );
        case SignInNeedsSecondFactor():
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => TwoFactorChallengeScreen(
                requirement: result.requirement,
                maskedEmail: result.maskedEmail,
                mode: TwoFactorChallengeMode.signIn,
              ),
            ),
          );
        case SignInNeedsTwoFactorSetup():
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => const TwoFactorSetupScreen(),
            ),
          );
        case SignInEmailNotConfirmed():
          setState(
            () => _errorMessage =
                'Email still unconfirmed - try the code again.',
          );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _errorMessage = AuthService.messageFor(error);
      });
    }
  }

  Future<void> _resend() async {
    if (_resendCountdown > 0 || _isResending) return;
    setState(() {
      _isResending = true;
      _errorMessage = null;
    });
    try {
      await AuthService.instance.resendSignupCode(widget.email);
      if (!mounted) return;
      _startCooldown();
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = AuthService.messageFor(error));
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AuthPageScaffold(
      title: 'Confirm Email',
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
                    Icons.mark_email_read_outlined,
                    size: 38,
                    color: settingsAccentColor(context),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Check your email',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'We sent a 6-digit code to\n${widget.email}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 36),
                Form(
                  child: CodeField(
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
                TextButton(
                  onPressed:
                      _resendCountdown > 0 || _isResending ? null : _resend,
                  child: Text(
                    _resendCountdown > 0
                        ? 'Resend code (${_resendCountdown}s)'
                        : 'Resend code',
                    style: TextStyle(
                      color: _resendCountdown > 0
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                          : theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }
}
