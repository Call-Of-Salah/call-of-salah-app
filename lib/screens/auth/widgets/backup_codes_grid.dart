import 'package:flutter/material.dart';

import '../../settings/settings_glass.dart';

/// The two-column monospace grid of one-time backup codes, shared by
/// the standalone [BackupCodesScreen] and the settings Backup codes
/// page's "save your codes" state.
class BackupCodesGrid extends StatelessWidget {
  const BackupCodesGrid({super.key, required this.codes});

  final List<String> codes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: settingsCardDecoration(context),
      padding: const EdgeInsets.all(16),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 3.6,
        children: [
          for (final code in codes)
            Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                code,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 15,
                  letterSpacing: 0.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
