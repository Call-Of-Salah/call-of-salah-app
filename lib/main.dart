import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'screens/auth/change_password_screen.dart';
import 'screens/auth/login_screen.dart';
import 'services/auth/auth_service.dart';
import 'services/device/device_id_service.dart';
import 'services/firebase/analytics_service.dart';
import 'services/firebase/crashlytics_service.dart';
import 'widgets/app_feedback.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Route uncaught Flutter/async errors to the crash sink (placeholder -
  // see services/firebase/crashlytics_service.dart).
  CrashlyticsService.initialize();

  // Fire-and-forget analytics (placeholder - debugPrint only for now).
  AnalyticsService.initialize();

  // Initialize Supabase auth (no-op until AppConfig's Supabase
  // credentials are filled in) and evaluate any restored session.
  await AuthService.instance.initialize();

  // Resolve this installation's id, sent with account API calls that
  // register this device (see AuthService.registerCurrentDevice).
  await DeviceIdService.instance.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

/// Shows [LoginScreen] while signed out and a placeholder home once
/// [AuthService.currentUser] publishes a fully-verified user. The auth
/// screens' `finishAuthFlow` pops to the first route and relies on this
/// rebuild to swap in the home screen.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<User?>(
      valueListenable: AuthService.instance.currentUser,
      builder: (context, user, _) {
        if (user == null) return const LoginScreen();
        return _SignedInHome(user: user);
      },
    );
  }
}

/// Placeholder home shown to a signed-in user - replace with the real
/// app shell. Includes a couple of account entries so the auth
/// screens are reachable end-to-end.
class _SignedInHome extends StatelessWidget {
  const _SignedInHome({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(AppConfig.appName)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Signed in as',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              user.email ?? '',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ChangePasswordScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.lock_outline),
              label: const Text('Change password'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                await AuthService.instance.signOut();
                if (!context.mounted) return;
                AppFeedback.showSnackBar(
                  context,
                  'Signed out',
                  isError: false,
                );
              },
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
