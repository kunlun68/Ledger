# 记账 App (Ledger) MVP 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建一个本地优先的 Flutter 记账 App MVP：收支记录 + 分类管理 + 统计图表。

**Architecture:** 三层简化架构（个人自用 + 学习项目，YAGNI）：
- `data/` — drift 表、DAO、数据库连接（drift 生成的类型直接作为 entity，不设 repository 接口层）
- `application/` — Riverpod providers 编排数据 + 纯函数统计
- `presentation/` — 页面和组件，只管 UI

**Tech Stack:** Flutter 3.27+ / Dart 3，drift + drift_flutter（SQLite），flutter_riverpod，fl_chart，go_router，intl。测试用 `flutter test` + drift `NativeDatabase.memory()`。

**Spec:** [需求分析与功能规划](../..//C:/Users/Tao/.claude/plans/github-wondrous-teacup.md)（已批准）

## Global Constraints

- 金额一律用**整数分**（`amount_cents`，int 类型）存储与运算；**禁止 double** 参与金额计算
- 日期存整数 `yyyyMMdd`（int 类型，如 20260813），避免时区歧义；`created_at`/`updated_at` 用 drift DateTime
- 业务逻辑（金额解析、统计聚合、删除校验）必须先写测试（TDD，红灯→绿灯→提交）
- 数据库变更走 drift migration（`schemaVersion` + `onUpgrade`），禁止破坏性重建
- commit message 用简洁英文（如 `feat: add transactions dao`）
- 中文 UI 文案（代码/注释/变量保持英文）

---

### Task 1: 项目脚手架

**Files:**
- Create: `pubspec.yaml`（由 flutter create 生成后修改）
- Create: `lib/main.dart` 等默认骨架
- Create: `README.md`、`.gitignore`（flutter create 自带）
- Modify: 目录结构（新建 `lib/data/`、`lib/application/`、`lib/presentation/` 空目录）

**Interfaces:**
- Produces: 可运行的 Flutter 工程，`flutter analyze` 干净，默认测试通过

- [ ] **Step 1: 确认/安装 Flutter SDK**

本机未安装 Flutter（`flutter: command not found` 已验证）。安装：

```bash
# 方式 A：git clone（推荐，方便升级）
git clone https://github.com/flutter/flutter.git -b stable C:/src/flutter
# 然后执行 flutter.bat 触发首次编译，并把 C:\src\flutter\bin 加入 PATH
```

完成后验证：`flutter --version` 输出 3.27+，`flutter doctor` 无 fatal 项（Android toolchain 可后续装）。

- [ ] **Step 2: 创建项目**

```bash
cd d:/zhangben/Ledger
flutter create --project-name ledger --org com.zhangben --platforms android,ios .
```

- [ ] **Step 3: 添加依赖**

```bash
flutter pub add drift drift_flutter flutter_riverpod fl_chart go_router intl
flutter pub add --dev drift_dev build_runner
```

- [ ] **Step 4: 建目录骨架**

```bash
mkdir -p lib/data lib/application lib/presentation/screens lib/presentation/widgets lib/core test/data
```

- [ ] **Step 5: 验证**

```bash
flutter analyze   # 期望 0 错误 0 警告
flutter test      # 期望默认 widget_test 通过（或先删除默认 test/widget_test.dart）
```

- [ ] **Step 6: 初始化 git 并提交**

```bash
git init
git add -A
git commit -m "chore: scaffold flutter project"
```

---

### Task 2: drift 数据层 — 表定义与数据库

**Files:**
- Create: `lib/data/tables.dart`
- Create: `lib/data/database.dart`
- Create: `lib/data/transaction_type.dart`（enum TxType { expense, income }）
- Create: `build.yaml`
- Test: `test/data/database_test.dart`

**Interfaces:**
- Produces:
  - `class Transactions extends Table`，`class Categories extends Table`
  - `class AppDatabase extends _$AppDatabase`，`static const int schemaVersion = 1`
  - `AppDatabase.open({QueryExecutor? executor})` — 无参时用 `driftDatabase(name: 'ledger')`；测试传 `NativeDatabase.memory()`
  - drift 生成类：`Transaction`、`TransactionCompanion`、`Category`、`CategoryCompanion`（Task 3/4 使用）

- [ ] **Step 1: 写失败的建表测试**

```dart
// test/data/database_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:ledger/data/database.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.open(executor: NativeDatabase.memory()));
  tearDown(() => db.close());

  test('database opens and both tables exist', () async {
    await db.customSelect('SELECT name FROM sqlite_master WHERE type="table"').get();
    final tables = await db.customSelect('SELECT name FROM sqlite_master WHERE type="table"')
        .map((r) => r.read<String>('name')).get();
    expect(tables, containsAll(['transactions', 'categories']));
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/data/database_test.dart`
Expected: FAIL — 编译错误（`database.dart` 不存在）

- [ ] **Step 3: 实现表定义**

```dart
// lib/data/transaction_type.dart
enum TxType { expense, income }
```

```dart
// lib/data/tables.dart
import 'package:drift/drift.dart';
import 'transaction_type.dart';

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 20)();
  TextColumn get icon => text().withLength(min: 1, max: 50)();
  TextColumn get type => textEnum<TxType>()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isBuiltin => boolean().withDefault(const Constant(false))();
}

class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get type => textEnum<TxType>()();
  IntColumn get amountCents => integer()(); // 整数分，禁止 double
  IntColumn get categoryId => integer().references(Categories, #id)();
  TextColumn get note => text().withDefault(const Constant(''))();
  IntColumn get date => integer()(); // yyyyMMdd，如 20260813
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
```

- [ ] **Step 4: 实现数据库**

```dart
// lib/data/database.dart
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Categories, Transactions])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);
  static const int schemaVersion = 1;

  factory AppDatabase.open({QueryExecutor? executor}) =>
      AppDatabase(executor ?? driftDatabase(name: 'ledger'));

  @override
  int get schemaVersion => schemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => m.createAll(),
      );
}
```

```yaml
# build.yaml
targets:
  $default:
    builders:
      drift_dev:
        options:
          sql:
            dialect: sqlite
```

- [ ] **Step 5: 生成代码**

```bash
dart run build_runner build --delete-conflicting-outputs
```

Windows 上若测试报 `sqlite3.dll` 缺失：从 <https://www.sqlite.org/download.html> 下载 `sqlite-dll-win-x64` 压缩包，把 `sqlite3.dll` 放到 `C:\Windows\System32`。

- [ ] **Step 6: 运行测试确认通过**

Run: `flutter test test/data/database_test.dart`
Expected: PASS

- [ ] **Step 7: 提交**

```bash
git add -A
git commit -m "feat: add drift database schema"
```

---

### Task 3: 内置分类种子数据 + CategoriesDao

**Files:**
- Create: `lib/data/dao/categories_dao.dart`
- Test: `test/data/categories_dao_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `AppDatabase`、`CategoryCompanion`
- Produces:
  - `class CategoriesDao { CategoriesDao(this.db); }`
  - `Future<void> seedBuiltinCategories()` — 幂等，插入内置分类（见下）
  - `Stream<List<Category>> watchAll()` — 按 `type, sortOrder, id` 排序
  - `Future<List<Category>> getByType(TxType type)`
  - `Future<void> insertCategory(String name, String icon, TxType type)`
  - `Future<void> updateCategory(Category c, {String? name, String? icon, int? sortOrder})`
  - `Future<void> deleteCategory(Category c)` — 若被交易引用抛 `CategoryInUseException`
  - `class CategoryInUseException implements Exception`

- [ ] **Step 1: 写失败的种子与查询测试**

```dart
// test/data/categories_dao_test.dart
import 'package:flutter_test/flutter_test.dart';
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
      type: TxType.expense, amountCents: 100, categoryId: food.id, date: 20260813));
    expect(() => dao.deleteCategory(food), throwsA(isA<CategoryInUseException>()));
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/data/categories_dao_test.dart`
Expected: FAIL — 编译错误（`categories_dao.dart` 不存在）

- [ ] **Step 3: 实现 DAO**

```dart
// lib/data/dao/categories_dao.dart
import 'package:drift/drift.dart';
import '../database.dart';
import '../transaction_type.dart';

