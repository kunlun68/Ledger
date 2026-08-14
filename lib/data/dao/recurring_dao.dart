import 'package:drift/drift.dart';
import '../../core/recurring.dart';
import '../database.dart';
import '../transaction_type.dart';

/// 周期规则与启动补生成。
class RecurringDao {
  RecurringDao(this.db);
  final AppDatabase db;

  Future<void> insertRule(
          {required TxType type,
          required int amountCents,
          required int categoryId,
          required int dayOfMonth,
          String note = '',
          required int lastGeneratedYyyymm}) =>
      db.into(db.recurringRules).insert(RecurringRulesCompanion.insert(
            type: type,
            amountCents: amountCents,
            categoryId: categoryId,
            dayOfMonth: dayOfMonth,
            note: Value(note),
            lastGeneratedYyyymm: Value(lastGeneratedYyyymm),
          ));

  Future<void> deleteRule(int id) =>
      (db.delete(db.recurringRules)..where((t) => t.id.equals(id))).go();

  Stream<List<RecurringRule>> watchAll() =>
      (db.select(db.recurringRules)..orderBy([(t) => OrderingTerm.desc(t.id)])).watch();

  /// 启动补生成：为每条规则补齐 (lastGenerated, now] 的缺失月份，单事务。
  Future<void> generateDue(int nowYyyymm) {
    return db.transaction(() async {
      final rules = await db.select(db.recurringRules).get();
      for (final r in rules) {
        final months = monthsBetween(r.lastGeneratedYyyymm, nowYyyymm);
        for (final m in months) {
          await db.into(db.transactions).insert(TransactionsCompanion.insert(
                type: r.type,
                amountCents: r.amountCents,
                categoryId: r.categoryId,
                note: Value(r.note),
                date: m * 100 + clampDayToMonth(r.dayOfMonth, m),
              ));
        }
        if (months.isNotEmpty) {
          await (db.update(db.recurringRules)..where((t) => t.id.equals(r.id)))
              .write(RecurringRulesCompanion(lastGeneratedYyyymm: Value(nowYyyymm)));
        }
      }
    });
  }
}
