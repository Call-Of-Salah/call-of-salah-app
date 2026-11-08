import 'package:flutter/material.dart';

import '../../services/auth/auth_service.dart';
import '../../widgets/glass/glass_action_sheet.dart';
import '../settings/settings_glass.dart';
import 'backup_codes_screen.dart';
import 'totp_enrollment_screen.dart';
import 'widgets/auth_page_scaffold.dart';
import 'widgets/auth_sheet.dart';

/// Seam for tests - everything the setup screen calls through to.
abstract class TwoFactorSetupAuth {
  Future<void> signOut();
  Future<bool> isTotpEnabled();
}

class _AuthServiceTwoFactorSetupAuth implements TwoFactorSetupAuth {
  const _AuthServiceTwoFactorSetupAuth();
  @override
  Future<void> signOut() => AuthService.instance.signOut();
  @override
  Future<bool> isTotpEnabled() async => AuthService.instance.isTotpEnabled;
}

/// Mandatory two-factor setup shown when a fully verified account has
/// no second factor yet. There is no skip - backing out asks to sign
/// out instead. Once a method is enabled the screen pushes
/// [BackupCodesScreen] then pops home.
class TwoFactorSetupScreen extends StatefulWidget {
  const TwoFactorSetupScreen({super.key, this.auth});

  final TwoFactorSetupAuth? auth;

  @override
  State<TwoFactorSetupScreen> createState() => _TwoFactorSetupScreenState();
}

class _TwoFactorSetupScreenState extends State<TwoFactorSetupScreen> {
  late final TwoFactorSetupAuth _auth =
      widget.auth ?? const _AuthServiceTwoFactorSetupAuth();
  bool _busy = false;

  Future<bool> _onBack() async {
    if (_busy) return false;
    setState(() => _busy = true);
    final leave = await showGlassConfirm(
      context,
      icon: Icons.shield_outlined,
      title: 'Two-factor required',
      message:
          'Two-factor authentication is required to use your account. Sign out?',
      confirmLabel: 'Sign out',
      cancelLabel: 'Stay',
      destructive: true,
    );
    if (!mounted) return false;
    if (leave) {
      await _auth.signOut();
      if (!mounted) return false;
      finishAuthFlow(context);
      return false;
    }
    setState(() => _busy = false);
    return false;
  }

  Future<void> _afterMethodEnabled() async {
    // A method is now on - offer the backup codes, then finish.
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const BackupCodesScreen()),
    );
    if (!mounted) return;
    finishAuthFlow(context, message: "You're signed in");
  }

  Future<void> _chooseTotp() async {
    final enrolled = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const TotpEnrollmentScreen(fromSetup: true),
      ),
    );
    if (!mounted || enrolled != true) return;
    await _afterMethodEnabled();
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: AuthPageScaffold(
        title: 'Secure Your Account',
        onBack: _onBack,
        // Setup is mandatory - leaving goes through the sign-out
        // confirm (the back button), not the sheet's close button.
        closable: false,
        body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.shield_outlined,
                  size: 38,
                  color: settingsAccentColor(context),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Two-factor authentication',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Your account requires a second step after your password. '
                'Choose how you want to get your codes.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: settingsSecondaryTextColor(context),
                ),
              ),
              const SizedBox(height: 28),
              _OptionCard(
                icon: Icons.phonelink_lock_outlined,
                title: 'Authenticator app',
                subtitle:
                    'Codes from an app like Google Authenticator - works offline.',
                recommended: true,
                onTap: _busy ? null : _chooseTotp,
              ),

            ],
          ),
        ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.recommended = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool recommended;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: settingsCardDecoration(context),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 28, color: settingsAccentColor(context)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(title, style: settingsCardTitleStyle(context)),
                        if (recommended) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: settingsAccentColor(context)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Recommended',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: settingsAccentColor(context),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: settingsSecondaryTextColor(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: settingsSecondaryTextColor(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
