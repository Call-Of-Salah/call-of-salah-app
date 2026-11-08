import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import '../api/platform_http_client.dart';

/// The `purpose` of an email-2FA code, matching the values the backend's
/// `/v1/account/2fa/email/*` endpoints accept (see
/// `docs/backend-api-contract.md`).
enum Email2faPurpose {
  /// Completing the second factor right after password sign-in.
  signIn('sign_in'),

  /// Turning email 2FA on for the account.
  enable('enable'),

  /// Turning email 2FA off.
  disable('disable');

  const Email2faPurpose(this.value);

  /// Wire value sent in the JSON body.
  final String value;
}

/// Non-2xx response from an account endpoint. [errorCode] is the
/// machine-readable `error` field of the JSON error body (e.g.
/// `invalid_code`, `rate_limited`), [retryAfter] the `retry_after`
/// seconds hint on `rate_limited` responses.
class AccountApiException implements Exception {
  const AccountApiException(this.statusCode, {this.errorCode, this.retryAfter});

  final int statusCode;
  final String? errorCode;
  final int? retryAfter;

  @override
  String toString() =>
      'AccountApiException(statusCode: $statusCode, errorCode: $errorCode, retryAfter: $retryAfter)';
}

/// Request timed out. The explicit timeout matters on proxied
/// networks, where a request can otherwise hang indefinitely.
class AccountApiTimeoutException implements Exception {
  const AccountApiTimeoutException(this.uri);

  final Uri uri;

  @override
  String toString() => 'AccountApiTimeoutException(uri: $uri)';
}

/// Thin HTTP client for the `/v1/account*` backend endpoints. Every
/// request carries the caller's Supabase access token as
/// `Authorization: Bearer`, which the backend validates with Supabase
/// Auth.
///
/// If the backend requires app attestation, attach a Firebase App Check
/// token here (`X-Firebase-AppCheck` header, `firebase_app_check`
/// dependency).
class AccountApiClient {
  AccountApiClient({http.Client? httpClient})
      : _httpClient = httpClient ?? createPlatformHttpClient();

  final http.Client _httpClient;

  /// 30s ceiling per request - long enough for slow networks, short
  /// enough that a hung request surfaces as a timeout error.
  static const Duration _timeout = Duration(seconds: 30);

