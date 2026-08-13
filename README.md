# Ledger 记账

本地优先的移动端记账 App（Android）。个人自用 + 学习项目，数据完全保存在本地 SQLite，无网络依赖。

## 功能

- **记一笔**：支出/收入切换、金额输入（精确到分）、分类选择、日期、备注；支持编辑已有记录
- **账单列表**：按月查看、按日分组、滑动删除（可撤销）、点击进入编辑
- **分类管理**：内置默认分类（餐饮/交通/购物等 11 类）、自定义分类、内置分类删除保护、使用中的分类不可删除
- **统计图表**：本月支出分类占比饼图、近 6 个月收支趋势柱状图、支出分类排行
- **首页仪表盘**：当月结余/收入/支出 + 最近记录，月份自由切换

## 技术栈

| 层 | 技术 |
| --- | --- |
| UI | Flutter / Material 3 |
| 状态管理 | flutter_riverpod |
| 数据库 | drift (SQLite, 类型安全 ORM) |
| 图表 | fl_chart |
| 金额 | 整数「分」存储（int），杜绝浮点误差 |

## 数据模型

- `transactions`：id、type(expense/income)、amount_cents(int)、category_id、note、date(yyyyMMdd)、created_at、updated_at
- `categories`：id、name、icon、type、sort_order、is_builtin

## 运行

```bash
# 安装依赖
flutter pub get

# 运行（需连接 Android 设备/模拟器）
flutter run

# 单元测试 / widget 测试
flutter test

# 构建 release APK
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

## 目录结构

```text
lib/
├── main.dart / app.dart       # 入口、错误兜底
├── data/                      # drift 表、数据库、DAO
├── core/                      # 金额解析/格式化、日期、统计聚合（纯函数）
├── application/               # Riverpod providers
└── presentation/
    ├── screens/               # 首页/记一笔/账单/分类/统计
    ├── widgets/               # 金额输入、分类选择器
    └── theme/                 # 主题色
```

## 开发规范

- TDD：业务逻辑与页面交互先写测试再实现（`flutter test` 37 个用例全绿）
- 金额运算禁止 double，一律使用整数分 + `parseCents`/`formatCents`
- 数据仅存本地，无任何隐私数据上传

## 后续规划 (P1/P2)

- P1：月度预算、多账户与转账、周期记账、CSV 导出/备份
- P2：支付宝/微信账单导入、WebDAV/坚果云同步、深色模式
