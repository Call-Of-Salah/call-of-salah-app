import 'package:http/http.dart' as http;

/// Builds the [http.Client] used by the account API client.
///
/// Plain `package:http` for now. If the app ever needs requests to
/// traverse OS/enterprise-configured proxies (PAC file, manual proxy,
/// MDM-pushed config) the way native networking APIs do, route through
/// each platform's native stack instead (`cupertino_http` on
/// iOS/macOS, `cronet_http` on Android).
http.Client createPlatformHttpClient() {
  return http.Client();
}
