# 周期记账 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用户创建周期规则（房租/订阅/工资）后，每次打开 App 自动补齐缺失月份的记录。

**Architecture:** 新表 recurring_rules（schemaVersion 3）+ `last_generated_yyyymm` 幂等追踪；core 纯函数算缺失月份与月末收窄；RecurringDao 单事务补生成；main() 启动触发；设置页入口 → 规则列表页。

**Tech Stack:** drift migration + 现有 riverpod 栈，零新依赖。

**Spec:** docs/superpowers/specs/2026-08-14-recurring-design.md

## Global Constraints

- 金额一律整数分（amountCents int）；日期 int yyyyMMdd/yyyymm
- 生成幂等：同月不重复生成；新规则创建时 lastGenerated = 当月（当月不生成）
- TDD：先写失败测试 → 确认红 → 实现 → 绿 → commit
- drift widget 测试末尾必须：`await tester.pumpWidget(const SizedBox()); await tester.pump(Duration.zero);`；内存 db + UncontrolledProviderScope container 模式
- bash 调用需导出：`export PATH="/c/src/flutter/bin:$PATH" PUB_HOSTED_URL="https://pub.flutter-io.cn" FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"`
- 改 tables.dart 后必须重跑：`dart run build_runner build --delete-conflicting-outputs`
- commit message 简洁英文 + `Co-Authored-By: Claude <noreply@anthropic.com>`

---

### Task 1: recurring_rules 表 + v3 migration + 重新生成

**Files:**
- Modify: `lib/data/tables.dart`（+RecurringRules）
- Modify: `lib/data/database.dart`（+表注册、schemaVersion 3、onUpgrade）
- Modify: `test/data/migration_test.dart`（追加 v2→v3 测试）
- Regenerate: `lib/data/database.g.dart`

**Interfaces:**
- Produces: `RecurringRule` 数据类（id/type/amountCents/categoryId/note/dayOfMonth/lastGeneratedYyyymm/createdAt）；`RecurringRulesCompanion`

- [ ] **Step 1: 写失败测试**

```dart
// test/data/migration_test.dart main() 内追加：
  test('migration from v2 keeps data and creates recurring_rules', () async {
    final dir = Directory.systemTemp.createTempSync('ledger_migration2');
    final file = File('${dir.path}${Platform.pathSeparator}test.db');
    addTearDown(() {
      dir.deleteSync(recursive: true);
    });

    // 手写 v2 schema（categories 含 monthly_budget_cents）
    final v2 = AppDatabase.open(executor: NativeDatabase(file));
    await v2.customStatement('DROP TABLE IF EXISTS transactions');
    await v2.customStatement('DROP TABLE IF EXISTS categories');
    await v2.customStatement('''
CREATE TABLE categories (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  icon TEXT NOT NULL,
  type TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_builtin INTEGER NOT NULL DEFAULT 0,
  monthly_budget_cents INTEGER NOT NULL DEFAULT 0
)''');
    await v2.customStatement('''
CREATE TABLE transactions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  type TEXT NOT NULL,
  amount_cents INTEGER NOT NULL,
  category_id INTEGER NOT NULL REFERENCES categories(id),
  note TEXT NOT NULL DEFAULT '',
  date INTEGER NOT NULL,
  created_at INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL DEFAULT 0
)''');
    await v2.customStatement(
        "INSERT INTO categories (name, icon, type, sort_order, is_builtin, monthly_budget_cents) "
        "VALUES ('餐饮', 'restaurant', 'expense', 0, 1, 15000)");
    await v2.customStatement('PRAGMA user_version = 2');
    await v2.close();

    final db = AppDatabase.open(executor: NativeDatabase(file));
    addTearDown(db.close);
    final cats = await db.select(db.categories).get();
    expect(cats.single.name, '餐饮');
    expect(cats.single.monthlyBudgetCents, 15000);
    expect(await db.select(db.recurringRules).get(), isEmpty); // 新表存在且为空
  });
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/data/migration_test.dart`
Expected: FAIL — 编译错误（`db.recurringRules` 不存在）

- [ ] **Step 3: 实现**

```dart
// lib/data/tables.dart 文件末尾追加：
class RecurringRules extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get type => textEnum<TxType>()();
  IntColumn get amountCents => integer()(); // 单位：分
  IntColumn get categoryId => integer().references(Categories, #id)();
  TextColumn get note => text().withDefault(const Constant(''))();
  IntColumn get dayOfMonth => integer()(); // 每月几号，1-31
  /// 上次生成的月份 yyyymm，0 = 从未生成
  IntColumn get lastGeneratedYyyymm => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
```

