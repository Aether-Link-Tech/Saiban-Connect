import 'package:flutter/material.dart';

class SaibaanConnectApp extends StatelessWidget {
  const SaibaanConnectApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SAIBAAN Connect',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF168B52),
        primary: const Color(0xFF142B5A),
      ),
      useMaterial3: true,
    ),
    home: const Scaffold(
      body: Center(child: Text('SAIBAAN Connect — implementation scaffold')),
    ),
  );
}
