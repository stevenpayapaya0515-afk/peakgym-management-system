import 'dart:async';

import 'package:flutter/material.dart';

import 'core/services/api_service.dart';
import 'core/storage/token_storage.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/idle_session_guard.dart';
import 'screens/admin/admin_dashboard.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/staff/staff_dashboard.dart';

void main() {
  runApp(const PeakGymApp());
}

class PeakGymApp extends StatelessWidget {
  const PeakGymApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Email invitation links use /register?invite=... on Flutter Web.
    // The URL token stays in memory; it is not logged or displayed.
    final uri = Uri.base;
    final register = uri.path == '/register';
    return MaterialApp(
      title: 'PeakGym Management System',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: register
          ? RegisterScreen(invitationToken: uri.queryParameters['invite'] ?? '')
          : const _SessionStartup(),
    );
  }
}

/// Restore an authenticated session when Flutter Web reloads (F5 / Ctrl+R).
/// Web relies on the HttpOnly cookie; native Flutter still uses its saved JWT.
/// Only the backend can decide if the session is still valid.
class _SessionStartup extends StatefulWidget {
  const _SessionStartup();

  @override
  State<_SessionStartup> createState() => _SessionStartupState();
}

class _SessionStartupState extends State<_SessionStartup> {
  late Future<Widget> _destination;

  @override
  void initState() {
    super.initState();
    _destination = _restoreSession();
  }

  Future<Widget> _restoreSession() async {
    final token = await TokenStorage.getToken();
    if (!TokenStorage.usesCookieSession && (token == null || token.isEmpty)) {
      return const LoginScreen();
    }

    final response = await ApiService.get('/auth/me', token: token)
        .timeout(const Duration(seconds: 12));
    final status = response['status_code'];
    if (status == 401 || status == 403) {
      // No valid session. Do not fabricate or restore an expired login.
      if (!TokenStorage.usesCookieSession) {
        await TokenStorage.deleteToken();
      }
      return const LoginScreen();
    }
    if (status != 200) {
      throw StateError('Unable to verify the current session.');
    }

    final role = response['role']?.toString().trim().toLowerCase();
    final Widget dashboard;
    if (role == 'admin') {
      dashboard = const AdminDashboard();
    } else if (role == 'staff') {
      dashboard = const StaffDashboard();
    } else {
      throw StateError('Unknown account role.');
    }

    final idleSeconds = (response['idle_timeout_seconds'] as num?)?.toInt() ?? 480;
    final warningSeconds = (response['warning_before_seconds'] as num?)?.toInt() ?? 60;
    return IdleSessionGuard(
      idleTimeoutSeconds: idleSeconds,
      warningBeforeSeconds: warningSeconds,
      child: dashboard,
    );
  }

  void _retry() {
    setState(() => _destination = _restoreSession());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _destination,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppTheme.primaryGreen),
            ),
          );
        }
        if (snapshot.hasData) return snapshot.data!;
        // A network/server error is not proof that the session expired.
        // Preserve the cookie and allow a retry rather than forcing re-login.
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off_outlined,
                      size: 40, color: AppTheme.secondaryText),
                  const SizedBox(height: 16),
                  const Text(
                    'Unable to verify your session',
                    style: TextStyle(
                      color: AppTheme.primaryText,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Check the backend connection, then try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.secondaryText),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _retry,
                    child: const Text('RETRY'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
