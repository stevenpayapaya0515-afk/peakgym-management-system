import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';

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
          : const LoginScreen(),
    );
  }
}
