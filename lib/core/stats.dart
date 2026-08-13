import '../data/database.dart';
import '../data/transaction_type.dart';

int totalByType(List<Transaction> txs, TxType type) => txs
    .where((t) => t.type == type)
    .fold(0, (sum, t) => sum + t.amountCents);

/// 按分类汇总支出：categoryId → 分（仅支出，收入不计入）
Map<int, int> expenseByCategory(List<Transaction> txs) {
  final map = <int, int>{};
  for (final t in txs.where((t) => t.type == TxType.expense)) {
    map[t.categoryId] = (map[t.categoryId] ?? 0) + t.amountCents;
  }
  return map;
}

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
