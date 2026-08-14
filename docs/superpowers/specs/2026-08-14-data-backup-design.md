# 数据备份/导出 — 设计文档

**日期**: 2026-08-14
**状态**: 已批准（用户 2026-08-14 确认）
**范围**: P1 子项目 1/4。后续子项目：预算管理、周期记账、多账户。

## 目标

让用户能把记账数据完整备份/恢复到任意设备，并导出 CSV 供 Excel 分析或分享。个人本地工具，不做云同步（P2）。

## 已确认的决策（用户拍板）

1. **形态**：JSON 完整备份/恢复 + CSV 导出，两者都要
2. **文件传输**：分享 sheet（share_plus）+ 系统文件选择器（file_picker），Android 零权限
3. **恢复语义**：全量替换，执行前弹确认框（不可撤销提示）
4. **UI 入口**：新建"设置"页，首页 AppBar 齿轮图标进入

## 文件格式

### JSON 备份

文件名 `ledger-backup-YYYYMMDD.json`，UTF-8。

```json
{
  "app": "ledger",
  "version": 1,
  "exportedAt": "2026-08-14T21:00:00.000",
  "categories": [
    {"id":1,"name":"餐饮","icon":"restaurant","type":"expense","sortOrder":0,"isBuiltin":true}
  ],
  "transactions": [
    {"id":1,"type":"expense","amountCents":1234,"categoryId":1,"note":"午饭","date":20260813,"createdAt":"...","updatedAt":"..."}
  ]
}
```

- 序列化/反序列化手写（两页代码，不引入 json 代码生成）
- `fromJson` 严格校验，失败抛 `BackupFormatException`（带中文 message）：
  - `app != "ledger"` → "不是本应用的备份文件"
  - `version > 1` → "备份文件版本过新，请升级应用"
  - 字段缺失/类型错 → "备份文件内容损坏"
- 备份保留原始 id；恢复后 AUTOINCREMENT 序列继续

### CSV 导出

文件名 `ledger-YYYYMMDD.csv`，列：`date,type,category,amount,note`

- `date`: `2026-08-13`；`type`: `支出`/`收入`；`category`: 分类名（未找到的 categoryId 显示"未分类"）；`amount`: `formatCents` 元字符串（如 `12.34`）；`note`: 原文
- **文件以 UTF-8 BOM（`﻿`）开头** —— Excel 打开无 BOM 的 UTF-8 CSV 中文乱码
- 手写转义：字段含 `,` `"` `\n` 时用双引号包裹，内部 `"` 翻倍
- 排序与 `watchAll` 一致（date 降序）

## 架构

```text
core/backup.dart              纯函数：toJson/fromJson、toCsv、转义、校验（无 Flutter 依赖）
data/dao/backup_dao.dart      restoreAll()：单事务清空 categories+transactions → 按备份插入（全有或全无）
application/providers.dart    +backupIOProvider（平台通道抽象）
presentation/screens/settings_screen.dart  设置页（三入口 + 恢复确认流程）
presentation/screens/home_screen.dart      AppBar 齿轮入口
```

### 平台通道抽象 BackupIO

```dart
abstract class BackupIO {
  Future<void> shareFile(String path, {required String text});   // 分享面板
  Future<String?> pickBackupFile();                               // 选文件并返回内容，取消返回 null
}
```

- 真实实现 `SharePlusBackupIO`：share_plus 分享 `XFile`；file_picker 选 `.json` 读文本
- widget 测试注入 fake（内存内容/记录调用），避免平台通道在测试环境不可用

### 恢复流程（settings_screen）

1. `pickBackupFile()` → 内容 → `parseBackup(content)`（校验，失败 SnackBar 报 `BackupFormatException.message`）
2. AlertDialog："将清空现有 N 条记录并替换为备份内容，此操作不可撤销"（N = 当前交易数）
3. 确认 → 单事务：清空 categories + transactions → 按备份插入 → SnackBar "已恢复 X 条交易、Y 个分类"
4. 取消 → 无操作

恢复后 drift 的 watch stream 自动推送新数据，所有在挂载页面（首页/账单/统计）无需手动刷新。

事务性：用 drift `transaction()` 包住全部删除+插入，任一步失败整体回滚。

### 导出/备份流程

1. 从 DAO 取全量数据 → core 序列化 → 写 `Directory.systemTemp` 临时文件
2. `shareFile(path, text: '记账备份')` → 完成后删除临时文件（best-effort）

## 依赖

- `share_plus`（分享面板）、`file_picker`（选文件）—— 均成熟标准包，Android 无需权限
- 不引入 CSV/序列化代码生成依赖（手写，有单测覆盖）

## 错误处理

| 场景 | 行为 |
| --- | --- |
|---|---|
| 备份文件损坏/不兼容 | SnackBar 显示具体中文原因，数据不动 |
| 分享面板取消 | 静默返回 |
| 临时文件写入失败 | SnackBar "导出失败" |
| 恢复中途数据库错误 | 事务回滚，SnackBar "恢复失败" |

## 测试（TDD）

- `core/backup_test.dart`：JSON 往返、fromJson 拒绝坏文件（3 种错误）、CSV 转义（逗号/引号/换行）、BOM 存在、金额格式、type 中文映射
- `data/`：replaceAll 清空+插入、事务回滚（插入非法数据时原数据保留）
- `presentation/settings_screen_test.dart`：三入口渲染、恢复确认框（确认→恢复执行、取消→不动数据）、损坏文件 SnackBar、导出调用 fake BackupIO
- `home_screen_test.dart`：齿轮图标打开设置页

## 明确不做

- 自动定时备份、加密（P2 云同步时再评估）
- CSV 导入（P2 账单导入是独立需求）
- 备份到云端

## 验收

- 备份 → 微信/QQ 接收 JSON → 另一台设备恢复 → 数据一致
- 恢复确认框取消 → 数据不变
- CSV 用 Excel 打开中文正常
- 全量测试绿 + analyze 零问题
