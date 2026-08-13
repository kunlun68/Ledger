import 'package:flutter/material.dart';

class AppTheme {
  static const expenseColor = Color(0xFFE53935); // 支出红
  static const incomeColor = Color(0xFF43A047); // 收入绿

  static ThemeData get light => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E88E5)),
        useMaterial3: true,
      );
}
