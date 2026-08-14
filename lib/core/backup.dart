import 'dart:convert';
import '../data/database.dart';
import '../data/transaction_type.dart';

/// 备份文件校验失败，message 为面向用户的中文提示。
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
            'monthlyBudgetCents': c.monthlyBudgetCents,
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
    // 旧版备份（v1）无此字段，默认 0
    monthlyBudgetCents: m['monthlyBudgetCents'] as int? ?? 0,
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