class CategoryInUseException implements Exception {}

const builtinCategories = <(String, String, TxType)>[
  ('餐饮', 'restaurant', TxType.expense),
  ('交通', 'directions_bus', TxType.expense),
  ('购物', 'shopping_bag', TxType.expense),
  ('居住', 'home', TxType.expense),
  ('娱乐', 'sports_esports', TxType.expense),
  ('医疗', 'local_hospital', TxType.expense),
  ('教育', 'school', TxType.expense),
  ('工资', 'payments', TxType.income),
  ('兼职', 'work', TxType.income),
  ('理财', 'trending_up', TxType.income),
  ('红包', 'redeem', TxType.income),
];

class CategoriesDao {
  CategoriesDao(this.db);
  final AppDatabase db;

  Future<void> seedBuiltinCategories() async {
    final existing = await db.select(db.categories).get();
    if (existing.isNotEmpty) return; // 幂等：已有任何分类就不再种
    await db.batch((b) => b.insertAll(db.categories, [
      for (var i = 0; i < builtinCategories.length; i++)
        CategoriesCompanion.insert(
          name: builtinCategories[i].$1,
          icon: builtinCategories[i].$2,
          type: builtinCategories[i].$3,
          sortOrder: Value(i),
          isBuiltin: const Value(true),
        ),
    ]));
  }

  Stream<List<Category>> watchAll() => (db.select(db.categories)
        ..orderBy([
          (t) => OrderingTerm.asc(t.type),
          (t) => OrderingTerm.asc(t.sortOrder),
          (t) => OrderingTerm.asc(t.id),
        ]))
      .watch();

  Future<List<Category>> getByType(TxType type) => (db.select(db.categories)
        ..where((t) => t.type.equalsValue(type))
        ..orderBy([(t) => OrderingTerm.asc(t.sortOrder), (t) => OrderingTerm.asc(t.id)]))
      .get();

  Future<void> insertCategory(String name, String icon, TxType type) =>
      db.into(db.categories).insert(CategoriesCompanion.insert(name: name, icon: icon, type: type));

  Future<void> updateCategory(Category c, {String? name, String? icon, int? sortOrder}) =>
      db.update(db.categories).replace(c.copyWith(
            name: name ?? c.name,
            icon: icon ?? c.icon,
            sortOrder: sortOrder ?? c.sortOrder,
          ));

