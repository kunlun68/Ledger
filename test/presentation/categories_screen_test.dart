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

  testWidgets('builtin category cannot be deleted', (tester) async {
    await pump(tester);
    await tester.tap(find.text('餐饮'));
    await tester.pumpAndSettle();
    expect(find.text('内置分类不可删除'), findsOneWidget);
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
