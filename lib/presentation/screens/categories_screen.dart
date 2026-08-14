import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../data/dao/categories_dao.dart';
import '../../data/database.dart';
import '../../data/transaction_type.dart';
import '../widgets/category_picker.dart' show categoryIcons;

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

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(allCategoriesProvider).value ?? const <Category>[];
    return Scaffold(
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
            onDelete: deleteFlow),
        _CategoryList(
            cats: cats.where((c) => c.type == TxType.income).toList(),
            onDelete: deleteFlow),
      ]),
    );
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({required this.cats, required this.onDelete});
  final List<Category> cats;
  final Future<void> Function(Category) onDelete;

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
          onTap: c.isBuiltin
              ? () => ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('内置分类不可删除')))
              : null,
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