  Future<void> deleteCategory(Category c) async {
    final used = await (db.select(db.transactions)
          ..where((t) => t.categoryId.equals(c.id)))
        .get();
    if (used.isNotEmpty) throw CategoryInUseException();
    await db.delete(db.categories).deleteWhere((t) => t.id.equals(c.id));
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/data/categories_dao_test.dart`
Expected: PASS（若上一步已生成代码则直接过）

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "feat: add categories dao with seed data"
```

---

### Task 4: TransactionsDao — CRUD 与按月查询

**Files:**
- Create: `lib/data/dao/transactions_dao.dart`
- Test: `test/data/transactions_dao_test.dart`

**Interfaces:**
- Consumes: Task 2/3 的 `AppDatabase`、`TransactionCompanion`、`Category`
- Produces:
  - `class TransactionsDao { TransactionsDao(this.db); }`
  - `Future<void> insertTransaction(TxType type, int amountCents, int categoryId, int date, String note)`
  - `Future<void> updateTransaction(Transaction t, {TxType? type, int? amountCents, int? categoryId, int? date, String? note})`
  - `Future<void> deleteTransaction(int id)`
  - `Future<Transaction?> getById(int id)`
  - `Future<List<Transaction>> getByMonth(int yyyymm)` — 按月（含首尾日）排序（date asc, id asc）
  - `Future<List<Transaction>> search(String keyword, {int limit = 100})` — note 模糊匹配
  - `Stream<List<Transaction>> watchByMonth(int yyyymm)`

- [ ] **Step 1: 写失败测试**

```dart
// test/data/transactions_dao_test.dart
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
  late int salaryId;

  Future<void> seed() async {
    final catDao = CategoriesDao(db);
    await catDao.seedBuiltinCategories();
    final cats = await catDao.getByType(TxType.expense);
    foodId = cats.firstWhere((c) => c.name == '餐饮').id;
    salaryId = (await catDao.getByType(TxType.income)).first.id;
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
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/data/transactions_dao_test.dart`
Expected: FAIL — 编译错误

- [ ] **Step 3: 实现 DAO**

```dart
// lib/data/dao/transactions_dao.dart
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
            note: note,
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
      db.delete(db.transactions).deleteWhere((t) => t.id.equals(id));

  Future<Transaction?> getById(int id) =>
      (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingleOrNull();

  // yyyymm: 202608 → 2026-08-01 00:00 至 2026-08-31 23:59（本地时区）
  Future<List<Transaction>> getByMonth(int yyyymm) async {
    final start = _monthRange(yyyymm).$1;
    final end = _monthRange(yyyymm).$2;
    final rows = await (db.select(db.transactions)
          ..where((t) => t.date.isBetweenValues(start, end))
          ..orderBy([(t) => OrderingTerm.asc(t.date), (t) => OrderingTerm.asc(t.id)]))
        .get();
    return rows;
  }

  Stream<List<Transaction>> watchByMonth(int yyyymm) {
    final (start, end) = _monthRange(yyyymm);
    return (db.select(db.transactions)
          ..where((t) => t.date.isBetweenValues(start, end))
          ..orderBy([(t) => OrderingTerm.asc(t.date), (t) => OrderingTerm.asc(t.id)]))
        .watch();
  }

  Future<List<Transaction>> search(String keyword, {int limit = 100}) =>
      (db.select(db.transactions)
            ..where((t) => t.note.like('%$keyword%'))
            ..orderBy([(t) => OrderingTerm.desc(t.date)])
            ..limit(limit))
          .get();

  (int, int) _monthRange(int yyyymm) {
    final year = yyyymm ~/ 100;
    final month = yyyymm % 100;
    final start = year * 10000 + month * 100 + 1;
    final end = DateTime(year, month + 1, 0).year * 10000 +
        DateTime(year, month + 1, 0).month * 100 +
        DateTime(year, month + 1, 0).day;
    return (start, end);
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/data/transactions_dao_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "feat: add transactions dao with month query"
```

---

### Task 5: 金额工具与统计纯函数

**Files:**
- Create: `lib/core/money.dart`
- Create: `lib/core/stats.dart`
- Create: `lib/core/date_util.dart`
- Test: `test/core/money_test.dart`、`test/core/stats_test.dart`

**Interfaces:**
- Consumes: `Transaction`、`TxType`
- Produces:
  - `int parseCents(String input)` — "12.34"→1234、"12"→1200、"0.5"→50；非法输入或超过两位小数抛 `FormatException`
  - `String formatCents(int cents)` — 1234→"12.34"、-50→"-0.50"、0→"0.00"
  - `int todayYyyymmdd()` — 本地日期转 yyyyMMdd
  - `int yyyymmOf(int yyyymmdd)` — 20260813→202608
  - `String formatYyyymm(int yyyymm)` — 202608→"2026年8月"
  - `int totalByType(List<Transaction> txs, TxType type)` — 求和
  - `Map<int, int> expenseByCategory(List<Transaction> txs)` — categoryId→分，仅支出
  - `List<({int yyyymm, int expenseCents, int incomeCents})> monthlyTrend(List<Transaction> txs, {required int months})` — 近 N 个自然月（含本月），缺失月补 0

- [ ] **Step 1: 写失败测试**

```dart
// test/core/money_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/money.dart';

void main() {
  test('parseCents basic', () {
    expect(parseCents('12.34'), 1234);
    expect(parseCents('12'), 1200);
    expect(parseCents('0.5'), 50);
    expect(parseCents('0'), 0);
  });
  test('parseCents rejects invalid input', () {
    expect(() => parseCents('12.345'), throwsFormatException);
    expect(() => parseCents('abc'), throwsFormatException);
    expect(() => parseCents(''), throwsFormatException);
    expect(() => parseCents('1.2.3'), throwsFormatException);
  });
  test('formatCents', () {
    expect(formatCents(1234), '12.34');
    expect(formatCents(0), '0.00');
    expect(formatCents(-50), '-0.50');
    expect(formatCents(100000), '1000.00');
  });
}
```

```dart
// test/core/stats_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/stats.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/data/transaction_type.dart';

Transaction tx(TxType type, int cents, int categoryId, int date) =>
    Transaction(id: 0, type: type, amountCents: cents, categoryId: categoryId,
        note: '', date: date, createdAt: DateTime(2026), updatedAt: DateTime(2026));

void main() {
  test('totalByType sums only matching type', () {
    final txs = [tx(TxType.expense, 100, 1, 20260801), tx(TxType.expense, 250, 1, 20260802), tx(TxType.income, 100000, 2, 20260803)];
    expect(totalByType(txs, TxType.expense), 350);
    expect(totalByType(txs, TxType.income), 100000);
  });

  test('expenseByCategory groups expenses only', () {
    final txs = [tx(TxType.expense, 100, 1, 20260801), tx(TxType.expense, 200, 1, 20260802), tx(TxType.expense, 50, 2, 20260803), tx(TxType.income, 999, 3, 20260804)];
    expect(expenseByCategory(txs), {1: 300, 2: 50});
  });

  test('monthlyTrend fills missing months with zero', () {
    final txs = [tx(TxType.expense, 100, 1, 20260715), tx(TxType.expense, 200, 1, 20260810), tx(TxType.income, 5000, 2, 20260601)];
    final trend = monthlyTrend(txs, months: 3);
    expect(trend.map((t) => t.yyyymm), [202606, 202607, 202608]);
    expect(trend[1].expenseCents, 100);
    expect(trend[0].incomeCents, 5000);
    expect(trend[2].expenseCents, 200);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/core/money_test.dart test/core/stats_test.dart`
Expected: FAIL — 编译错误

- [ ] **Step 3: 实现**

```dart
// lib/core/money.dart
/// 金额以「分」(int) 为单位。输入 "12.34" → 1234。
int parseCents(String input) {
  final s = input.trim();
  if (s.isEmpty || s == '-' || s == '.') throw const FormatException('invalid amount');
  final negative = s.startsWith('-');
  final body = negative ? s.substring(1) : s;
  final parts = body.split('.');
  if (parts.length > 2) throw const FormatException('invalid amount');
  final whole = parts[0];
  if (whole.isEmpty || whole.contains(RegExp(r'[^0-9]'))) {
    throw const FormatException('invalid amount');
  }
  if (parts.length == 2) {
    final frac = parts[1];
    if (frac.length > 2 || frac.isEmpty || frac.contains(RegExp(r'[^0-9]'))) {
      throw const FormatException('invalid amount');
    }
    final cents = int.parse(whole) * 100 + int.parse(frac.padRight(2, '0'));
    return negative ? -cents : cents;
  }
  final cents = int.parse(whole) * 100;
  return negative ? -cents : cents;
}

/// 1234 → "12.34"。避免 double 参与任何金额运算。
String formatCents(int cents) {
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  return '$sign${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
}
```

```dart
// lib/core/date_util.dart
int todayYyyymmdd() {
  final n = DateTime.now();
  return n.year * 10000 + n.month * 100 + n.day;
}

int yyyymmOf(int yyyymmdd) => yyyymmdd ~/ 100;

String formatYyyymm(int yyyymm) {
  final m = yyyymm % 100;
  final y = yyyymm ~/ 100;
  if (m == 0) return '$y年';
  return '$y年$m月';
}
```

```dart
// lib/core/stats.dart
import '../data/database.dart';
import '../data/transaction_type.dart';

int totalByType(List<Transaction> txs, TxType type) => txs
    .where((t) => t.type == type)
    .fold(0, (sum, t) => sum + t.amountCents);

Map<int, int> expenseByCategory(List<Transaction> txs) {
  final map = <int, int>{};
  for (final t in txs.where((t) => t.type == TxType.expense)) {
    map[t.categoryId] = (map[t.categoryId] ?? 0) + t.amountCents;
  }
  return map;
}

typedef MonthTotal = ({int yyyymm, int expenseCents, int incomeCents});

/// 近 [months] 个自然月（含当月），缺失月份补 0。yyyymm 升序。
List<MonthTotal> monthlyTrend(List<Transaction> txs, {required int months}) {
  final now = DateTime.now();
  final result = <MonthTotal>[];
  for (var i = months - 1; i >= 0; i--) {
    final month = DateTime(now.year, now.month - i, 1);
    final yyyymm = month.year * 100 + month.month;
    final inMonth = txs.where((t) => t.date ~/ 100 == yyyymm);
    result.add((
      yyyymm: yyyymm,
      expenseCents: totalByType(inMonth.toList(), TxType.expense),
      incomeCents: totalByType(inMonth.toList(), TxType.income),
    ));
  }
  return result;
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/core/money_test.dart test/core/stats_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "feat: add money and stats pure functions"
```

---

### Task 6: Riverpod 应用层 providers

**Files:**
- Create: `lib/application/providers.dart`
- Test: `test/application/providers_test.dart`

**Interfaces:**
- Consumes: Task 2-5 全部
- Produces:
  - `final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError())` — 在 main 中 override 为真实库
  - `final categoriesDaoProvider = Provider(...)`、`transactionsDaoProvider = Provider(...)`
  - `final allCategoriesProvider = StreamProvider<List<Category>>`
  - `final currentMonthProvider = Provider<int>`（默认返回当月 yyyymm，可被 UI 覆盖）
  - `final monthTransactionsProvider = StreamProvider<List<Transaction>>` — 基于 currentMonthProvider
  - `final monthSummaryProvider = Provider<({int incomeCents, int expenseCents, int balanceCents})>` — 基于 monthTransactionsProvider 的当前值
  - `final categoryExpenseProvider = StreamProvider<Map<int, int>>` — 全部交易按月过滤后聚合（用 monthlyTrend 的输入，这里简化：最近 6 个月的饼图数据也在此）

- [ ] **Step 1: 写失败测试**

```dart
// test/application/providers_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:ledger/application/providers.dart';
import 'package:ledger/data/dao/categories_dao.dart';
import 'package:ledger/data/dao/transactions_dao.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/data/transaction_type.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase.open(executor: NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    await CategoriesDao(db).seedBuiltinCategories();
    final cats = await CategoriesDao(db).getByType(TxType.expense);
    await TransactionsDao(db).insertTransaction(TxType.expense, 1234, cats.first.id, 20260813, '午饭');
    await container.read(transactionsDaoProvider); // 确保 provider 图就绪
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('monthSummaryProvider computes income/expense/balance', () async {
    container.read(currentMonthProvider.notifier).state = 202608;
    final summary = await container.read(monthSummaryProvider.future);
    expect(summary.expenseCents, 1234);
    expect(summary.incomeCents, 0);
    expect(summary.balanceCents, -1234);
  });

  test('allCategoriesProvider emits seeded categories', () async {
    final cats = await container.read(allCategoriesProvider.future);
    expect(cats.length, greaterThan(5));
    expect(cats.every((c) => c.isBuiltin), isTrue);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/application/providers_test.dart`
Expected: FAIL — 编译错误

- [ ] **Step 3: 实现 providers**

```dart
// lib/application/providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/date_util.dart';
import '../core/stats.dart';
import '../data/dao/categories_dao.dart';
import '../data/dao/transactions_dao.dart';
import '../data/database.dart';

final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError());
final categoriesDaoProvider = Provider((ref) => CategoriesDao(ref.watch(databaseProvider)));
final transactionsDaoProvider = Provider((ref) => TransactionsDao(ref.watch(databaseProvider)));

final allCategoriesProvider = StreamProvider<List<Category>>(
    (ref) => ref.watch(categoriesDaoProvider).watchAll());

final currentMonthProvider =
    NotifierProvider<CurrentMonthNotifier, int>(CurrentMonthNotifier.new);

class CurrentMonthNotifier extends Notifier<int> {
  @override
  int build() => yyyymmOf(todayYyyymmdd());
  void setMonth(int yyyymm) => state = yyyymm;
}

final monthTransactionsProvider = StreamProvider<List<Transaction>>((ref) {
  final month = ref.watch(currentMonthProvider);
  return ref.watch(transactionsDaoProvider).watchByMonth(month);
});

final monthSummaryProvider = Provider<({int incomeCents, int expenseCents, int balanceCents})>(
    (ref) {
  final txs = ref.watch(monthTransactionsProvider).value ?? const <Transaction>[];
  final income = totalByType(txs, TxType.income);
  final expense = totalByType(txs, TxType.expense);
  return (incomeCents: income, expenseCents: expense, balanceCents: income - expense);
});

/// 当前月按分类支出：categoryId → 分（仅支出）
final categoryExpenseProvider = Provider<Map<int, int>>((ref) {
  final txs = ref.watch(monthTransactionsProvider).value ?? const <Transaction>[];
  return expenseByCategory(txs);
});
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/application/providers_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "feat: add riverpod providers"
```

---

### Task 7: 首页仪表盘

**Files:**
- Create: `lib/main.dart`、`lib/app.dart`（MaterialApp + go_router 路由骨架 + ProviderScope + databaseProvider override + 种子调用）
- Create: `lib/presentation/screens/home_screen.dart`
- Create: `lib/presentation/theme/app_theme.dart`
- Test: `test/presentation/home_screen_test.dart`

**Interfaces:**
- Consumes: Task 6 providers（`monthSummaryProvider`、`monthTransactionsProvider`、`allCategoriesProvider`、`currentMonthProvider`）
- Produces:
  - `void main()` — `WidgetsFlutterBinding.ensureInitialized(); await AppDatabase.open().migrator...` 简化：`final db = AppDatabase.open(); await CategoriesDao(db).seedBuiltinCategories(); runApp(ProviderScope(overrides: [...], child: const LedgerApp()))`
  - `class LedgerApp extends StatelessWidget` — MaterialApp(title: '记账', home: HomeScreen)
  - `class HomeScreen` — 本月收支摘要卡片（收入/支出/结余，绿色/红色/默认色）+ 最近 5 条记录 + 空状态"还没有记账记录"
  - 月份切换：AppBar 显示当前月（`formatYyyymm`），左右箭头切换 `currentMonthProvider`

- [ ] **Step 1: 写失败测试**

```dart
// test/presentation/home_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:ledger/application/providers.dart';
import 'package:ledger/data/dao/categories_dao.dart';
import 'package:ledger/data/dao/transactions_dao.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/presentation/screens/home_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.open(executor: NativeDatabase.memory());
    await CategoriesDao(db).seedBuiltinCategories();
  });
  tearDown(() => db.close());

  Widget wrap() => ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: HomeScreen()),
      );

  testWidgets('empty state shows hint', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();
    expect(find.text('还没有记账记录'), findsOneWidget);
    expect(find.text('0.00'), findsWidgets); // 支出/收入/结余
  });

  testWidgets('shows summary and recent transactions', (tester) async {
    final cats = await CategoriesDao(db).getByType(TxType.expense);
    await TransactionsDao(db).insertTransaction(TxType.expense, 1234, cats.first.id, 20260813, '午饭');
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();
    expect(find.text('12.34'), findsOneWidget); // 支出卡片
    expect(find.text('午饭'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/presentation/home_screen_test.dart`
Expected: FAIL — 编译错误

- [ ] **Step 3: 实现入口与主题**

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'application/providers.dart';
import 'data/dao/categories_dao.dart';
import 'data/database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase.open();
  await CategoriesDao(db).seedBuiltinCategories();
  runApp(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const LedgerApp(),
  ));
}
```

```dart
// lib/app.dart
import 'package:flutter/material.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/theme/app_theme.dart';

