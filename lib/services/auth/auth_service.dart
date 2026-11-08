import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_config.dart';
import '../device/device_id_service.dart';
import '../firebase/analytics_service.dart';
import '../firebase/crashlytics_service.dart';
import 'account_api_client.dart';
import 'account_session.dart';
import 'secure_session_storage.dart';

/// Which second factor(s) the user must complete before their session is
/// "fully verified" (see [AuthService.isFullyVerified] - the same rule the
/// backend's `/v1/account*` endpoints enforce).
class SecondFactorRequirement {
  const SecondFactorRequirement({this.totp = false, this.email = false});

  /// None required - the session is already fully verified.
  static const SecondFactorRequirement none = SecondFactorRequirement();

  /// A verified TOTP factor is enrolled and the session isn't `aal2` yet.
  final bool totp;

  /// Email 2FA is on and this session hasn't passed an email code.
  final bool email;

  bool get isRequired => totp || email;
}

/// Outcome of [AuthService.signIn]/[AuthService.verifySignupCode].
sealed class SignInResult {
  const SignInResult();
}

/// Signed in and fully verified - [AuthService.currentUser] is non-null.
class SignInSuccess extends SignInResult {
  const SignInSuccess();
}

/// Password accepted, but the session still needs a second factor.
/// [maskedEmail] is for "we sent a code to ..." copy.
class SignInNeedsSecondFactor extends SignInResult {
  const SignInNeedsSecondFactor(this.requirement, this.maskedEmail);

  final SecondFactorRequirement requirement;
  final String maskedEmail;
}

/// Fully verified but the account has no second factor yet - every
/// account must set one up before signing in is finished.
class SignInNeedsTwoFactorSetup extends SignInResult {
  const SignInNeedsTwoFactorSetup();
}

/// Thrown when disabling a second factor would leave the account with
/// none (mirrors the backend's `last_second_factor` rule).
class LastSecondFactorException implements Exception {
  const LastSecondFactorException();
}

/// Thrown by [AuthService.startTotpReplacement] when the session isn't
/// `aal2` and no current authenticator code was supplied.
class TotpCurrentCodeRequired implements Exception {
  const TotpCurrentCodeRequired();
}

/// Backend errors from the backup-code endpoints - kept distinct so
/// [AuthService.messageFor] can give `invalid_code` backup-specific copy.
class BackupCodeApiException implements Exception {
  const BackupCodeApiException(this.inner);
  final AccountApiException inner;
}

/// Sign-up worked but the email isn't confirmed yet; a fresh
/// confirmation code was re-sent.
class SignInEmailNotConfirmed extends SignInResult {
  const SignInEmailNotConfirmed(this.email);

  final String email;
}

/// Thrown by `signUp` when Supabase returns a user with no identities -
/// its "already registered, pretend it worked" anti-enumeration case.
class AuthEmailAlreadyRegistered implements Exception {
  const AuthEmailAlreadyRegistered();
}

/// Everything needed to finish a TOTP enrollment (QR/manual key + the
/// factor id to verify against).
class TotpEnrollment {
  const TotpEnrollment({
    required this.factorId,
    required this.secret,
    required this.uri,
  });

  final String factorId;
  final String secret;
  final String uri;
}

/// Singleton coordinating Supabase Auth for the app (the app talks to
/// Supabase Auth directly; the backend only handles email-2FA codes and
/// account deletion).
///
/// [currentUser] is non-null ONLY for a "fully verified" session - the
/// same rule the backend enforces server-side: no 2FA enabled, or the
/// session is `aal2` (TOTP), or this `session_id` passed email 2FA
/// (recorded locally by [SecureSessionStorage] and authoritatively in
/// the backend's `email_2fa_verified_sessions` table). A password-only
/// session still awaiting its second factor publishes `null`, so the
/// rest of the app never treats it as signed in.
/// Outcome of [AuthService.verifyRecoveryCode]: the second-factor
/// challenge to run, or [needsTwoFactorSetup] when the recovery session
/// is fully verified but the account has no method (recovery must route
/// to setup).
class RecoveryResult {
  const RecoveryResult({
    required this.requirement,
    required this.needsTwoFactorSetup,
  });
  final SecondFactorRequirement requirement;
  final bool needsTwoFactorSetup;
}

class AuthService {
  AuthService._({
    SecureSessionStorage? storage,
    AccountApiClient? apiClient,
  })  : _storage = storage ?? SecureSessionStorage(),
        _apiClient = apiClient ?? AccountApiClient();

  static AuthService? _instance;

  /// Singleton instance.
  static AuthService get instance => _instance ??= AuthService._();

  /// Replaces the singleton so tests can inject fakes. Only for tests.
  @visibleForTesting
  static void resetForTesting({
    SecureSessionStorage? storage,
    AccountApiClient? apiClient,
  }) {
    _instance = AuthService._(storage: storage, apiClient: apiClient);
  }

  final SecureSessionStorage _storage;
  final AccountApiClient _apiClient;

  bool _initialized = false;
  bool _available = false;

  /// Whether auth is usable - false when [AppConfig] has no Supabase
  /// credentials, in which case every method should be treated as
  /// unreachable by the UI (the Sign In entry point is hidden).
  bool get isAvailable => _available;

  /// Whether any Supabase session exists - including a
  /// half-authenticated (aal1-only, mid 2FA challenge) one where
  /// [currentUser] is still null. Never touches Supabase when auth isn't
  /// available (safe in widget tests).
  bool get hasSession => _available && _auth.currentSession != null;

  final ValueNotifier<User?> _currentUser = ValueNotifier<User?>(null);

  /// The signed-in user, non-null only for a fully verified session (see
  /// class doc).
  ValueListenable<User?> get currentUser => _currentUser;

