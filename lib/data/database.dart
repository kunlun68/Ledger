import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'tables.dart';
import 'transaction_type.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Categories, Transactions])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  factory AppDatabase.open({QueryExecutor? executor}) =>
      AppDatabase(executor ?? driftDatabase(name: 'ledger'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(categories, categories.monthlyBudgetCents);
          }
        },
      );
}
