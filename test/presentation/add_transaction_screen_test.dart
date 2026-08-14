import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:ledger/application/providers.dart';
import 'package:ledger/core/date_util.dart';
import 'package:ledger/data/dao/categories_dao.dart';
import 'package:ledger/data/dao/transactions_dao.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/data/transaction_type.dart';
import 'package:ledger/presentation/screens/add_transaction_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.open(executor: NativeDatabase.memory());
    await CategoriesDao(db).seedBuiltinCategories();
  });
  tearDown(() => db.close());

  Future<void> pumpForm(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: AddTransactionScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('saves a transaction and shows it in list', (tester) async {
    await pumpForm(tester);
    await tester.enterText(find.byType(TextField).first, '12.34');
    // 分类选择器自动选中第一个分类（餐饮），无需点击
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    // 表单默认日期是今天，断言跟随动态月份（避免跨月红）
    final txs = await TransactionsDao(db).getByMonth(yyyymmOf(todayYyyymmdd()));
    expect(txs.single.amountCents, 1234);
    expect(txs.single.type, TxType.expense);
    // 卸载树取消 stream 订阅；推进时钟执行 drift 的清理 Timer（Duration.zero）
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('invalid amount shows error snackbar', (tester) async {
    await pumpForm(tester);
    await tester.enterText(find.byType(TextField).first, 'abc');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('请输入有效金额'), findsOneWidget);
    expect(await TransactionsDao(db).getByMonth(yyyymmOf(todayYyyymmdd())), isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero); // 推进时钟执行 drift 清理 Timer
  });
}
