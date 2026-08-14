# 多账户 + 转账 — 设计文档

**日期**: 2026-08-14
**状态**: 已批准（用户 2026-08-14 确认）
**范围**: P1 子项目 4/4（最后一项）。

## 目标

支持现金/微信/支付宝/银行卡等多账户记账与账户间转账；首页显示总资产；收支统计不受转账干扰。

## 已确认的决策（用户拍板）

1. **初始余额**：无独立字段，余额纯靠交易聚合（新建账户余额 0，已有资金记一笔收入）
2. **转账建模**：单条双向记录（type=transfer + transfer_account_id）
3. **账户删除**：有交易/转账的账户不可删除
4. **首页**：加"总资产"（全账户余额合计），点击进账户页

## 数据模型（schemaVersion 3 → 4）

### 新表 accounts

```
id          INTEGER PK autoIncrement
name        TEXT（1-20 字）
icon        TEXT
sort_order  INTEGER DEFAULT 0
created_at  DATETIME DEFAULT currentDateAndTime
```

### transactions 表三处改动（drift TableMigration 重建，数据保留）

| 列 | 变更 | 说明 |
| --- | --- | --- |
| account_id | 新增 NOT NULL DEFAULT 1 | FK accounts；迁移时建默认账户"现金"(id=1)，旧交易自动归属 |
| transfer_account_id | 新增 可空 | FK accounts；仅转账记录使用 |
| category_id | 改为可空 | 转账没有分类概念 |

### TxType 枚举加 `transfer`

### recurring_rules 加 `account_id` NOT NULL DEFAULT 1

规则生成交易到指定账户；v3→v4 迁移一次完成所有列（本子项目尚未发布，规则表与交易表同版本迁移）。

### migration v4（onUpgrade from < 4）

1. 建 accounts 表 + 插入默认账户"现金"（id=1, icon='payments'）
2. `m.alterTable(TableMigration(transactions, ...))`：加 account_id（DEFAULT 1）、加 transfer_account_id、category_id 改可空

## 转账语义

- 转账 = 1 条记录：type=transfer、account=转出账户、transferAccount=转入账户、category=null
- **账户余额** = Σ该账户收入 − Σ该账户支出 + Σ转入 − Σ转出
- **收支统计**：现有 `totalByType` 只匹配 expense/income，transfer 天然被排除 → 月度摘要/预算/饼图/排行零改动
- 转账 date 参与列表排序与月份归属

## 数据访问

### AccountsDao（新）

```dart
Future<void> insertAccount(String name, String icon)
Future<void> deleteAccount(Account a)  // 有交易或转账引用抛 AccountInUseException
Stream<List<Account>> watchAll()       // sortOrder 升序
Future<int> balanceOf(int accountId)   // 按转账语义聚合
```

`AccountInUseException` 同 CategoryInUseException 模式。

### TransactionsDao 扩展

```dart
Future<void> insertTransfer({required int fromAccountId, required int toAccountId,
    required int amountCents, required int date, String note = ''})
// 现有 insertTransaction 加 required int accountId；updateTransaction 支持改账户
```

### core/stats.dart 扩展

```dart
/// accountId → 余额（分）。expense/income 按账户归属，transfer 双向计入。
Map<int, int> accountBalances(List<Transaction> txs)
int totalAssets(List<Transaction> txs)  // 全账户余额合计
```

### providers

- `accountsDaoProvider`、`allAccountsProvider = StreamProvider<List<Account>>`
- `totalAssetsProvider = Provider<int>`（watch allTransactionsProvider + accountBalances）

## UI

### 首页（home_screen.dart）

- 摘要卡上方"总资产 ¥x"（`formatCents`），点击 → AccountsScreen
- 本月结余/收入/支出保持

### 账户页（accounts_screen.dart，新）

- 列表：CircleAvatar（图标）+ 名称 + 余额（`formatCents`，负红正绿）
- FAB 新增 dialog（名称必填）
- AppBar 转账图标按钮 → TransferScreen
- 删除：`AccountInUseException` → SnackBar "该账户已有记录，无法删除"

### 转账页（transfer_screen.dart，新）

- 从账户 / 到账户（两个下拉或选择行，默认账户与第二个账户）、金额（AmountField）、日期（默认今天）、备注
- 校验：两账户不同（否则 "转出与转入账户不能相同"）、金额合法、解析成功保存

### 记一笔（add_transaction_screen.dart）

- 账户横向选择器（复用 CategoryPicker 样式，默认选中第一个账户）
- 保存带 accountId

### 账单列表（transactions_screen.dart + home_screen tile）

- subtitle 显示账户名；转账显示 "账户A → 账户B"（icon: swap_horiz）

### 周期规则（recurring_screen.dart）

- 新增 dialog 加账户选择（默认第一个）；规则行显示账户名

### 设置页

- 加"账户"入口（与周期记账并列）

## 备份/CSV 兼容

- 备份格式自动含新字段（encode/parse 补齐 accountId/transferAccountId，旧备份缺省 → 1/null）
- CSV：转账行 type="转账"、category 为空字符串；普通行加 account 列（列顺序：date,type,category,account,amount,note）

## 错误处理

| 场景 | 行为 |
| --- | --- |
| 删除有记录的账户 | SnackBar "该账户已有记录，无法删除" |
| 转账两账户相同 | SnackBar "转出与转入账户不能相同" |
| 新增账户名为空 | 确定键无效（dialog 不关） |

## 测试（TDD）

- migration v3→v4：旧交易归账户 1、accounts 含"现金"、transfer_account_id 可空可用
- accounts_dao_test：CRUD、余额（含转账双向）、删除保护
- stats_test 追加：accountBalances/totalAssets（含转账、排除规则）
- transactions_dao_test 追加：insertTransfer 双向记录
- add_transaction_screen_test：账户选择器默认值
- transfer_screen_test：转账成功（余额变化）、两账户相同报错
- accounts_screen_test：列表/新增/删除保护
- home_screen_test：总资产显示与跳转
- recurring_screen_test：规则带账户
- backup/csv 测试追加：新字段往返、转账 CSV 行

## 验收

- 新建"微信"账户 → 记支出 50 到微信 → 微信余额 -50、总资产 -50
- 现金 → 微信转 100 → 现金 -100、微信 +50（-50+100），总资产不变
- 统计页饼图/排行不出现转账
- 删除有记录的账户被拦截
- 旧数据升级后一切正常
- 全量测试绿 + analyze 零问题
