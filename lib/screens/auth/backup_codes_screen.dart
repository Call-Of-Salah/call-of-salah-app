import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/app_config.dart';
import '../../services/auth/auth_service.dart';
import '../../widgets/app_feedback.dart';
import '../settings/settings_glass.dart';
import 'widgets/auth_page_scaffold.dart';
import 'widgets/backup_codes_grid.dart';

/// Seam for tests - generates the set of codes.
abstract class BackupCodeGenerator {
  Future<List<String>> generate();
}

class _AuthServiceBackupCodeGenerator implements BackupCodeGenerator {
  const _AuthServiceBackupCodeGenerator();
  @override
  Future<List<String>> generate() => AuthService.instance.generateBackupCodes();
}

/// Shows a freshly generated set of 10 one-time backup codes. Generating
/// happens on open and already replaces the old set, so leaving before
/// pressing Done is blocked - the codes are live.
class BackupCodesScreen extends StatefulWidget {
  const BackupCodesScreen({super.key, this.generator});

  final BackupCodeGenerator? generator;

  @override
  State<BackupCodesScreen> createState() => _BackupCodesScreenState();
}

class _BackupCodesScreenState extends State<BackupCodesScreen> {
  late final BackupCodeGenerator _generator =
      widget.generator ?? const _AuthServiceBackupCodeGenerator();

  List<String>? _codes;
  String? _error;
  bool _saved = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _codes = null;
      _error = null;
    });
    try {
      final codes = await _generator.generate();
      if (!mounted) return;
      setState(() => _codes = codes);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = AuthService.messageFor(error));
    }
  }

  String get _codesText => _codes?.join('\n') ?? '';

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: _codesText));
    if (!mounted) return;
    AppFeedback.showSnackBar(context, 'Codes copied', isError: false);
  }

  Future<void> _share() async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: '${AppConfig.appName} backup codes\n\n$_codesText',
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  void _finish() {
    _done = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = settingsSecondaryTextColor(context);

    return PopScope(
      canPop: _done,
      onPopInvokedWithResult: (didPop, _) {
        // Codes are already live once generated - leaving is only
        // allowed via Done.
      },
      child: AuthPageScaffold(
        title: 'Backup Codes',
        // Codes are live once generated - leaving is only via Done, so
        // no back or close affordances.
        showBack: false,
        closable: false,
        body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Save your backup codes',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Each code works once at the two-factor step - use them if '
                "you can't get to your usual method. They won't be shown "
                'again.',
                style: TextStyle(fontSize: 14, height: 1.5, color: secondary),
              ),
              const SizedBox(height: 24),
              if (_codes != null)
                BackupCodesGrid(codes: _codes!)
              else if (_error != null)
                Column(
                  children: [
                    Text(_error!, style: TextStyle(color: secondary)),
                    TextButton(
                      onPressed: _load,
                      child: const Text('Try again'),
                    ),
                  ],
                )
              else
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                ),
              if (_codes != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _copyAll,
                        icon: const Icon(Icons.copy_outlined, size: 18),
                        label: const Text('Copy all'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _share,
                        icon: const Icon(Icons.ios_share_outlined, size: 18),
                        label: const Text('Share'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                InkWell(
                  onTap: () => setState(() => _saved = !_saved),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _saved,
                          onChanged: (v) =>
                              setState(() => _saved = v ?? false),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'I\'ve saved these codes somewhere safe',
                            style: TextStyle(
                              fontSize: 14,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saved ? _finish : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Done',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
    );
  }
}
