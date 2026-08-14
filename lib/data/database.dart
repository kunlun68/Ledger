import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'tables.dart';
import 'transaction_type.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Categories, Transactions, RecurringRules, Accounts])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  factory AppDatabase.open({QueryExecutor? executor}) =>
      AppDatabase(executor ?? driftDatabase(name: 'ledger'));

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(categories, categories.monthlyBudgetCents);
          }
          if (from < 3) {
            await m.createTable(recurringRules);
          }
          if (from < 4) {
            await m.createTable(accounts);
            await into(accounts).insert(AccountsCompanion.insert(
                name: '现金', icon: 'payments', sortOrder: const Value(0)));
            // 手工重建 transactions：category_id 改可空 + 加 account 两列，
            // 旧数据归默认账户（account_id=1）
            await customStatement('ALTER TABLE transactions RENAME TO transactions_old');
            await m.createTable(transactions);
            await customStatement('''
INSERT INTO transactions (id, type, amount_cents, category_id, note, date,
    account_id, transfer_account_id, created_at, updated_at)
SELECT id, type, amount_cents, category_id, note, date, 1, NULL, created_at, updated_at
FROM transactions_old''');
            await customStatement('DROP TABLE transactions_old');
            // from < 3 时 recurringRules 刚以当前定义（含 account_id）创建，无需加列
            if (from >= 3) {
              await m.addColumn(recurringRules, recurringRules.accountId);
            }
          }
        },
      );
}
