import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:ledger/application/providers.dart';
import 'package:ledger/data/dao/categories_dao.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/data/transaction_type.dart';
import 'package:ledger/presentation/screens/categories_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.open(executor: NativeDatabase.memory());
    await CategoriesDao(db).seedBuiltinCategories();
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: CategoriesScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows builtin categories', (tester) async {
    await pump(tester);
    expect(find.text('餐饮'), findsOneWidget);
    // TabBarView 懒加载：切换到收入 Tab 才能看到收入分类
    await tester.tap(find.text('收入'));
    await tester.pumpAndSettle();
    expect(find.text('工资'), findsOneWidget);
    // 卸载树取消 stream 订阅；推进时钟执行 drift 的清理 Timer（Duration.zero）
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('adds custom category', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '猫粮');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('猫粮'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('builtin category has no delete button, tap opens budget dialog', (tester) async {
    await pump(tester);
    expect(find.byIcon(Icons.delete_outline), findsNothing); // 内置分类无删除按钮
    await tester.tap(find.text('餐饮'));
    await tester.pumpAndSettle();
    expect(find.textContaining('设置预算'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('sets budget and shows old value on reopen', (tester) async {
    await pump(tester);
    await tester.tap(find.text('餐饮'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '100.50');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    final dao = CategoriesDao(db);
    final food = (await dao.getByType(TxType.expense)).firstWhere((c) => c.name == '餐饮');
    expect(food.monthlyBudgetCents, 10050);
    // 重开显示旧值
    await tester.tap(find.text('餐饮'));
    await tester.pumpAndSettle();
    expect(find.text('100.50'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('empty input clears budget', (tester) async {
    final dao = CategoriesDao(db);
    final food = (await dao.getByType(TxType.expense)).firstWhere((c) => c.name == '餐饮');
    await dao.updateBudget(food.id, 10000);
    await pump(tester);
    await tester.tap(find.text('餐饮'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    final after = (await dao.getByType(TxType.expense)).firstWhere((c) => c.name == '餐饮');
    expect(after.monthlyBudgetCents, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('income category has no budget dialog', (tester) async {
    await pump(tester);
    await tester.tap(find.text('收入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('工资'));
    await tester.pumpAndSettle();
    expect(find.textContaining('设置预算'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('invalid budget amount shows error and keeps dialog open', (tester) async {
    await pump(tester);
    await tester.tap(find.text('餐饮'));
    await tester.pumpAndSettle();
    // formatter 允许 "."（\d{0,7}(\.\d{0,2})?），但 parseCents 拒绝 → 非法场景
    await tester.enterText(find.byType(TextField), '.');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('请输入有效金额'), findsOneWidget); // SnackBar
    expect(find.textContaining('设置预算'), findsOneWidget); // dialog 未关
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('adds category to the active tab type', (tester) async {
    await pump(tester);
    await tester.tap(find.text('收入'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '奖金');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('奖金'), findsOneWidget); // 出现在当前收入 Tab
    final incomeCats = await CategoriesDao(db).getByType(TxType.income);
    expect(incomeCats.any((c) => c.name == '奖金'), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
