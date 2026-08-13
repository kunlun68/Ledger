import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/stats.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/data/transaction_type.dart';

Transaction tx(TxType type, int cents, int categoryId, int date) => Transaction(
    id: 0,
    type: type,
    amountCents: cents,
    categoryId: categoryId,
    note: '',
    date: date,
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
}
