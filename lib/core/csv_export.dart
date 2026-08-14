import 'money.dart';
import '../data/database.dart';
import '../data/transaction_type.dart';

/// 生成 CSV 全文（含 UTF-8 BOM，行分隔 \r\n，Excel 兼容）。
/// 列：date,type,category,account,amount,note
String buildCsv(List<Transaction> txs, List<Category> cats, List<Account> accounts) {
  final catName = <int, String>{
    for (final c in cats) c.id: c.name,
  };
  final accountName = <int, String>{
    for (final a in accounts) a.id: a.name,
  };
  final buf = StringBuffer('﻿date,type,category,account,amount,note\r\n');
  for (final t in txs) {
    final isTransfer = t.type == TxType.transfer;
    buf
      ..write(_formatDate(t.date))
      ..write(',')
      ..write(isTransfer
          ? '转账'
          : t.type == TxType.expense
              ? '支出'
              : '收入')
      ..write(',')
      ..write(isTransfer ? '' : escapeCsv(catName[t.categoryId] ?? '未分类'))
      ..write(',')
      ..write(escapeCsv(accountName[t.accountId] ?? '未知账户'))
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
