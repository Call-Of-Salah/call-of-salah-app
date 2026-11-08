/// Form-field validators for the auth screens, plus the shared password
/// requirement list that also drives the live requirements checklist on
/// the signup/reset screens.
library;

/// A single password rule shown in the live checklist - [label] is the
/// user-facing requirement text, [isMet] decides whether a password
/// satisfies it.
class PasswordRequirement {
  const PasswordRequirement({required this.label, required this.isMet});

  final String label;
  final bool Function(String password) isMet;
}

class AuthValidation {
  AuthValidation._();

  /// RFC-5321 maximum address length.
  static const int maxEmailLength = 254;

  /// bcrypt's 72-byte input limit - Supabase hashes with bcrypt, so
  /// longer passwords would be silently truncated server-side.
  static const int maxPasswordLength = 72;

  static const int minPasswordLength = 12;

  /// Non-alphanumeric characters allowed by the password policy - must
  /// stay consistent with the Supabase dashboard's password requirement
  /// so signup doesn't pass client-side but fail server-side.
  static const String allowedSpecialChars =
      r'^$*.[]{}()?"!@#%&/\,><' "':;|_~`";

  /// The shared requirement list: [validateSignupPassword] uses it, and
  /// the checklist widget renders one row per entry.
  static final List<PasswordRequirement> passwordRequirements = [
    PasswordRequirement(
      label: 'At least $minPasswordLength characters',
      isMet: (p) => p.length >= minPasswordLength,
    ),
    PasswordRequirement(
      label: 'At least one uppercase letter (A-Z)',
      isMet: (p) => p.codeUnits.any((c) => c >= 65 && c <= 90),
    ),
    PasswordRequirement(
      label: 'At least one lowercase letter (a-z)',
      isMet: (p) => p.codeUnits.any((c) => c >= 97 && c <= 122),
    ),
    PasswordRequirement(
      label: 'At least one number (0-9)',
      isMet: (p) => p.codeUnits.any((c) => c >= 48 && c <= 57),
    ),
    PasswordRequirement(
      label: 'At least one special character ($allowedSpecialChars)',
      isMet: (p) => p.split('').any(allowedSpecialChars.contains),
    ),
  ];

  /// Email validation with format checks and common domain-typo
  /// suggestions. Returns an error message, or null when valid.
  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your email';
    }

    final email = value.trim();

    if (email.length > maxEmailLength) {
      return 'Email address is too long (maximum $maxEmailLength characters)';
    }

    if (!isValidEmail(email)) {
      return 'Please enter a valid email address';
    }

    final domainSuggestion = suggestDomainCorrection(email);
    if (domainSuggestion != null) {
      return 'Did you mean: $domainSuggestion?';
    }

    return null;
  }

  /// Loose-but-practical email format check (basic shape, single `@`,
  /// sane local/domain lengths, no edge dots/dashes).
  static bool isValidEmail(String email) {
    if (email.isEmpty) return false;

    if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
        .hasMatch(email)) {
      return false;
    }

    if (email.startsWith('.') || email.endsWith('.')) return false;
    if (email.contains('..')) return false;
    if (email.split('@').length != 2) return false;

    final parts = email.split('@');
    final localPart = parts[0];
    final domainPart = parts[1];

    if (localPart.isEmpty || localPart.length > 64) return false;
    if (localPart.startsWith('.') || localPart.endsWith('.')) return false;

    if (domainPart.isEmpty || domainPart.length > 253) return false;
    if (domainPart.startsWith('-') || domainPart.endsWith('-')) return false;
    if (domainPart.startsWith('.') || domainPart.endsWith('.')) return false;

    return true;
  }

  /// Suggests a corrected domain for common typos (`gmail.con` ->
  /// `gmail.com`), or null if the domain isn't a known typo.
  static String? suggestDomainCorrection(String email) {
    const commonTypos = {
      'gmail.co': 'gmail.com',
      'gmail.con': 'gmail.com',
      'gmial.com': 'gmail.com',
      'gmai.com': 'gmail.com',
      'yahoo.co': 'yahoo.com',
      'yahoo.con': 'yahoo.com',
      'hotmail.co': 'hotmail.com',
      'hotmail.con': 'hotmail.com',
      'outlook.co': 'outlook.com',
      'outlook.con': 'outlook.com',
    };

    final atIndex = email.lastIndexOf('@');
    if (atIndex == -1) return null;

    final domain = email.substring(atIndex + 1).toLowerCase();
    if (commonTypos.containsKey(domain)) {
      final localPart = email.substring(0, atIndex);
      return '$localPart@${commonTypos[domain]}';
    }

    return null;
  }

  /// Signup/new-password validation driven by [passwordRequirements] -
  /// returns a single-line failure message (the live checklist shows the
  /// per-rule detail), plus the bcrypt length cap.
  static String? validateSignupPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a password';
    }
    final password = value;
    if (password.length > maxPasswordLength) {
      return 'Password is too long (maximum $maxPasswordLength characters)';
    }
    final unmet = passwordRequirements.any((r) => !r.isMet(password));
    if (unmet) {
      return "Password doesn't meet the requirements";
    }
    return null;
  }

  /// Login password validation - presence only; correctness is the
  /// server's job, and over-validating locally would lock users out of
  /// accounts created under older policies.
  static String? validateLoginPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your password';
    }
    return null;
  }

  /// Confirm-password validation.
  static String? validateConfirmPassword(
    String? value,
    String originalPassword,
  ) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }
    if (value != originalPassword) {
      return 'Passwords do not match';
    }
    return null;
  }

  /// Full-name validation (sign up asks for first + last name).
  static String? validateName(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your full name';
    }

    final trimmedName = value.trim();

    if (trimmedName.length < 4) {
      return 'Name must be at least 3 characters';
    }
    if (trimmedName.length > 50) {
      return 'Name is too long (maximum 50 characters)';
    }

    final nameParts = trimmedName.split(RegExp(r'\s+'));
    if (nameParts.length < 2) {
      return 'Please enter both first and last name';
    }

    for (final part in nameParts) {
      if (part.length < 2) {
        return 'Each name must be at least 2 characters';
      }
    }

    if (!RegExp(r"^[a-zA-Z\s\-']+$").hasMatch(trimmedName)) {
      return 'Name can only contain letters, spaces, hyphens, and apostrophes';
    }

    return null;
  }

  /// The 6-digit codes used for email confirmation, password reset and
  /// the backend's email-2FA codes.
  static String? validateCode(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter the code';
    }
    if (!RegExp(r'^\d{6}$').hasMatch(value.trim())) {
      return 'The code is 6 digits';
    }
    return null;
  }
}
