import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:ledger/data/dao/categories_dao.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/data/transaction_type.dart';

void main() {
  late AppDatabase db;
  late CategoriesDao dao;
  setUp(() {
    db = AppDatabase.open(executor: NativeDatabase.memory());
    dao = CategoriesDao(db);
  });
  tearDown(() => db.close());

  test('seed inserts builtin categories idempotently', () async {
    await dao.seedBuiltinCategories();
    final first = await dao.getByType(TxType.expense);
    expect(first.length, greaterThan(5));
    await dao.seedBuiltinCategories(); // 再跑一次不重复
    final again = await dao.getByType(TxType.expense);
    expect(again.length, first.length);
    expect(again.every((c) => c.isBuiltin), isTrue);
  });

  test('insert custom category', () async {
    await dao.insertCategory('猫粮', 'pets', TxType.expense);
    final list = await dao.getByType(TxType.expense);
    expect(list.any((c) => c.name == '猫粮' && !c.isBuiltin), isTrue);
  });

  test('delete category in use throws CategoryInUseException', () async {
    await dao.seedBuiltinCategories();
    final food = (await dao.getByType(TxType.expense)).first;
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
        type: TxType.expense,
        amountCents: 100,
        categoryId: Value(food.id),
        date: 20260813));
    expect(() => dao.deleteCategory(food), throwsA(isA<CategoryInUseException>()));
  });

  test('update category', () async {
    await dao.insertCategory('猫粮', 'pets', TxType.expense);
    final c = (await dao.getByType(TxType.expense)).firstWhere((c) => c.name == '猫粮');
    await dao.updateCategory(c, name: '猫粮2');
    final updated = (await dao.getByType(TxType.expense)).firstWhere((c) => c.id == c.id);
    expect(updated.name, '猫粮2');
  });

  test('updateBudget sets and clears monthly budget', () async {
    await dao.seedBuiltinCategories();
    final food = (await dao.getByType(TxType.expense)).first;
    await dao.updateBudget(food.id, 15000);
    var after = (await dao.getByType(TxType.expense)).first;
    expect(after.monthlyBudgetCents, 15000);
    await dao.updateBudget(food.id, 0); // 清除
    after = (await dao.getByType(TxType.expense)).first;
    expect(after.monthlyBudgetCents, 0);
  });
}
