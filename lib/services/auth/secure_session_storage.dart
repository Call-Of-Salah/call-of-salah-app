import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase session persistence backed by `flutter_secure_storage`
/// (iOS Keychain / Android Keystore) rather than the SDK's default
/// SharedPreferences - access/refresh tokens are credentials and belong
/// in secure storage. Also stores the app's own "this session passed
/// email 2FA" marker (`AuthService` writes it after a `sign_in` verify;
/// the backend keeps the authoritative copy in
/// `email_2fa_verified_sessions`).
///
/// Note: the iOS Keychain survives app reinstall, so a deleted account's
/// stored session is cleared at most by the explicit sign-out on delete.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _sessionKey = 'supabase_session';
  static const String _emailVerifiedSessionKey =
      'email_2fa_verified_session_id';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async {
    return await _storage.read(key: _sessionKey) != null;
  }

  @override
  Future<String?> accessToken() async {
    return _storage.read(key: _sessionKey);
  }

  @override
  Future<void> removePersistedSession() async {
    await _storage.delete(key: _sessionKey);
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    await _storage.write(key: _sessionKey, value: persistSessionString);
  }

  /// The Supabase `session_id` that last passed an email-2FA `sign_in`
  /// verify, or null. `AuthService` compares this against the current
  /// session's id to decide whether the session is "fully verified".
  Future<String?> readEmailVerifiedSessionId() async {
    return _storage.read(key: _emailVerifiedSessionKey);
  }

  Future<void> writeEmailVerifiedSessionId(String sessionId) async {
    await _storage.write(key: _emailVerifiedSessionKey, value: sessionId);
  }

  Future<void> clearEmailVerifiedSessionId() async {
    await _storage.delete(key: _emailVerifiedSessionKey);
  }
}
