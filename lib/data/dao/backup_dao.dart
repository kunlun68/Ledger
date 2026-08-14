import 'package:drift/drift.dart';
import '../database.dart';

/// 备份/恢复的数据访问：取全量 + 单事务全量替换。
class BackupDao {
  BackupDao(this.db);
  final AppDatabase db;

  Future<({List<Category> categories, List<Transaction> transactions, List<Account> accounts})>
      exportAll() async {
    final categories = await (db.select(db.categories)
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder), (t) => OrderingTerm.asc(t.id)]))
        .get();
    final transactions = await (db.select(db.transactions)
          ..orderBy([(t) => OrderingTerm.desc(t.date), (t) => OrderingTerm.desc(t.id)]))
        .get();
    final accounts = await (db.select(db.accounts)
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder), (t) => OrderingTerm.asc(t.id)]))
        .get();
    return (categories: categories, transactions: transactions, accounts: accounts);
  }

  /// 全量替换：单事务，任一步失败整体回滚。保留备份中的原始 id。
  Future<void> restoreAll(
      {required List<Category> categories, required List<Transaction> transactions}) {
    return db.transaction(() async {
      await (db.delete(db.transactions)).go();
      await (db.delete(db.categories)).go();
      for (final c in categories) {
        await db.into(db.categories).insert(CategoriesCompanion.insert(
              id: Value(c.id),
              name: c.name,
              icon: c.icon,
              type: c.type,
              sortOrder: Value(c.sortOrder),
              isBuiltin: Value(c.isBuiltin),
            ));
      }
      for (final t in transactions) {
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: Value(t.id),
              type: t.type,
              amountCents: t.amountCents,
              categoryId: Value(t.categoryId),
              accountId: Value(t.accountId),
              transferAccountId: Value(t.transferAccountId),
              note: Value(t.note),
              date: t.date,
              createdAt: Value(t.createdAt),
              updatedAt: Value(t.updatedAt),
            ));
      }
    });
  }
}
