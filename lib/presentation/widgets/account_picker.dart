import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../data/database.dart';

/// 账户横向选择器（样式同 CategoryPicker）。
class AccountPicker extends ConsumerWidget {
  const AccountPicker({super.key, required this.selectedId, required this.onSelect});

  final int selectedId;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(allAccountsProvider).value ?? const <Account>[];
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 56,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: accounts.length,
        itemBuilder: (_, i) {
          final a = accounts[i];
          final selected = a.id == selectedId;
          return InkWell(
            onTap: () => onSelect(a.id),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: selected ? colorScheme.primaryContainer : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.account_balance_wallet_outlined, size: 18),
                const SizedBox(width: 6),
                Text(a.name, style: const TextStyle(fontSize: 13)),
              ]),
            ),
          );
        },
      ),
    );
  }
}
