import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:ledger/application/providers.dart';
import 'package:ledger/data/dao/categories_dao.dart';
import 'package:ledger/data/dao/transactions_dao.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/data/transaction_type.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase.open(executor: NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    await CategoriesDao(db).seedBuiltinCategories();
    final cats = await CategoriesDao(db).getByType(TxType.expense);
    await TransactionsDao(db)
        .insertTransaction(TxType.expense, 1234, cats.first.id, 20260813, '午饭');
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('monthSummaryProvider computes income/expense/balance', () async {
    container.read(currentMonthProvider.notifier).state = 202608;
    await container.read(monthTransactionsProvider.future); // 确保流就绪
    final summary = container.read(monthSummaryProvider);
    expect(summary.expenseCents, 1234);
    expect(summary.incomeCents, 0);
    expect(summary.balanceCents, -1234);
  });

  test('allCategoriesProvider emits seeded categories', () async {
    final cats = await container.read(allCategoriesProvider.future);
    expect(cats.length, greaterThan(5));
    expect(cats.every((c) => c.isBuiltin), isTrue);
  });

  test('monthTransactionsProvider filters by current month', () async {
    container.read(currentMonthProvider.notifier).state = 202608;
    final txs = await container.read(monthTransactionsProvider.future);
    expect(txs.single.note, '午饭');
    container.read(currentMonthProvider.notifier).state = 202609;
    final empty = await container.read(monthTransactionsProvider.future);
    expect(empty, isEmpty);
  });

  test('categoryExpenseProvider groups by category', () async {
    container.read(currentMonthProvider.notifier).state = 202608;
    await container.read(monthTransactionsProvider.future);
    final map = container.read(categoryExpenseProvider);
    expect(map.values.single, 1234);
  });
}