class LedgerApp extends StatelessWidget {
  const LedgerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '记账',
        theme: AppTheme.light,
        home: const HomeScreen(),
      );
}
```

```dart
// lib/presentation/theme/app_theme.dart
import 'package:flutter/material.dart';

class AppTheme {
  static const expenseColor = Color(0xFFE53935); // 支出红
  static const incomeColor = Color(0xFF43A047);  // 收入绿

  static ThemeData get light => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E88E5)),
        useMaterial3: true,
        fontFamily: null, // 跟随系统中文
      );
}
```

- [ ] **Step 4: 实现首页**

```dart
// lib/presentation/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../core/date_util.dart';
import '../../core/money.dart';
import '../theme/app_theme.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(currentMonthProvider);
    final summary = ref.watch(monthSummaryProvider);
    final txs = ref.watch(monthTransactionsProvider).value ?? const [];
    final cats = ref.watch(allCategoriesProvider).value ?? const [];

    String catName(int id) =>
        cats.where((c) => c.id == id).map((c) => c.name).firstOrNull ?? '未分类';

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
              onPressed: () => ref.read(currentMonthProvider.notifier).setMonth(_shift(month, -1)),
              icon: const Icon(Icons.chevron_left)),
          Text(formatYyyymm(month), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          IconButton(
              onPressed: () => ref.read(currentMonthProvider.notifier).setMonth(_shift(month, 1)),
              icon: const Icon(Icons.chevron_right)),
        ]),
      ),
      body: Column(children: [
        _SummaryCard(summary: summary),
        Expanded(
          child: txs.isEmpty
              ? const Center(child: Text('还没有记账记录'))
              : ListView.builder(
                  itemCount: txs.length > 5 ? 5 : txs.length,
                  itemBuilder: (_, i) => _TransactionTile(tx: txs[i], categoryName: catName(txs[i].categoryId)),
                ),
        ),
      ]),
    );
  }

  int _shift(int yyyymm, int delta) {
    final y = yyyymm ~/ 100, m = yyyymm % 100;
    final d = DateTime(y, m + delta, 1);
    return d.year * 100 + d.month;
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});
  final ({int incomeCents, int expenseCents, int balanceCents}) summary;

  @override
  Widget build(BuildContext context) {
    final c = context.colorScheme;
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text('结余', style: TextStyle(color: c.onSurfaceVariant, fontSize: 13)),
          Text(formatCents(summary.balanceCents),
              style: TextStyle(
                  fontSize: 32, fontWeight: FontWeight.bold,
                  color: summary.balanceCents >= 0 ? AppTheme.incomeColor : AppTheme.expenseColor)),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            Text('收入 ${formatCents(summary.incomeCents)}', style: const TextStyle(color: AppTheme.incomeColor)),
            Text('支出 ${formatCents(summary.expenseCents)}', style: const TextStyle(color: AppTheme.expenseColor)),
          ]),
        ]),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.tx, required this.categoryName});
  final Transaction tx;
  final String categoryName;

  @override
  Widget build(BuildContext context) {
    final isExpense = tx.type == TxType.expense;
    final color = isExpense ? AppTheme.expenseColor : AppTheme.incomeColor;
    final sign = isExpense ? '-' : '+';
    return ListTile(
      leading: CircleAvatar(child: Text(categoryName.characters.first)),
      title: Text(categoryName),
      subtitle: Text(tx.note.isEmpty ? ' ' : tx.note),
      trailing: Text('$sign${formatCents(tx.amountCents)}',
          style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 16)),
      onTap: () {}, // Task 9 接编辑
    );
  }
}
```

- [ ] **Step 5: 运行测试确认通过**

Run: `flutter test test/presentation/home_screen_test.dart`
Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add -A
git commit -m "feat: add home dashboard screen"
```

