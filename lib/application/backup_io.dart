import 'dart:io';
import 'package:file_selector/file_selector.dart';
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
    // file_selector 走系统 SAF，取消选择返回 null
    final file = await openFile(acceptedTypeGroups: [
      const XTypeGroup(label: 'json', extensions: ['json']),
    ]);
    if (file == null) return null;
    return File(file.path).readAsString();
  }
}
