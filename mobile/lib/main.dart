import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Android reads its Firebase configuration from android/app/google-services.json
  // (created by `flutterfire configure`).
  await Firebase.initializeApp();
  runApp(const ProviderScope(child: SaibaanConnectApp()));
}
