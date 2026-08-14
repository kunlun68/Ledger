import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:ledger/application/providers.dart';
import 'package:ledger/data/dao/categories_dao.dart';
import 'package:ledger/data/dao/transactions_dao.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/data/transaction_type.dart';
import 'package:ledger/presentation/screens/add_transaction_screen.dart';
import 'package:ledger/presentation/screens/categories_screen.dart';
import 'package:ledger/presentation/screens/home_screen.dart';
import 'package:ledger/presentation/screens/settings_screen.dart';
import 'package:ledger/presentation/screens/statistics_screen.dart';
import 'package:ledger/presentation/screens/transactions_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.open(executor: NativeDatabase.memory());
    await CategoriesDao(db).seedBuiltinCategories();
    await db.into(db.accounts).insert(
        AccountsCompanion.insert(name: '现金', icon: 'payments', sortOrder: const Value(0)));
  });
  tearDown(() => db.close());

  Future<ProviderContainer> makeContainer() async {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    container.read(currentMonthProvider.notifier).state = 202608;
    return container;
  }

  testWidgets('empty state shows hint', (tester) async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const MaterialApp(home: HomeScreen())));
    await tester.pumpAndSettle();
    expect(find.text('还没有记账记录'), findsOneWidget);
    expect(find.text('0.00'), findsWidgets); // 支出/收入/结余
  });

  testWidgets('shows summary and recent transactions', (tester) async {
    final cats = await CategoriesDao(db).getByType(TxType.expense);
    await TransactionsDao(db)
        .insertTransaction(TxType.expense, 1234, cats.first.id, 20260813, '午饭', accountId: 1);
    final container = await makeContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const MaterialApp(home: HomeScreen())));
    await tester.pumpAndSettle();
    expect(find.text('支出 12.34'), findsOneWidget); // 支出卡片
    expect(find.text('-12.34'), findsNWidgets(2)); // 结余卡片 + 记录行
    expect(find.text('午饭'), findsOneWidget);
  });

  testWidgets('FAB opens add transaction screen', (tester) async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const MaterialApp(home: HomeScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('记一笔'), findsOneWidget);
    expect(find.byType(AddTransactionScreen), findsOneWidget);
  });

  testWidgets('tapping a transaction opens edit screen', (tester) async {
    final cats = await CategoriesDao(db).getByType(TxType.expense);
    await TransactionsDao(db)
        .insertTransaction(TxType.expense, 1234, cats.first.id, 20260813, '午饭', accountId: 1);
    final container = await makeContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const MaterialApp(home: HomeScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('午饭'));
    await tester.pumpAndSettle();
    expect(find.text('编辑记录'), findsOneWidget);
    expect(find.text('12.34'), findsOneWidget); // 金额预填
  });

  testWidgets('view all opens transactions screen', (tester) async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const MaterialApp(home: HomeScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看全部'));
    await tester.pumpAndSettle();
    expect(find.text('账单'), findsOneWidget);
    expect(find.byType(TransactionsScreen), findsOneWidget);
  });

  testWidgets('category icon opens categories screen', (tester) async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const MaterialApp(home: HomeScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.category_outlined));
    await tester.pumpAndSettle();
    expect(find.text('分类管理'), findsOneWidget);
    expect(find.byType(CategoriesScreen), findsOneWidget);
  });

  testWidgets('chart icon opens statistics screen', (tester) async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const MaterialApp(home: HomeScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.pie_chart_outline));
    await tester.pumpAndSettle();
    expect(find.text('本月暂无支出记录'), findsOneWidget);
    expect(find.byType(StatisticsScreen), findsOneWidget);
  });

  testWidgets('settings icon opens settings screen', (tester) async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const MaterialApp(home: HomeScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}
