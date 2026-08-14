import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:ledger/application/providers.dart';
import 'package:ledger/data/dao/accounts_dao.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/presentation/screens/transfer_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.open(executor: NativeDatabase.memory());
    await db.into(db.accounts).insert(AccountsCompanion.insert(
        name: '现金', icon: 'payments', sortOrder: const Value(0)));
    await db.into(db.accounts).insert(AccountsCompanion.insert(
        name: '微信', icon: 'wechat', sortOrder: const Value(1)));
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const MaterialApp(home: TransferScreen())));
    await tester.pumpAndSettle();
  }

  testWidgets('transfer saves and updates balances', (tester) async {
    await pump(tester);
    // 默认从=现金（第一个）、到=微信（第二个），无需点击
    await tester.enterText(find.byType(TextField).first, '100');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final dao = AccountsDao(db);
    final cash = (await db.select(db.accounts).get()).firstWhere((a) => a.name == '现金');
    final wx = (await db.select(db.accounts).get()).firstWhere((a) => a.name == '微信');
    expect(await dao.balanceOf(cash.id), -10000);
    expect(await dao.balanceOf(wx.id), 10000);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('same account shows error', (tester) async {
    await pump(tester);
    // 到账户也选现金
    await tester.tap(find.text('现金').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '100');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('转出与转入账户不能相同'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
