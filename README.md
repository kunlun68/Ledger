# Ledger 记账

本地优先的移动端记账 App（Android）。个人自用 + 学习项目，数据完全保存在本地 SQLite，无网络依赖、无隐私上传。

## 下载安装

最新版 APK（GitHub Releases）：[https://github.com/kunlun68/Ledger/releases/latest](https://github.com/kunlun68/Ledger/releases/latest)

安装方式：下载 APK 后直接打开安装（需允许"安装未知来源应用"）；覆盖安装保留本地数据。

## 功能

### 记账

- **记一笔**：支出/收入切换、金额输入（精确到分）、分类选择、账户选择、日期、备注；支持编辑已有记录
- **账单列表**：按月查看、按日分组、滑动删除（可撤销）、点击进入编辑
- **首页仪表盘**：当月结余/收入/支出 + 最近 5 条记录 + 总资产，月份自由切换

### 多账户与转账

- 现金/微信/支付宝/银行卡等多账户，每个账户独立余额
- 账户间转账（转出账户减、转入账户加，总资产不变，不计入收支统计）
- 有交易或周期规则引用的账户不可删除

### 分类管理

- 内置默认分类（餐饮/交通/购物/居住/娱乐/医疗/教育等 + 收入类），支持自定义分类
- 内置分类删除保护，使用中的分类不可删除

### 预算

- 按分类设置月度预算，统计页显示进度条，超支标红

### 周期记账

- 房租/订阅/工资等规则：按每月第 N 天自动生成记录，打开 App 自动补齐遗漏月份
- 自动处理大小月（如 2 月 30 日自动收窄到月末）

### 统计图表

- 本月支出分类占比饼图
- 近 6 个月收支趋势柱状图
- 分类支出排行 + 预算进度

### 备份与导出

- **JSON 完整备份/恢复**：换机、重装不丢数据（通过系统分享面板发送备份文件）
- **CSV 流水导出**：Excel/记事本可直接打开，中文不乱码（UTF-8 BOM）

## 技术栈

| 层 | 技术 |
| --- | --- |
| UI | Flutter / Material 3，最低 Android 7.0 |
| 状态管理 | flutter_riverpod |
| 数据库 | drift (SQLite 类型安全 ORM) + build_runner 代码生成，schema 版本化迁移 |
| 图表 | fl_chart |
| 文件 | share_plus（分享备份）、file_selector（系统文件选择器恢复备份） |
| 金额 | 整数「分」存储（int），全程杜绝浮点误差 |

## 数据模型

- `transactions`：id、type(expense/income/transfer)、amount_cents(int)、category_id、note、date(yyyyMMdd)、account_id、transfer_account_id、created_at、updated_at
- `categories`：id、name、icon、type、sort_order、is_builtin、monthly_budget_cents
- `accounts`：id、name、icon、sort_order
- `recurring_rules`：id、type、amount_cents、category_id、account_id、day_of_month、note、last_generated_yyyymm

## 构建

```bash
# 安装依赖
flutter pub get

# 运行（需连接 Android 设备/模拟器）
flutter run

# 构建 release APK
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

> 注：测试套件（101 个用例）在本机维护、未随仓库分发；gradle.properties 中 `kotlin.incremental=false` 为 Windows 构建兼容设置，勿删。

## 目录结构

```text
lib/
├── main.dart / app.dart       # 入口、启动时补齐周期记账
├── data/                      # drift 表、迁移、DAO
├── core/                      # 金额解析/格式化、日期、统计聚合、备份编解码、CSV（纯函数）
├── application/               # Riverpod providers、备份 IO 抽象
└── presentation/
    ├── screens/               # 首页/记一笔/转账/账单/分类/统计/设置/账户/周期规则
    ├── widgets/               # 金额输入、分类/账户选择器
    └── theme/                 # 主题色
```

## 开发规范

- TDD：业务逻辑先写测试再实现；迁移路径有完整测试覆盖（v1 → v4）
- 金额运算禁止 double，一律使用整数分 + `parseCents`/`formatCents`
- 数据仅存本地，无任何隐私数据上传

## 后续规划 (P2)

- 支付宝/微信账单 CSV 导入 + 自动归类
- WebDAV/坚果云同步
- 深色模式
