import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../services/auth/auth_service.dart';
import '../../widgets/app_logo.dart';
import '../../utils/auth_validation.dart';
import '../settings/settings_glass.dart';
import 'forgot_password_screen.dart';
import 'signup_screen.dart';
import 'two_factor_challenge_screen.dart';
import 'two_factor_setup_screen.dart';
import 'verify_email_screen.dart';
import 'widgets/auth_error_banner.dart';
import 'widgets/auth_page_scaffold.dart';
import 'widgets/auth_sheet.dart';

/// Email+password sign in via Supabase ([AuthService]). A
/// `SignInNeedsSecondFactor` result swaps this screen for the 2FA
/// challenge.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final email = _emailController.text.trim();
      final result = await AuthService.instance.signIn(
        email,
        _passwordController.text,
      );
      if (!mounted) return;
      setState(() => _isLoading = false);

      switch (result) {
        case SignInSuccess():
          finishAuthFlow(context, message: 'Signed in');
        case SignInNeedsSecondFactor():
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TwoFactorChallengeScreen(
                requirement: result.requirement,
                maskedEmail: result.maskedEmail,
                mode: TwoFactorChallengeMode.signIn,
              ),
            ),
          );
        case SignInNeedsTwoFactorSetup():
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const TwoFactorSetupScreen(),
            ),
          );
        case SignInEmailNotConfirmed():
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => VerifyEmailScreen(
                email: result.email,
                codeAlreadySent: true,
              ),
            ),
          );
      }
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

    return AuthPageScaffold(
      title: 'Sign In',
      actions: [
        SettingsHeaderButton(
          icon: Icons.person_add_alt_1_rounded,
          tooltip: 'Create account',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const SignUpScreen(),
              ),
            );
          },
        ),
      ],
      body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: AutofillGroup(
              onDisposeAction: AutofillContextAction.cancel,
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 10),
                    const AppLogo(size: 130),
                    const SizedBox(height: 32),
                    Text(
                      AppConfig.appName,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _emailController,
                      focusNode: _emailFocus,
                      keyboardType: TextInputType.emailAddress,
                      enableSuggestions: false,
                      autocorrect: false,
                      autofillHints: const [
                        AutofillHints.email,
                        AutofillHints.username,
                      ],
                      textCapitalization: TextCapitalization.none,
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: const Icon(Icons.email),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      validator: AuthValidation.validateEmail,
                      onChanged: (_) {
                        if (_errorMessage != null) {
                          setState(() => _errorMessage = null);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      focusNode: _passwordFocus,
                      obscureText: _obscurePassword,
                      keyboardType: TextInputType.visiblePassword,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      validator: AuthValidation.validateLoginPassword,
                      onChanged: (_) {
                        if (_errorMessage != null) {
                          setState(() => _errorMessage = null);
                        }
                      },
                      onFieldSubmitted: (_) => _signIn(),
                    ),
                    const SizedBox(height: 24),
                    if (_errorMessage != null)
                      AuthErrorBanner(message: _errorMessage!),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _signIn,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
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
                            : const Text(
                                'Sign In',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ForgotPasswordScreen(),
                          ),
                        );
                      },
                      child: Text(
                        'Forgot Password?',
                        style: TextStyle(color: theme.colorScheme.primary),
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
