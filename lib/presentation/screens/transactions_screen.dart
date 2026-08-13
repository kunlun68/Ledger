import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/transaction_type.dart';
import '../theme/app_theme.dart';
import 'add_transaction_screen.dart';

/// 账单列表：按月内分组（日期间隔标题），滑动删除 + 撤销，点击进编辑。
class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key, required this.initialMonth, required this.onExit});
  final int initialMonth;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txs = ref.watch(monthTransactionsProvider).value ?? const <Transaction>[];
    final cats = ref.watch(allCategoriesProvider).value ?? const <Category>[];
    final dao = ref.read(transactionsDaoProvider);

    String catName(int id) =>
        cats.where((c) => c.id == id).map((c) => c.name).firstOrNull ?? '未分类';

    // 按日期分组（date 降序）
    final groups = <int, List<Transaction>>{};
    for (final t in txs.reversed) {
      groups.putIfAbsent(t.date, () => []).add(t);
    }

    Future<void> delete(Transaction tx) async {
      await dao.deleteTransaction(tx.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('已删除'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => dao.insertTransaction(
              tx.type, tx.amountCents, tx.categoryId, tx.date, tx.note),
        ),
      ));
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: onExit),
        title: Text('账单'),
      ),
      body: txs.isEmpty
          ? const Center(child: Text('本月还没有记录'))
          : ListView(
              children: [
                for (final entry in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text('${entry.key}',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12)),
                  ),
                  for (final tx in entry.value)
                    Dismissible(
                      key: ValueKey(tx.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                          color: AppTheme.expenseColor,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.delete, color: Colors.white)),
                      onDismissed: (_) => delete(tx),
                      child: ListTile(
                        leading: CircleAvatar(child: Text(catName(tx.categoryId).characters.first)),
                        title: Text(catName(tx.categoryId)),
                        subtitle: Text(tx.note.isEmpty ? ' ' : tx.note),
                        trailing: Text(
                          '${tx.type == TxType.expense ? '-' : '+'}${formatCents(tx.amountCents)}',
                          style: TextStyle(
                              color: tx.type == TxType.expense
                                  ? AppTheme.expenseColor
                                  : AppTheme.incomeColor,
                              fontWeight: FontWeight.w600),
                        ),
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => AddTransactionScreen(initial: tx))),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}
