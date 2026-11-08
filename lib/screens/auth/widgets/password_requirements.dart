import 'package:flutter/material.dart';

import '../../../utils/auth_validation.dart';
import '../../settings/settings_glass.dart';

/// Live checklist under the signup/new-password field: one row per rule
/// in [AuthValidation.passwordRequirements], ticking as the user types
/// (the same list drives `validateSignupPassword`, so a fully ticked
/// checklist always passes validation).
class PasswordRequirements extends StatelessWidget {
  const PasswordRequirements({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metColor = settingsAccentColor(context);
    final unmetColor = theme.colorScheme.onSurface.withValues(alpha: 0.5);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final password = controller.text;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final requirement in AuthValidation.passwordRequirements)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(
                      requirement.isMet(password)
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: requirement.isMet(password) ? metColor : unmetColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        requirement.label,
                        style: TextStyle(
                          fontSize: 13,
                          color: requirement.isMet(password)
                              ? theme.colorScheme.onSurface
                              : unmetColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
