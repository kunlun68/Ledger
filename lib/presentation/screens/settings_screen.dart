import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../core/backup.dart';
import '../../core/csv_export.dart';
import '../../core/date_util.dart';
import 'accounts_screen.dart';
import 'recurring_screen.dart';

/// 设置页：导出 CSV / 备份 / 恢复。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dao = ref.watch(backupDaoProvider);
    final io = ref.watch(backupIOProvider);

    void show(String msg) =>
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

    /// 写临时文件并分享。不主动删除：分享面板返回不等同于接收方读完文件
    /// （微信/QQ 需时间拷贝），留给系统 cache 清理（Android 自动清应用 cache 目录）。
    Future<void> share(String name, String content) async {
      final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}$name');
      try {
        await file.writeAsString(content);
        await io.shareFile(file.path, text: '记账备份');
      } catch (_) {
        if (context.mounted) show('导出失败');
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
      if (!context.mounted) return;
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
        ListTile(
            leading: const Icon(Icons.event_repeat),
            title: const Text('周期记账'),
            subtitle: const Text('房租/订阅等每月自动入账'),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const RecurringScreen()))),
        ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('账户'),
            subtitle: const Text('现金/微信/银行卡等多账户与转账'),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AccountsScreen()))),
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