```dart
// lib/data/database.dart
@DriftDatabase(tables: [Categories, Transactions, RecurringRules])
// ...
  int get schemaVersion => 3;
// migration：
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(categories, categories.monthlyBudgetCents);
          }
          if (from < 3) {
            await m.createTable(recurringRules);
          }
        },
```

重新生成：

```bash
export PATH="/c/src/flutter/bin:$PATH" PUB_HOSTED_URL="https://pub.flutter-io.cn" FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/data/migration_test.dart`
Expected: PASS（2 tests）。注意 v1→v2 测试仍然过（旧路径保留）。

- [ ] **Step 5: 提交**

```bash
git add lib/data/tables.dart lib/data/database.dart lib/data/database.g.dart test/data/migration_test.dart
git commit -m "feat: add recurring rules table with v3 migration"
```

---

### Task 2: 周期计算纯函数

**Files:**
- Create: `lib/core/recurring.dart`
- Test: `test/core/recurring_test.dart`

**Interfaces:**
- Produces:
  - `int clampDayToMonth(int day, int yyyymm)` — day 超过该月天数时收窄到月末
  - `List<int> monthsBetween(int fromYyyymm, int toYyyymm)` — (from, to] 缺失月份升序；from >= to 返回空

- [ ] **Step 1: 写失败测试**

```dart
// test/core/recurring_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/recurring.dart';

void main() {
  test('clampDayToMonth narrows day to month end', () {
    expect(clampDayToMonth(31, 202601), 31); // 1 月 31 天
    expect(clampDayToMonth(31, 202602), 28); // 平年 2 月
    expect(clampDayToMonth(31, 202402), 29); // 闰年 2 月
    expect(clampDayToMonth(30, 202602), 28); // 30 日进 2 月
    expect(clampDayToMonth(15, 202602), 15); // 正常
  });

  test('monthsBetween returns exclusive-from ascending months', () {
    expect(monthsBetween(202608, 202608), isEmpty); // from >= to
    expect(monthsBetween(202608, 202607), isEmpty); // 反向
    expect(monthsBetween(202601, 202603), [202602, 202603]);
    expect(monthsBetween(202512, 202602), [202601, 202602]); // 跨年
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/core/recurring_test.dart`
Expected: FAIL — 编译错误

- [ ] **Step 3: 实现**

