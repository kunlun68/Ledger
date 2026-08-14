import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:ledger/application/providers.dart';
import 'package:ledger/data/dao/categories_dao.dart';
import 'package:ledger/data/dao/transactions_dao.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/data/transaction_type.dart';
import 'package:ledger/presentation/screens/transactions_screen.dart';

void main() {
  late AppDatabase db;
  late int foodId;

  setUp(() async {
    db = AppDatabase.open(executor: NativeDatabase.memory());
    await CategoriesDao(db).seedBuiltinCategories();
    foodId = (await CategoriesDao(db).getByType(TxType.expense)).first.id;
    await TransactionsDao(db).insertTransaction(TxType.expense, 100, foodId, 20260813, '午饭');
    await TransactionsDao(db).insertTransaction(TxType.expense, 200, foodId, 20260801, '早饭');
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
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
      child: MaterialApp(home: TransactionsScreen(onExit: () {})),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('lists transactions grouped by day', (tester) async {
    await pump(tester);
    expect(find.text('午饭'), findsOneWidget);
    expect(find.text('早饭'), findsOneWidget);
    // 卸载树取消 stream 订阅；推进时钟执行 drift 的清理 Timer（Duration.zero）
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('swipe deletes and undo restores', (tester) async {
    await pump(tester);
    await tester.drag(find.text('午饭'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(await TransactionsDao(db).getByMonth(202608), hasLength(1));
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(await TransactionsDao(db).getByMonth(202608), hasLength(2));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
