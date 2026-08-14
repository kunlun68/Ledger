# 预算管理 — 设计文档

**日期**: 2026-08-14
**状态**: 已批准（用户 2026-08-14 确认）
**范围**: P1 子项目 2/4。后续子项目：周期记账、多账户。

## 目标

给每个支出分类设置固定月度预算，统计页展示消费进度，超支醒目标红。App 内展示，不做系统通知。

## 已确认的决策（用户拍板）

1. **提醒形态**：App 内进度显示（统计页分类排行 + 超支红色），不做系统推送
2. **预算粒度**：每分类一个固定月度预算，每月自动按该额度计算

## 数据模型

`categories` 表加一列：

```
monthly_budget_cents: int, 默认 0（0 = 无预算），单位分
```

- `schemaVersion` 1 → 2，migration `addColumn`（列有默认值，旧行自动补 0）
- 不做独立 budgets 表 —— 预算即分类属性，独立表为过度设计
- 需重跑 `dart run build_runner build --delete-conflicting-outputs` 重新生成 database.g.dart
- 收入分类不使用该列（UI 上不提供设置入口）

## 超支判定（core/budget.dart 纯函数）

- `int budgetOf(Category c)` → `c.monthlyBudgetCents`（0 = 无预算）
- `bool isOverBudget(int spentCents, int budgetCents)` → `budgetCents > 0 && spentCents > budgetCents`
- 进度展示值 `min(spent/budget, 1.0)`（仅展示用 double，不参与金额运算）

当月每分类支出复用现有 `categoryExpenseProvider`（providers.dart，无需新增 provider）。

## UI

### 分类管理页（categories_screen.dart）

- 支出分类 ListTile `onTap` → 预算 dialog：
  - 标题"设置预算"（显示分类名）
  - TextField 预填当前预算（无预算为空），`AmountInputFormatter` 复用，hint "0.00 表示无预算"
  - 确定：`parseCents` 校验（失败 SnackBar"请输入有效金额"）→ `CategoriesDao.updateBudget(categoryId, cents)`（0 = 清除）
- 收入分类：`onTap` 为 null（不设预算）
- **行为调整**：内置分类 onTap 原为"内置分类不可删除"提示，改为打开预算 dialog（提示信息量低）；删除保护仍由"无删除按钮"体现

### 统计页（statistics_screen.dart）

分类排行 ListTile 增强：
- 有预算（budget > 0）：subtitle 显示 `LinearProgressIndicator`（value = min(spent/budget, 1)），trailing 显示"已花 x / y"两行（`formatCents`）
- 超支：trailing 文字与进度条用 `AppTheme.expenseColor`，无预算保持现状

## 数据访问

`CategoriesDao` 加：

```dart
Future<void> updateBudget(int categoryId, int monthlyBudgetCents)
```

（update with where，不影响其他字段）

## 错误处理

| 场景 | 行为 |
| --- | --- |
| 预算输入非法金额 | SnackBar "请输入有效金额"，dialog 不关闭 |
| dialog 取消 | 不改数据 |

## 测试（TDD）

- `test/data/categories_dao_test.dart` 追加：updateBudget 设置/清除
- `test/data/migration_test.dart`（新）：文件库 v1 插入数据 → 关闭 → 用当前代码打开 → 数据保留、monthlyBudgetCents == 0；测试用 `NativeDatabase(File)` 临时文件
- `test/core/budget_test.dart`（新）：isOverBudget 边界（相等不算超、0 预算不算超）
- `test/presentation/categories_screen_test.dart` 调整+追加：内置分类点击 → 预算 dialog（原"内置分类不可删除"断言删除）；设置预算 → 重开 dialog 显示旧值；清空预算；收入分类点击无 dialog
- `test/presentation/statistics_screen_test.dart` 追加：有预算分类显示"已花/预算"与进度；超支红色；无预算分类保持原样

## 验收

- 给"餐饮"设 100 元预算 → 记 120 元餐饮支出 → 统计页该分类红字显示已花 120.00/100.00
- 无预算分类不受影响
- 旧数据升级后一切正常（migration 测试覆盖）
- 全量测试绿 + analyze 零问题
