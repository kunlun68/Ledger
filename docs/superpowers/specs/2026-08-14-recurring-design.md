# 周期记账 — 设计文档

**日期**: 2026-08-14
**状态**: 已批准（用户 2026-08-14 确认）
**范围**: P1 子项目 3/4。剩余子项目：多账户。

## 目标

房租、订阅、工资等周期性收支自动入账：用户创建规则后，每次打开 App 自动补齐缺失月份的记录。

## 已确认的决策（用户拍板）

1. **触发方式**：App 启动时自动补生成（catch-up），无手动按钮、无后台调度
2. **规则生命周期**：固定字段 + 无限期（生成直到规则被删除），无结束日期
3. **UI 入口**：设置页加"周期记账"入口 → 独立规则列表页

## 数据模型

新表 `recurring_rules`（schemaVersion 2 → 3）：

```
id                INTEGER PK autoIncrement
type              TEXT（textEnum<TxType>）
amount_cents      INTEGER（分）
category_id       INTEGER REFERENCES categories(id)
note              TEXT DEFAULT ''
day_of_month      INTEGER（1-31）
last_generated_yyyymm  INTEGER DEFAULT 0（0 = 从未生成）
created_at        DATETIME DEFAULT currentDateAndTime
```

- `last_generated_yyyymm` 是幂等关键：启动时补齐 `(last_generated, now]` 缺失月份，随后推进
- 新规则创建时 `last_generated = 当月`（当月不生成，下月起生效）
- 删除规则：已生成记录保留，不追溯删除
- 不做"生成记录 ↔ 规则"关联标记（YAGNI）

## 生成逻辑

### core/recurring.dart（纯函数，无 Flutter 依赖）

```dart
/// 把 day 收窄到 yyyymm 月份实际天数内（2 月 30 日 → 2 月末）
int clampDayToMonth(int day, int yyyymm)

/// (from, to] 的缺失月份序列，升序；from >= to 返回空
List<int> monthsBetween(int fromYyyymm, int toYyyymm)
```

### data/dao/recurring_dao.dart

```dart
class RecurringDao {
  Future<void> insertRule({type, amountCents, categoryId, note, dayOfMonth})
  Future<void> deleteRule(int id)
  Stream<List<RecurringRule>> watchAll()   // 按 id 降序
  /// 启动补生成：单事务，对每条规则补齐 (lastGenerated, now] 各月交易，更新 lastGenerated
  Future<void> generateDue(int nowYyyymm)
}
```

generateDue 事务内：查规则 → 对每条规则 monthsBetween → 每缺失月 insert 一笔 transaction（date = `yyyymm*100 + clampDayToMonth(day, yyyymm)`，createdAt/updatedAt 自然时间）→ update 规则 lastGenerated = now。任一步失败整体回滚。

### 触发点

`main()`：`seedBuiltinCategories` 之后 `await RecurringDao(db).generateDue(yyyymmOf(todayYyyymmdd()))`。

## UI

### 设置页（settings_screen.dart）

追加一行入口 ListTile："周期记账"（icon: Icons.event_repeat）→ Navigator.push RecurringScreen

### 规则页（recurring_screen.dart，新建）

- AppBar "周期记账"；空状态"还没有周期规则"
- 规则列表：CircleAvatar（分类图标）+ 分类名 + 金额（类型色 ±）+ "每月 N 号" + 备注 + 删除 IconButton
- FAB → 新增 dialog：
  - SegmentedButton 支出/收入
  - 金额 TextField（复用 `AmountInputFormatter`）
  - 分类选择（复用 `CategoryPicker`）
  - "每月几号" TextField（数字 1-31，`FilteringTextInputFormatter.digitsOnly` + 校验）
  - 备注 TextField
  - 确定：parseCents 校验（失败 SnackBar "请输入有效金额"）；day 校验 1-31（失败 SnackBar "请输入 1-31 的日期"）；分类未选（失败 "请选择分类"）
- 删除：确认框（"删除后已生成的记录不受影响"）→ 删除 + SnackBar "已删除"

## 错误处理

| 场景 | 行为 |
| --- | --- |
| 金额非法 | SnackBar "请输入有效金额"，dialog 不关 |
| 日期超出 1-31 | SnackBar "请输入 1-31 的日期"，dialog 不关 |
| 分类未选择 | SnackBar "请选择分类"，dialog 不关 |
| 删除确认框取消 | 不删除 |

## 测试（TDD）

- `test/core/recurring_test.dart`：clampDayToMonth（2 月 28/29 平闰年、30 日进 2 月、31 日进各月）、monthsBetween（空/单月/多月/反向）
- `test/data/recurring_dao_test.dart`：generateDue 跨 2 月补 2 笔（日期与金额正确）、幂等（重跑不重复）、创建当月不生成、lastGenerated 推进、删除规则
- `test/data/migration_test.dart` 追加：v2 数据 → v3 后无损 + recurring_rules 表存在
- `test/presentation/recurring_screen_test.dart`：列表渲染、新增规则全流程（含非法 day/金额 SnackBar）、删除确认
- `test/presentation/settings_screen_test.dart` 追加：入口导航

## 验收

- 建规则"房租 每月 1 号 3000 支出"→ 下月打开 App 自动出现当月房租记录
- 跨月未打开 → 一次补齐多个月
- 2 月 30 号的规则 → 生成在 2 月末
- 删除规则 → 历史记录仍在
- 全量测试绿 + analyze 零问题
