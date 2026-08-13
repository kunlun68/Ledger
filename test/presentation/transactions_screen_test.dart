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
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: TransactionsScreen(
          initialMonth: 202608,
          onExit: () {},
        ),
      ),
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
