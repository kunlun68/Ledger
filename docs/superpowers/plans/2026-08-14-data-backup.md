# 数据备份/导出 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让用户能 JSON 完整备份/恢复记账数据，并导出 CSV 供 Excel 分析或分享。

**Architecture:** core 层纯函数做序列化（JSON/CSV），BackupDao 单事务做全量替换，BackupIO 抽象隔离 share_plus/file_picker 平台通道（widget 测试注入 fake），SettingsScreen 编排三入口 UI。恢复前弹不可撤销确认框。

**Tech Stack:** Dart 纯函数 + drift 事务 + share_plus/file_picker（Android 零权限）

**Spec:** docs/superpowers/specs/2026-08-14-data-backup-design.md

## Global Constraints

- 金额一律整数分（amountCents int），禁止 double 运算；展示用 formatCents
- 日期存 int yyyyMMdd；CSV 内展示为 yyyy-MM-dd
- UI 文案中文；commit message 简洁英文，末尾加 `Co-Authored-By: Claude <noreply@anthropic.com>`
- TDD：先写失败测试 → 确认红 → 实现 → 绿 → commit
- 所有 drift widget 测试末尾必须：`await tester.pumpWidget(const SizedBox()); await tester.pump(Duration.zero);`（卸载树 + 推进 drift 清理 Timer，否则 teardown 挂死）。测试用内存 db（`NativeDatabase.memory()`）+ `UncontrolledProviderScope` container 模式（参考 test/presentation/home_screen_test.dart 的 makeContainer，并显式设 `currentMonthProvider.notifier).state`）
- bash 调用需导出：`export PATH="/c/src/flutter/bin:$PATH" PUB_HOSTED_URL="https://pub.flutter-io.cn" FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"`
- 备份文件名 `ledger-backup-YYYYMMDD.json`、`ledger-YYYYMMDD.csv`（YYYYMMDD 用 `todayYyyymmdd()`，见 lib/core/date_util.dart）
- JSON 信封：`{"app":"ledger","version":1,"exportedAt":ISO8601,"categories":[...],"transactions":[...]}`；fromJson 严格校验（app 不符/version 过新/字段缺失分别报中文错误）
- CSV 必须以 UTF-8 BOM 开头；行分隔 `\r\n`；字段含 `,` `"` 换行时引号包裹+翻倍

---

### Task 1: JSON 序列化核心模块

**Files:**
- Create: `lib/core/backup.dart`
- Test: `test/core/backup_test.dart`

**Interfaces:**
- Consumes: `Category`/`Transaction`（drift 生成数据类，lib/data/database.dart）、`TxType`（lib/data/transaction_type.dart）
- Produces:
  - `class BackupFormatException implements Exception { BackupFormatException(this.message); final String message; }`
  - `class BackupData { final List<Category> categories; final List<Transaction> transactions; BackupData({required this.categories, required this.transactions}); }`
  - `String encodeBackup(List<Category> cats, List<Transaction> txs)` — JSON 字符串
  - `BackupData parseBackup(String content)` — 校验失败抛 BackupFormatException

- [ ] **Step 1: 写失败测试**