---

### Task 8: 记一笔 / 编辑表单

**Files:**
- Create: `lib/presentation/screens/add_transaction_screen.dart`
- Create: `lib/presentation/widgets/amount_field.dart`、`category_picker.dart`
- Modify: `lib/app.dart`（路由），`lib/presentation/screens/home_screen.dart`（FAB 入口、点击记录进编辑）
- Test: `test/presentation/add_transaction_screen_test.dart`

**Interfaces:**
- Consumes: Task 3-6（`CategoriesDao`/`TransactionsDao`、`allCategoriesProvider`）
- Produces:
  - `class AddTransactionScreen extends ConsumerStatefulWidget`，构造参数：`{Transaction? initial}`（非空=编辑模式）
  - 路由：`GoRouter(routes: [GoRoute(path: '/', builder: ...Home), GoRoute(path: '/add', builder: ...), GoRoute(path: '/edit/:id', ...)])` — 简化用 MaterialPageRoute 亦可，直接 Navigator.push 传参，无状态路由（个人项目 YAGNI，用 Navigator.push + MaterialPageRoute）
  - 表单：类型 Tab（支出/收入）、金额 TextField（`keyboardType: TextInputType.numberWithOptions(decimal: true)`）、分类横向选择（带图标 + 名称）、日期行（默认今天，点开 showDatePicker）、备注行、保存按钮
  - 保存时：`parseCents` 失败弹 SnackBar"请输入有效金额"；成功 pop 并刷新（drift Stream 自动刷新）

- [ ] **Step 1: 写失败测试**

```dart
// test/presentation/add_transaction_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:ledger/application/providers.dart';
import 'package:ledger/data/dao/categories_dao.dart';
import 'package:ledger/data/dao/transactions_dao.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/presentation/screens/add_transaction_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.open(executor: NativeDatabase.memory());
    await CategoriesDao(db).seedBuiltinCategories();
  });
  tearDown(() => db.close());

  Future<void> pumpForm(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: AddTransactionScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('saves a transaction and shows it in list', (tester) async {
    await pumpForm(tester);
    await tester.enterText(find.byType(TextField).first, '12.34');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final txs = await TransactionsDao(db).getByMonth(202608);
    expect(txs.single.amountCents, 1234);
    expect(txs.single.type, TxType.expense);
  });

  testWidgets('invalid amount shows error snackbar', (tester) async {
    await pumpForm(tester);
    await tester.enterText(find.byType(TextField).first, 'abc');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('请输入有效金额'), findsOneWidget);
    expect(await TransactionsDao(db).getByMonth(202608), isEmpty);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/presentation/add_transaction_screen_test.dart`
Expected: FAIL — 编译错误

- [ ] **Step 3: 实现金额输入与分类选择器**

```dart
// lib/presentation/widgets/amount_field.dart
import 'package:flutter/material.dart';

/// 金额输入框：仅允许数字与一个小数点，最多两位小数。
class AmountField extends StatelessWidget {
  const AmountField({super.key, required this.controller, this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
      textAlign: TextAlign.center,
      decoration: const InputDecoration(
        hintText: '0.00',
        prefixText: '¥ ',
        border: InputBorder.none,
      ),
      inputFormatters: [AmountInputFormatter()],
      onChanged: onChanged,
    );
  }
}

class AmountInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue neu) {
    final text = neu.text;
    if (text.isEmpty) return neu;
    if (!RegExp(r'^\d{0,7}(\.\d{0,2})?$').hasMatch(text)) return old;
    return neu;
  }
}
```

```dart
// lib/presentation/widgets/category_picker.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../data/transaction_type.dart';

class CategoryPicker extends ConsumerWidget {
  const CategoryPicker({super.key, required this.type, required this.selectedId, required this.onSelect});
  final TxType type;
  final int selectedId;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(allCategoriesProvider).value ?? const <Category>[];
    final filtered = cats.where((c) => c.type == type).toList();
    return SizedBox(
      height: 76,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: filtered.length,
        itemBuilder: (_, i) {
          final c = filtered[i];
          final selected = c.id == selectedId;
          return InkWell(
            onTap: () => onSelect(c.id),
            child: Container(
              width: 64,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.fromCodePoint(_iconCodePoint(c.icon)), color: selected ? Theme.of(context).colorScheme.primary : null),
                Text(c.name, style: const TextStyle(fontSize: 12)),
              ]),
            ),
          );
        },
      ),
    );
  }

  int _iconCodePoint(String name) {
    // 简单映射：内置分类 icon 名 → Material Icons codepoint
    const map = {
      'restaurant': 0xe56c, 'directions_bus': 0xe1df, 'shopping_bag': 0xe1cf,
      'home': 0xe88a, 'sports_esports': 0xe21b, 'local_hospital': 0xe548,
      'school': 0xe80c, 'payments': 0xe8a1, 'work': 0xe8f9,
      'trending_up': 0xe8e5, 'redeem': 0xe838,
    };
    return map[name] ?? 0xe3a4; // fallback: Icons.face
  }
}
```

