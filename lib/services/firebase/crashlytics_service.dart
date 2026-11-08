import 'dart:developer';

import 'package:flutter/foundation.dart';

/// Placeholder crash/error sink. Auth code calls [recordError] for
/// unexpected failures; errors are logged locally for now. Wire this to
/// Crashlytics (or another provider) when the crash-reporting stack
/// lands.
class CrashlyticsService {
  CrashlyticsService._();

  /// Call once during app initialization.
  static void initialize() {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      recordError(details.exception, details.stack,
          reason: 'FlutterError: ${details.context}');
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      recordError(error, stack, reason: 'Uncaught async error');
      return true;
    };
  }

  /// Reports a caught (non-fatal) error/exception. Never throws -
  /// callers treat this as a fire-and-forget sink.
  static void recordError(Object error, StackTrace? stack, {String? reason}) {
    log(
      'CrashlyticsService.recordError (reason: $reason): $error',
      name: 'CrashlyticsService',
      error: error,
      stackTrace: stack,
    );
  }
}
