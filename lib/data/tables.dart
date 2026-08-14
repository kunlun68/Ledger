import 'package:drift/drift.dart';
import 'transaction_type.dart';

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 20)();
  TextColumn get icon => text().withLength(min: 1, max: 50)();
  TextColumn get type => textEnum<TxType>()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isBuiltin => boolean().withDefault(const Constant(false))();
  /// 每月预算（分），0 = 无预算
  IntColumn get monthlyBudgetCents => integer().withDefault(const Constant(0))();
}

class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get type => textEnum<TxType>()();
  IntColumn get amountCents => integer()(); // 金额单位：分，禁止 double
  IntColumn get categoryId => integer().references(Categories, #id)();
  TextColumn get note => text().withDefault(const Constant(''))();
  IntColumn get date => integer()(); // yyyyMMdd，如 20260813
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
