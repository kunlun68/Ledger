import 'package:drift/drift.dart';
import '../../core/stats.dart';
import '../database.dart';

/// 删除被交易或转账引用的账户时抛出
class AccountInUseException implements Exception {}

class AccountsDao {
  AccountsDao(this.db);
  final AppDatabase db;

  Future<void> insertAccount(String name, String icon) =>
      db.into(db.accounts).insert(AccountsCompanion.insert(name: name, icon: icon));

  Future<void> deleteAccount(Account a) async {
    final used = await (db.select(db.transactions)
          ..where((t) => t.accountId.equals(a.id) | t.transferAccountId.equals(a.id)))
        .get();
    if (used.isNotEmpty) throw AccountInUseException();
    // 周期规则也引用账户（生成交易时写入），一并保护
    final rules = await (db.select(db.recurringRules)
          ..where((t) => t.accountId.equals(a.id)))
        .get();
    if (rules.isNotEmpty) throw AccountInUseException();
    await (db.delete(db.accounts)..where((t) => t.id.equals(a.id))).go();
  }

  Stream<List<Account>> watchAll() => (db.select(db.accounts)
        ..orderBy([(t) => OrderingTerm.asc(t.sortOrder), (t) => OrderingTerm.asc(t.id)]))
      .watch();

  Future<int> balanceOf(int accountId) async {
    final txs = await db.select(db.transactions).get();
    return accountBalances(txs)[accountId] ?? 0;
  }
}
