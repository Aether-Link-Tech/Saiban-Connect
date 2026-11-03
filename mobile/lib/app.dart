import 'package:flutter/material.dart';

import 'core/constants/app_constants.dart';
import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/screens/auth_gate.dart';

class SaibaanConnectApp extends StatelessWidget {
  const SaibaanConnectApp({super.key, this.home});

  /// Overridable for widget tests.
  final Widget? home;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: scaffoldMessengerKey,
        theme: AppTheme.light(),
        home: home ?? const AuthGate(),
      );
}
