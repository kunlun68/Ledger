import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../core/money.dart';
import '../../core/stats.dart';
import '../../data/dao/accounts_dao.dart';
import '../../data/database.dart';
import '../theme/app_theme.dart';
import 'transfer_screen.dart';

/// 账户列表：余额展示、新增、删除（有记录不可删）、转账入口。
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(allAccountsProvider).value ?? const <Account>[];
    final dao = ref.watch(accountsDaoProvider);
    final txs = ref.watch(allTransactionsProvider).value ?? const <Transaction>[];
    final balances = accountBalances(txs);

    void show(String msg) =>
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

    Future<void> addDialog() async {
      final nameCtrl = TextEditingController();
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('新增账户'),
          content: TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(hintText: '账户名称')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                await dao.insertAccount(name, 'wallet');
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      );
    }

    Future<void> deleteFlow(Account a) async {
      try {
        await dao.deleteAccount(a);
      } on AccountInUseException {
        if (context.mounted) show('该账户已有记录，无法删除');
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('账户'),
        actions: [
          IconButton(
              icon: const Icon(Icons.swap_horiz),
              tooltip: '转账',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const TransferScreen()))),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: addDialog, child: const Icon(Icons.add)),
      body: accounts.isEmpty
          ? const Center(child: Text('请先创建账户'))
          : ListView.builder(
              itemCount: accounts.length,
              itemBuilder: (_, i) {
                final a = accounts[i];
                final balance = balances[a.id] ?? 0;
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.account_balance_wallet_outlined)),
                  title: Text(a.name),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(formatCents(balance),
                        style: TextStyle(
                            color: balance >= 0 ? AppTheme.incomeColor : AppTheme.expenseColor,
                            fontWeight: FontWeight.w600)),
                    IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => deleteFlow(a)),
                  ]),
                );
              },
            ),
    );
  }
}
