import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/auth/auth_service.dart';
import '../../widgets/app_feedback.dart';
import '../settings/settings_glass.dart';
import 'widgets/auth_error_banner.dart';
import 'widgets/auth_page_scaffold.dart';
import 'widgets/auth_sheet.dart';
import 'widgets/code_field.dart';

/// Walks the user through enrolling a TOTP authenticator app
/// (loading -> QR/Manual -> code -> success/error), backed by
/// [AuthService]'s Supabase MFA calls.
///
/// Seam for tests - the two auth calls this screen makes. The
/// default delegates to [AuthService]; widget tests inject a fake.
abstract class TotpEnrollmentAuth {
  Future<TotpEnrollment> start({String? currentCode});
  Future<void> confirm(String factorId, String code);
}

/// Pops `true` once enrollment succeeded, `false`/nothing otherwise;
/// leaving mid-flow leaves the unfinished factor for Supabase to
/// expire, so no "Verification method removed" email is sent.
class TotpEnrollmentScreen extends StatefulWidget {
  /// [fromSetup] means the screen was opened by the required-setup flow:
  /// the success copy points at the upcoming backup-codes step instead
  /// of suggesting email codes.
  const TotpEnrollmentScreen({
    super.key,
    this.fromSetup = false,
    this.replacement = false,
    this.currentCode,
    this.auth,
  });

  final bool fromSetup;

  /// Replacement mode: the old factor keeps working until the new one
  /// verifies - starts via `startTotpReplacement`, confirms via
  /// `confirmTotpReplacement`, and leaving just abandons the
  /// unverified factor (Supabase expires it), leaving the old
  /// authenticator intact.
  final bool replacement;

  /// Current authenticator code for the aal2 step-up in replacement
  /// mode (needed when the session is only aal1).
  final String? currentCode;

  /// Test seam; production leaves it null.
  final TotpEnrollmentAuth? auth;

  @override
  State<TotpEnrollmentScreen> createState() => _TotpEnrollmentScreenState();
}

enum _EnrollStep { loading, showQr, success, error }

class _TotpEnrollmentScreenState extends State<TotpEnrollmentScreen> {
  _EnrollStep _step = _EnrollStep.loading;

  TotpEnrollment? _enrollment;
  String? _loadError;
  bool _completed = false;

  final TextEditingController _codeController = TextEditingController();
  bool _isVerifying = false;
  String? _verifyError;
  bool _manualTab = false; // QR vs manual-key view

  @override
  void initState() {
    super.initState();
    _startEnrollment();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _startEnrollment() async {
    setState(() {
      _step = _EnrollStep.loading;
      _loadError = null;
    });
    try {
      final enrollment = widget.auth != null
          ? await widget.auth!.start(currentCode: widget.currentCode)
          : widget.replacement
              ? await AuthService.instance.startTotpReplacement(
                  currentCode: widget.currentCode)
              : await AuthService.instance.startTotpEnrollment();
      if (!mounted) return;
      setState(() {
        _enrollment = enrollment;
        _step = _EnrollStep.showQr;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = AuthService.messageFor(error);
        _step = _EnrollStep.error;
      });
    }
  }

  Future<void> _verify() async {
    if (_codeController.text.trim().length != 6) {
      setState(() => _verifyError = 'Please enter the 6-digit code.');
      return;
    }
    setState(() {
      _isVerifying = true;
      _verifyError = null;
    });
    try {
      if (widget.auth != null) {
        await widget.auth!.confirm(
            _enrollment!.factorId, _codeController.text.trim());
      } else if (widget.replacement) {
        await AuthService.instance.confirmTotpReplacement(
          _enrollment!.factorId,
          _codeController.text.trim(),
        );
      } else {
        await AuthService.instance.confirmTotpEnrollment(
          _enrollment!.factorId,
          _codeController.text.trim(),
        );
      }
      if (!mounted) return;
      setState(() {
        _completed = true;
        _step = _EnrollStep.success;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _verifyError = AuthService.messageFor(error);
        _codeController.clear();
      });
    }
  }

  /// Leaving before success just pops - the unverified factor is left
  /// for Supabase to expire, so no "Verification method removed" email
  /// is sent. `_enrollTotp` sweeps leftovers as a fallback if the next
  /// enroll is rejected for them.
  Future<void> _leave() async {
    popAuthRoute(context, _completed);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: AuthPageScaffold(
        title: 'Enable Authenticator App',
        onBack: () => _leave(),
        body: switch (_step) {
          _EnrollStep.loading => const Center(
              child: CircularProgressIndicator(),
            ),
          _EnrollStep.showQr => _buildQrStep(),
          _EnrollStep.success => _buildSuccess(),
          _EnrollStep.error => _buildError(),
        },
      ),
    );
  }

  Widget _buildQrStep() {
    final theme = Theme.of(context);
    final enrollment = _enrollment!;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Scan with your authenticator app',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Or add it to your password manager.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 20),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('QR Code')),
                ButtonSegment(value: true, label: Text('Manual')),
              ],
              selected: {_manualTab},
              onSelectionChanged: (selected) =>
                  setState(() => _manualTab = selected.first),
            ),
            const SizedBox(height: 20),
            if (_manualTab) _buildManualKey(theme, enrollment),
            if (!_manualTab)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: enrollment.uri,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
            const SizedBox(height: 24),
            CodeField(
              controller: _codeController,
              enabled: !_isVerifying,
              onSubmitted: (_) => _verify(),
              onChanged: (_) {
                if (_verifyError != null) {
                  setState(() => _verifyError = null);
                }
              },
            ),
            const SizedBox(height: 20),
            if (_verifyError != null) AuthErrorBanner(message: _verifyError!),
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
                        'Verify and enable',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualKey(ThemeData theme, TotpEnrollment enrollment) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Manual entry key',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  enrollment.secret,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 20),
                tooltip: 'Copy key',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: enrollment.secret));
                  AppFeedback.showSnackBar(
                      context, 'Key copied to clipboard', isError: false);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess() {
    final theme = Theme.of(context);
    final emailOff = !widget.fromSetup && !AuthService.instance.isEmail2faEnabled;

    return Center(
      key: const ValueKey('success'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer
                    .withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle_outline,
                size: 44,
                color: settingsAccentColor(context),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Authenticator enabled',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.fromSetup
                  ? 'From now on you\'ll enter a code from your authenticator '
                      'app when signing in. Next you\'ll get backup codes to '
                      'keep somewhere safe.'
                  : emailOff
                  ? 'From now on you\'ll enter a code from your authenticator '
                      'app when signing in. Email codes are a good backup - '
                      'you can turn them on in Settings > Account.'
                  : 'From now on you\'ll enter a code from your authenticator '
                      'app when signing in.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => popAuthRoute(context, true),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Colors.red.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              _loadError ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () => _leave(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Go Back'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _startEnrollment,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
