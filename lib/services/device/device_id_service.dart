import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../firebase/crashlytics_service.dart';

/// Resolves and persists an identifier for this app installation. Sent
/// with account API requests (device registration) so the backend can
/// attribute/rate-limit per-installation without any user-identifying
/// information.
///
/// Deliberately resolved so it **survives** the user deleting and
/// re-downloading the app - unlike plain SharedPreferences, which is wiped
/// on uninstall on both platforms (this used to just be a SharedPreferences
/// UUID, which reset on every reinstall):
/// - Android: [Settings.Secure.ANDROID_ID] (fetched via [_channel]), stable
///   per (app signing key + user + device) since Android 8 - survives an
///   uninstall/reinstall of the app without depending on Auto Backup/cloud
///   restore timing. Falls back to a SharedPreferences-persisted UUID (the
///   old behavior) if the platform channel is ever unavailable.
/// - iOS (and any other platform): a UUID persisted in the Keychain via
///   `flutter_secure_storage`, which - unlike `NSUserDefaults`/
///   SharedPreferences - is not cleared when the app is uninstalled.
class DeviceIdService {
  DeviceIdService._({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const String _prefKey = 'device_install_uuid';
  static const String _secureStorageKey = 'device_install_uuid';
  // Native side isn't wired up in this app yet - the channel call fails
  // and [_resolveAndroidId] falls back to the SharedPreferences UUID.
  // Add a `getAndroidId` handler in MainActivity if ANDROID_ID-based
  // stability across reinstalls is needed here too.
  static const MethodChannel _channel = MethodChannel(
    'app.callofsalah/device_id',
  );

  static DeviceIdService? _instance;

  /// Singleton instance.
  static DeviceIdService get instance => _instance ??= DeviceIdService._();

  /// Replaces the singleton with a fresh, uninitialized instance so tests
  /// can inject a fake [secureStorage] and don't leak `_deviceId` state
  /// between test cases. Only for tests.
  @visibleForTesting
  static void resetForTesting({FlutterSecureStorage? secureStorage}) {
    _instance = DeviceIdService._(secureStorage: secureStorage);
  }

  final FlutterSecureStorage _secureStorage;

  String? _deviceId;

  /// Resolves and caches the installation id (see class doc for how, per
  /// platform), generating/migrating one if needed. Must be awaited during
  /// app startup (see `main.dart`) before [deviceId] is read.
  Future<void> initialize() async {
    if (_deviceId != null) return;
    _deviceId = Platform.isAndroid
        ? await _resolveAndroidId()
        : await _resolveKeychainId();
  }

  /// Prefers the native `ANDROID_ID`; falls back to the legacy
  /// SharedPreferences UUID if the platform channel call fails for any
  /// reason (e.g. running on an unsupported embedder).
  Future<String> _resolveAndroidId() async {
    try {
      final androidId = await _channel.invokeMethod<String>('getAndroidId');
      if (androidId != null && androidId.isNotEmpty) {
        return androidId;
      }
    } catch (error, stackTrace) {
      CrashlyticsService.recordError(
        error,
        stackTrace,
        reason: 'DeviceIdService: Error fetching ANDROID_ID, falling back to SharedPreferences UUID',
      );
    }
    return _resolveLegacySharedPreferencesId();
  }

  /// Reads (or generates) the Keychain-persisted UUID. A pre-existing
  /// SharedPreferences value (from before this Keychain migration) is
  /// reused as the seed rather than discarded, so already-installed users
  /// don't have their id change out from under them the first time this
  /// runs.
  Future<String> _resolveKeychainId() async {
    try {
      final existing = await _secureStorage.read(key: _secureStorageKey);
      if (existing != null && existing.isNotEmpty) {
        return existing;
      }

      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(_prefKey);
      final id = (legacy != null && legacy.isNotEmpty)
          ? legacy
          : const Uuid().v4();

      await _secureStorage.write(key: _secureStorageKey, value: id);
      return id;
    } catch (error, stackTrace) {
      // Secure storage unavailable for some reason - fall back to the
      // previous SharedPreferences-only behavior (won't survive reinstall).
      CrashlyticsService.recordError(
        error,
        stackTrace,
        reason: 'DeviceIdService: Error reading/writing Keychain id, falling back to SharedPreferences UUID',
      );
      return _resolveLegacySharedPreferencesId();
    }
  }

  Future<String> _resolveLegacySharedPreferencesId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_prefKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final generated = const Uuid().v4();
    await prefs.setString(_prefKey, generated);
    return generated;
  }

  /// The persisted installation UUID. Only valid after [initialize] has
  /// completed.
  ///
  /// Throws a [StateError] (in every build mode, not just debug) if read
  /// before [initialize] has completed, rather than silently returning an
  /// empty string - callers depend on this being a real, unique value.
  String get deviceId {
    final id = _deviceId;
    if (id == null) {
      throw StateError('DeviceIdService.initialize() must be awaited first');
    }
    return id;
  }
}
