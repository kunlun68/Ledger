import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'application/providers.dart';
import 'core/date_util.dart';
import 'data/dao/categories_dao.dart';
import 'data/dao/recurring_dao.dart';
import 'data/database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final db = AppDatabase.open();
    await CategoriesDao(db).seedBuiltinCategories();
    await RecurringDao(db).generateDue(yyyymmOf(todayYyyymmdd()));
    runApp(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const LedgerApp(),
    ));
  } catch (e) {
    // 数据库初始化失败时兜底：显示错误页而非崩溃白屏
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('数据库初始化失败：$e'),
          ),
        ),
      ),
    ));
  }
}
