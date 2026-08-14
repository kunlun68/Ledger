import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../core/date_util.dart';
import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/transaction_type.dart';
import '../widgets/account_picker.dart';
import '../widgets/amount_field.dart';
import '../widgets/category_picker.dart';

/// 记一笔 / 编辑记录。传入 [initial] 时为编辑模式。
class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key, this.initial});

  final Transaction? initial;

  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  late TxType _type;
  late final TextEditingController _amount;
  int _categoryId = -1;
  int _accountId = -1;
  int _date = 0;
  String _note = '';

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    _type = t?.type ?? TxType.expense;
    _amount = TextEditingController(text: t == null ? '' : formatCents(t.amountCents));
    _categoryId = t?.categoryId ?? -1;
    _accountId = t?.accountId ?? -1;
    _date = t?.date ?? todayYyyymmdd();
    _note = t?.note ?? '';
    _autoSelectCategory(ref.read(allCategoriesProvider).value);
    _autoSelectAccount(ref.read(allAccountsProvider).value);
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// 新记录时自动选中第一个分类；分类流到达后经 build 中的 watch 兜底。
  void _autoSelectCategory(List<Category>? cats) {
    if (cats == null || _categoryId >= 0) return;
    final first = cats.where((c) => c.type == _type).firstOrNull;
    if (first != null) _categoryId = first.id;
  }

  /// 自动选中第一个账户；账户流到达后经 build 中的 watch 兜底。
  void _autoSelectAccount(List<Account>? accounts) {
    if (accounts == null || accounts.isEmpty || _accountId >= 0) return;
    _accountId = accounts.first.id;
  }

  Future<void> _save() async {
    int cents;
    try {
      cents = parseCents(_amount.text);
    } on FormatException {
      _show('请输入有效金额');
      return;
    }
    if (_categoryId < 0) {
      _show('请选择分类');
      return;
    }
    final dao = ref.read(transactionsDaoProvider);
    final t = widget.initial;
    if (t == null) {
      await dao.insertTransaction(_type, cents, _categoryId, _date, _note.trim(),
          accountId: _accountId);
    } else {
      await dao.updateTransaction(t,
          type: _type, amountCents: cents, categoryId: _categoryId, date: _date, note: _note.trim());
    }
    if (mounted) Navigator.pop(context);
  }

  /// 编辑模式下删除当前记录（带确认）。
  Future<void> _delete() async {
    final t = widget.initial;
    if (t == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记录'),
        content: const Text('删除后不可恢复'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(transactionsDaoProvider).deleteTransaction(t.id);
    if (mounted) Navigator.pop(context);
  }

  void _show(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    _autoSelectCategory(ref.watch(allCategoriesProvider).value);
    _autoSelectAccount(ref.watch(allAccountsProvider).value);
    return Scaffold(
      appBar: AppBar(title: Text(widget.initial == null ? '记一笔' : '编辑记录')),
      body: SafeArea(
        child: Column(children: [
          SegmentedButton<TxType>(
            segments: const [
              ButtonSegment(value: TxType.expense, label: Text('支出')),
              ButtonSegment(value: TxType.income, label: Text('收入')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() {
              _type = s.first;
              _categoryId = -1; // 换类型需重选分类
            }),
          ),
          const SizedBox(height: 8),
          AmountField(controller: _amount),
          AccountPicker(
              selectedId: _accountId, onSelect: (id) => setState(() => _accountId = id)),
          CategoryPicker(
              type: _type, selectedId: _categoryId, onSelect: (id) => setState(() => _categoryId = id)),
          ListTile(
            leading: const Icon(Icons.event),
            title: Text('日期 ${_date.toString()}'),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                // 编辑旧记录时从记录日期开始，而非今天
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
          if (widget.initial != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: OutlinedButton(
                onPressed: _delete,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('删除'),
              ),
            ),
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
