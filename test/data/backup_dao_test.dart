import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:ledger/data/dao/backup_dao.dart';
import 'package:ledger/data/dao/categories_dao.dart';
import 'package:ledger/data/dao/transactions_dao.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/data/transaction_type.dart';

void main() {
  late AppDatabase db;
  late BackupDao dao;

  setUp(() {
    db = AppDatabase.open(executor: NativeDatabase.memory());
    dao = BackupDao(db);
  });
  tearDown(() => db.close());

  test('exportAll returns seeded data', () async {
    await CategoriesDao(db).seedBuiltinCategories();
    final cats = await CategoriesDao(db).getByType(TxType.expense);
    await TransactionsDao(db)
        .insertTransaction(TxType.expense, 100, cats.first.id, 20260813, '午饭');
    final all = await dao.exportAll();
    expect(all.categories, hasLength(11));
    expect(all.transactions, hasLength(1));
    expect(all.transactions.single.note, '午饭');
  });

  test('restoreAll replaces everything preserving ids', () async {
    await CategoriesDao(db).seedBuiltinCategories();
    final backup = await dao.exportAll();
    // 备份后再加一条，恢复应将其清掉
    await TransactionsDao(db)
        .insertTransaction(TxType.expense, 999, backup.categories.first.id, 20260813, '要消失');
    await dao.restoreAll(categories: backup.categories, transactions: backup.transactions);
    final after = await dao.exportAll();
    expect(after.transactions.any((t) => t.note == '要消失'), isFalse);
    expect(after.categories.map((c) => c.id).toSet(), backup.categories.map((c) => c.id).toSet());
  });

  test('restoreAll rolls back on failure (duplicate ids)', () async {
    await CategoriesDao(db).seedBuiltinCategories();
    final backup = await dao.exportAll();
    await TransactionsDao(db)
        .insertTransaction(TxType.expense, 999, backup.categories.first.id, 20260813, '保留我');
    // 构造主键冲突：两个分类同 id
    final bad = [...backup.categories, backup.categories.first];
    await expectLater(
        dao.restoreAll(categories: bad, transactions: backup.transactions), throwsA(anything));
    final after = await dao.exportAll();
    expect(after.transactions.any((t) => t.note == '保留我'), isTrue);
  });
}
