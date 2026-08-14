import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/transaction_type.dart';
import '../theme/app_theme.dart';
import 'add_transaction_screen.dart';
import '../widgets/app_scaffold.dart';

/// 账单列表：按月内分组（日期间隔标题），滑动删除 + 撤销，点击进编辑。
/// 显示月份由 [currentMonthProvider] 决定（与首页共享）。
class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key, required this.onExit});
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txs = ref.watch(monthTransactionsProvider).value ?? const <Transaction>[];
    final cats = ref.watch(allCategoriesProvider).value ?? const <Category>[];
    final accounts = ref.watch(allAccountsProvider).value ?? const <Account>[];
    final dao = ref.read(transactionsDaoProvider);

    String catName(int? id) => id == null
        ? '未分类'
        : cats.where((c) => c.id == id).map((c) => c.name).firstOrNull ?? '未分类';
    String accountName(int id) =>
        accounts.where((a) => a.id == id).map((a) => a.name).firstOrNull ?? '未知账户';

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
              tx.type, tx.amountCents, tx.categoryId, tx.date, tx.note,
              accountId: tx.accountId),
        ),
      ));
    }

    return AppScaffold(
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
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                      child: Dismissible(
                        key: ValueKey(tx.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          decoration: BoxDecoration(
                            color: AppTheme.expenseColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) => delete(tx),
                        child: Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            leading: tx.type == TxType.transfer
                                ? const CircleAvatar(child: Icon(Icons.swap_horiz))
                                : CircleAvatar(
                                    child: Text(catName(tx.categoryId).characters.first)),
                            title: Text(tx.type == TxType.transfer
                                ? '${accountName(tx.accountId)} → ${accountName(tx.transferAccountId ?? 0)}'
                                : catName(tx.categoryId)),
                            subtitle: Text(tx.type == TxType.transfer
                                ? (tx.note.isEmpty ? '转账' : tx.note)
                                : '${accountName(tx.accountId)}${tx.note.isEmpty ? '' : ' · ${tx.note}'}'),
                            trailing: Text(
                              '${tx.type == TxType.expense ? '-' : tx.type == TxType.income ? '+' : ''}${formatCents(tx.amountCents)}',
                              style: TextStyle(
                                  color: tx.type == TxType.expense
                                      ? AppTheme.expenseColor
                                      : tx.type == TxType.income
                                          ? AppTheme.incomeColor
                                          : null,
                                  fontWeight: FontWeight.w600),
                            ),
                            // 转账记录不可编辑（记一笔表单只支持支出/收入）
                            onTap: tx.type == TxType.transfer
                                ? null
                                : () => Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => AddTransactionScreen(initial: tx))),
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}
