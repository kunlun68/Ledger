import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:ledger/data/dao/accounts_dao.dart';
import 'package:ledger/data/dao/categories_dao.dart';
import 'package:ledger/data/dao/transactions_dao.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/data/transaction_type.dart';

void main() {
  late AppDatabase db;
  late AccountsDao dao;

  setUp(() async {
    db = AppDatabase.open(executor: NativeDatabase.memory());
    dao = AccountsDao(db);
    await db.into(db.accounts).insert(
        const AccountsCompanion.insert(name: '现金', icon: 'payments', sortOrder: Value(0)));
  });
  tearDown(() => db.close());

  test('insert and watchAll', () async {
    await dao.insertAccount('微信', 'wechat');
    final accounts = await db.select(db.accounts).get();
    expect(accounts.map((a) => a.name), containsAll(['现金', '微信']));
  });

  test('balanceOf reflects income expense and transfers', () async {
    await CategoriesDao(db).seedBuiltinCategories();
    final food = (await CategoriesDao(db).getByType(TxType.expense)).first.id;
    await TransactionsDao(db)
        .insertTransaction(TxType.income, 10000, null, 20260801, '初始', accountId: 1);
    await TransactionsDao(db)
        .insertTransaction(TxType.expense, 3000, food, 20260802, '', accountId: 1);
    await dao.insertAccount('微信', 'wechat');
    final wxId = (await db.select(db.accounts).get()).firstWhere((a) => a.name == '微信').id;
    await TransactionsDao(db).insertTransfer(
        fromAccountId: 1, toAccountId: wxId, amountCents: 2000, date: 20260803);
    expect(await dao.balanceOf(1), 10000 - 3000 - 2000);
    expect(await dao.balanceOf(wxId), 2000);
  });

  test('deleteAccount throws when account has transactions', () async {
    await TransactionsDao(db)
        .insertTransaction(TxType.expense, 100, 1, 20260801, '', accountId: 1);
    final cash = (await db.select(db.accounts).get()).single;
    expect(() => dao.deleteAccount(cash), throwsA(isA<AccountInUseException>()));
  });

  test('deleteAccount works when empty', () async {
    await dao.insertAccount('微信', 'wechat');
    final wx = (await db.select(db.accounts).get()).firstWhere((a) => a.name == '微信');
    await dao.deleteAccount(wx);
    expect((await db.select(db.accounts).get()).map((a) => a.name), ['现金']);
  });
}
