import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/settings/settings_glass.dart';

/// Shared snackbar helper used across the auth flow.
class AppFeedback {
  AppFeedback._();

  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSnackBar(
    BuildContext context,
    String message, {
    required bool isError,
    Duration? duration,
  }) {
    // Error haptic + floating pill with icon.
    if (isError) HapticFeedback.heavyImpact();
    final messenger = ScaffoldMessenger.of(context)
      ..hideCurrentMaterialBanner()
      ..hideCurrentSnackBar();
    return messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        duration: duration ?? const Duration(seconds: 5),
        backgroundColor: isError
            ? Colors.red.shade700
            : settingsBrandColor(context),
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_rounded : Icons.check_circle_rounded,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
