import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/backup.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/data/transaction_type.dart';

Category _cat({int id = 1, String name = '餐饮', int budget = 0}) => Category(
    id: id,
    name: name,
    icon: 'restaurant',
    type: TxType.expense,
    sortOrder: 0,
    isBuiltin: true,
    monthlyBudgetCents: budget);

Transaction _tx({int id = 1}) => Transaction(
    id: id,
    type: TxType.expense,
    amountCents: 1234,
    categoryId: 1,
    note: '午饭',
    date: 20260813,
    accountId: 2,
    transferAccountId: null,
    createdAt: DateTime(2026, 8, 13, 12),
    updatedAt: DateTime(2026, 8, 13, 12));

void main() {
  test('encode and parse roundtrip preserves all fields', () {
    final parsed = parseBackup(encodeBackup([_cat(budget: 15000)], [_tx()]));
    expect(parsed.categories.single.id, 1);
    expect(parsed.categories.single.name, '餐饮');
    expect(parsed.categories.single.type, TxType.expense);
    expect(parsed.categories.single.isBuiltin, true);
    expect(parsed.categories.single.monthlyBudgetCents, 15000);
    expect(parsed.transactions.single.id, 1);
    expect(parsed.transactions.single.amountCents, 1234);
    expect(parsed.transactions.single.categoryId, 1);
    expect(parsed.transactions.single.note, '午饭');
    expect(parsed.transactions.single.date, 20260813);
    expect(parsed.transactions.single.type, TxType.expense);
    expect(parsed.transactions.single.accountId, 2);
    expect(parsed.transactions.single.transferAccountId, isNull);
    expect(parsed.transactions.single.createdAt, DateTime(2026, 8, 13, 12));
  });

  test('parses legacy backup without account fields as account 1', () {
    final legacy = '{"app":"ledger","version":1,"categories":[],"transactions":['
        '{"id":1,"type":"expense","amountCents":100,"categoryId":1,"note":"","date":20260801,'
        '"createdAt":"2026-08-01T00:00:00.000","updatedAt":"2026-08-01T00:00:00.000"}]}';
    final parsed = parseBackup(legacy);
    expect(parsed.transactions.single.accountId, 1);
    expect(parsed.transactions.single.transferAccountId, isNull);
  });

  test('parses legacy backup without monthlyBudgetCents as 0', () {
    final legacy = '{"app":"ledger","version":1,"categories":['
        '{"id":1,"name":"餐饮","icon":"restaurant","type":"expense","sortOrder":0,"isBuiltin":true}],'
        '"transactions":[]}';
    final parsed = parseBackup(legacy);
    expect(parsed.categories.single.monthlyBudgetCents, 0);
  });

  test('rejects non-ledger file', () {
    expect(
        () => parseBackup('{"app":"other","version":1,"categories":[],"transactions":[]}'),
        throwsA(isA<BackupFormatException>()
            .having((e) => e.message, 'message', '不是本应用的备份文件')));
  });

  test('rejects newer version', () {
    expect(
        () => parseBackup('{"app":"ledger","version":99,"categories":[],"transactions":[]}'),
        throwsA(isA<BackupFormatException>()
            .having((e) => e.message, 'message', '备份文件版本过新，请升级应用')));
  });

  test('rejects malformed content', () {
    expect(
        () => parseBackup('not json at all'),
        throwsA(isA<BackupFormatException>()
            .having((e) => e.message, 'message', '备份文件内容损坏')));
    expect(
        () => parseBackup('{"app":"ledger","version":1,"categories":"oops","transactions":[]}'),
        throwsA(isA<BackupFormatException>()));
    expect(
        () => parseBackup(
            '{"app":"ledger","version":1,"categories":[],"transactions":[{"id":"x"}]}'),
        throwsA(isA<BackupFormatException>()));
  });
}
