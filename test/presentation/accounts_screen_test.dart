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
import 'package:ledger/presentation/screens/accounts_screen.dart';
import 'package:ledger/presentation/screens/transfer_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.open(executor: NativeDatabase.memory());
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
        container: container, child: const MaterialApp(home: AccountsScreen())));
    await tester.pumpAndSettle();
  }

  testWidgets('shows account list with balance', (tester) async {
    await pump(tester);
    expect(find.text('现金'), findsOneWidget);
    expect(find.text('0.00'), findsOneWidget); // 余额
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('adds account via dialog', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '银行卡');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('银行卡'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('delete account in use shows snackbar', (tester) async {
    await CategoriesDao(db).seedBuiltinCategories();
    final food = (await CategoriesDao(db).getByType(TxType.expense)).first.id;
    await TransactionsDao(db)
        .insertTransaction(TxType.expense, 100, food, 20260801, '', accountId: 1);
    await pump(tester);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('该账户已有记录，无法删除'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('transfer button opens transfer screen', (tester) async {
    await pump(tester);
    await tester.tap(find.byIcon(Icons.swap_horiz));
    await tester.pumpAndSettle();
    expect(find.byType(TransferScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
