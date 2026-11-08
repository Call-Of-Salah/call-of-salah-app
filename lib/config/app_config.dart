/// App-wide constants.
class AppConfig {
  AppConfig._();

  /// Display name used in share text and auth emails (Supabase TOTP
  /// issuer, backup-code share text).
  static const String appName = 'Call of Salah';

  /// Base URL of the account API (`/v1/account*` endpoints - see
  /// `AccountApiClient`). PLACEHOLDER: the backend isn't built yet -
  /// point `--dart-define=API_BASE_URL=...` at the real service when it
  /// exists. Debug builds default to a local server on port 8787.
  static const String _placeholderApiBaseUrl = 'http://localhost:8787';

  static final String apiBaseUrl = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _placeholderApiBaseUrl,
  );

  /// Supabase project URL and publishable key for auth (Supabase
  /// dashboard: Project Settings -> API Keys). PLACEHOLDERS: fill these
  /// in (or pass `--dart-define=SUPABASE_URL=...` /
  /// `--dart-define=SUPABASE_PUBLISHABLE_KEY=...`) once the Supabase
  /// project exists - the future backend's `/v1/account*` endpoints
  /// must point at the same project. Clearing either one disables
  /// Sign In/Account entirely (`AuthService.isAvailable` stays false).
  /// The publishable key is safe to ship in the app (unlike a secret
  /// key).
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  /// Whether auth has been configured (both Supabase values above set).
  /// When false, `AuthService.initialize` is a no-op and the app behaves
  /// exactly as if the auth feature didn't exist.
  static bool get isAuthConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