- [ ] **Step 4: 实现表单页**

```dart
// lib/presentation/screens/add_transaction_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../core/date_util.dart';
import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/transaction_type.dart';
import '../widgets/amount_field.dart';
import '../widgets/category_picker.dart';

class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key, this.initial});
  final Transaction? initial;

  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  late TxType _type;
  late final TextEditingController _amount;
  int _categoryId = -1;
  int _date = 0;
  String _note = '';

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    _type = t?.type ?? TxType.expense;
    _amount = TextEditingController(text: t == null ? '' : formatCents(t.amountCents));
    _categoryId = t?.categoryId ?? -1;
    _date = t?.date ?? todayYyyymmdd();
    _note = t?.note ?? '';
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cents = parseCents(_amount.text);
    if (_categoryId < 0) {
      _show('请选择分类');
      return;
    }
    final dao = ref.read(transactionsDaoProvider);
    final t = widget.initial;
    try {
      if (t == null) {
        await dao.insertTransaction(_type, cents, _categoryId, _date, _note.trim());
      } else {
        await dao.updateTransaction(t, type: _type, amountCents: cents,
            categoryId: _categoryId, date: _date, note: _note.trim());
      }
      if (mounted) Navigator.pop(context);
    } on FormatException {
      _show('请输入有效金额');
    }
  }

  void _show(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.initial == null ? '记一笔' : '编辑记录')),
      body: SafeArea(
        child: Column(children: [
          SegmentedButton<TxType>(
            segments: const [
              ButtonSegment(value: TxType.expense, label: Text('支出')),
              ButtonSegment(value: TxType.income, label: Text('收入')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() {
              _type = s.first;
              _categoryId = -1; // 换类型需重选分类
            }),
          ),
          AmountField(controller: _amount),
          CategoryPicker(
              type: _type, selectedId: _categoryId,
              onSelect: (id) => setState(() => _categoryId = id)),
          ListTile(
            leading: const Icon(Icons.event),
            title: Text('日期 ${_date.toString()}'),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                setState(() => _date = picked.year * 10000 + picked.month * 100 + picked.day);
              }
            },
          ),
          TextField(
            decoration: const InputDecoration(labelText: '备注', prefixIcon: Icon(Icons.notes)),
            onChanged: (v) => _note = v,
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: const Text('保存'),
            ),
          ),
        ]),
      ),
    );
  }
}
```

- [ ] **Step 5: 接通入口（修改 home_screen.dart）**

```dart
// HomeScreen 的 Scaffold 加 FAB；_TransactionTile.onTap 跳编辑
floatingActionButton: FloatingActionButton(
  onPressed: () => Navigator.push(context, MaterialPageRoute(
      builder: (_) => const AddTransactionScreen())),
  child: const Icon(Icons.add),
),
// _TransactionTile.onTap:
// Navigator.push(context, MaterialPageRoute(builder: (_) => AddTransactionScreen(initial: tx)))
```

- [ ] **Step 6: 运行测试确认通过**

Run: `flutter test test/presentation/add_transaction_screen_test.dart`
Expected: PASS

- [ ] **Step 7: 提交**

```bash
git add -A
git commit -m "feat: add transaction form screen"
```

---

### Task 9: 账单列表（按月分组 + 搜索 + 滑动删除）

**Files:**
- Create: `lib/presentation/screens/transactions_screen.dart`
- Modify: `lib/presentation/screens/home_screen.dart`（"查看全部"入口）
- Test: `test/presentation/transactions_screen_test.dart`

**Interfaces:**
- Consumes: Task 4/6/7 全部
- Produces:
  - `class TransactionsScreen extends ConsumerWidget` — 当前月全部记录，按月内分组显示（日期间隔标题），`Dismissible` 滑动删除 + 撤销 SnackBar，点击进编辑
  - `Future<void> _delete(BuildContext, WidgetRef, Transaction)` — 删除 + SnackBar("已删除" + 撤销按钮，撤销 = 重新 insert)

- [ ] **Step 1: 写失败测试**

```dart
// test/presentation/transactions_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:ledger/application/providers.dart';
import 'package:ledger/data/dao/categories_dao.dart';
import 'package:ledger/data/dao/transactions_dao.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/data/transaction_type.dart';
import 'package:ledger/presentation/screens/transactions_screen.dart';

void main() {
  late AppDatabase db;
  late int foodId;

  setUp(() async {
    db = AppDatabase.open(executor: NativeDatabase.memory());
    await CategoriesDao(db).seedBuiltinCategories();
    foodId = (await CategoriesDao(db).getByType(TxType.expense)).first.id;
    await TransactionsDao(db).insertTransaction(TxType.expense, 100, foodId, 20260813, '午饭');
    await TransactionsDao(db).insertTransaction(TxType.expense, 200, foodId, 20260801, '早饭');
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: TransactionsScreen(
          initialMonth: 202608,
          onExit: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('lists transactions grouped by day', (tester) async {
    await pump(tester);
    expect(find.text('午饭'), findsOneWidget);
    expect(find.text('早饭'), findsOneWidget);
  });

  testWidgets('swipe deletes and undo restores', (tester) async {
    await pump(tester);
    await tester.drag(find.text('午饭'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(await TransactionsDao(db).getByMonth(202608), hasLength(1));
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(await TransactionsDao(db).getByMonth(202608), hasLength(2));
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/presentation/transactions_screen_test.dart`
Expected: FAIL — 编译错误

- [ ] **Step 3: 实现列表页**

```dart
// lib/presentation/screens/transactions_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../core/date_util.dart';
import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/transaction_type.dart';
import '../theme/app_theme.dart';
import 'add_transaction_screen.dart';

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key, required this.initialMonth, required this.onExit});
  final int initialMonth;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(currentMonthProvider);
    final txs = ref.watch(monthTransactionsProvider).value ?? const <Transaction>[];
    final cats = ref.watch(allCategoriesProvider).value ?? const <Category>[];
    final dao = ref.read(transactionsDaoProvider);

    String catName(int id) =>
        cats.where((c) => c.id == id).map((c) => c.name).firstOrNull ?? '未分类';

    // 按日期分组（date 降序）
    final groups = <int, List<Transaction>>{};
    for (final t in txs.reversed) {
      groups.putIfAbsent(t.date, () => []).add(t);
    }

    Future<void> delete(Transaction tx) async {
      await dao.deleteTransaction(tx.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('已删除'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => dao.insertTransaction(
              tx.type, tx.amountCents, tx.categoryId, tx.date, tx.note),
        ),
      ));
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: onExit),
        title: Text('账单'),
      ),
      body: txs.isEmpty
          ? const Center(child: Text('本月还没有记录'))
          : ListView(
              children: [
                for (final entry in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text('${entry.key}',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12)),
                  ),
                  for (final tx in entry.value)
                    Dismissible(
                      key: ValueKey(tx.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                          color: AppTheme.expenseColor,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.delete, color: Colors.white)),
                      onDismissed: (_) => delete(tx),
                      child: ListTile(
                        leading: CircleAvatar(child: Text(catName(tx.categoryId).characters.first)),
                        title: Text(catName(tx.categoryId)),
                        subtitle: Text(tx.note.isEmpty ? ' ' : tx.note),
                        trailing: Text(
                          '${tx.type == TxType.expense ? '-' : '+'}${formatCents(tx.amountCents)}',
                          style: TextStyle(
                              color: tx.type == TxType.expense
                                  ? AppTheme.expenseColor
                                  : AppTheme.incomeColor,
                              fontWeight: FontWeight.w600),
                        ),
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => AddTransactionScreen(initial: tx))),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/presentation/transactions_screen_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "feat: add grouped transactions list with swipe delete"
```

