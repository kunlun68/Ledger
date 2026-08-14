import 'package:drift/drift.dart';
import '../database.dart';
import '../transaction_type.dart';

/// 删除被交易引用的分类时抛出
class CategoryInUseException implements Exception {}

const builtinCategories = <(String, String, TxType)>[
  ('餐饮', 'restaurant', TxType.expense),
  ('交通', 'directions_bus', TxType.expense),
  ('购物', 'shopping_bag', TxType.expense),
  ('居住', 'home', TxType.expense),
  ('娱乐', 'sports_esports', TxType.expense),
  ('医疗', 'local_hospital', TxType.expense),
  ('教育', 'school', TxType.expense),
  ('工资', 'payments', TxType.income),
  ('兼职', 'work', TxType.income),
  ('理财', 'trending_up', TxType.income),
  ('红包', 'redeem', TxType.income),
];

class CategoriesDao {
  CategoriesDao(this.db);
  final AppDatabase db;

  /// 幂等：已有任何分类就不再种
  Future<void> seedBuiltinCategories() async {
    final existing = await db.select(db.categories).get();
    if (existing.isNotEmpty) return;
    await db.batch((b) => b.insertAll(db.categories, [
          for (var i = 0; i < builtinCategories.length; i++)
            CategoriesCompanion.insert(
              name: builtinCategories[i].$1,
              icon: builtinCategories[i].$2,
              type: builtinCategories[i].$3,
              sortOrder: Value(i),
              isBuiltin: const Value(true),
            ),
        ]));
  }

  Stream<List<Category>> watchAll() => (db.select(db.categories)
        ..orderBy([
          (t) => OrderingTerm.asc(t.type),
          (t) => OrderingTerm.asc(t.sortOrder),
          (t) => OrderingTerm.asc(t.id),
        ]))
      .watch();

  Future<List<Category>> getByType(TxType type) => (db.select(db.categories)
        ..where((t) => t.type.equalsValue(type))
        ..orderBy([(t) => OrderingTerm.asc(t.sortOrder), (t) => OrderingTerm.asc(t.id)]))
      .get();

  Future<void> insertCategory(String name, String icon, TxType type) =>
      db.into(db.categories).insert(CategoriesCompanion.insert(name: name, icon: icon, type: type));

  Future<void> updateCategory(Category c, {String? name, String? icon, int? sortOrder}) =>
      db.update(db.categories).replace(c.copyWith(
            name: name ?? c.name,
            icon: icon ?? c.icon,
            sortOrder: sortOrder ?? c.sortOrder,
          ));

  /// 设置每月预算（分），0 = 清除预算。
  Future<void> updateBudget(int categoryId, int monthlyBudgetCents) =>
      (db.update(db.categories)..where((t) => t.id.equals(categoryId)))
          .write(CategoriesCompanion(monthlyBudgetCents: Value(monthlyBudgetCents)));

  Future<void> deleteCategory(Category c) async {
    final used = await (db.select(db.transactions)
          ..where((t) => t.categoryId.equals(c.id)))
        .get();
    if (used.isNotEmpty) throw CategoryInUseException();
    await (db.delete(db.categories)..where((t) => t.id.equals(c.id))).go();
  }
}
