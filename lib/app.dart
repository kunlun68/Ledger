import 'package:flutter/material.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/theme/app_theme.dart';

class LedgerApp extends StatelessWidget {
  const LedgerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '记账',
        theme: AppTheme.light,
        home: const HomeScreen(),
      );
}
