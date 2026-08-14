import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:ledger/application/backup_io.dart';
import 'package:ledger/application/providers.dart';
import 'package:ledger/core/backup.dart';
import 'package:ledger/data/dao/backup_dao.dart';
import 'package:ledger/data/dao/categories_dao.dart';
import 'package:ledger/data/dao/transactions_dao.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/data/transaction_type.dart';
import 'package:ledger/presentation/screens/accounts_screen.dart';
import 'package:ledger/presentation/screens/recurring_screen.dart';
import 'package:ledger/presentation/screens/settings_screen.dart';

class FakeBackupIO implements BackupIO {
  String? pickedContent;
  final shared = <String>[];

  @override
  Future<void> shareFile(String path, {required String text}) async {
    shared.add(path);
  }

  @override
  Future<String?> pickBackupFile() async => pickedContent;
}

void main() {
  late AppDatabase db;
  late FakeBackupIO io;

  setUp(() async {
    db = AppDatabase.open(executor: NativeDatabase.memory());
    await CategoriesDao(db).seedBuiltinCategories();
    io = FakeBackupIO();
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      backupIOProvider.overrideWithValue(io),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const MaterialApp(home: SettingsScreen())));
    await tester.pumpAndSettle();
  }

  testWidgets('shows three entries', (tester) async {
    await pump(tester);
    expect(find.text('导出 CSV'), findsOneWidget);
    expect(find.text('备份'), findsOneWidget);
    expect(find.text('恢复'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('export csv shares a temp file', (tester) async {
    final cats = await CategoriesDao(db).getByType(TxType.expense);
    await TransactionsDao(db)
        .insertTransaction(TxType.expense, 100, cats.first.id, 20260813, '午饭', accountId: 1);
    await pump(tester);
    // 真实文件 IO 在 fake-async zone 不会完成，需 runAsync 驱动
    await tester.runAsync(() async {
      await tester.tap(find.text('导出 CSV'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(io.shared, hasLength(1));
    // readAsStringSync 会自动剥离 BOM，用字节断言
    final bytes = File(io.shared.single).readAsBytesSync();
    expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('restore confirm replaces data', (tester) async {
    final cats = await CategoriesDao(db).getByType(TxType.expense);
    await TransactionsDao(db)
        .insertTransaction(TxType.expense, 100, cats.first.id, 20260813, '旧记录', accountId: 1);
    // 备份内容：1 个交易"新记录"
    io.pickedContent = encodeBackup(cats, [
      Transaction(
          id: 42,
          type: TxType.expense,
          amountCents: 200,
          categoryId: cats.first.id,
          note: '新记录',
          date: 20260814,
          accountId: 1,
          transferAccountId: null,
          createdAt: DateTime(2026, 8, 14),
          updatedAt: DateTime(2026, 8, 14))
    ]);
    await pump(tester);
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    expect(find.textContaining('此操作不可撤销'), findsOneWidget); // 确认框
    await tester.tap(find.widgetWithText(FilledButton, '恢复'));
    await tester.pumpAndSettle();
    final all = await BackupDao(db).exportAll();
    expect(all.transactions.single.note, '新记录');
    expect(find.textContaining('已恢复'), findsOneWidget); // SnackBar
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('restore cancel keeps data', (tester) async {
    final cats = await CategoriesDao(db).getByType(TxType.expense);
    await TransactionsDao(db)
        .insertTransaction(TxType.expense, 100, cats.first.id, 20260813, '旧记录', accountId: 1);
    io.pickedContent = encodeBackup(cats, const []);
    await pump(tester);
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    final all = await BackupDao(db).exportAll();
    expect(all.transactions.single.note, '旧记录');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('corrupt backup shows error and keeps data', (tester) async {
    io.pickedContent = 'not json';
    await pump(tester);
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    expect(find.text('备份文件内容损坏'), findsOneWidget);
    final all = await BackupDao(db).exportAll();
    expect(all.transactions, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('foreign backup file shows error', (tester) async {
    io.pickedContent = '{"app":"other","version":1}';
    await pump(tester);
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    expect(find.text('不是本应用的备份文件'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('recurring entry opens recurring screen', (tester) async {
    await pump(tester);
    await tester.tap(find.text('周期记账'));
    await tester.pumpAndSettle();
    expect(find.byType(RecurringScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('accounts entry opens accounts screen', (tester) async {
    await pump(tester);
    await tester.tap(find.text('账户'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountsScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
