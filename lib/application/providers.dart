import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/date_util.dart';
import '../core/stats.dart';
import '../data/dao/categories_dao.dart';
import '../data/dao/transactions_dao.dart';
import '../data/database.dart';
import '../data/transaction_type.dart';

/// 在 main() 中 override 为真实数据库
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError());

final categoriesDaoProvider = Provider((ref) => CategoriesDao(ref.watch(databaseProvider)));
final transactionsDaoProvider = Provider((ref) => TransactionsDao(ref.watch(databaseProvider)));

final allCategoriesProvider = StreamProvider<List<Category>>(
    (ref) => ref.watch(categoriesDaoProvider).watchAll());

final allTransactionsProvider = StreamProvider<List<Transaction>>(
    (ref) => ref.watch(transactionsDaoProvider).watchAll());

/// 当前查看的月份 yyyymm，默认当月
final currentMonthProvider = NotifierProvider<CurrentMonthNotifier, int>(CurrentMonthNotifier.new);

class CurrentMonthNotifier extends Notifier<int> {
  @override
  int build() => yyyymmOf(todayYyyymmdd());

  void setMonth(int yyyymm) => state = yyyymm;
}

final monthTransactionsProvider = StreamProvider<List<Transaction>>((ref) {
  final month = ref.watch(currentMonthProvider);
  return ref.watch(transactionsDaoProvider).watchByMonth(month);
});

final monthSummaryProvider =
    Provider<({int incomeCents, int expenseCents, int balanceCents})>((ref) {
  final txs = ref.watch(monthTransactionsProvider).value ?? const <Transaction>[];
  final income = totalByType(txs, TxType.income);
  final expense = totalByType(txs, TxType.expense);
  return (incomeCents: income, expenseCents: expense, balanceCents: income - expense);
});

/// 当前月按分类支出：categoryId → 分（仅支出）
final categoryExpenseProvider = Provider<Map<int, int>>((ref) {
  final txs = ref.watch(monthTransactionsProvider).value ?? const <Transaction>[];
  return expenseByCategory(txs);
});