---

### Task 10: 分类管理页

**Files:**
- Create: `lib/presentation/screens/categories_screen.dart`
- Modify: `lib/presentation/screens/home_screen.dart`（AppBar 入口图标 → 分类页）
- Test: `test/presentation/categories_screen_test.dart`

**Interfaces:**
- Consumes: Task 3 `CategoriesDao`（含 `CategoryInUseException`）
- Produces:
  - `class CategoriesScreen extends ConsumerWidget` — 支出/收入两个 Tab；每类 ListTile（图标+名称，内置分类显示"内置"标签）；FAB 新增（dialog 输入名称 + 选图标）；长按/详情编辑；删除时内置分类或 CategoryInUseException 弹 SnackBar 提示
  - 图标选择：提供固定图标列表（复用 category_picker 的 icon map 键）

- [ ] **Step 1: 写失败测试**

```dart
// test/presentation/categories_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:ledger/application/providers.dart';
import 'package:ledger/data/dao/categories_dao.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/presentation/screens/categories_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.open(executor: NativeDatabase.memory());
    await CategoriesDao(db).seedBuiltinCategories();
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: CategoriesScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows builtin categories', (tester) async {
    await pump(tester);
    expect(find.text('餐饮'), findsOneWidget);
    expect(find.text('工资'), findsWidgets); // 收入 Tab 也要有（TabBar 存在即可）
  });

  testWidgets('adds custom category', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '猫粮');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('猫粮'), findsOneWidget);
  });

  testWidgets('builtin category cannot be deleted', (tester) async {
    await pump(tester);
    await tester.tap(find.text('餐饮'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('内置分类不可删除'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/presentation/categories_screen_test.dart`
Expected: FAIL — 编译错误

- [ ] **Step 3: 实现分类页**

```dart
// lib/presentation/screens/categories_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../data/dao/categories_dao.dart';
import '../../data/database.dart';
import '../../data/transaction_type.dart';
import '../widgets/category_picker.dart' show CategoryPickerIcon; // 复用图标映射

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(allCategoriesProvider).value ?? const <Category>[];
    final dao = ref.read(categoriesDaoProvider);

    Future<void> addDialog() async {
      final nameCtrl = TextEditingController();
      final type = TxType.expense; // 简化：默认支出，Tab 切换影响新增类型可后续增强
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('新增分类'),
          content: TextField(controller: nameCtrl, decoration: const InputDecoration(hintText: '分类名称')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                await dao.insertCategory(name, 'face', type);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      );
    }

    Future<void> deleteFlow(Category c) async {
      if (c.isBuiltin) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('内置分类不可删除')));
        return;
      }
      try {
        await dao.deleteCategory(c);
      } on CategoryInUseException {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('该分类已被记录使用，无法删除')));
        }
      }
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('分类管理'),
          bottom: const TabBar(tabs: [Tab(text: '支出'), Tab(text: '收入')]),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: addDialog, child: const Icon(Icons.add)),
        body: TabBarView(children: [
          _CategoryList(cats: cats.where((c) => c.type == TxType.expense).toList(),
              onDelete: deleteFlow),
          _CategoryList(cats: cats.where((c) => c.type == TxType.income).toList(),
              onDelete: deleteFlow),
        ]),
      ),
    );
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({required this.cats, required this.onDelete});
  final List<Category> cats;
  final Future<void> Function(Category) onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: cats.length,
      itemBuilder: (_, i) {
        final c = cats[i];
        return ListTile(
          leading: CircleAvatar(child: Text(c.name.characters.first)),
          title: Text(c.name),
          subtitle: c.isBuiltin ? const Text('内置分类') : null,
          trailing: c.isBuiltin
              ? null
              : IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => onDelete(c)),
        );
      },
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/presentation/categories_screen_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "feat: add categories management screen"
```

---

### Task 11: 统计页（图表）

**Files:**
- Create: `lib/presentation/screens/statistics_screen.dart`
- Create: `lib/presentation/widgets/category_pie_chart.dart`、`monthly_bar_chart.dart`
- Modify: `lib/presentation/screens/home_screen.dart`（底部导航加入口，或 AppBar 图标）
- Test: `test/presentation/statistics_screen_test.dart`

**Interfaces:**
- Consumes: Task 5 `stats.dart`、Task 6 providers
- Produces:
  - `class StatisticsScreen extends ConsumerWidget` — 三块：分类占比饼图（fl_chart PieChart，当前月支出，颜色来自 `AppTheme` 色板轮换）、近 6 月收支柱状图（fl_chart BarChart）、分类支出排行 ListTile
  - 数据源：`categoryExpenseProvider`（饼图/排行）、`monthlyTrend`（柱状图，取全量交易——需要新 provider `allTransactionsProvider = StreamProvider`，本任务一并加）
  - 无数据时显示"本月暂无支出记录"

- [ ] **Step 1: 加 allTransactionsProvider（修改 providers.dart）并写失败测试**

```dart
// providers.dart 新增：
final allTransactionsProvider = StreamProvider<List<Transaction>>(
    (ref) => ref.watch(transactionsDaoProvider).watchAll());

// TransactionsDao 新增：
Stream<List<Transaction>> watchAll() =>
    (db.select(db.transactions)..orderBy([(t) => OrderingTerm.desc(t.date)])).watch();
```

```dart
// test/presentation/statistics_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:ledger/application/providers.dart';
import 'package:ledger/data/dao/categories_dao.dart';
import 'package:ledger/data/dao/transactions_dao.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/data/transaction_type.dart';
import 'package:ledger/presentation/screens/statistics_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.open(executor: NativeDatabase.memory());
    await CategoriesDao(db).seedBuiltinCategories();
    final cats = await CategoriesDao(db).getByType(TxType.expense);
    await TransactionsDao(db).insertTransaction(TxType.expense, 1000, cats[0].id, 20260810, 'a');
    await TransactionsDao(db).insertTransaction(TxType.expense, 2000, cats[1].id, 20260811, 'b');
  });
  tearDown(() => db.close());

  testWidgets('shows category ranking', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(home: StatisticsScreen(initialMonth: 202608)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('10.00'), findsOneWidget); // 1000 分
    expect(find.text('20.00'), findsOneWidget); // 2000 分
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/presentation/statistics_screen_test.dart`
Expected: FAIL — 编译错误

- [ ] **Step 3: 实现统计页**

