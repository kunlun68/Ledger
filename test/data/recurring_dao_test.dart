import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:ledger/data/dao/categories_dao.dart';
import 'package:ledger/data/dao/recurring_dao.dart';
import 'package:ledger/data/dao/transactions_dao.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/data/transaction_type.dart';

void main() {
  late AppDatabase db;
  late RecurringDao dao;

  setUp(() async {
    db = AppDatabase.open(executor: NativeDatabase.memory());
    dao = RecurringDao(db);
    await CategoriesDao(db).seedBuiltinCategories();
  });
  tearDown(() => db.close());

  Future<int> foodId() async =>
      (await CategoriesDao(db).getByType(TxType.expense)).first.id;

  test('generateDue backfills missing months', () async {
    await dao.insertRule(
        type: TxType.expense,
        amountCents: 300000,
        categoryId: await foodId(),
        dayOfMonth: 1,
        note: '房租',
        lastGeneratedYyyymm: 202604);
    await dao.generateDue(202608);
    final txs = await TransactionsDao(db).getByMonth(202605);
    expect(txs, hasLength(1));
    expect(txs.single.date, 20260501);
    expect(txs.single.amountCents, 300000);
    final txs2 = await TransactionsDao(db).getByMonth(202608);
    expect(txs2.single.date, 20260801);
  });

  test('generateDue is idempotent', () async {
    await dao.insertRule(
        type: TxType.expense,
        amountCents: 100,
        categoryId: await foodId(),
        dayOfMonth: 15,
        note: '',
        lastGeneratedYyyymm: 202606);
    await dao.generateDue(202608);
    await dao.generateDue(202608); // 再跑不重复
    final txs = await TransactionsDao(db).getByMonth(202607);
    expect(txs, hasLength(1));
  });

  test('rule created this month generates nothing this month', () async {
    await dao.insertRule(
        type: TxType.expense,
        amountCents: 100,
        categoryId: await foodId(),
        dayOfMonth: 1,
        note: '',
        lastGeneratedYyyymm: 202608);
    await dao.generateDue(202608);
    final txs = await TransactionsDao(db).getByMonth(202608);
    expect(txs, isEmpty);
  });

  test('clamps day 30 to february end', () async {
    await dao.insertRule(
        type: TxType.expense,
        amountCents: 100,
        categoryId: await foodId(),
        dayOfMonth: 30,
        note: '',
        lastGeneratedYyyymm: 202601);
    await dao.generateDue(202602);
    final txs = await TransactionsDao(db).getByMonth(202602);
    expect(txs.single.date, 20260228);
  });

  test('deleteRule removes rule', () async {
    await dao.insertRule(
        type: TxType.expense,
        amountCents: 100,
        categoryId: await foodId(),
        dayOfMonth: 1,
        note: '',
        lastGeneratedYyyymm: 202608);
    final rules = await dao.watchAll().first;
    expect(rules, hasLength(1));
    await dao.deleteRule(rules.single.id);
    expect(await dao.watchAll().first, isEmpty);
  });
}
