import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:ledger/application/providers.dart';
import 'package:ledger/data/dao/categories_dao.dart';
import 'package:ledger/data/dao/transactions_dao.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/data/transaction_type.dart';
import 'package:ledger/presentation/screens/statistics_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.open(executor: NativeDatabase.memory());
    await CategoriesDao(db).seedBuiltinCategories();
    final cats = await CategoriesDao(db).getByType(TxType.expense);
    await TransactionsDao(db).insertTransaction(TxType.expense, 1000, cats[0].id, 20260810, 'a');
    await TransactionsDao(db).insertTransaction(TxType.expense, 2000, cats[1].id, 20260811, 'b');
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, AppDatabase db) async {
    // 显式固定月份，避免依赖"今天是几月"导致跨月红
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    container.read(currentMonthProvider.notifier).state = 202608;
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: StatisticsScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows category ranking', (tester) async {
    await pump(tester, db);
    expect(find.text('10.00'), findsOneWidget); // 1000 分
    expect(find.text('20.00'), findsOneWidget); // 2000 分
    // 卸载树取消 stream 订阅；推进时钟执行 drift 的清理 Timer（Duration.zero）
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('shows empty state when no expense this month', (tester) async {
    final emptyDb = AppDatabase.open(executor: NativeDatabase.memory());
    await CategoriesDao(emptyDb).seedBuiltinCategories();
    addTearDown(emptyDb.close);
    await pump(tester, emptyDb);
    expect(find.text('本月暂无支出记录'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
