import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:ledger/data/database.dart';

void main() {
  test('migration from v1 keeps data and adds monthlyBudgetCents', () async {
    final dir = Directory.systemTemp.createTempSync('ledger_migration');
    final file = File('${dir.path}${Platform.pathSeparator}test.db');
    addTearDown(() {
      dir.deleteSync(recursive: true);
    });

    // 1) 手写 v1 schema（无 monthlyBudgetCents）并插入一行，标记 user_version = 1
    final v1 = AppDatabase.open(executor: NativeDatabase(file));
    await v1.customStatement('DROP TABLE IF EXISTS transactions');
    await v1.customStatement('DROP TABLE IF EXISTS categories');
    await v1.customStatement('''
CREATE TABLE categories (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  icon TEXT NOT NULL,
  type TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_builtin INTEGER NOT NULL DEFAULT 0
)''');
    await v1.customStatement('''
CREATE TABLE transactions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  type TEXT NOT NULL,
  amount_cents INTEGER NOT NULL,
  category_id INTEGER NOT NULL REFERENCES categories(id),
  note TEXT NOT NULL DEFAULT '',
  date INTEGER NOT NULL,
  created_at INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL DEFAULT 0
)''');
    await v1.customStatement(
        "INSERT INTO categories (name, icon, type, sort_order, is_builtin) "
        "VALUES ('餐饮', 'restaurant', 'expense', 0, 1)");
    await v1.customStatement('PRAGMA user_version = 1');
    await v1.close();

    // 2) 用当前代码（v2）重新打开，触发 onUpgrade
    final db = AppDatabase.open(executor: NativeDatabase(file));
    addTearDown(db.close);
    final cats = await db.select(db.categories).get();
    expect(cats, hasLength(1));
    expect(cats.single.name, '餐饮');
    expect(cats.single.monthlyBudgetCents, 0); // 新列默认 0
    expect(await db.select(db.transactions).get(), isEmpty);
  });
}
