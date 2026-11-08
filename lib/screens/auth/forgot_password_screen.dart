import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/auth/auth_service.dart';
import '../../utils/auth_validation.dart';
import '../settings/settings_glass.dart';
import 'two_factor_challenge_screen.dart';
import 'two_factor_setup_screen.dart';
import 'widgets/auth_error_banner.dart';
import 'widgets/auth_page_scaffold.dart';
import 'widgets/auth_sheet.dart';
import 'widgets/code_field.dart';
import 'widgets/password_requirements.dart';

/// Three-step forgot-password flow: email -> emailed 6-digit code
/// (verified into a recovery session, with the second-factor challenge
/// in between when the account has 2FA) -> new password.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

enum _ResetStep { email, code, newPassword }

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  static const int _resendCooldownSeconds = 60;

  _ResetStep _step = _ResetStep.email;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  final _emailFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  int _resendCountdown = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
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

  Future<void> _sendCode() async {
    if (!_emailFormKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await AuthService.instance
          .sendPasswordResetCode(_emailController.text.trim());
      if (!mounted) return;
      setState(() => _step = _ResetStep.code);
      _startCooldown();
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = AuthService.messageFor(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendCode() async {
    if (_resendCountdown > 0) return;
    setState(() => _errorMessage = null);
    try {
      await AuthService.instance
          .sendPasswordResetCode(_emailController.text.trim());
      if (!mounted) return;
      _startCooldown();
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = AuthService.messageFor(error));
    }
  }

  Future<void> _verifyCode() async {
    if (_codeController.text.trim().length != 6) {
      setState(() => _errorMessage = 'Please enter the 6-digit code.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final result = await AuthService.instance.verifyRecoveryCode(
        _emailController.text.trim(),
        _codeController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (result.needsTwoFactorSetup) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const TwoFactorSetupScreen(),
          ),
        );
        if (!mounted) return;
        setState(() => _step = _ResetStep.newPassword);
        return;
      }
      final requirement = result.requirement;
      if (requirement.isRequired) {
        final verified = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => TwoFactorChallengeScreen(
              requirement: requirement,
              maskedEmail:
                  AuthService.maskEmail(_emailController.text.trim()),
              mode: TwoFactorChallengeMode.passwordReset,
            ),
          ),
        );
        if (!mounted) return;
        if (verified != true) {
          // Cancelled challenge: the recovery session is dropped and the
          // user stays on the code step so they can try again.
          await AuthService.instance.signOut();
          if (!mounted) return;
          setState(() => _errorMessage = 'Password reset cancelled.');
          return;
        }
      }
      setState(() => _step = _ResetStep.newPassword);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = AuthService.messageFor(error);
      });
    }
  }

  Future<void> _updatePassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await AuthService.instance.updatePassword(_passwordController.text);
      if (!mounted) return;
      finishAuthFlow(context, message: "Password updated - you're signed in");
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = AuthService.messageFor(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    final (String title, Widget subtitle, Widget body) = switch (_step) {
      _ResetStep.email => (
          'Reset your password',
          Text(
            'Enter your account email and we\'ll send you a 6-digit code.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: subtitleColor, height: 1.5),
          ),
          _buildEmailStep(theme),
        ),
      _ResetStep.code => (
          'Check your email',
          Text(
            'We sent a 6-digit code to\n${_emailController.text.trim()}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: subtitleColor, height: 1.5),
          ),
          _buildCodeStep(theme),
        ),
      _ResetStep.newPassword => (
          'New password',
          Text(
            'Choose a new password for your account.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: subtitleColor, height: 1.5),
          ),
          _buildPasswordStep(theme),
        ),
    };

    return AuthPageScaffold(
      title: 'Forgot Password',
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
                    Icons.lock_reset,
                    size: 38,
                    color: settingsAccentColor(context),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                subtitle,
                const SizedBox(height: 36),
                if (_errorMessage != null)
                  AuthErrorBanner(message: _errorMessage!),
                body,
              ],
            ),
          ),
        ),
    );
  }

  Widget _buildEmailStep(ThemeData theme) {
    return AutofillGroup(
      onDisposeAction: AutofillContextAction.cancel,
      child: Form(
        key: _emailFormKey,
        child: Column(
          children: [
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              enableSuggestions: false,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              textCapitalization: TextCapitalization.none,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _sendCode(),
              decoration: InputDecoration(
                labelText: 'Email',
                prefixIcon: const Icon(Icons.email),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              validator: AuthValidation.validateEmail,
            ),
            const SizedBox(height: 24),
            _primaryButton(theme, 'Send code', _sendCode),
          ],
        ),
      ),
    );
  }

  Widget _buildCodeStep(ThemeData theme) {
    return Column(
      children: [
        CodeField(
          controller: _codeController,
          enabled: !_isLoading,
          onSubmitted: (_) => _verifyCode(),
          onChanged: (_) {
            if (_errorMessage != null) {
              setState(() => _errorMessage = null);
            }
          },
        ),
        const SizedBox(height: 24),
        _primaryButton(theme, 'Verify', _verifyCode),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _resendCountdown > 0 ? null : _resendCode,
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
    );
  }

  Widget _buildPasswordStep(ThemeData theme) {
    return AutofillGroup(
      onDisposeAction: AutofillContextAction.cancel,
      child: Form(
        key: _passwordFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              keyboardType: TextInputType.visiblePassword,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'New password',
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              validator: AuthValidation.validateSignupPassword,
            ),
            const SizedBox(height: 8),
            PasswordRequirements(controller: _passwordController),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmController,
              obscureText: _obscurePassword,
              keyboardType: TextInputType.visiblePassword,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Confirm new password',
                prefixIcon: const Icon(Icons.lock_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              validator: (value) => AuthValidation.validateConfirmPassword(
                value,
                _passwordController.text,
              ),
              onFieldSubmitted: (_) => _updatePassword(),
            ),
            const SizedBox(height: 24),
            _primaryButton(theme, 'Update password', _updatePassword),
          ],
        ),
      ),
    );
  }

  Widget _primaryButton(ThemeData theme, String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
