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
  IntColumn get categoryId => integer().nullable().references(Categories, #id)();
  TextColumn get note => text().withDefault(const Constant(''))();
  IntColumn get date => integer()(); // yyyyMMdd，如 20260813
  IntColumn get accountId => integer().references(Accounts, #id).withDefault(const Constant(1))();
  IntColumn get transferAccountId => integer().nullable().references(Accounts, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 20)();
  TextColumn get icon => text().withLength(min: 1, max: 50)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class RecurringRules extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get type => textEnum<TxType>()();
  IntColumn get amountCents => integer()(); // 单位：分
  IntColumn get categoryId => integer().references(Categories, #id)();
  TextColumn get note => text().withDefault(const Constant(''))();
  IntColumn get dayOfMonth => integer()(); // 每月几号，1-31
  IntColumn get accountId => integer().references(Accounts, #id).withDefault(const Constant(1))();
  /// 上次生成的月份 yyyymm，0 = 从未生成
  IntColumn get lastGeneratedYyyymm => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
