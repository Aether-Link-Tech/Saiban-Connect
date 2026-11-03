import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Run `flutterfire configure` and initialize with generated platform options.
  await Firebase.initializeApp();
  runApp(const SaibaanConnectApp());
}
