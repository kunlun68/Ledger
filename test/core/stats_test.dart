import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/stats.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/data/transaction_type.dart';

Transaction tx(TxType type, int cents, int categoryId, int date,
        {int account = 1, int? to}) =>
    Transaction(
        id: 0,
        type: type,
        amountCents: cents,
        categoryId: type == TxType.transfer ? null : categoryId,
        note: '',
        date: date,
        accountId: account,
        transferAccountId: to,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026));

void main() {
  test('totalByType sums only matching type', () {
    final txs = [
      tx(TxType.expense, 100, 1, 20260801),
      tx(TxType.expense, 250, 1, 20260802),
      tx(TxType.income, 100000, 2, 20260803),
    ];
    expect(totalByType(txs, TxType.expense), 350);
    expect(totalByType(txs, TxType.income), 100000);
  });

  test('expenseByCategory groups expenses only', () {
    final txs = [
      tx(TxType.expense, 100, 1, 20260801),
      tx(TxType.expense, 200, 1, 20260802),
      tx(TxType.expense, 50, 2, 20260803),
      tx(TxType.income, 999, 3, 20260804),
    ];
    expect(expenseByCategory(txs), {1: 300, 2: 50});
  });

  test('monthlyTrend fills missing months with zero', () {
    final txs = [
      tx(TxType.expense, 100, 1, 20260715),
      tx(TxType.expense, 200, 1, 20260810),
      tx(TxType.income, 5000, 2, 20260601),
    ];
    final trend = monthlyTrend(txs, months: 3);
    expect(trend.map((t) => t.yyyymm).toList(), [202606, 202607, 202608]);
    expect(trend[1].expenseCents, 100);
    expect(trend[0].incomeCents, 5000);
    expect(trend[2].expenseCents, 200);
  });

  test('accountBalances sums income/expense and moves transfers', () {
    final txs = [
      tx(TxType.income, 10000, 1, 20260801), // 账户 1 +100
      tx(TxType.expense, 3000, 1, 20260802), // 账户 1 -30
      tx(TxType.transfer, 2000, 1, 20260803, to: 2), // 1→2 转 20
      tx(TxType.income, 500, 1, 20260804, account: 3), // 账户 3 +5
    ];
    final b = accountBalances(txs);
    expect(b[1], 10000 - 3000 - 2000);
    expect(b[2], 2000);
    expect(b[3], 500);
    expect(totalAssets(txs), 10000 - 3000 + 500);
  });
}
