import '../data/database.dart';
import '../data/transaction_type.dart';

int totalByType(List<Transaction> txs, TxType type) => txs
    .where((t) => t.type == type)
    .fold(0, (sum, t) => sum + t.amountCents);

/// 按分类汇总支出：categoryId → 分（仅支出，收入不计入）
Map<int, int> expenseByCategory(List<Transaction> txs) {
  final map = <int, int>{};
  for (final t in txs.where((t) => t.type == TxType.expense)) {
    final cid = t.categoryId;
    if (cid == null) continue; // 转账等无分类记录不参与
    map[cid] = (map[cid] ?? 0) + t.amountCents;
  }
  return map;
}

/// accountId → 余额（分）。expense/income 按账户归属，transfer 双向计入。
Map<int, int> accountBalances(List<Transaction> txs) {
  final map = <int, int>{};
  for (final t in txs) {
    switch (t.type) {
      case TxType.expense:
        map[t.accountId] = (map[t.accountId] ?? 0) - t.amountCents;
      case TxType.income:
        map[t.accountId] = (map[t.accountId] ?? 0) + t.amountCents;
      case TxType.transfer:
        map[t.accountId] = (map[t.accountId] ?? 0) - t.amountCents;
        final to = t.transferAccountId;
        if (to != null) map[to] = (map[to] ?? 0) + t.amountCents;
    }
  }
  return map;
}

/// 总资产：全部账户余额合计（分）。
int totalAssets(List<Transaction> txs) =>
    accountBalances(txs).values.fold(0, (a, b) => a + b);

typedef MonthTotal = ({int yyyymm, int expenseCents, int incomeCents});

/// 近 [months] 个自然月（含当月），缺失月份补 0，yyyymm 升序。
List<MonthTotal> monthlyTrend(List<Transaction> txs, {required int months}) {
  final now = DateTime.now();
  final result = <MonthTotal>[];
  for (var i = months - 1; i >= 0; i--) {
    final month = DateTime(now.year, now.month - i, 1);
    final yyyymm = month.year * 100 + month.month;
    final inMonth = txs.where((t) => t.date ~/ 100 == yyyymm).toList();
    result.add((
      yyyymm: yyyymm,
      expenseCents: totalByType(inMonth, TxType.expense),
      incomeCents: totalByType(inMonth, TxType.income),
    ));
  }
  return result;
}