```dart
// lib/core/recurring.dart
/// 把 day 收窄到 yyyymm 月份实际天数内（2 月 30 日 → 2 月末）。
int clampDayToMonth(int day, int yyyymm) {
  final year = yyyymm ~/ 100, month = yyyymm % 100;
  final lastDay = DateTime(year, month + 1, 0).day;
  return day > lastDay ? lastDay : day;
}

/// (from, to] 的缺失月份序列，升序；from >= to 返回空。
List<int> monthsBetween(int fromYyyymm, int toYyyymm) {
  final result = <int>[];
  if (fromYyyymm >= toYyyymm) return result;
  var cur = fromYyyymm;
  while (cur < toYyyymm) {
    final next = DateTime(cur ~/ 100, cur % 100 + 1, 1);
    cur = next.year * 100 + next.month;
    if (cur <= toYyyymm) result.add(cur);
  }
  return result;
}
```

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/core/recurring_test.dart`
Expected: PASS（2 tests）

- [ ] **Step 5: 提交**

```bash
git add lib/core/recurring.dart test/core/recurring_test.dart
git commit -m "feat: add recurring date helpers"
```

---

### Task 3: RecurringDao + providers + 启动触发

**Files:**
- Create: `lib/data/dao/recurring_dao.dart`
- Create: `test/data/recurring_dao_test.dart`
- Modify: `lib/application/providers.dart`（+recurringDaoProvider/recurringRulesProvider）
- Modify: `lib/main.dart`（启动 generateDue）

**Interfaces:**
- Consumes: Task 1 `RecurringRule`、Task 2 `clampDayToMonth`/`monthsBetween`
- Produces:
  - `class RecurringDao { RecurringDao(this.db); final AppDatabase db; }`
  - `Future<void> insertRule({required TxType type, required int amountCents, required int categoryId, required int dayOfMonth, String note = '', required int lastGeneratedYyyymm})`
  - `Future<void> deleteRule(int id)`
  - `Stream<List<RecurringRule>> watchAll()` — id 降序
  - `Future<void> generateDue(int nowYyyymm)` — 单事务补齐 (lastGenerated, now] 各月交易并推进 lastGenerated
  - `final recurringDaoProvider`、`final recurringRulesProvider = StreamProvider<List<RecurringRule>>`

- [ ] **Step 1: 写失败测试**

```dart
// test/data/recurring_dao_test.dart
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
        type: TxType.expense, amountCents: 300000, categoryId: await foodId(),
        dayOfMonth: 1, note: '房租', lastGeneratedYyyymm: 202604);
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
        type: TxType.expense, amountCents: 100, categoryId: await foodId(),
        dayOfMonth: 15, note: '', lastGeneratedYyyymm: 202606);
    await dao.generateDue(202608);
    await dao.generateDue(202608); // 再跑不重复
    final txs = await TransactionsDao(db).getByMonth(202607);
    expect(txs, hasLength(1));
  });

  test('rule created this month generates nothing this month', () async {
    await dao.insertRule(
        type: TxType.expense, amountCents: 100, categoryId: await foodId(),
        dayOfMonth: 1, note: '', lastGeneratedYyyymm: 202608);
    await dao.generateDue(202608);
    final txs = await TransactionsDao(db).getByMonth(202608);
    expect(txs, isEmpty);
  });

  test('clamps day 30 to february end', () async {
    await dao.insertRule(
        type: TxType.expense, amountCents: 100, categoryId: await foodId(),
        dayOfMonth: 30, note: '', lastGeneratedYyyymm: 202601);
    await dao.generateDue(202602);
    final txs = await TransactionsDao(db).getByMonth(202602);
    expect(txs.single.date, 20260228);
  });

  test('deleteRule removes rule', () async {
    await dao.insertRule(
        type: TxType.expense, amountCents: 100, categoryId: await foodId(),
        dayOfMonth: 1, note: '', lastGeneratedYyyymm: 202608);
    final rules = await dao.watchAll().first;
    expect(rules, hasLength(1));
    await dao.deleteRule(rules.single.id);
    expect(await dao.watchAll().first, isEmpty);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/data/recurring_dao_test.dart`
Expected: FAIL — 编译错误

- [ ] **Step 3: 实现**

```dart
// lib/data/dao/recurring_dao.dart
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
```

```dart
// lib/application/providers.dart
// import 追加：'../data/dao/recurring_dao.dart'
// 文件末尾追加：
final recurringDaoProvider = Provider((ref) => RecurringDao(ref.watch(databaseProvider)));
final recurringRulesProvider = StreamProvider<List<RecurringRule>>(
    (ref) => ref.watch(recurringDaoProvider).watchAll());
```

```dart
// lib/main.dart
// import 追加：
import 'data/dao/recurring_dao.dart';
import 'core/date_util.dart';
// seed 之后、runApp 之前：
    await RecurringDao(db).generateDue(yyyymmOf(todayYyyymmdd()));
```

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/data/recurring_dao_test.dart test/application/providers_test.dart`
Expected: PASS（5 + 4 tests）。main.dart 改动靠全量回归（Task 5）与真机验收。

- [ ] **Step 5: 提交**

```bash
git add lib/data/dao/recurring_dao.dart test/data/recurring_dao_test.dart lib/application/providers.dart lib/main.dart
git commit -m "feat: add recurring dao with startup catch-up generation"
```

---

### Task 4: 规则列表页 + 设置页入口

**Files:**
- Create: `lib/presentation/screens/recurring_screen.dart`
- Create: `test/presentation/recurring_screen_test.dart`
- Modify: `lib/presentation/screens/settings_screen.dart`（入口 ListTile）
- Modify: `test/presentation/settings_screen_test.dart`（入口导航测试）

**Interfaces:**
- Consumes: Task 3 `recurringDaoProvider`/`recurringRulesProvider`；`CategoryPicker`（lib/presentation/widgets/category_picker.dart）；`AmountInputFormatter`（lib/presentation/widgets/amount_field.dart）；`parseCents`/`formatCents`；`TxType`
- Produces: `class RecurringScreen extends ConsumerWidget`

- [ ] **Step 1: 写失败测试**

```dart
// test/presentation/recurring_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:ledger/application/providers.dart';
import 'package:ledger/data/dao/categories_dao.dart';
import 'package:ledger/data/dao/recurring_dao.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/data/transaction_type.dart';
import 'package:ledger/presentation/screens/recurring_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.open(executor: NativeDatabase.memory());
    await CategoriesDao(db).seedBuiltinCategories();
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const MaterialApp(home: RecurringScreen())));
    await tester.pumpAndSettle();
  }

  testWidgets('shows empty state', (tester) async {
    await pump(tester);
    expect(find.text('还没有周期规则'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('adds a rule and shows it in list', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '3000');
    await tester.enterText(find.byType(TextField).last, '1'); // 每月几号
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('3000.00'), findsOneWidget);
    expect(find.text('每月 1 号'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('invalid day shows error and keeps dialog', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '100');
    await tester.enterText(find.byType(TextField).last, '32');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('请输入 1-31 的日期'), findsOneWidget);
    expect(find.text('新增周期规则'), findsOneWidget); // dialog 未关
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('deletes a rule after confirm', (tester) async {
    await RecurringDao(db).insertRule(
        type: TxType.expense, amountCents: 300000, categoryId: 1,
        dayOfMonth: 1, note: '房租', lastGeneratedYyyymm: 202608);
    await pump(tester);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(await RecurringDao(db).watchAll().first, isEmpty);
    expect(find.text('还没有周期规则'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
```

```dart
// test/presentation/settings_screen_test.dart
// import 追加：
import 'package:ledger/presentation/screens/recurring_screen.dart';
// main() 内追加：
  testWidgets('recurring entry opens recurring screen', (tester) async {
    await pump(tester);
    await tester.tap(find.text('周期记账'));
    await tester.pumpAndSettle();
    expect(find.byType(RecurringScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/presentation/recurring_screen_test.dart test/presentation/settings_screen_test.dart`
Expected: FAIL — 编译错误（recurring_screen.dart 不存在）

- [ ] **Step 3: 实现**

```dart
// lib/presentation/screens/recurring_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../core/date_util.dart';
import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/transaction_type.dart';
import '../theme/app_theme.dart';
import '../widgets/amount_field.dart' show AmountInputFormatter;
import '../widgets/category_picker.dart';

/// 周期规则列表：新增/删除规则，规则生成的记录由启动时 generateDue 补齐。
class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(recurringRulesProvider).value ?? const <RecurringRule>[];
    final cats = ref.watch(allCategoriesProvider).value ?? const <Category>[];
    final dao = ref.watch(recurringDaoProvider);

    String catName(int id) =>
        cats.where((c) => c.id == id).map((c) => c.name).firstOrNull ?? '未分类';

    Future<void> addDialog() async {
      final amountCtrl = TextEditingController();
      final dayCtrl = TextEditingController();
      final noteCtrl = TextEditingController();
      var type = TxType.expense;
      var categoryId = -1;

      // 新分类流到达后自动选中第一个匹配分类（同步兜底，见 AddTransactionScreen 模式）
      void autoSelect() {
        if (categoryId >= 0) return;
        final first = cats.where((c) => c.type == type).firstOrNull;
        if (first != null) categoryId = first.id;
      }

      autoSelect();
      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            autoSelect();
            return AlertDialog(
              title: const Text('新增周期规则'),
              content: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SegmentedButton<TxType>(
                    segments: const [
                      ButtonSegment(value: TxType.expense, label: Text('支出')),
                      ButtonSegment(value: TxType.income, label: Text('收入')),
                    ],
                    selected: {type},
                    onSelectionChanged: (s) => setDialogState(() {
                      type = s.first;
                      categoryId = -1; // 换类型重选分类
                      autoSelect();
                    }),
                  ),
                  TextField(
                    controller: amountCtrl,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [AmountInputFormatter()],
                    decoration: const InputDecoration(labelText: '金额', prefixText: '¥ '),
                  ),
                  CategoryPicker(
                      type: type, selectedId: categoryId,
                      onSelect: (id) => setDialogState(() => categoryId = id)),
                  TextField(
                    controller: dayCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: '每月几号（1-31）'),
                  ),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(labelText: '备注'),
                  ),
                ]),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                TextButton(
                  onPressed: () async {
                    final int cents;
                    try {
                      cents = parseCents(amountCtrl.text);
                    } on FormatException {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('请输入有效金额')));
                      }
                      return;
                    }
                    final day = int.tryParse(dayCtrl.text);
                    if (day == null || day < 1 || day > 31) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('请输入 1-31 的日期')));
                      }
                      return;
                    }
                    if (categoryId < 0) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('请选择分类')));
                      }
                      return;
                    }
                    await dao.insertRule(
                        type: type,
                        amountCents: cents,
                        categoryId: categoryId,
                        dayOfMonth: day,
                        note: noteCtrl.text.trim(),
                        lastGeneratedYyyymm: yyyymmOf(todayYyyymmdd()));
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        ),
      );
    }

    Future<void> deleteFlow(RecurringRule r) async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('删除规则'),
          content: const Text('删除后已生成的记录不受影响'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
          ],
        ),
      );
      if (ok != true) return;
      await dao.deleteRule(r.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已删除')));
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('周期记账')),
      floatingActionButton: FloatingActionButton(onPressed: addDialog, child: const Icon(Icons.add)),
      body: rules.isEmpty
          ? const Center(child: Text('还没有周期规则'))
          : ListView.builder(
              itemCount: rules.length,
              itemBuilder: (_, i) {
                final r = rules[i];
                final isExpense = r.type == TxType.expense;
                return ListTile(
                  leading: CircleAvatar(
                      child: Icon(categoryIcons[catName(r.categoryId)] != Icons.face
                          ? Icons.event_repeat
                          : Icons.event_repeat)),
                  title: Text(catName(r.categoryId)),
                  subtitle: Text('每月 ${r.dayOfMonth} 号${r.note.isEmpty ? '' : ' · ${r.note}'}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('${isExpense ? '-' : '+'}${formatCents(r.amountCents)}',
                        style: TextStyle(
                            color: isExpense ? AppTheme.expenseColor : AppTheme.incomeColor,
                            fontWeight: FontWeight.w600)),
                    IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => deleteFlow(r)),
                  ]),
                );
              },
            ),
    );
  }
}
```

注意：leading 的 CircleAvatar 图标判定很绕——直接统一用 `Icons.event_repeat`：

```dart
                  leading: const CircleAvatar(child: Icon(Icons.event_repeat)),
```

```dart
// lib/presentation/screens/settings_screen.dart
// import 追加：
import 'recurring_screen.dart';
// ListView children 中、恢复 ListTile 之后追加：
        ListTile(
            leading: const Icon(Icons.event_repeat),
            title: const Text('周期记账'),
            subtitle: const Text('房租/订阅等每月自动入账'),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const RecurringScreen()))),
```

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/presentation/recurring_screen_test.dart test/presentation/settings_screen_test.dart`
Expected: PASS（4 + 7 tests）。若"新增规则"测试的分类选择有问题（CategoryPicker 自动选中第一个分类），沿用 AddTransactionScreen 已验证的 autoSelect 模式即可。

- [ ] **Step 5: 提交**

```bash
git add lib/presentation/screens/recurring_screen.dart test/presentation/recurring_screen_test.dart lib/presentation/screens/settings_screen.dart test/presentation/settings_screen_test.dart
git commit -m "feat: add recurring rules screen with settings entry"
```

---

### Task 5: README + 全量验证

**Files:**
- Modify: `README.md`

- [ ] **Step 1: README 功能清单追加**

```markdown
- **周期记账**：房租/订阅/工资等规则，打开 App 自动补齐每月记录（2 月 30 号自动收窄到月末）
```

- [ ] **Step 2: 全量验证**

```bash
export PATH="/c/src/flutter/bin:$PATH" PUB_HOSTED_URL="https://pub.flutter-io.cn" FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
flutter test && flutter analyze
```

Expected: 全部 PASS（原有 68 + 新增约 15 ≈ 83 tests）；analyze 零问题

- [ ] **Step 3: 提交**

```bash
git add README.md
git commit -m "docs: add recurring feature to readme"
```

---

## Self-Review 记录

- **Spec 覆盖**：表+migration（Task 1）、clampDayToMonth/monthsBetween（Task 2）、insertRule/deleteRule/watchAll/generateDue（Task 3）、main 启动触发（Task 3）、规则页列表/新增/删除（Task 4）、设置页入口（Task 4）、README（Task 5）。spec 验收"跨月补多笔""幂等""2 月末收窄"由 Task 3 测试覆盖。
- **类型一致性**：`clampDayToMonth(int,int)→int`、`monthsBetween(int,int)→List<int>`、`insertRule({type,amountCents,categoryId,dayOfMonth,note,lastGeneratedYyyymm})` 在 Task 3/4 一致；Task 4 测试用 `RecurringDao(db).insertRule` 与 Task 3 签名一致。
- **行为一致性**：Task 4 新增规则传 `lastGeneratedYyyymm: yyyymmOf(todayYyyymmdd())`（当月不生成，与 spec 一致）；删除规则用 FilledButton 确认（测试用 find.text('删除') 匹配，页面无其他"删除"文本冲突——dialog 标题是"删除规则"，`find.text('删除')` 精确匹配按钮）。
- **风险**：Task 4 新增 dialog 的 `find.byType(TextField).first/.last` 依赖布局顺序（金额在前、day 在后，备注在中间）——布局含 4 个 TextField，`.first`=金额、`.last`=备注而非几号！修正：测试里 day 输入用 `find.widgetWithText(TextField, '每月几号（1-31）')`。执行时如失败按此调整（实现与测试都是本计划的产物，允许在执行中精确化 finder）。
