import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../core/date_util.dart';
import '../../core/money.dart';
import '../../data/database.dart';
import '../widgets/account_picker.dart';
import '../widgets/amount_field.dart';
import '../widgets/app_scaffold.dart';

/// 账户间转账：从账户 → 到账户。
class TransferScreen extends ConsumerStatefulWidget {
  const TransferScreen({super.key});

  @override
  ConsumerState<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends ConsumerState<TransferScreen> {
  late final TextEditingController _amount;
  int _fromId = -1;
  int _toId = -1;
  int _date = 0;
  String _note = '';

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController();
    _date = todayYyyymmdd();
    _autoSelect(ref.read(allAccountsProvider).value);
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// 默认从=第一个账户、到=第二个账户（只有一个账户时到=从，保存时报错提示）。
  void _autoSelect(List<Account>? accounts) {
    if (accounts == null || accounts.isEmpty) return;
    if (_fromId < 0) _fromId = accounts.first.id;
    if (_toId < 0 && accounts.length > 1) _toId = accounts[1].id;
  }

  Future<void> _save() async {
    int cents;
    try {
      cents = parseCents(_amount.text);
    } on FormatException {
      _show('请输入有效金额');
      return;
    }
    if (_toId < 0) {
      _show('至少需要两个账户才能转账');
      return;
    }
    if (_fromId == _toId) {
      _show('转出与转入账户不能相同');
      return;
    }
    await ref.read(transactionsDaoProvider).insertTransfer(
        fromAccountId: _fromId, toAccountId: _toId, amountCents: cents, date: _date,
        note: _note.trim());
    if (mounted) Navigator.pop(context);
  }

  void _show(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    _autoSelect(ref.watch(allAccountsProvider).value);
    return AppScaffold(
      appBar: AppBar(title: const Text('转账')),
      body: SafeArea(
        child: Column(children: [
          const SizedBox(height: 8),
          Text('从', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          AccountPicker(selectedId: _fromId, onSelect: (id) => setState(() => _fromId = id)),
          Text('到', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          AccountPicker(selectedId: _toId, onSelect: (id) => setState(() => _toId = id)),
          AmountField(controller: _amount),
          ListTile(
            leading: const Icon(Icons.event),
            title: Text('日期 ${_date.toString()}'),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime(_date ~/ 10000, (_date ~/ 100) % 100, _date % 100),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                setState(() => _date = picked.year * 10000 + picked.month * 100 + picked.day);
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(labelText: '备注', prefixIcon: Icon(Icons.notes)),
              onChanged: (v) => _note = v,
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: const Text('保存'),
            ),
          ),
        ]),
      ),
    );
  }
}
