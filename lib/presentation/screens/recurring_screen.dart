import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../core/date_util.dart';
import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/transaction_type.dart';
import '../theme/app_theme.dart';
import '../widgets/amount_field.dart' show AmountInputFormatter;
import '../widgets/category_picker.dart';

/// 周期规则列表：新增/删除规则，规则生成的记录由启动时 generateDue 补齐。
class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(recurringRulesProvider).value ?? const <RecurringRule>[];
    final cats = ref.watch(allCategoriesProvider).value ?? const <Category>[];
    final dao = ref.watch(recurringDaoProvider);

    String catName(int id) =>
        cats.where((c) => c.id == id).map((c) => c.name).firstOrNull ?? '未分类';

    Future<void> addDialog() async {
      final amountCtrl = TextEditingController();
      final dayCtrl = TextEditingController();
      final noteCtrl = TextEditingController();
      var type = TxType.expense;
      var categoryId = -1;

      // 同步兜底自动选中第一个匹配分类（与 AddTransactionScreen 同模式）
      void autoSelect() {
        if (categoryId >= 0) return;
        final first = cats.where((c) => c.type == type).firstOrNull;
        if (first != null) categoryId = first.id;
      }

      autoSelect();
      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            autoSelect();
            return AlertDialog(
              title: const Text('新增周期规则'),
              content: SizedBox(
                width: 340, // 固定宽度避免 intrinsic 测量触及横向 ListView（CategoryPicker）
                child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SegmentedButton<TxType>(
                    segments: const [
                      ButtonSegment(value: TxType.expense, label: Text('支出')),
                      ButtonSegment(value: TxType.income, label: Text('收入')),
                    ],
                    selected: {type},
                    onSelectionChanged: (s) => setDialogState(() {
                      type = s.first;
                      categoryId = -1; // 换类型重选分类
                      autoSelect();
                    }),
                  ),
                  TextField(
                    controller: amountCtrl,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [AmountInputFormatter()],
                    decoration: const InputDecoration(labelText: '金额', prefixText: '¥ '),
                  ),
                  CategoryPicker(
                      type: type,
                      selectedId: categoryId,
                      onSelect: (id) => setDialogState(() => categoryId = id)),
                  TextField(
                    controller: dayCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: '每月几号（1-31）'),
                  ),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(labelText: '备注'),
                  ),
                ]),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                TextButton(
                  onPressed: () async {
                    final int cents;
                    try {
                      cents = parseCents(amountCtrl.text);
                    } on FormatException {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('请输入有效金额')));
                      }
                      return;
                    }
                    final day = int.tryParse(dayCtrl.text);
                    if (day == null || day < 1 || day > 31) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('请输入 1-31 的日期')));
                      }
                      return;
                    }
                    if (categoryId < 0) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('请选择分类')));
                      }
                      return;
                    }
                    await dao.insertRule(
                        type: type,
                        amountCents: cents,
                        categoryId: categoryId,
                        dayOfMonth: day,
                        note: noteCtrl.text.trim(),
                        lastGeneratedYyyymm: yyyymmOf(todayYyyymmdd()));
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        ),
      );
    }

    Future<void> deleteFlow(RecurringRule r) async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('删除规则'),
          content: const Text('删除后已生成的记录不受影响'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
          ],
        ),
      );
      if (ok != true) return;
      await dao.deleteRule(r.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已删除')));
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('周期记账')),
      floatingActionButton:
          FloatingActionButton(onPressed: addDialog, child: const Icon(Icons.add)),
      body: rules.isEmpty
          ? const Center(child: Text('还没有周期规则'))
          : ListView.builder(
              itemCount: rules.length,
              itemBuilder: (_, i) {
                final r = rules[i];
                final isExpense = r.type == TxType.expense;
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.event_repeat)),
                  title: Text(catName(r.categoryId)),
                  subtitle:
                      Text('每月 ${r.dayOfMonth} 号${r.note.isEmpty ? '' : ' · ${r.note}'}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('${isExpense ? '-' : '+'}${formatCents(r.amountCents)}',
                        style: TextStyle(
                            color: isExpense ? AppTheme.expenseColor : AppTheme.incomeColor,
                            fontWeight: FontWeight.w600)),
                    IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => deleteFlow(r)),
                  ]),
                );
              },
            ),
    );
  }
}
