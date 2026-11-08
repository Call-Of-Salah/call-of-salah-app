import 'package:flutter/foundation.dart';

/// Placeholder analytics sink. Auth code calls [logEvent] for
/// sign-up/login/2FA events; events are debug-printed in debug builds.
/// Wire this to Firebase Analytics (or another provider) when the
/// analytics stack lands.
class AnalyticsService {
  AnalyticsService._();

  static bool _initialized = false;

  /// Call once during app initialization.
  static void initialize() {
    _initialized = true;
  }

  static void logAppOpen() {
    logEvent(name: 'app_open', parameters: {'app_repository': 'call_of_salah'});
  }

  static void logEvent({
    required String name,
    Map<String, Object>? parameters,
  }) {
    assert(_initialized, 'AnalyticsService.initialize() not called');
    if (kDebugMode) {
      debugPrint('Analytics: $name $parameters');
    }
  }
}
