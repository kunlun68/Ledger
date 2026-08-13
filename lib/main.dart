import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'application/providers.dart';
import 'data/dao/categories_dao.dart';
import 'data/database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase.open();
  await CategoriesDao(db).seedBuiltinCategories();
  runApp(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const LedgerApp(),
  ));
}