```dart
// test/core/backup_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/backup.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/data/transaction_type.dart';

Category _cat({int id = 1, String name = '餐饮'}) => Category(
    id: id, name: name, icon: 'restaurant', type: TxType.expense, sortOrder: 0, isBuiltin: true);

Transaction _tx({int id = 1}) => Transaction(
    id: id,
    type: TxType.expense,
    amountCents: 1234,
    categoryId: 1,
    note: '午饭',
    date: 20260813,
    createdAt: DateTime(2026, 8, 13, 12),
    updatedAt: DateTime(2026, 8, 13, 12));

void main() {
  test('encode and parse roundtrip preserves all fields', () {
    final data = BackupData(categories: [_cat()], transactions: [_tx()]);
    final parsed = parseBackup(encodeBackup([_cat()], [_tx()]));
    expect(parsed.categories.single.id, 1);
    expect(parsed.categories.single.name, '餐饮');
    expect(parsed.categories.single.type, TxType.expense);
    expect(parsed.categories.single.isBuiltin, true);
    expect(parsed.transactions.single.id, 1);
    expect(parsed.transactions.single.amountCents, 1234);
    expect(parsed.transactions.single.categoryId, 1);
    expect(parsed.transactions.single.note, '午饭');
    expect(parsed.transactions.single.date, 20260813);
    expect(parsed.transactions.single.type, TxType.expense);
    expect(parsed.transactions.single.createdAt, DateTime(2026, 8, 13, 12));
  });

  test('rejects non-ledger file', () {
    expect(() => parseBackup('{"app":"other","version":1,"categories":[],"transactions":[]}'),
        throwsA(isA<BackupFormatException>()
            .having((e) => e.message, 'message', '不是本应用的备份文件')));
  });

  test('rejects newer version', () {
    expect(() => parseBackup('{"app":"ledger","version":99,"categories":[],"transactions":[]}'),
        throwsA(isA<BackupFormatException>()
            .having((e) => e.message, 'message', '备份文件版本过新，请升级应用')));
  });

  test('rejects malformed content', () {
    expect(() => parseBackup('not json at all'),
        throwsA(isA<BackupFormatException>()
            .having((e) => e.message, 'message', '备份文件内容损坏')));
    expect(() => parseBackup('{"app":"ledger","version":1,"categories":"oops","transactions":[]}'),
        throwsA(isA<BackupFormatException>()));
    expect(() => parseBackup(
            '{"app":"ledger","version":1,"categories":[],"transactions":[{"id":"x"}]}'),
        throwsA(isA<BackupFormatException>()));
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/core/backup_test.dart`
Expected: FAIL — 编译错误（backup.dart 不存在）

- [ ] **Step 3: 实现**

```dart
// lib/core/backup.dart
import 'dart:convert';
import '../data/database.dart';
import '../data/transaction_type.dart';

class BackupFormatException implements Exception {
  BackupFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BackupData {
  BackupData({required this.categories, required this.transactions});
  final List<Category> categories;
  final List<Transaction> transactions;
}

const _appTag = 'ledger';
const _version = 1;

String encodeBackup(List<Category> cats, List<Transaction> txs) => jsonEncode({
      'app': _appTag,
      'version': _version,
      'exportedAt': DateTime.now().toIso8601String(),
      'categories': [
        for (final c in cats)
          {
            'id': c.id,
            'name': c.name,
            'icon': c.icon,
            'type': c.type.name,
            'sortOrder': c.sortOrder,
            'isBuiltin': c.isBuiltin,
          }
      ],
      'transactions': [
        for (final t in txs)
          {
            'id': t.id,
            'type': t.type.name,
            'amountCents': t.amountCents,
            'categoryId': t.categoryId,
            'note': t.note,
            'date': t.date,
            'createdAt': t.createdAt.toIso8601String(),
            'updatedAt': t.updatedAt.toIso8601String(),
          }
      ],
    });

BackupData parseBackup(String content) {
  final Object? decoded;
  try {
    decoded = jsonDecode(content);
  } on FormatException {
    throw BackupFormatException('备份文件内容损坏');
  }
  if (decoded is! Map<String, dynamic>) throw BackupFormatException('备份文件内容损坏');
  if (decoded['app'] != _appTag) throw BackupFormatException('不是本应用的备份文件');
  final version = decoded['version'];
  if (version is! int || version > _version) {
    throw BackupFormatException('备份文件版本过新，请升级应用');
  }
  final catsJson = decoded['categories'];
  final txsJson = decoded['transactions'];
  if (catsJson is! List || txsJson is! List) throw BackupFormatException('备份文件内容损坏');

  try {
    return BackupData(
      categories: [for (final c in catsJson) _parseCategory(c)],
      transactions: [for (final t in txsJson) _parseTransaction(t)],
    );
  } on BackupFormatException {
    rethrow;
  } catch (_) {
    throw BackupFormatException('备份文件内容损坏');
  }
}

Category _parseCategory(Object? raw) {
  final m = raw as Map<String, dynamic>;
  return Category(
    id: m['id'] as int,
    name: m['name'] as String,
    icon: m['icon'] as String,
    type: TxType.values.byName(m['type'] as String),
    sortOrder: m['sortOrder'] as int,
    isBuiltin: m['isBuiltin'] as bool,
  );
}

Transaction _parseTransaction(Object? raw) {
  final m = raw as Map<String, dynamic>;
  return Transaction(
    id: m['id'] as int,
    type: TxType.values.byName(m['type'] as String),
    amountCents: m['amountCents'] as int,
    categoryId: m['categoryId'] as int,
    note: m['note'] as String,
    date: m['date'] as int,
    createdAt: DateTime.parse(m['createdAt'] as String),
    updatedAt: DateTime.parse(m['updatedAt'] as String),
  );
}
```

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/core/backup_test.dart`
Expected: PASS（4 tests）

- [ ] **Step 5: 提交**

```bash
git add lib/core/backup.dart test/core/backup_test.dart
git commit -m "feat: add backup JSON serialize/parse with validation"
```

---

### Task 2: CSV 导出纯函数

**Files:**
- Create: `lib/core/csv_export.dart`
- Test: `test/core/csv_export_test.dart`

**Interfaces:**
- Consumes: Task 1 无；`formatCents`（lib/core/money.dart）、`TxType`
- Produces: `String buildCsv(List<Transaction> txs, List<Category> cats)` — 含 BOM 的完整 CSV 文本；`String escapeCsv(String field)` — 供测试直接验证转义

- [ ] **Step 1: 写失败测试**

```dart
// test/core/csv_export_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/csv_export.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/data/transaction_type.dart';