```dart
// lib/presentation/screens/statistics_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../application/providers.dart';
import '../../core/date_util.dart';
import '../../core/money.dart';
import '../../core/stats.dart';
import '../../data/database.dart';
import '../theme/app_theme.dart';

/// 分类色板：饼图/柱状图共用，按 index 轮换
const pieColors = <Color>[
  Color(0xFF1E88E5), Color(0xFF43A047), Color(0xFFFB8C00), Color(0xFF8E24AA),
  Color(0xFFE53935), Color(0xFF00ACC1), Color(0xFF6D4C41), Color(0xFF546E7A),
  Color(0xFFF4511E), Color(0xFF7CB342), Color(0xFF5E35B1), Color(0xFFD81B60),
];

class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key, this.initialMonth});
  final int? initialMonth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(currentMonthProvider);
    final cats = ref.watch(allCategoriesProvider).value ?? const <Category>[];
    final all = ref.watch(allTransactionsProvider).value ?? const <Transaction>[];
    final byCategory = ref.watch(categoryExpenseProvider);
    final trend = monthlyTrend(all, months: 6);

    String catName(int id) =>
        cats.where((c) => c.id == id).map((c) => c.name).firstOrNull ?? '未分类';

    final ranking = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(title: Text('统计 · ${formatYyyymm(month)}')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _SectionCard(title: '本月支出分类占比', child: ranking.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('本月暂无支出记录')))
              : SizedBox(
                  height: 220,
                  child: PieChart(PieChartData(
                    sections: [
                      for (var i = 0; i < ranking.length; i++)
                        PieChartSectionData(
                          value: ranking[i].value.toDouble(),
                          color: pieColors[i % pieColors.length],
                          title: catName(ranking[i].key),
                          titleStyle: const TextStyle(fontSize: 11, color: Colors.white),
                          radius: 40,
                        ),
                    ],
                    centerSpaceRadius: 40,
                  )))),
          _SectionCard(title: '近 6 个月收支趋势', child: SizedBox(
              height: 200,
              child: BarChart(BarChartData(
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= trend.length) return const SizedBox.shrink();
                      final m = trend[i].yyyymm % 100;
                      return Padding(padding: const EdgeInsets.only(top: 4),
                          child: Text('$m月', style: const TextStyle(fontSize: 10)));
                    },
                  )),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                barGroups: [
                  for (var i = 0; i < trend.length; i++) ...[
                    BarChartGroupData(x: i, barsSpace: 2, barRods: [
                      BarChartRodData(
                          toY: (trend[i].incomeCents / 100).toDouble(),
                          color: AppTheme.incomeColor, width: 12),
                      BarChartRodData(
                          toY: (trend[i].expenseCents / 100).toDouble(),
                          color: AppTheme.expenseColor, width: 12),
                    ]),
                  ],
                ],
              )))),
          _SectionCard(title: '支出分类排行', child: ranking.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('暂无数据'))
              : Column(children: [
                  for (final e in ranking)
                    ListTile(
                      dense: true,
                      leading: CircleAvatar(
                          backgroundColor: pieColors[ranking.indexOf(e) % pieColors.length],
                          child: Text(catName(e.key).characters.first,
                              style: const TextStyle(color: Colors.white, fontSize: 12))),
                      title: Text(catName(e.key)),
                      trailing: Text(formatCents(e.value),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                ])),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            child,
          ]),
        ),
      );
}
```

- [ ] **Step 4: 首页加底部导航（修改 home_screen.dart）**

```dart
// HomeScreen 改为带 BottomNavigationBar 的 StatefulWidget 壳，或简化：AppBar actions 加图标
actions: [
  IconButton(icon: const Icon(Icons.pie_chart_outline),
      onPressed: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const StatisticsScreen()))),
  IconButton(icon: const Icon(Icons.category_outlined),
      onPressed: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const CategoriesScreen()))),
],
// 并加列表页入口："查看全部"按钮 → TransactionsScreen
```

- [ ] **Step 5: 运行测试确认通过**

Run: `flutter test test/presentation/statistics_screen_test.dart`
Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add -A
git commit -m "feat: add statistics screen with charts"
```

---

### Task 12: 打磨与打包

**Files:**
- Modify: `lib/main.dart`（错误兜底：数据库打开失败显示错误页而非崩溃）
- Modify: `android/app/src/main/AndroidManifest.xml`（应用名改"记账"）
- Create: `README.md`（项目介绍、技术栈、运行方式、功能清单）
- Test: `test/widget_test.dart`（App 级冒烟测试：启动显示首页）

**Interfaces:**
- Produces: 可安装的 release APK，验收清单全过

- [ ] **Step 1: 写冒烟测试（先失败）**

```dart
// test/widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:ledger/app.dart';
import 'package:ledger/application/providers.dart';
import 'package:ledger/data/database.dart';

void main() {
  testWidgets('app boots and shows home', (tester) async {
    final db = AppDatabase.open(executor: NativeDatabase.memory());
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const LedgerApp(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('记账'), findsOneWidget); // AppBar 月份附近标题
    await db.close();
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/widget_test.dart`
Expected: 因首页无"记账"文本而 FAIL（或编译通过但断言失败）

- [ ] **Step 3: 改应用名与 README**

```xml
<!-- AndroidManifest.xml -->
<application android:label="记账" ...>
```

README.md：项目简介（本地优先记账 App）、功能列表（MVP 完成项）、技术栈表格、`flutter run` / `flutter build apk` 用法、目录结构说明。

- [ ] **Step 4: 调整测试断言后运行全部测试**

Run: `flutter test`
Expected: 全部 PASS（断言失败则调整断言——冒烟测试目标是"App 能启动且首页可渲染"）

- [ ] **Step 5: 构建 release APK**

```bash
flutter build apk --release
```

产物：`build/app/outputs/flutter-apk/app-release.apk`

- [ ] **Step 6: 真机验收清单（用户手动执行）**

- 记一笔支出（12.34 元）→ 首页本月支出显示 12.34、结余为 -12.34
- 切月份 → 空月显示"还没有记账记录"
- 编辑记录 → 金额/分类变化正确
- 滑动删除 → 撤销恢复
- 分类页新增"猫粮" → 记一笔时可选到；删除内置分类被拦截
- 统计页：饼图/柱状图/排行与记录一致；空月显示"本月暂无支出记录"
- **杀进程重启 App → 数据仍在（持久化）**
- 录一笔后等 1 秒，检查无红色错误弹窗（FlutterError.onError 无异常）

- [ ] **Step 7: 提交**

```bash
git add -A
git commit -m "chore: polish app for release"
```

---

## 里程碑与任务映射

| 里程碑 | 任务 | 交付 |
|---|---|---|
| M0 环境搭建 | Task 1 | 可运行工程 + git |
| M1 数据层 | Task 2-6 | 表/DAO/工具/providers + 全绿单元测试 |
| M2 记账核心 | Task 7-9 | 首页/表单/列表，完整记账闭环 |
| M3 分类管理 | Task 10 | 分类 CRUD + 保护 |
| M4 统计图表 | Task 11 | 图表页 |
| M5 打磨发布 | Task 12 | APK + 验收清单 |

## Self-Review 记录

- **Spec 覆盖**：需求分析中 MVP 四项（收支记录、分类管理、统计图表、基础体验）→ Task 8/9（收支）、Task 3/10（分类）、Task 11（统计）、Task 7/12（基础体验），全部有对应任务。P1/P2 范围外。
- **金额约束**：所有金额路径均为 int 分（Task 4 DAO、Task 5 工具、Task 8 表单），图表仅展示时 `/100` 转 double，无运算。
- **类型一致性**：`parseCents`/`formatCents`/`yyyymmOf`/`formatYyyymm`/`todayYyyymmdd`/`totalByType`/`expenseByCategory`/`monthlyTrend` 在各任务中签名一致；`CategoryInUseException` 在 Task 3 定义、Task 10 消费。
