import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../data/database.dart';
import '../../data/transaction_type.dart';

/// 分类图标名 → IconData（内置分类使用，自定义分类默认 face）
const categoryIcons = <String, IconData>{
  'restaurant': Icons.restaurant,
  'directions_bus': Icons.directions_bus,
  'shopping_bag': Icons.shopping_bag,
  'home': Icons.home,
  'sports_esports': Icons.sports_esports,
  'local_hospital': Icons.local_hospital,
  'school': Icons.school,
  'payments': Icons.payments,
  'work': Icons.work,
  'trending_up': Icons.trending_up,
  'redeem': Icons.redeem,
  'face': Icons.face,
};

IconData iconOf(String name) => categoryIcons[name] ?? Icons.face;

class CategoryPicker extends ConsumerWidget {
  const CategoryPicker(
      {super.key, required this.type, required this.selectedId, required this.onSelect});

  final TxType type;
  final int selectedId;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(allCategoriesProvider).value ?? const <Category>[];
    final filtered = cats.where((c) => c.type == type).toList();
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 84,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: filtered.length,
        itemBuilder: (_, i) {
          final c = filtered[i];
          final selected = c.id == selectedId;
          return InkWell(
            onTap: () => onSelect(c.id),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 64,
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? colorScheme.primaryContainer : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(iconOf(c.icon),
                      color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant),
                  const SizedBox(height: 4),
                  Text(c.name, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