void main() {
  final cats = [
    Category(id: 1, name: '餐饮', icon: 'restaurant', type: TxType.expense, sortOrder: 0, isBuiltin: true),
    Category(id: 2, name: '工资', icon: 'payments', type: TxType.income, sortOrder: 0, isBuiltin: true),
  ];

  Transaction tx(int id, TxType type, int cents, int categoryId, String note) => Transaction(
      id: id, type: type, amountCents: cents, categoryId: categoryId, note: note,
      date: 20260813, createdAt: DateTime(2026, 8, 13), updatedAt: DateTime(2026, 8, 13));

  test('starts with UTF-8 BOM and header', () {
    final csv = buildCsv([], cats);
    expect(csv.startsWith('﻿'), isTrue);
    expect(csv.contains('date,type,category,amount,note'), isTrue);
  });

  test('formats rows: date, chinese type, category name, amount, note', () {
    final csv = buildCsv(
        [tx(1, TxType.expense, 1234, 1, '午饭'), tx(2, TxType.income, 500000, 2, '')], cats);
    final lines = csv.split('\r\n');
    expect(lines[1], '2026-08-13,支出,餐饮,12.34,午饭');
    expect(lines[2], '2026-08-13,收入,工资,5000.00,');
  });

  test('unknown categoryId shows 未分类', () {
    final csv = buildCsv([tx(1, TxType.expense, 100, 999, '')], cats);
    expect(csv.split('\r\n')[1], contains('未分类'));
  });

  test('escapeCsv wraps fields with comma, quote, newline', () {
    expect(escapeCsv('a,b'), '"a,b"');
    expect(escapeCsv('a"b'), '"a""b"');
    expect(escapeCsv('a\nb'), '"a\nb"');
    expect(escapeCsv('plain'), 'plain');
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/core/csv_export_test.dart`
Expected: FAIL — 编译错误

- [ ] **Step 3: 实现**

```dart
// lib/core/csv_export.dart
import '../core/money.dart';
import '../data/database.dart';
import '../data/transaction_type.dart';

/// 生成 CSV 全文（含 UTF-8 BOM，行分隔 \r\n，Excel 兼容）。
String buildCsv(List<Transaction> txs, List<Category> cats) {
  final catName = <int, String>{
    for (final c in cats) c.id: c.name,
  };
  final buf = StringBuffer('﻿date,type,category,amount,note\r\n');
  for (final t in txs) {
    buf
      ..write(_formatDate(t.date))
      ..write(',')
      ..write(t.type == TxType.expense ? '支出' : '收入')
      ..write(',')
      ..write(escapeCsv(catName[t.categoryId] ?? '未分类'))
      ..write(',')
      ..write(formatCents(t.amountCents))
      ..write(',')
      ..write(escapeCsv(t.note))
      ..write('\r\n');
  }
  return buf.toString();
}

/// 含 `,` `"` 换行的字段用双引号包裹，内部 `"` 翻倍。
String escapeCsv(String field) {
  if (!field.contains(',') && !field.contains('"') && !field.contains('\n')) {
    return field;
  }
  return '"${field.replaceAll('"', '""')}"';
}

String _formatDate(int yyyymmdd) {
  final y = yyyymmdd ~/ 10000, m = (yyyymmdd ~/ 100) % 100, d = yyyymmdd % 100;
  return '$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
}
```

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/core/csv_export_test.dart`
Expected: PASS（4 tests）

- [ ] **Step 5: 提交**

```bash
git add lib/core/csv_export.dart test/core/csv_export_test.dart
git commit -m "feat: add csv export with BOM and escaping"
```

---

### Task 3: BackupDao（取全量 + 单事务恢复）

**Files:**
- Create: `lib/data/dao/backup_dao.dart`
- Test: `test/data/backup_dao_test.dart`

**Interfaces:**
- Consumes: `AppDatabase`（lib/data/database.dart）
- Produces:
  - `class BackupDao { BackupDao(this.db); final AppDatabase db; }`
  - `Future<({List<Category> categories, List<Transaction> transactions})> exportAll()` — 分类按 sortOrder 升序、交易按 date 降序
  - `Future<void> restoreAll({required List<Category> categories, required List<Transaction> transactions})` — 单事务：清空 transactions → 清空 categories → 按原 id 插入；任一步失败整体回滚

- [ ] **Step 1: 写失败测试**

```dart
// test/data/backup_dao_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:ledger/data/dao/backup_dao.dart';
import 'package:ledger/data/dao/categories_dao.dart';
import 'package:ledger/data/dao/transactions_dao.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/data/transaction_type.dart';

void main() {
  late AppDatabase db;
  late BackupDao dao;

  setUp(() {
    db = AppDatabase.open(executor: NativeDatabase.memory());
    dao = BackupDao(db);
  });
  tearDown(() => db.close());

  test('exportAll returns seeded data', () async {
    await CategoriesDao(db).seedBuiltinCategories();
    final cats = await CategoriesDao(db).getByType(TxType.expense);
    await TransactionsDao(db).insertTransaction(TxType.expense, 100, cats.first.id, 20260813, '午饭');
    final all = await dao.exportAll();
    expect(all.categories, hasLength(11));
    expect(all.transactions, hasLength(1));
    expect(all.transactions.single.note, '午饭');
  });

  test('restoreAll replaces everything preserving ids', () async {
    await CategoriesDao(db).seedBuiltinCategories();
    final backup = await dao.exportAll();
    // 备份后再加一条，恢复应将其清掉
    await TransactionsDao(db)
        .insertTransaction(TxType.expense, 999, backup.categories.first.id, 20260813, '要消失');
    await dao.restoreAll(categories: backup.categories, transactions: backup.transactions);
    final after = await dao.exportAll();
    expect(after.transactions.any((t) => t.note == '要消失'), isFalse);
    expect(after.categories.map((c) => c.id).toSet(),
        backup.categories.map((c) => c.id).toSet());
  });

  test('restoreAll rolls back on failure (duplicate ids)', () async {
    await CategoriesDao(db).seedBuiltinCategories();
    final backup = await dao.exportAll();
    await TransactionsDao(db)
        .insertTransaction(TxType.expense, 999, backup.categories.first.id, 20260813, '保留我');
    // 构造主键冲突：两个分类同 id
    final bad = [...backup.categories, backup.categories.first];
    await expectLater(
        dao.restoreAll(categories: bad, transactions: backup.transactions), throwsA(anything));
    final after = await dao.exportAll();
    expect(after.transactions.any((t) => t.note == '保留我'), isTrue);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/data/backup_dao_test.dart`
Expected: FAIL — 编译错误

- [ ] **Step 3: 实现**

```dart
// lib/data/dao/backup_dao.dart
import 'package:drift/drift.dart';
import '../database.dart';

/// 备份/恢复的数据访问：取全量 + 单事务全量替换。
class BackupDao {
  BackupDao(this.db);
  final AppDatabase db;

  Future<({List<Category> categories, List<Transaction> transactions})> exportAll() async {
    final categories = await (db.select(db.categories)
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder), (t) => OrderingTerm.asc(t.id)]))
        .get();
    final transactions = await (db.select(db.transactions)
          ..orderBy([(t) => OrderingTerm.desc(t.date), (t) => OrderingTerm.desc(t.id)]))
        .get();
    return (categories: categories, transactions: transactions);
  }

  /// 全量替换：单事务，任一步失败整体回滚。保留备份中的原始 id。
  Future<void> restoreAll(
      {required List<Category> categories, required List<Transaction> transactions}) {
    return db.transaction(() async {
      await (db.delete(db.transactions)).go();
      await (db.delete(db.categories)).go();
      for (final c in categories) {
        await db.into(db.categories).insert(CategoriesCompanion.insert(
              id: Value(c.id),
              name: c.name,
              icon: c.icon,
              type: c.type,
              sortOrder: Value(c.sortOrder),
              isBuiltin: Value(c.isBuiltin),
            ));
      }
      for (final t in transactions) {
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: Value(t.id),
              type: t.type,
              amountCents: t.amountCents,
              categoryId: t.categoryId,
              note: Value(t.note),
              date: t.date,
              createdAt: Value(t.createdAt),
              updatedAt: Value(t.updatedAt),
            ));
      }
    });
  }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/data/backup_dao_test.dart`
Expected: PASS（3 tests）。若回滚测试不抛异常，说明主键冲突未触发 —— 检查是否两个 `Value(c.id)` 相同（`backup.categories.first` 是同一 Category 实例的浅拷贝 list，id 相同必冲突）。

- [ ] **Step 5: 提交**

```bash
git add lib/data/dao/backup_dao.dart test/data/backup_dao_test.dart
git commit -m "feat: add backup dao with transactional restore"
```

---

### Task 4: 平台通道抽象 + 依赖

**Files:**
- Create: `lib/application/backup_io.dart`
- Modify: `lib/application/providers.dart`（追加两个 provider）
- Modify: `pubspec.yaml`（flutter pub add 安装）
- Test: `test/application/backup_io_test.dart`（provider 解析冒烟）

**Interfaces:**
- Consumes: Task 1/3 无
- Produces:
  - `abstract class BackupIO { Future<void> shareFile(String path, {required String text}); Future<String?> pickBackupFile(); }`
  - `class SharePlusBackupIO implements BackupIO` — share_plus 分享 + file_picker 读 .json 内容（取消返回 null）
  - `final backupIOProvider = Provider<BackupIO>((ref) => SharePlusBackupIO());`
  - `final backupDaoProvider = Provider((ref) => BackupDao(ref.watch(databaseProvider)));`

- [ ] **Step 1: 安装依赖**

```bash
export PATH="/c/src/flutter/bin:$PATH" PUB_HOSTED_URL="https://pub.flutter-io.cn" FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
cd /d/zhangben/Ledger && flutter pub add share_plus file_picker
```

Expected: pubspec.yaml 出现 share_plus/file_picker 条目，`flutter pub get` 成功。**share_plus 新版（10+）API 是 `SharePlus.instance.share(ShareParams(...))`；若编译报错说明装的版本 API 不同，以该版本 README 为准做等价替换（分享 XFile 语义不变）。**

- [ ] **Step 2: 写失败测试**

```dart
// test/application/backup_io_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:ledger/application/backup_io.dart';
import 'package:ledger/application/providers.dart';
import 'package:ledger/data/database.dart';

void main() {
  test('backupIOProvider and backupDaoProvider resolve', () {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(AppDatabase.open(executor: NativeDatabase.memory())),
    ]);
    addTearDown(container.dispose);
    expect(container.read(backupIOProvider), isA<SharePlusBackupIO>());
    expect(container.read(backupDaoProvider), isA<BackupDao>());
  });
}
```

- [ ] **Step 3: 运行确认失败**

Run: `flutter test test/application/backup_io_test.dart`
Expected: FAIL — 编译错误（backup_io.dart 不存在）

- [ ] **Step 4: 实现**

```dart
// lib/application/backup_io.dart
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

/// 平台通道抽象：widget 测试注入 fake，避免测试环境平台通道不可用。
abstract class BackupIO {
  /// 弹系统分享面板分享 [path] 文件。
  Future<void> shareFile(String path, {required String text});

  /// 系统文件选择器挑 .json 备份并返回内容；用户取消返回 null。
  Future<String?> pickBackupFile();
}

class SharePlusBackupIO implements BackupIO {
  @override
  Future<void> shareFile(String path, {required String text}) =>
      SharePlus.instance.share(ShareParams(files: [XFile(path)], text: text));

  @override
  Future<String?> pickBackupFile() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    final path = result?.files.single.path;
    if (path == null) return null;
    return File(path).readAsString();
  }
}
```

```dart
// lib/application/providers.dart 末尾追加
final backupDaoProvider = Provider((ref) => BackupDao(ref.watch(databaseProvider)));
final backupIOProvider = Provider<BackupIO>((ref) => SharePlusBackupIO());
```

（providers.dart 需新增 import：`../data/dao/backup_dao.dart`、`backup_io.dart`）

- [ ] **Step 5: 运行确认通过**

Run: `flutter test test/application/backup_io_test.dart && flutter analyze`
Expected: PASS；analyze 零问题（若 share API 名不符，按 Step 1 说明调整）

- [ ] **Step 6: 提交**

```bash
git add lib/application/backup_io.dart lib/application/providers.dart test/application/backup_io_test.dart pubspec.yaml pubspec.lock
git commit -m "feat: add backup io abstraction with share/file picker"
```

---

### Task 5: 设置页（三入口 + 恢复确认流程）

**Files:**
- Create: `lib/presentation/screens/settings_screen.dart`
- Test: `test/presentation/settings_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 `encodeBackup`/`parseBackup`/`BackupData`/`BackupFormatException`、Task 2 `buildCsv`、Task 3 `BackupDao.exportAll/restoreAll`、Task 4 `BackupIO`/providers、`todayYyyymmdd()`（lib/core/date_util.dart）
- Produces: `class SettingsScreen extends ConsumerWidget` — 列表含"导出 CSV""备份""恢复"三项

- [ ] **Step 1: 写失败测试**

```dart
// test/presentation/settings_screen_test.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:ledger/application/backup_io.dart';
import 'package:ledger/application/providers.dart';
import 'package:ledger/core/backup.dart';
import 'package:ledger/data/dao/backup_dao.dart';
import 'package:ledger/data/dao/categories_dao.dart';
import 'package:ledger/data/dao/transactions_dao.dart';
import 'package:ledger/data/database.dart';
import 'package:ledger/data/transaction_type.dart';
import 'package:ledger/presentation/screens/settings_screen.dart';

class FakeBackupIO implements BackupIO {
  String? pickedContent;
  final shared = <String>[];

  @override
  Future<void> shareFile(String path, {required String text}) async {
    shared.add(path);
  }

  @override
  Future<String?> pickBackupFile() async => pickedContent;
}

void main() {
  late AppDatabase db;
  late FakeBackupIO io;

  setUp(() async {
    db = AppDatabase.open(executor: NativeDatabase.memory());
    await CategoriesDao(db).seedBuiltinCategories();
    io = FakeBackupIO();
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      backupIOProvider.overrideWithValue(io),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const MaterialApp(home: SettingsScreen())));
    await tester.pumpAndSettle();
  }

  testWidgets('shows three entries', (tester) async {
    await pump(tester);
    expect(find.text('导出 CSV'), findsOneWidget);
    expect(find.text('备份'), findsOneWidget);
    expect(find.text('恢复'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('export csv shares a temp file', (tester) async {
    final cats = await CategoriesDao(db).getByType(TxType.expense);
    await TransactionsDao(db).insertTransaction(TxType.expense, 100, cats.first.id, 20260813, '午饭');
    await pump(tester);
    await tester.tap(find.text('导出 CSV'));
    await tester.pumpAndSettle();
    expect(io.shared, hasLength(1));
    final content = File(io.shared.single).readAsStringSync();
    expect(content.startsWith('﻿'), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('restore confirm replaces data', (tester) async {
    final cats = await CategoriesDao(db).getByType(TxType.expense);
    await TransactionsDao(db).insertTransaction(TxType.expense, 100, cats.first.id, 20260813, '旧记录');
    // 备份内容：1 个交易"新记录"
    io.pickedContent = encodeBackup(
        cats,
        [Transaction(
            id: 42, type: TxType.expense, amountCents: 200, categoryId: cats.first.id,
            note: '新记录', date: 20260814,
            createdAt: DateTime(2026, 8, 14), updatedAt: DateTime(2026, 8, 14))]);
    await pump(tester);
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    expect(find.textContaining('将清空'), findsOneWidget); // 确认框
    await tester.tap(find.widgetWithText(FilledButton, '恢复'));
    await tester.pumpAndSettle();
    final all = await BackupDao(db).exportAll();
    expect(all.transactions.single.note, '新记录');
    expect(find.textContaining('已恢复'), findsOneWidget); // SnackBar
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('restore cancel keeps data', (tester) async {
    final cats = await CategoriesDao(db).getByType(TxType.expense);
    await TransactionsDao(db).insertTransaction(TxType.expense, 100, cats.first.id, 20260813, '旧记录');
    io.pickedContent = encodeBackup(cats, const []);
    await pump(tester);
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    final all = await BackupDao(db).exportAll();
    expect(all.transactions.single.note, '旧记录');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('corrupt backup shows error and keeps data', (tester) async {
    io.pickedContent = 'not json';
    await pump(tester);
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    expect(find.text('备份文件内容损坏'), findsOneWidget);
    final all = await BackupDao(db).exportAll();
    expect(all.transactions, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('foreign backup file shows error', (tester) async {
    io.pickedContent = '{"app":"other","version":1}';
    await pump(tester);
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    expect(find.text('不是本应用的备份文件'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/presentation/settings_screen_test.dart`
Expected: FAIL — 编译错误（settings_screen.dart 不存在）

- [ ] **Step 3: 实现**

```dart
// lib/presentation/screens/settings_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/backup_io.dart';
import '../../application/providers.dart';
import '../../core/backup.dart';
import '../../core/csv_export.dart';
import '../../core/date_util.dart';

/// 设置页：导出 CSV / 备份 / 恢复。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dao = ref.watch(backupDaoProvider);
    final io = ref.watch(backupIOProvider);

    void show(String msg) =>
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

    /// 写临时文件并分享；分享面板返回后尽力清理临时文件。
    Future<void> share(String name, String content) async {
      final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}$name');
      try {
        await file.writeAsString(content);
        await io.shareFile(file.path, text: '记账备份');
      } catch (_) {
        show('导出失败');
      } finally {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {} // 清理失败不影响
      }
    }

    Future<void> exportCsv() async {
      final all = await dao.exportAll();
      await share('ledger-${todayYyyymmdd()}.csv', buildCsv(all.transactions, all.categories));
    }

    Future<void> exportBackup() async {
      final all = await dao.exportAll();
      await share(
          'ledger-backup-${todayYyyymmdd()}.json', encodeBackup(all.categories, all.transactions));
    }

    Future<void> restore() async {
      final content = await io.pickBackupFile();
      if (content == null) return;
      final BackupData data;
      try {
        data = parseBackup(content);
      } on BackupFormatException catch (e) {
        show(e.message);
        return;
      }
      final current = await dao.exportAll();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('恢复备份'),
          content: Text('将清空现有 ${current.transactions.length} 条记录并替换为备份内容'
              '（${data.transactions.length} 条交易），此操作不可撤销'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('恢复')),
          ],
        ),
      );
      if (ok != true) return;
      try {
        await dao.restoreAll(categories: data.categories, transactions: data.transactions);
      } catch (_) {
        show('恢复失败');
        return;
      }
      show('已恢复 ${data.transactions.length} 条交易、${data.categories.length} 个分类');
    }

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(children: [
        ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('导出 CSV'),
            subtitle: const Text('全部流水，供 Excel 分析或分享'),
            onTap: exportCsv),
        ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('备份'),
            subtitle: const Text('完整备份（含分类），可用于换机恢复'),
            onTap: exportBackup),
        ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('恢复'),
            subtitle: const Text('从备份文件恢复，将清空现有数据'),
            onTap: restore),
        const Divider(),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('备份文件包含财务隐私数据，分享时请选择可信渠道。',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
        ),
      ]),
    );
  }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/presentation/settings_screen_test.dart`
Expected: PASS（6 tests）。若 confirm 对话框按钮找不到（TextButton/FilledButton 匹配问题），用 `find.widgetWithText(FilledButton, '恢复')` 已处理；SnackBar 需 pumpAndSettle 后仍在展示期内。

- [ ] **Step 5: 提交**

```bash
git add lib/presentation/screens/settings_screen.dart test/presentation/settings_screen_test.dart
git commit -m "feat: add settings screen with backup/export/restore"
```

---

### Task 6: 首页入口 + README + 全量验证

**Files:**
- Modify: `lib/presentation/screens/home_screen.dart`（AppBar actions 加齿轮）
- Modify: `test/presentation/home_screen_test.dart`（入口测试）
- Modify: `README.md`（功能清单加备份/导出）

**Interfaces:**
- Consumes: Task 5 `SettingsScreen`

- [ ] **Step 1: 写失败测试**

```dart
// test/presentation/home_screen_test.dart 追加 import 与测试
import 'package:ledger/presentation/screens/settings_screen.dart';
// ...main() 内追加：
  testWidgets('settings icon opens settings screen', (tester) async {
    final container = await makeContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const MaterialApp(home: HomeScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/presentation/home_screen_test.dart`
Expected: FAIL — 找不到 settings 图标

- [ ] **Step 3: 实现**

```dart
// lib/presentation/screens/home_screen.dart
// import 追加：
import 'settings_screen.dart';
// AppBar actions 最前追加（在统计图标前）：
          IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: '设置',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()))),
```

README.md 的"## 功能"清单追加一行：

```markdown
- **备份/导出**：JSON 完整备份与恢复（换机/重装不丢数据）、CSV 流水导出（Excel 可直接打开）
```

- [ ] **Step 4: 全量验证**

```bash
export PATH="/c/src/flutter/bin:$PATH" PUB_HOSTED_URL="https://pub.flutter-io.cn" FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
flutter test && flutter analyze
```

Expected: 全部 PASS（原有 38 + 新增 18 ≈ 56 tests）；analyze 零问题

- [ ] **Step 5: 提交**

```bash
git add lib/presentation/screens/home_screen.dart test/presentation/home_screen_test.dart README.md
git commit -m "feat: add settings entry from home and update readme"
```

---

## Self-Review 记录

- **Spec 覆盖**：JSON 格式（Task 1）、CSV/BOM/转义（Task 2）、单事务恢复+保留 id（Task 3）、BackupIO 抽象+share/file_picker（Task 4）、设置页三入口+确认框+错误 SnackBar（Task 5）、首页入口（Task 6）、README（Task 6）、隐私提示文案（Task 5）。spec 验收项"CSV Excel 中文正常"依赖真机验证（BOM 已由 Task 2 测试锁定）。
- **类型一致性**：`encodeBackup(List<Category>, List<Transaction>)`/`parseBackup(String)→BackupData`/`buildCsv(List<Transaction>, List<Category>)`/`escapeCsv(String)`/`BackupDao.exportAll()→({List<Category>, List<Transaction>})`/`restoreAll({categories, transactions})`/`BackupIO.shareFile(path, {text})`/`pickBackupFile()→String?` 跨任务一致；Task 5 的 fake 实现与 Task 4 抽象签名完全一致。
- **测试模式**：全部沿用已验证的 drift teardown 模式与 container override 模式（Global Constraints）。
- **已知风险**：share_plus 版本 API 形状（Task 4 Step 1 已给降级路径）；Task 5 确认框按钮 finder 若匹配多个（页面无其他 FilledButton，安全）。