  /// When true, auth state changes don't republish [currentUser]. Set
  /// for the duration of a delete-account re-auth: `signInWithPassword`
  /// swaps the session (dropping it to `aal1`), which would otherwise
  /// briefly flip the UI to signed-out mid-flow. Cleared by
  /// [completeReauth] or [abandonReauth].
  bool _holdPublishedUser = false;

  StreamSubscription<AuthState>? _authSubscription;

  /// Cancels the auth-state subscription. Only used by tests tearing
  /// down between cases - the app-level singleton lives for the whole
  /// run.
  @visibleForTesting
  Future<void> dispose() async {
    await _authSubscription?.cancel();
    _authSubscription = null;
  }

  GoTrueClient get _auth => Supabase.instance.client.auth;

  /// Initializes Supabase and evaluates any restored session. No-op when
  /// auth isn't configured; never throws - startup must not block on an
  /// auth/ failure (errors go to Crashlytics and the app stays
  /// signed out).
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (!AppConfig.isAuthConfigured) return;

    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabasePublishableKey,
        authOptions: FlutterAuthClientOptions(
          localStorage: _storage,
          // Signup/recovery use in-app 6-digit codes, not deep links.
          detectSessionInUri: false,
        ),
      );
      _authSubscription = _auth.onAuthStateChange.listen(
        (state) => unawaited(_evaluateAndPublish(state.session)),
        onError: (Object error, StackTrace stackTrace) {
          CrashlyticsService.recordError(
            error,
            stackTrace,
            reason: 'AuthService: auth state stream error',
          );
        },
      );

      // Evaluate the restored session (an initialSession event also
      // arrives on the stream, so this may run twice - harmless).
      await _evaluateAndPublish(_auth.currentSession);

      // App killed mid-challenge: a persisted password-only session
      // awaiting its second factor is signed out rather than left
      // half-authenticated.
      if (_auth.currentSession != null && _currentUser.value == null) {
        await _auth.signOut();
      }
      _available = true;
    } catch (error, stackTrace) {
      CrashlyticsService.recordError(
        error,
        stackTrace,
        reason: 'AuthService: initialize failed',
      );
    }
  }

  // ---------------------------------------------------------------------
  // Fully-verified rule (pure, mirrors backend's isFullyVerified).
  // ---------------------------------------------------------------------

  /// Whether the user has at least one second-factor method - required
  /// for every account since two-factor is mandatory.
  @visibleForTesting
  static bool hasAnySecondFactor({
    required bool hasVerifiedTotp,
    required bool emailEnabled,
  }) => hasVerifiedTotp || emailEnabled;

  /// Whether a session counts as "fully verified": the user has no
  /// second factor, or the session reached `aal2` (TOTP), or it passed
  /// email 2FA ([emailSessionVerified]), or the session itself proved
  /// inbox access ([inboxProven] - sign-up confirmation or password
  /// recovery; mirrors the backend's `sessionProvedInbox`).
  ///
  /// With an authenticator, a session that didn't start with the
  /// password ([passwordSession] false - a password-reset session) only
  /// proved the inbox, so it needs `aal2` - same as the backend's rule.
  @visibleForTesting
  static bool isFullyVerified({
    required bool hasVerifiedTotp,
    required bool emailEnabled,
    required String? aal,
    required bool emailSessionVerified,
    bool inboxProven = false,
    bool passwordSession = true,
  }) {
    if (!hasVerifiedTotp && !emailEnabled) return true;
    if (aal == 'aal2') return true;
    if (hasVerifiedTotp && !passwordSession) return false;
    return emailSessionVerified || inboxProven;
  }

  /// The second factor(s) still outstanding for a session described by
  /// the same inputs as [isFullyVerified] - empty when fully verified.
  @visibleForTesting
  static SecondFactorRequirement requirementFor({
    required bool hasVerifiedTotp,
    required bool emailEnabled,
    required String? aal,
    required bool emailSessionVerified,
    bool inboxProven = false,
    bool passwordSession = true,
  }) {
    if (isFullyVerified(
      hasVerifiedTotp: hasVerifiedTotp,
      emailEnabled: emailEnabled,
      aal: aal,
      emailSessionVerified: emailSessionVerified,
      inboxProven: inboxProven,
      passwordSession: passwordSession,
    )) {
      return SecondFactorRequirement.none;
    }
    // An email code can't help a no-password session with an
    // authenticator (it already proved the inbox) - only TOTP can.
    return SecondFactorRequirement(
      totp: hasVerifiedTotp,
      email: emailEnabled && (passwordSession || !hasVerifiedTotp),
    );
  }

  /// Decodes a Supabase access token's JWT payload (base64url, no
  /// signature check - the token came from the SDK). Null on malformed
  /// input.
  static Map<dynamic, dynamic>? _jwtPayload(String accessToken) {
    try {
      final parts = accessToken.split('.');
      if (parts.length < 2) return null;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return payload is Map ? payload : null;
    } catch (_) {
      return null;
    }
  }

  /// Extracts the `session_id` claim from a Supabase access token JWT.
  /// Null on malformed input.
  @visibleForTesting
  static String? sessionIdFromAccessToken(String accessToken) {
    final sessionId = _jwtPayload(accessToken)?['session_id'];
    return sessionId is String ? sessionId : null;
  }

  /// True when the session itself proved inbox access (sign-up
  /// confirmation or password recovery verified a code/link sent to
  /// the inbox) - the same method list as the backend's
  /// `sessionProvedInbox`. Malformed tokens/claims -> false.
  @visibleForTesting
  static bool sessionProvedInbox(String accessToken) {
    const inboxMethods = {'otp', 'email/signup', 'recovery', 'magiclink'};
    final amr = _jwtPayload(accessToken)?['amr'];
    if (amr is! List) return false;
    for (final e in amr) {
      if (e is String && inboxMethods.contains(e)) return true;
      if (e is Map &&
          e['method'] is String &&
          inboxMethods.contains(e['method'])) {
        return true;
      }
    }
    return false;
  }

  /// True when the session started with the password (`amr` has
  /// `password`). Malformed tokens/claims -> false.
  @visibleForTesting
  static bool sessionUsedPassword(String accessToken) {
    final amr = _jwtPayload(accessToken)?['amr'];
    if (amr is! List) return false;
    return amr.any((e) =>
        e == 'password' || (e is Map && e['method'] == 'password'));
  }

  /// `john@domain.com` -> `j***@domain.com` - same masking as the backend.
  static String maskEmail(String email) {
    final at = email.indexOf('@');
    if (at <= 0 || at == email.length - 1) return '***';
    return '${email[0]}***@${email.substring(at + 1)}';
  }

  // ---------------------------------------------------------------------
  // Session evaluation
  // ---------------------------------------------------------------------

  static bool _hasVerifiedTotp(User? user) =>
      _verifiedTotpFactor(user) != null;

  static Factor? _verifiedTotpFactor(User? user) {
    for (final factor in user?.factors ?? const <Factor>[]) {
      if (factor.factorType == FactorType.totp &&
          factor.status == FactorStatus.verified) {
        return factor;
      }
    }
    return null;
  }

  /// Email 2FA is always on for accounts with a confirmed email (same
  /// rule as the backend's `emailFactorOn`).
  static bool _emailFactorOn(User? user) => user?.emailConfirmedAt != null;

  /// Exempt from the second step - only the app-store review account.
  /// `app_metadata` is writable only with the service role / SQL editor,
  /// never by the user; the backend's `skipsTwoFactor` enforces the same
  /// rule server-side (and the website's `rules.ts`).
  @visibleForTesting
  static bool skipsTwoFactor(User? user) =>
      user?.appMetadata['skip_two_factor'] == true;

  /// Computes the second-factor requirement for [session] (null-safe).
  Future<SecondFactorRequirement> _requirement(Session? session) async {
    if (session == null || skipsTwoFactor(session.user)) {
      return SecondFactorRequirement.none;
    }
    final sessionId = sessionIdFromAccessToken(session.accessToken);
    final marked = await _storage.readEmailVerifiedSessionId();
    return requirementFor(
      hasVerifiedTotp: _hasVerifiedTotp(session.user),
      emailEnabled: _emailFactorOn(session.user),
      aal: _auth.mfa.getAuthenticatorAssuranceLevel().currentLevel?.name,
      emailSessionVerified: marked != null && marked == sessionId,
      inboxProven: sessionProvedInbox(session.accessToken),
      passwordSession: sessionUsedPassword(session.accessToken),
    );
  }

  /// Republishes [currentUser] from [session] unless the re-auth hold is
  /// active (see [_holdPublishedUser]).
  Future<void> _evaluateAndPublish(Session? session) async {
    if (_holdPublishedUser) return;
    if (session == null) {
      _currentUser.value = null;
      return;
    }
    final requirement = await _requirement(session);
    if (requirement.isRequired) {
      _currentUser.value = null;
      return;
    }
    // A fully verified session with no second factor still can't publish:
    // two-factor is required, so the UI routes to setup instead.
    _currentUser.value = _hasAnySecondFactor(session.user) ? session.user : null;
    if (_currentUser.value != null) {
      unawaited(registerCurrentDevice());
    }
  }

  /// The `session_id` this device already registered a label for -
  /// [registerCurrentDevice] runs at most once per session.
  String? _registeredDeviceSessionId;

  /// Dedupes concurrent [registerCurrentDevice] calls (token refresh
  /// can republish the user while a registration is still in-flight).
  Future<void>? _deviceRegistration;

  /// Registers this session's readable device label
  /// ("iPhone 16 Pro · iOS 26.1 · v26.11.27") with the backend so the
  /// "Signed-in devices" list can name it. Fire-and-forget from
  /// [_evaluateAndPublish]: at most once per `session_id` (a failed
  /// attempt may run again on the next publish), and every error is
  /// swallowed (never reported to Crashlytics) - a missing label only
  /// means the list shows "Unknown device".
  Future<void> registerCurrentDevice() async {
    try {
      final session = _auth.currentSession;
      final sessionId = session == null
          ? null
          : sessionIdFromAccessToken(session.accessToken);
      if (session == null ||
          sessionId == null ||
          _registeredDeviceSessionId == sessionId ||
          _deviceRegistration != null) {
        return;
      }
      final registration =
          _registerCurrentDeviceInner(session.accessToken, sessionId);
      _deviceRegistration = registration;
      try {
        await registration;
      } finally {
        _deviceRegistration = null;
      }
    } catch (_) {
      // Best-effort by design - see the doc comment.
    }
  }

  Future<void> _registerCurrentDeviceInner(
      String accessToken, String sessionId) async {
    final deviceInfo = DeviceInfoPlugin();
    final String platform;
    final String model;
    final String osVersion;
    if (Platform.isIOS) {
      final ios = await deviceInfo.iosInfo;
      platform = 'ios';
      model = ios.modelName.isNotEmpty ? ios.modelName : ios.model;
      osVersion = ios.systemVersion;
    } else if (Platform.isAndroid) {
      final android = await deviceInfo.androidInfo;
      platform = 'android';
      model = '${android.manufacturer} ${android.model}'.trim();
      osVersion = 'Android ${android.version.release}';
    } else {
      return;
    }
    // Stable install id lets the backend retire older sessions of this
    // same physical device (leftover from reinstalls or re-sign-ins).
    // Uninitialized (e.g. tests) -> just omit it.
    String? deviceId;
    try {
      deviceId = DeviceIdService.instance.deviceId;
    } catch (_) {}
    final appVersion = (await PackageInfo.fromPlatform()).version;
    // The session restored on cold start can carry an already-expired
    // access token (the SDK refreshes it moments later) - the backend
    // then rejects it as `bad_jwt`. Refresh first when it's near expiry.
    await _apiClient.registerSessionDevice(await freshAccessToken(accessToken), {
      'platform': platform,
      'model': model,
      'osVersion': osVersion,
      'appVersion': appVersion,
      'deviceId': ?deviceId,
    });
    // Only a successful registration is remembered - a failed one
    // retries on the next user publish.
    _registeredDeviceSessionId = sessionId;
  }

  bool _hasAnySecondFactor(User? user) => hasAnySecondFactor(
        hasVerifiedTotp: _hasVerifiedTotp(user),
        emailEnabled: _emailFactorOn(user),
      );

  String get _accessToken {
    final token = _auth.currentSession?.accessToken;
    if (token == null) {
      throw const AuthException('No active session', code: 'session_expired');
    }
    return token;
  }

  /// The current session's access token for other backend clients.
  /// Throws `session_expired` like
  /// [_accessToken] when there is no active session.
  String get sessionAccessToken => _accessToken;

  /// [_accessToken], refreshed first when it's expired or about to expire -
  /// every backend call goes through this, since the session restored on
  /// cold start can still carry an expired token (`bad_jwt`).
  Future<String> _freshToken() => freshAccessToken(_accessToken);

  /// Current session access token; refreshed first when it expires within 60s
  /// or [forceRefresh]. Concurrent callers share one refresh.
  Future<String> freshAccessToken(String fallback,
      {bool forceRefresh = false}) async {
    if (_refreshing != null) return _refreshing!;
    Session? session;
    try {
      session = _auth.currentSession;
    } catch (_) {
      return fallback; // Supabase not initialized (tests / unconfigured).
    }
    if (session == null) return fallback;
    final expiresAt = session.expiresAt;
    final fresh = !forceRefresh &&
        (expiresAt == null ||
            expiresAt > DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60);
    if (fresh) return session.accessToken;
    return _refreshToken(fallback);
  }

  Future<String>? _refreshing;

  Future<String> _refreshToken(String fallback) async {
    if (_refreshing != null) return _refreshing!;
    final task = _refreshTokenInner(fallback);
    _refreshing = task;
    try {
      return await task;
    } finally {
      _refreshing = null;
    }
  }

  Future<String> _refreshTokenInner(String fallback) async {
    try {
      final res = await _auth.refreshSession();
      return res.session?.accessToken ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  // ---------------------------------------------------------------------
  // Sign up / sign in / email confirmation
  // ---------------------------------------------------------------------

  /// Email+password sign up with `full_name` saved in user metadata.
  /// Throws [AuthEmailAlreadyRegistered] when Supabase returns its
  /// "already registered" shape (a user object with no identities, which
  /// it uses so the response doesn't reveal the account exists).
  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final response = await _guard('signUp', () {
      return _auth.signUp(
        email: email,
        password: password,
        data: {'full_name': name},
      );
    });
    final identities = response.user?.identities;
    if (identities != null && identities.isEmpty) {
      throw const AuthEmailAlreadyRegistered();
    }
    AnalyticsService.logEvent(name: 'sign_up', parameters: {'method': 'email'});
  }

  /// Password sign-in. Returns [SignInNeedsSecondFactor] when the session
  /// still owes a factor (the UI swaps to the challenge screen), or
  /// [SignInEmailNotConfirmed] after re-sending the confirmation code.
  Future<SignInResult> signIn(String email, String password) async {
    try {
      final response = await _auth.signInWithPassword(
        email: email,
        password: password,
      );
      return await _finishSignIn(response.session);
    } on AuthException catch (error) {
      if (error.code == 'email_not_confirmed') {
        // Resend so the user always has a fresh code waiting on the
        // verify screen.
        try {
          await resendSignupCode(email);
        } catch (_) {
          // Best-effort resend - the verify screen has its own resend.
        }
        return SignInEmailNotConfirmed(email);
      }
      _reportIfUnexpected('signIn', error);
      rethrow;
    }
  }

  /// Shared tail of [signIn]/[verifySignupCode]/[verifyRecoveryCode]-via-
  /// sign-in: evaluates the requirement; publishes the user (and logs
  /// `login`) only when fully verified.
  Future<SignInResult> _finishSignIn(Session? session) async {
    final requirement = await _requirement(session);
    if (requirement.isRequired) {
      return SignInNeedsSecondFactor(
        requirement,
        maskEmail(session?.user.email ?? ''),
      );
    }
    await _evaluateAndPublish(session);
    if (!_hasAnySecondFactor(session?.user)) {
      return const SignInNeedsTwoFactorSetup();
    }
    AnalyticsService.logEvent(name: 'login', parameters: {'method': 'email'});
    return const SignInSuccess();
  }

  /// Verifies the 6-digit signup confirmation code. Tries
  /// [OtpType.email] first, falling back to [OtpType.signup] if the
  /// project rejects that type for signup confirmation.
  Future<SignInResult> verifySignupCode(String email, String code) async {
    AuthResponse response;
    try {
      response = await _auth.verifyOTP(
        type: OtpType.email,
        email: email,
        token: code,
      );
    } on AuthException catch (error) {
      _reportIfUnexpected('verifySignupCode(email)', error);
      response = await _guard('verifySignupCode(signup)', () {
        return _auth.verifyOTP(
          type: OtpType.signup,
          email: email,
          token: code,
        );
      });
    }
    return _finishSignIn(response.session);
  }

  /// Sends a fresh signup-confirmation code (signup OTP, which is also
  /// what the confirmation email contains).
  Future<void> resendSignupCode(String email) async {
    await _guard('resendSignupCode', () {
      return _auth.resend(type: OtpType.signup, email: email);
    });
  }

  // ---------------------------------------------------------------------
  // Password reset
  // ---------------------------------------------------------------------

  /// Emails a 6-digit password-reset code (the project's "Reset
  /// password" template shows `{{ .Token }}`).
  Future<void> sendPasswordResetCode(String email) async {
    await _guard('sendPasswordResetCode', () {
      return _auth.resetPasswordForEmail(email);
    });
  }

  /// Verifies the reset code, which signs the user into a recovery
  /// session. Returns that session's second-factor requirement - when
  /// non-empty the UI runs the challenge before calling
  /// [updatePassword], and [currentUser] stays unpublished.
  Future<RecoveryResult> verifyRecoveryCode(
    String email,
    String code,
  ) async {
    final response = await _guard('verifyRecoveryCode', () {
      return _auth.verifyOTP(
        type: OtpType.recovery,
        email: email,
        token: code,
      );
    });
    final requirement = await _requirement(response.session);
    if (!requirement.isRequired) {
      await _evaluateAndPublish(response.session);
    }
    return RecoveryResult(
      requirement: requirement,
      needsTwoFactorSetup:
          !requirement.isRequired && !_hasAnySecondFactor(response.session?.user),
    );
  }

  /// Sets the new password (password reset or Settings -> Account ->
  /// Change password; the session must already be fully verified, and
  /// `aal2` when an authenticator is set up). Then signs out every
  /// other session, so a device that knew the old password (or stole a
  /// session) is cut off - best-effort, the change itself already
  /// succeeded.
  Future<void> updatePassword(String newPassword) async {
    await _guard('updatePassword', () {
      return _auth.updateUser(UserAttributes(password: newPassword));
    });
    try {
      await _auth.signOut(scope: SignOutScope.others);
    } catch (error, stackTrace) {
      CrashlyticsService.recordError(
        error,
        stackTrace,
        reason: 'AuthService: sign out others after password change',
      );
    }
    AnalyticsService.logEvent(name: 'password_changed');
  }

  // ---------------------------------------------------------------------
  // Second factor
  // ---------------------------------------------------------------------

  /// Verifies a TOTP code against the user's verified factor, raising
  /// the session to `aal2`. Used by the post-sign-in challenge and by
  /// [disableTotp].
  Future<void> verifyTotp(String code) async {
    final factor = _verifiedTotpFactor(_auth.currentUser);
    if (factor == null) {
      throw const AuthException('No verified TOTP factor', code: 'mfa_factor_not_found');
    }
    await _guard('verifyTotp', () {
      return _auth.mfa.challengeAndVerify(factorId: factor.id, code: code);
    });
  }

  /// Asks the backend to email an email-2FA code for [purpose].
  Future<void> sendEmail2faCode(Email2faPurpose purpose) async {
    await _guard('sendEmail2faCode', () async {
      return _apiClient.sendEmail2faCode(await _freshToken(), purpose);
    });
  }

  /// Verifies an emailed code for [purpose]. On a `sign_in` verify the
  /// backend records this `session_id` as verified; the marker is also
  /// written locally so this device stops asking, then the user is
  /// published.
  Future<void> verifyEmail2faCode(Email2faPurpose purpose, String code) async {
    await _guard('verifyEmail2faCode', () async {
      return _apiClient.verifyEmail2faCode(await _freshToken(), purpose, code);
    });
    if (purpose == Email2faPurpose.signIn) {
      final sessionId = sessionIdFromAccessToken(_accessToken);
      if (sessionId != null) {
        await _storage.writeEmailVerifiedSessionId(sessionId);
      }
    }
    if (purpose == Email2faPurpose.signIn) {
      await _evaluateAndPublish(_auth.currentSession);
      AnalyticsService.logEvent(name: 'login', parameters: {'method': 'email'});
    }
  }

  /// Verifies a one-time [code] backup code at the second-factor
  /// challenge (backend endpoint). On success the session is marked
  /// verified server-side and locally, the user is published (respecting
  /// the reauth hold) and the remaining-code count is returned.
  Future<int> verifyBackupCode(String code) async {
    try {
      final remaining = await _guard('verifyBackupCode', () async {
        return _apiClient.verifyBackupCode(await _freshToken(), code);
      });
      final sessionId = sessionIdFromAccessToken(_accessToken);
      if (sessionId != null) {
        await _storage.writeEmailVerifiedSessionId(sessionId);
      }
      if (!_holdPublishedUser) {
        await _evaluateAndPublish(_auth.currentSession);
        AnalyticsService.logEvent(
          name: 'login',
          parameters: {'method': 'backup_code'},
        );
      }
      return remaining;
    } on AccountApiException catch (error) {
      throw BackupCodeApiException(error);
    }
  }

  /// Unused backup-code count (backend `GET /backup-codes`).
  Future<int> backupCodesRemaining() async {
    return _guard('backupCodesRemaining', () async {
      return _apiClient.getBackupCodeCount(await _freshToken());
    });
  }

  /// Generates a fresh set of 10 backup codes (invalidates the old set).
  /// Plaintext codes are returned only here.
  Future<List<String>> generateBackupCodes() async {
    return _guard('generateBackupCodes', () async {
      return _apiClient.generateBackupCodes(await _freshToken());
    });
  }

  /// The user's live sign-in sessions, then the recently signed-out ones
  /// (`endedAt` set; backend `GET /v1/account/sessions`) for the
  /// "Signed-in devices" page.
  Future<List<AccountSession>> listSessions() async {
    final rows = await _guard('listSessions', () async {
      return _apiClient.listSessions(await _freshToken());
    });
    return rows.map(AccountSession.fromJson).toList();
  }

  /// Revokes another device's session (backend `DELETE
  /// /v1/account/sessions/{id}`). Revoking the current session is
  /// rejected server-side - the UI uses [signOut] for that.
  Future<void> revokeSession(String sessionId) async {
    await _guard('revokeSession', () async {
      return _apiClient.revokeSession(await _freshToken(), sessionId);
    });
  }

  /// Signs out every session except this one (Supabase
  /// `signOut(scope: others)`). The backend is told nothing - stale
  /// device labels are filtered out by the list endpoint's join to
  /// `auth.sessions`.
  Future<void> signOutOtherSessions() async {
    await _guard('signOutOtherSessions', () {
      return _auth.signOut(scope: SignOutScope.others);
    });
  }

  /// "Lost my phone": deletes every TOTP factor via the backend's admin
  /// call, then refreshes so `currentUser.factors` is accurate.
  Future<void> resetTotp() async {
    await _guard('resetTotp', () async {
      return _apiClient.resetTotp(await _freshToken());
    });
    await refreshSession();
  }

  /// Lost-phone step of a password reset: the backend checks and
  /// consumes the backup [code] and removes the authenticator, so the
  /// reset session (inbox only, `aal1`) may then set the new password.
  Future<void> resetTotpWithBackupCode(String code) async {
    try {
      await _guard('resetTotpWithBackupCode', () async {
        return _apiClient.resetTotp(await _freshToken(), backupCode: code);
      });
    } on AccountApiException catch (error) {
      throw BackupCodeApiException(error);
    }
    await refreshSession();
    AnalyticsService.logEvent(
      name: 'two_factor_disabled',
      parameters: {'method': 'totp'},
    );
  }

  // ---------------------------------------------------------------------
  // TOTP management
  // ---------------------------------------------------------------------

  /// Enrolls a new unverified TOTP factor with a timestamped friendly
  /// name and returns the factor id, secret and otpauth URI for the
  /// QR/manual step.
  ///
  /// Leftover unverified factors (from abandoned attempts) are only
  /// swept as a fallback when GoTrue rejects the enroll with
  /// `mfa_factor_name_conflict` or `too_many_enrolled_mfa_factors` -
  /// this is the ONLY place they are unenrolled, because every
  /// `mfa.unenroll` triggers Supabase's "Verification method removed"
  /// email. GoTrue itself silently deletes expired unverified factors
  /// on the next enroll.
  Future<TotpEnrollment> _enrollTotp(String label) async {
    Future<TotpEnrollment> enroll() async {
      final response = await _guard(label, () {
        return _auth.mfa.enroll(
          factorType: FactorType.totp,
          issuer: AppConfig.appName,
          // GoTrue rejects duplicate friendly names.
          friendlyName: 'Authenticator ${DateTime.now().millisecondsSinceEpoch}',
        );
      });
      final totp = response.totp;
      if (totp == null) {
        throw const AuthException('Enroll returned no TOTP details', code: 'mfa_enroll_failed');
      }
      return TotpEnrollment(factorId: response.id, secret: totp.secret, uri: totp.uri);
    }

    try {
      return await enroll();
    } on AuthException catch (error) {
      if (error.code != 'mfa_factor_name_conflict' &&
          error.code != 'too_many_enrolled_mfa_factors') {
        rethrow;
      }
      final leftover = _auth.currentUser?.factors
              ?.where(
                (f) => f.factorType == FactorType.totp && f.status != FactorStatus.verified,
              )
              .toList() ??
          const <Factor>[];
      for (final factor in leftover) {
        try {
          await _auth.mfa.unenroll(factor.id);
        } catch (_) {
          // Best-effort - a genuinely stuck factor surfaces as the
          // retry below failing again.
        }
      }
      return enroll();
    }
  }

  /// Starts TOTP enrollment. Returns the factor id, secret and
  /// otpauth URI for the QR/manual step.
  Future<TotpEnrollment> startTotpEnrollment() =>
      _enrollTotp('startTotpEnrollment');

  /// Confirms enrollment by verifying the first authenticator code.
  Future<void> confirmTotpEnrollment(String factorId, String code) async {
    await _guard('confirmTotpEnrollment', () {
      return _auth.mfa.challengeAndVerify(factorId: factorId, code: code);
    });
    await refreshSession();
    AnalyticsService.logEvent(
      name: 'two_factor_enabled',
      parameters: {'method': 'totp'},
    );
  }

  /// Removes the authenticator. With an `aal2` session the verified
  /// factor(s) unenroll directly; with [currentCode] the code is
  /// verified first to reach `aal2`; otherwise (lost phone, signed in
  /// via email/backup code) the backend's admin reset deletes them.
  /// Email codes always remain a second factor, so there is no
  /// last-factor guard any more.
  Future<void> removeTotp({String? currentCode}) async {
    final aal =
        _auth.mfa.getAuthenticatorAssuranceLevel().currentLevel?.name;
    if (aal != 'aal2' && currentCode == null) {
      // No aal2 and no code to prove the authenticator - the backend
      // path is the lost-phone reset. It already deleted the factors
      // server-side, so don't unenroll the (stale) local copies - an
      // aal1 session would be refused.
      await _guard('resetTotp', () async {
        return _apiClient.resetTotp(await _freshToken());
      });
    } else {
      if (aal != 'aal2') await verifyTotp(currentCode!);
      for (final factor in _auth.currentUser?.factors ??
          const <Factor>[]) {
        if (factor.factorType == FactorType.totp &&
            factor.status == FactorStatus.verified) {
          await _guard('removeTotp', () => _auth.mfa.unenroll(factor.id));
        }
      }
    }
    await refreshSession();
    AnalyticsService.logEvent(
      name: 'two_factor_disabled',
      parameters: {'method': 'totp'},
    );
  }

  /// Starts a safe authenticator swap: enrolls a NEW unverified factor
  /// while the old verified one keeps working. Requires `aal2` - either
  /// already reached or via [currentCode] verified with [verifyTotp]
  /// ([TotpCurrentCodeRequired] when neither holds).
  Future<TotpEnrollment> startTotpReplacement({String? currentCode}) async {
    if (_auth.mfa.getAuthenticatorAssuranceLevel().currentLevel?.name !=
        'aal2') {
      if (currentCode == null) {
        throw const TotpCurrentCodeRequired();
      }
      await verifyTotp(currentCode);
    }
    return _enrollTotp('startTotpReplacement');
  }

  /// Confirms the replacement factor from [startTotpReplacement] with
  /// its first code, then unenrolls every OTHER verified TOTP factor
  /// (the session is aal2, so this is allowed) and refreshes.
  Future<void> confirmTotpReplacement(
      String newFactorId, String code) async {
    await _guard('confirmTotpReplacement', () {
      return _auth.mfa.challengeAndVerify(factorId: newFactorId, code: code);
    });
    for (final factor in _auth.currentUser?.factors ??
        const <Factor>[]) {
      if (factor.factorType == FactorType.totp &&
          factor.status == FactorStatus.verified &&
          factor.id != newFactorId) {
        await _guard('confirmTotpReplacement.cleanup',
            () => _auth.mfa.unenroll(factor.id));
      }
    }
    await refreshSession();
    AnalyticsService.logEvent(
      name: 'two_factor_replaced',
      parameters: {'method': 'totp'},
    );
  }

  // ---------------------------------------------------------------------
  // Status / sign out / delete
  // ---------------------------------------------------------------------

  /// Whether the user has a verified TOTP factor enrolled.
  bool get isTotpEnabled => _hasVerifiedTotp(_auth.currentUser);

  /// When the verified TOTP factor was enrolled - the Account page's
  /// "Added 3 Nov 2026" line. Null when no authenticator is set up.
  DateTime? get totpAddedAt =>
      _verifiedTotpFactor(_auth.currentUser)?.createdAt;

  /// Whether the current session already completed a second factor at
  /// the authenticator level (`aal2`) - needed before GoTrue lets us
  /// unenroll or replace a verified TOTP factor.
  bool get isAal2 =>
      _auth.mfa.getAuthenticatorAssuranceLevel().currentLevel?.name ==
      'aal2';

  /// Whether email codes are an active second factor - always true for
  /// a confirmed email (there is no opt-in any more).
  bool get isEmail2faEnabled => _emailFactorOn(_auth.currentUser);

  /// Re-fetches the session/user from Supabase (e.g. after
  /// `app_metadata` changed server-side) and republishes.
  Future<void> refreshSession() async {
    await _guard('refreshSession', () => _auth.refreshSession());
  }

  /// Refresh alias for screens that just want fresh user data.
  Future<void> refreshUser() => refreshSession();

  /// Re-authenticates with [password] ahead of a destructive action.
  /// Holds [currentUser] steady while the session is swapped (see
  /// [_holdPublishedUser]); returns the new session's second-factor
  /// requirement for the UI's challenge step.
  Future<SecondFactorRequirement> reauthenticate(String password) async {
    _holdPublishedUser = true;
    try {
      final email = _auth.currentUser?.email;
      if (email == null) {
        throw const AuthException('No signed-in user', code: 'session_expired');
      }
      await _guard('reauthenticate', () {
        return _auth.signInWithPassword(email: email, password: password);
      });
      return await _requirement(_auth.currentSession);
    } catch (_) {
      // Keep the hold - the caller either retries or abandons; a failed
      // password attempt left the session unchanged anyway.
      rethrow;
    }
  }

  /// Keeps [currentUser] published while a factor is swapped out -
  /// call [endFactorChange] when the swap finishes (or is abandoned).
  /// Without this, deleting the only remaining factor mid-flow would
  /// unpublish the user and tear down the screen doing the work.
  void beginFactorChange() {
    _holdPublishedUser = true;
  }

  /// Ends a [beginFactorChange] hold and republishes the user.
  Future<void> endFactorChange() async {
    _holdPublishedUser = false;
    await _evaluateAndPublish(_auth.currentSession);
  }

  /// Ends a successful re-auth hold and republishes the user.
  Future<void> completeReauth() => endFactorChange();

  /// Abandons a re-auth flow. The old session's refresh token was
  /// replaced by the re-auth `signInWithPassword`, so the only safe
  /// state left is signed out.
  Future<void> abandonReauth() async {
    _holdPublishedUser = false;
    await signOut();
  }

  /// Deletes the account via the backend (which enforces the
  /// fully-verified + recent-reauth rules), then signs out locally.
  Future<void> deleteAccount() async {
    await _guard('deleteAccount', () async {
      return _apiClient.deleteAccount(await _freshToken());
    });
    _holdPublishedUser = false;
    await _storage.clearEmailVerifiedSessionId();
    await _auth.signOut();
  }

  /// Signs out and clears the local email-2FA marker.
  Future<void> signOut() async {
    _holdPublishedUser = false;
    await _storage.clearEmailVerifiedSessionId();
    try {
      await _auth.signOut();
    } catch (_) {
      // Local persistence is already cleared by signOut's own path;
      // a remote sign-out failure shouldn't trap the UI.
    }
    _currentUser.value = null;
  }

  // ---------------------------------------------------------------------
  // Error handling
  // ---------------------------------------------------------------------

  /// Runs [call], reporting unexpected failures to Crashlytics before
  /// rethrowing. User-caused errors (wrong password, invalid code) are
  /// rethrown quietly via [_isExpectedError].
  Future<T> _guard<T>(String operation, Future<T> Function() call) async {
    try {
      return await call();
    } catch (error, stackTrace) {
      _reportIfUnexpected(operation, error, stackTrace);
      rethrow;
    }
  }

  void _reportIfUnexpected(
    String operation,
    Object error, [
    StackTrace? stackTrace,
  ]) {
    if (_isExpectedError(error)) return;
    CrashlyticsService.recordError(
      error,
      stackTrace ?? StackTrace.current,
      reason: 'AuthService: $operation failed',
    );
  }

  /// Errors the user caused and can fix - wrong credentials, bad/expired
  /// codes, rate limits, backend precondition errors. Not worth a
  /// Crashlytics report.
  static bool _isExpectedError(Object error) {
    if (error is AuthEmailAlreadyRegistered) return true;
    if (error is LastSecondFactorException) return true;
    if (error is BackupCodeApiException) return true;
    if (error is AccountApiException) return true;
    if (error is AuthRetryableFetchException) return true;
    if (error is AuthException) {
      // User-facing failures always carry a `code`; a server-side 5xx or
      // a codeless exception is an infra problem worth reporting.
      if (error.code == null) return false;
      final status = int.tryParse(error.statusCode ?? '');
      return status == null || status < 500;
    }
    return false;
  }

  static String _messageForApi(AccountApiException error) {
    switch (error.errorCode) {
      case 'invalid_code':
        return 'That code isn\'t correct. Check the email and try again.';
      case 'code_expired':
        return 'That code has expired. Send a new one and try again.';
      case 'too_many_attempts':
        return 'Too many attempts. Send a new code and try again.';
      case 'rate_limited':
        final retry = error.retryAfter;
        return retry != null
            ? 'Please wait $retry seconds before requesting another code.'
            : 'Too many codes sent. Please try again later.';
      case 'second_factor_required':
        return 'Please complete two-factor verification first.';
      case 'reauth_required':
        return 'Please confirm your password again to continue.';
      case 'email_2fa_always_on':
        return 'Email verification is always on for this account. Please update the app.';
      case 'email_not_confirmed':
        return 'Confirm your email address first.';
      case 'no_second_factor':
        return 'Set up two-factor verification first.';
      case 'last_second_factor':
        return 'You need at least one two-factor method. Turn on another method first.';
      case 'sole_owner':
        return 'You\'re the only owner of a managed resource. Transfer ownership before deleting your account.';
      case 'totp_reset_failed':
        return 'Couldn\'t remove the authenticator app. Please try again.';
      case 'cannot_revoke_current':
        return 'Use Sign out to sign out of this device.';
      case 'not_found':
        return 'That device is no longer signed in.';
      case 'email_send_failed':
      case 'delete_failed':
      case 'flag_update_failed':
        return 'Something went wrong on our side. Please try again.';
      default:
        if (error.statusCode == 401) {
          return 'Your session has expired. Please sign in again.';
        }
        return 'Something went wrong. Please try again.';
    }
  }

  /// Maps an error thrown anywhere in this service to user-facing copy.
  /// Pure/static so it's unit-testable.
  static String messageFor(Object error) {
    if (error is LastSecondFactorException) {
      return 'You need at least one two-factor method. Turn on another method first.';
    }
    if (error is BackupCodeApiException) {
      return error.inner.errorCode == 'invalid_code'
          ? 'That backup code isn\'t valid or has already been used.'
          : _messageForApi(error.inner);
    }
    if (error is AuthEmailAlreadyRegistered) {
      return 'An account with this email already exists. Try signing in instead.';
    }
    if (error is AccountApiException) {
      return _messageForApi(error);
    }
    if (error is AccountApiTimeoutException ||
        error is AuthRetryableFetchException ||
        error is SocketException ||
        error is TimeoutException) {
      return 'No internet connection. Check your connection and try again.';
    }
    if (error is AuthException) {
      switch (error.code) {
        case 'invalid_credentials':
          return 'Incorrect email or password.';
        case 'email_not_confirmed':
          return 'Please confirm your email first - we\'ve sent you a new code.';
        case 'user_already_exists':
        case 'email_exists':
          return 'An account with this email already exists. Try signing in instead.';
        case 'weak_password':
          return 'That password is too weak. Please choose a stronger one.';
        case 'same_password':
          return 'New password must be different from the current one.';
        case 'otp_expired':
          return 'That code has expired. Send a new one and try again.';
        case 'over_email_send_rate_limit':
        case 'over_request_rate_limit':
          return 'Too many attempts. Please wait a moment and try again.';
        case 'mfa_verification_failed':
          return 'That code isn\'t correct. Check your authenticator app and try again.';
        case 'mfa_challenge_expired':
          return 'That code has expired. Please try again.';
        case 'mfa_factor_name_conflict':
          return 'An authenticator is already set up. Remove it first or try again.';
        case 'session_expired':
          return 'Your session has expired. Please sign in again.';
        default:
          return error.message;
      }
    }
    return 'Something went wrong. Please try again.';
  }
}
