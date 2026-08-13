import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:ledger/data/dao/categories_dao.dart';
import 'package:ledger/data/dao/transactions_dao.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/data/transaction_type.dart';

void main() {
  late AppDatabase db;
  late TransactionsDao dao;
  late int foodId;

  Future<void> seed() async {
    final catDao = CategoriesDao(db);
    await catDao.seedBuiltinCategories();
    final cats = await catDao.getByType(TxType.expense);
    foodId = cats.firstWhere((c) => c.name == '餐饮').id;
  }

  setUp(() {
    db = AppDatabase.open(executor: NativeDatabase.memory());
    dao = TransactionsDao(db);
  });
  tearDown(() => db.close());

  test('insert and getById roundtrip', () async {
    await seed();
    await dao.insertTransaction(TxType.expense, 1234, foodId, 20260813, '午饭');
    final t = await dao.getById(1);
    expect(t!.amountCents, 1234);
    expect(t.note, '午饭');
    expect(t.date, 20260813);
  });

  test('getByMonth returns only transactions in that month, sorted', () async {
    await seed();
    await dao.insertTransaction(TxType.expense, 100, foodId, 20260731, '七月末');
    await dao.insertTransaction(TxType.expense, 200, foodId, 20260801, '八月一');
    await dao.insertTransaction(TxType.expense, 300, foodId, 20260813, '八月十三');
    final august = await dao.getByMonth(202608);
    expect(august.map((t) => t.note).toList(), ['八月一', '八月十三']);
  });

  test('update and delete', () async {
    await seed();
    await dao.insertTransaction(TxType.expense, 100, foodId, 20260813, 'a');
    final t = await dao.getById(1);
    await dao.updateTransaction(t!, amountCents: 999, note: 'b');
    final updated = await dao.getById(1);
    expect(updated!.amountCents, 999);
    expect(updated.note, 'b');
    await dao.deleteTransaction(1);
    expect(await dao.getById(1), isNull);
  });

  test('search matches note keyword', () async {
    await seed();
    await dao.insertTransaction(TxType.expense, 100, foodId, 20260813, '麦当劳');
    await dao.insertTransaction(TxType.expense, 200, foodId, 20260813, '星巴克');
    final hits = await dao.search('麦当');
    expect(hits.single.note, '麦当劳');
  });

  test('watchByMonth emits updates', () async {
    await seed();
    final stream = dao.watchByMonth(202608);
    final emitted = <List<Transaction>>[];
    final sub = stream.listen(emitted.add);
    await dao.insertTransaction(TxType.expense, 100, foodId, 20260813, 'x');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    expect(emitted.length, greaterThanOrEqualTo(1));
    expect(emitted.last.single.note, 'x');
  });
}
