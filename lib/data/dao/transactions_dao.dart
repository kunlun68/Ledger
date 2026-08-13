import 'package:drift/drift.dart';
import '../database.dart';
import '../transaction_type.dart';

class TransactionsDao {
  TransactionsDao(this.db);
  final AppDatabase db;

  Future<void> insertTransaction(
          TxType type, int amountCents, int categoryId, int date, String note) =>
      db.into(db.transactions).insert(TransactionsCompanion.insert(
            type: type,
            amountCents: amountCents,
            categoryId: categoryId,
            date: date,
            note: Value(note),
          ));

  Future<void> updateTransaction(Transaction t,
          {TxType? type, int? amountCents, int? categoryId, int? date, String? note}) =>
      db.update(db.transactions).replace(t.copyWith(
            type: type ?? t.type,
            amountCents: amountCents ?? t.amountCents,
            categoryId: categoryId ?? t.categoryId,
            date: date ?? t.date,
            note: note ?? t.note,
            updatedAt: DateTime.now(),
          ));

  Future<void> deleteTransaction(int id) =>
      (db.delete(db.transactions)..where((t) => t.id.equals(id))).go();

  Future<Transaction?> getById(int id) =>
      (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// 按月查询，[yyyymm] 形如 202608。date 升序、id 升序。
  Future<List<Transaction>> getByMonth(int yyyymm) =>
      (db.select(db.transactions)
            ..where((t) => t.date.isBetweenValues(_monthRange(yyyymm).$1, _monthRange(yyyymm).$2))
            ..orderBy([(t) => OrderingTerm.asc(t.date), (t) => OrderingTerm.asc(t.id)]))
          .get();

  Stream<List<Transaction>> watchByMonth(int yyyymm) {
    final (start, end) = _monthRange(yyyymm);
    return (db.select(db.transactions)
          ..where((t) => t.date.isBetweenValues(start, end))
          ..orderBy([(t) => OrderingTerm.asc(t.date), (t) => OrderingTerm.asc(t.id)]))
        .watch();
  }

  Stream<List<Transaction>> watchAll() =>
      (db.select(db.transactions)..orderBy([(t) => OrderingTerm.desc(t.date)])).watch();

  Future<List<Transaction>> search(String keyword, {int limit = 100}) =>
      (db.select(db.transactions)
            ..where((t) => t.note.like('%$keyword%'))
            ..orderBy([(t) => OrderingTerm.desc(t.date)])
            ..limit(limit))
          .get();

  /// yyyymm 对应的首日和末日，返回 yyyyMMdd
  (int, int) _monthRange(int yyyymm) {
    final year = yyyymm ~/ 100;
    final month = yyyymm % 100;
    final lastDay = DateTime(year, month + 1, 0).day;
    return (year * 10000 + month * 100 + 1, year * 10000 + month * 100 + lastDay);
  }
}
