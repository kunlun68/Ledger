import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../core/date_util.dart';
import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/transaction_type.dart';
import '../theme/app_theme.dart';
import 'add_transaction_screen.dart';
import 'transactions_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(currentMonthProvider);
    final summary = ref.watch(monthSummaryProvider);
    final txs = ref.watch(monthTransactionsProvider).value ?? const <Transaction>[];
    final cats = ref.watch(allCategoriesProvider).value ?? const <Category>[];

    String catName(int id) =>
        cats.where((c) => c.id == id).map((c) => c.name).firstOrNull ?? '未分类';

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
                onPressed: () =>
                    ref.read(currentMonthProvider.notifier).setMonth(_shift(month, -1)),
                icon: const Icon(Icons.chevron_left)),
            Text(formatYyyymm(month),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            IconButton(
                onPressed: () =>
                    ref.read(currentMonthProvider.notifier).setMonth(_shift(month, 1)),
                icon: const Icon(Icons.chevron_right)),
          ],
        ),
      ),
      body: Column(children: [
        _SummaryCard(summary: summary),
        Expanded(
          child: txs.isEmpty
              ? const Center(child: Text('还没有记账记录'))
              : ListView.builder(
                  itemCount: txs.length > 5 ? 5 : txs.length,
                  itemBuilder: (_, i) => _TransactionTile(
                      tx: txs[i],
                      categoryName: catName(txs[i].categoryId),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => AddTransactionScreen(initial: txs[i])),
                      )),
                ),
        ),
        TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      TransactionsScreen(initialMonth: month, onExit: () => Navigator.pop(context))),
            ),
            icon: const Icon(Icons.list),
            label: const Text('查看全部'),
          ),
      ]),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddTransactionScreen()),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  int _shift(int yyyymm, int delta) {
    final y = yyyymm ~/ 100, m = yyyymm % 100;
    final d = DateTime(y, m + delta, 1);
    return d.year * 100 + d.month;
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final ({int incomeCents, int expenseCents, int balanceCents}) summary;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text('结余', style: TextStyle(color: c.onSurfaceVariant, fontSize: 13)),
          Text(
            formatCents(summary.balanceCents),
            style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: summary.balanceCents >= 0
                    ? AppTheme.incomeColor
                    : AppTheme.expenseColor),
          ),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            Text('收入 ${formatCents(summary.incomeCents)}',
                style: const TextStyle(color: AppTheme.incomeColor)),
            Text('支出 ${formatCents(summary.expenseCents)}',
                style: const TextStyle(color: AppTheme.expenseColor)),
          ]),
        ]),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile(
      {required this.tx, required this.categoryName, required this.onTap});

  final Transaction tx;
  final String categoryName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isExpense = tx.type == TxType.expense;
    final color = isExpense ? AppTheme.expenseColor : AppTheme.incomeColor;
    final sign = isExpense ? '-' : '+';
    return ListTile(
      leading: CircleAvatar(child: Text(categoryName.characters.first)),
      title: Text(categoryName),
      subtitle: Text(tx.note.isEmpty ? ' ' : tx.note),
      trailing: Text(
        '$sign${formatCents(tx.amountCents)}',
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 16),
      ),
      onTap: onTap,
    );
  }
}
