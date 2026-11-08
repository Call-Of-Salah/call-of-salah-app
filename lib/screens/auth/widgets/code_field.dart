import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../utils/auth_validation.dart';

/// The 6-digit code entry field shared by the email-confirmation,
/// password-reset and 2FA screens: numeric keypad, one-time-code
/// autofill, digits only, centred large text.
class CodeField extends StatelessWidget {
  const CodeField({
    super.key,
    required this.controller,
    this.focusNode,
    this.enabled = true,
    this.onSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      keyboardType: TextInputType.number,
      autofillHints: const [AutofillHints.oneTimeCode],
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      textAlign: TextAlign.center,
      onFieldSubmitted: onSubmitted,
      onChanged: onChanged,
      validator: AuthValidation.validateCode,
      style: const TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.bold,
        letterSpacing: 12,
      ),
      decoration: InputDecoration(
        hintText: '000000',
        hintStyle: TextStyle(
          fontSize: 30,
          letterSpacing: 12,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25),
          fontWeight: FontWeight.bold,
        ),
        counterText: '',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 18),
      ),
    );
  }
}
