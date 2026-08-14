import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/csv_export.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/data/transaction_type.dart';

void main() {
  final cats = [
    Category(
        id: 1,
        name: '餐饮',
        icon: 'restaurant',
        type: TxType.expense,
        sortOrder: 0,
        isBuiltin: true,
        monthlyBudgetCents: 0),
    Category(
        id: 2,
        name: '工资',
        icon: 'payments',
        type: TxType.income,
        sortOrder: 0,
        isBuiltin: true,
        monthlyBudgetCents: 0),
  ];
  final accounts = [
    Account(id: 1, name: '现金', icon: 'payments', sortOrder: 0, createdAt: DateTime(2026)),
    Account(id: 2, name: '微信', icon: 'wechat', sortOrder: 1, createdAt: DateTime(2026)),
  ];

  Transaction tx(int id, TxType type, int cents, int categoryId, String note,
          {int account = 1, int? to}) =>
      Transaction(
          id: id,
          type: type,
          amountCents: cents,
          categoryId: type == TxType.transfer ? null : categoryId,
          note: note,
          date: 20260813,
          accountId: account,
          transferAccountId: to,
          createdAt: DateTime(2026, 8, 13),
          updatedAt: DateTime(2026, 8, 13));

  test('starts with UTF-8 BOM and header', () {
    final csv = buildCsv([], cats, accounts);
    expect(csv.startsWith('﻿'), isTrue);
    expect(csv.contains('date,type,category,account,amount,note'), isTrue);
  });

  test('formats rows: date, chinese type, category name, account, amount, note', () {
    final csv = buildCsv(
        [tx(1, TxType.expense, 1234, 1, '午饭'), tx(2, TxType.income, 500000, 2, '')],
        cats,
        accounts);
    final lines = csv.split('\r\n');
    expect(lines[1], '2026-08-13,支出,餐饮,现金,12.34,午饭');
    expect(lines[2], '2026-08-13,收入,工资,现金,5000.00,');
  });

  test('transfer row: type 转账, empty category, both accounts', () {
    final csv = buildCsv(
        [tx(3, TxType.transfer, 1000, 1, '', account: 1, to: 2)], cats, accounts);
    expect(csv.split('\r\n')[1], '2026-08-13,转账,,现金,10.00,');
  });

  test('unknown categoryId shows 未分类', () {
    final csv = buildCsv([tx(1, TxType.expense, 100, 999, '')], cats, accounts);
    expect(csv.split('\r\n')[1], contains('未分类'));
  });

  test('escapeCsv wraps fields with comma, quote, newline', () {
    expect(escapeCsv('a,b'), '"a,b"');
    expect(escapeCsv('a"b'), '"a""b"');
    expect(escapeCsv('a\nb'), '"a\nb"');
    expect(escapeCsv('plain'), 'plain');
  });
}
