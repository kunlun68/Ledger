import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../core/money.dart';
import '../../data/dao/categories_dao.dart';
import '../../data/database.dart';
import '../../data/transaction_type.dart';
import '../widgets/amount_field.dart' show AmountInputFormatter;
import '../widgets/category_picker.dart' show categoryIcons;
import '../widgets/app_scaffold.dart';

/// 分类管理：支出/收入两个 Tab；新增分类跟随当前 Tab 类型；
/// 内置分类不可删除；被记录使用的分类删除时提示。
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> addDialog() async {
    final nameCtrl = TextEditingController();
    final type = _tab.index == 0 ? TxType.expense : TxType.income;
    final dao = ref.read(categoriesDaoProvider);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新增分类'),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(hintText: '分类名称')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              await dao.insertCategory(name, 'face', type);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> deleteFlow(Category c) async {
    try {
      await ref.read(categoriesDaoProvider).deleteCategory(c);
    } on CategoryInUseException {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('该分类已被记录使用，无法删除')));
    }
  }

  /// 设置/清除月度预算。空输入 = 清除；非法金额保持 dialog 打开。
  Future<void> budgetDialog(Category c) async {
    final dao = ref.read(categoriesDaoProvider);
    final ctrl = TextEditingController(
        text: c.monthlyBudgetCents > 0 ? formatCents(c.monthlyBudgetCents) : '');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('设置预算 · ${c.name}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [AmountInputFormatter()],
          decoration: const InputDecoration(hintText: '0.00 表示无预算', prefixText: '¥ '),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              final text = ctrl.text.trim();
              if (text.isEmpty) {
                await dao.updateBudget(c.id, 0); // 清除预算
                if (ctx.mounted) Navigator.pop(ctx);
                return;
              }
              final int cents;
              try {
                cents = parseCents(text);
              } on FormatException {
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('请输入有效金额')));
                }
                return; // dialog 保持打开
              }
              await dao.updateBudget(c.id, cents);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(allCategoriesProvider).value ?? const <Category>[];
    return AppScaffold(
      appBar: AppBar(
        title: const Text('分类管理'),
        bottom: TabBar(
            controller: _tab,
            tabs: const [Tab(text: '支出'), Tab(text: '收入')]),
      ),
      floatingActionButton: FloatingActionButton(
          onPressed: addDialog, child: const Icon(Icons.add)),
      body: TabBarView(controller: _tab, children: [
        _CategoryList(
            cats: cats.where((c) => c.type == TxType.expense).toList(),
            onDelete: deleteFlow,
            onTapCategory: budgetDialog),
        _CategoryList(
            cats: cats.where((c) => c.type == TxType.income).toList(),
            onDelete: deleteFlow,
            onTapCategory: null),
      ]),
    );
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList(
      {required this.cats, required this.onDelete, required this.onTapCategory});
  final List<Category> cats;
  final Future<void> Function(Category) onDelete;
  final Future<void> Function(Category)? onTapCategory;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: cats.length,
      itemBuilder: (_, i) {
        final c = cats[i];
        return ListTile(
          leading: CircleAvatar(child: Icon(categoryIcons[c.icon] ?? Icons.face)),
          title: Text(c.name),
          subtitle: c.isBuiltin ? const Text('内置分类') : null,
          onTap: onTapCategory == null ? null : () => onTapCategory!(c),
          trailing: c.isBuiltin
              ? null
              : IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => onDelete(c)),
        );
      },
    );
  }
}
