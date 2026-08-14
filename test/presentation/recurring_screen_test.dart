import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:ledger/application/providers.dart';
import 'package:ledger/data/dao/categories_dao.dart';
import 'package:ledger/data/dao/recurring_dao.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/data/transaction_type.dart';
import 'package:ledger/presentation/screens/recurring_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.open(executor: NativeDatabase.memory());
    await CategoriesDao(db).seedBuiltinCategories();
    await db.into(db.accounts).insert(
        AccountsCompanion.insert(name: '现金', icon: 'payments', sortOrder: const Value(0)));
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const MaterialApp(home: RecurringScreen())));
    await tester.pumpAndSettle();
  }

  testWidgets('shows empty state', (tester) async {
    await pump(tester);
    expect(find.text('还没有周期规则'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('adds a rule and shows it in list', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    // dialog 内 4 个 TextField：金额/分类选择器无 TextField/几号/备注
    await tester.enterText(find.widgetWithText(TextField, '金额'), '3000');
    await tester.enterText(find.widgetWithText(TextField, '每月几号（1-31）'), '1');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('-3000.00'), findsOneWidget);
    expect(find.textContaining('每月 1 号'), findsOneWidget);
    expect(find.textContaining('现金'), findsWidgets); // 行内显示账户名
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('invalid day shows error and keeps dialog', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '金额'), '100');
    await tester.enterText(find.widgetWithText(TextField, '每月几号（1-31）'), '32');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('请输入 1-31 的日期'), findsOneWidget);
    expect(find.text('新增周期规则'), findsOneWidget); // dialog 未关
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('deletes a rule after confirm', (tester) async {
    await RecurringDao(db).insertRule(
        type: TxType.expense,
        amountCents: 300000,
        categoryId: 1,
        dayOfMonth: 1,
        note: '房租',
        accountId: 1,
        lastGeneratedYyyymm: 202608);
    await pump(tester);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    // 一次性查询而非 stream.first（fake-async 下 stream 事件需 pump 派发，会死锁）
    expect(await db.select(db.recurringRules).get(), isEmpty);
    expect(find.text('还没有周期规则'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
