/// One sign-in session as returned by the backend's
/// `GET /v1/account/sessions` (see docs/backend-api-contract.md) - live,
/// or recently signed out when [AccountSession.endedAt] is set.
/// IPs and raw user agents are never sent - [device] carries only the
/// readable label the app itself registered for that session.
class AccountSessionDevice {
  const AccountSessionDevice({
    required this.platform,
    required this.model,
    required this.osVersion,
    required this.appVersion,
  });

  factory AccountSessionDevice.fromJson(Map<String, dynamic> json) =>
      AccountSessionDevice(
        platform: json['platform'] as String? ?? '',
        model: json['model'] as String? ?? '',
        osVersion: json['osVersion'] as String? ?? '',
        appVersion: json['appVersion'] as String? ?? '',
      );

  final String platform;
  final String model;
  final String osVersion;
  final String appVersion;

  /// "iPhone 16 Pro · iOS 26.1 · v26.11.27" /
  /// "Pixel 9 · Android 16 · v26.11.27" /
  /// "Chrome on macOS · Web · v26.11.52" (the website sends `Web` as
  /// its osVersion).
  String get label {
    final os = platform == 'ios' ? 'iOS $osVersion' : osVersion;
    return '$model · $os · v$appVersion';
  }
}

class AccountSession {
  const AccountSession({
    required this.id,
    required this.isCurrent,
    required this.createdAt,
    required this.lastActiveAt,
    this.device,
    this.endedAt,
  });

  factory AccountSession.fromJson(Map<String, dynamic> json) {
    final device = json['device'];
    final endedAt = DateTime.tryParse(json['endedAt'] as String? ?? '');
    return AccountSession(
      id: json['id'] as String? ?? '',
      isCurrent: json['current'] == true,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
      lastActiveAt:
          DateTime.tryParse(json['lastActiveAt'] as String? ?? '') ??
              endedAt ??
              DateTime.fromMillisecondsSinceEpoch(0),
      device: device is Map
          ? AccountSessionDevice.fromJson(
              Map<String, dynamic>.from(device))
          : null,
      endedAt: endedAt,
    );
  }

  final String id;
  final bool isCurrent;
  final DateTime createdAt;
  final DateTime lastActiveAt;
  final AccountSessionDevice? device;

  /// When the session was signed out/revoked/expired - null for live
  /// sessions. Ended sessions are listed for 30 days, read-only.
  final DateTime? endedAt;

  bool get isActive => endedAt == null;

  /// This session as signed out at [at] (a local revoke, before the
  /// next fetch).
  AccountSession endedAtTime(DateTime at) => AccountSession(
        id: id,
        isCurrent: false,
        createdAt: createdAt,
        lastActiveAt: lastActiveAt,
        device: device,
        endedAt: at,
      );

  /// The registered label, or "Unknown device" for sessions that never
  /// registered one (older app versions).
  String get deviceLabel => device?.label ?? 'Unknown device';
}
