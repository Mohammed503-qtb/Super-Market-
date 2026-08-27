import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../application/providers/auth_provider.dart';
import 'auth/login_screen.dart';
import 'dashboard/main_shell.dart';

/// الهيكل العام للتطبيق - يحدد ما إذا كان المستخدم مسجل دخول أم لا
class AppShell extends StatelessWidget {
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;

  const AppShell({
    super.key,
    required this.themeMode,
    required this.onToggleTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        // إذا لم يكن مسجل دخول، اعرض شاشة الدخول
        if (!auth.isAuthenticated) {
          return LoginScreen(themeMode: themeMode, onToggleTheme: onToggleTheme);
        }
        return MainShell(
          themeMode: themeMode,
          onToggleTheme: onToggleTheme,
        );
      },
    );
  }
}