  /// `DELETE /v1/account` - permanently deletes the user's account.
  /// The backend requires a fully-verified session and a recent
  /// (<=10 min) `last_sign_in_at` (`reauth_required` otherwise).
  Future<void> deleteAccount(String accessToken) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/v1/account');
    await _send(accessToken, uri, (headers) => _httpClient.delete(uri, headers: headers));
  }

  /// `POST /v1/account/2fa/email/send` - asks the backend to email a
  /// 6-digit code for [purpose]. Throws `rate_limited` (429, with
  /// [AccountApiException.retryAfter]) past the per-user send limits.
  Future<void> sendEmail2faCode(
    String accessToken,
    Email2faPurpose purpose,
  ) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/v1/account/2fa/email/send');
    await _send(
      accessToken,
      uri,
      (headers) => _httpClient.post(
        uri,
        headers: headers,
        body: jsonEncode({'purpose': purpose.value}),
      ),
    );
  }

  /// `POST /v1/account/2fa/email/verify` - verifies [code] for [purpose].
  /// Error codes: `invalid_code`, `code_expired`, `too_many_attempts`.
  Future<void> verifyEmail2faCode(
    String accessToken,
    Email2faPurpose purpose,
    String code,
  ) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/v1/account/2fa/email/verify');
    await _send(
      accessToken,
      uri,
      (headers) => _httpClient.post(
        uri,
        headers: headers,
        body: jsonEncode({'purpose': purpose.value, 'code': code}),
      ),
    );
  }

  /// `GET /v1/account/2fa/backup-codes` - unused backup-code count.
  Future<int> getBackupCodeCount(String accessToken) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/v1/account/2fa/backup-codes');
    final res = await _sendJson(accessToken, uri,
        (h) => _httpClient.get(uri, headers: h), expectBody: true);
    return (res['remaining'] as num).toInt();
  }

  /// `POST /v1/account/2fa/backup-codes/generate` - replaces the set and
  /// returns the new plaintext codes (only time they're returned).
  Future<List<String>> generateBackupCodes(String accessToken) async {
    final uri = Uri.parse(
        '${AppConfig.apiBaseUrl}/v1/account/2fa/backup-codes/generate');
    final res = await _sendJson(accessToken, uri,
        (h) => _httpClient.post(uri, headers: h, body: jsonEncode({})),
        expectBody: true);
    return (res['codes'] as List).cast<String>();
  }

  /// `POST /v1/account/2fa/backup-codes/verify` - consumes a backup code
  /// and marks the session verified; returns the remaining count.
  Future<int> verifyBackupCode(String accessToken, String code) async {
    final uri = Uri.parse(
        '${AppConfig.apiBaseUrl}/v1/account/2fa/backup-codes/verify');
    final res = await _sendJson(accessToken, uri,
        (h) => _httpClient.post(uri, headers: h,
            body: jsonEncode({'code': code})),
        expectBody: true);
    return (res['remaining'] as num).toInt();
  }

  /// `POST /v1/account/2fa/totp/reset` - deletes every TOTP factor via
  /// the backend's admin call (for "lost my phone" recovery). With
  /// [backupCode] the backend checks and consumes it instead of requiring
  /// a fully verified session (the lost-phone step of a password reset).
  Future<void> resetTotp(String accessToken, {String? backupCode}) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/v1/account/2fa/totp/reset');
    await _send(accessToken, uri, (h) => backupCode == null
        ? _httpClient.post(uri, headers: h)
        : _httpClient.post(uri, headers: h,
            body: jsonEncode({'backupCode': backupCode})));
  }

  /// `PUT /v1/account/sessions/current` - registers this session's
  /// readable device label (`{platform, model, osVersion, appVersion,
  /// deviceId}`; never an IP or user agent) for the "Signed-in devices"
  /// list. `deviceId` is the stable install id - the backend retires this
  /// user's other sessions from the same physical device.
  Future<void> registerSessionDevice(
    String accessToken,
    Map<String, String> device,
  ) async {
    final uri =
        Uri.parse('${AppConfig.apiBaseUrl}/v1/account/sessions/current');
    await _send(accessToken, uri,
        (h) => _httpClient.put(uri, headers: h, body: jsonEncode(device)));
  }

  /// `GET /v1/account/sessions` - the user's live sessions, newest
  /// activity first, followed by the recently signed-out ones
  /// (`previousSessions`, each with an `endedAt`; raw JSON maps, see
  /// `AccountSession.fromJson`).
  Future<List<Map<String, dynamic>>> listSessions(String accessToken) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/v1/account/sessions');
    final res = await _sendJson(accessToken, uri,
        (h) => _httpClient.get(uri, headers: h), expectBody: true);
    return [
      ...res['sessions'] as List,
      ...res['previousSessions'] as List? ?? const [],
    ].map((s) => Map<String, dynamic>.from(s as Map)).toList();
  }

  /// `DELETE /v1/account/sessions/{id}` - revokes one session. Error
  /// codes: `cannot_revoke_current` (400), `not_found` (404).
  Future<void> revokeSession(String accessToken, String sessionId) async {
    final uri = Uri.parse(
        '${AppConfig.apiBaseUrl}/v1/account/sessions/$sessionId');
    await _send(accessToken, uri,
        (h) => _httpClient.delete(uri, headers: h));
  }

  /// Shared request path: builds headers (App Check + Bearer + JSON),
  /// applies the timeout, expects a 204 and turns anything else into an
  /// [AccountApiException] carrying the body's `error`/`retry_after`.
  Future<void> _send(
    String accessToken,
    Uri uri,
    Future<http.Response> Function(Map<String, String> headers) request,
  ) async {
    await _sendJson(accessToken, uri, request);
  }

  Future<Map<String, dynamic>> _sendJson(
    String accessToken,
    Uri uri,
    Future<http.Response> Function(Map<String, String> headers) request, {
    bool expectBody = false,
  }) async {
    final headers = <String, String>{
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
    };
    // TODO(backend): attach a Firebase App Check token here
    // (`X-Firebase-AppCheck`) if the backend enforces attestation.

    final http.Response response;
    try {
      response = await request(headers).timeout(_timeout);
    } on TimeoutException {
      throw AccountApiTimeoutException(uri);
    }
    if (response.statusCode == 204) {
      return const {};
    }
    if (expectBody && response.statusCode == 200) {
      final body = jsonDecode(response.body);
      if (body is Map) return Map<String, dynamic>.from(body);
    }

    String? errorCode;
    int? retryAfter;
    try {
      final body = jsonDecode(response.body);
      if (body is Map) {
        errorCode = body['error'] as String?;
        retryAfter = body['retry_after'] as int?;
      }
    } catch (_) {
      // Non-JSON error body (e.g. a proxy/edge error page) - errorCode
      // stays null and callers fall back to the status code.
    }
    throw AccountApiException(
      response.statusCode,
      errorCode: errorCode,
      retryAfter: retryAfter,
    );
  }

  void close() => _httpClient.close();
}
