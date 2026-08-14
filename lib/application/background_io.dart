import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/background_settings.dart';

/// 设置持久化抽象：widget 测试注入内存实现。
abstract class SettingsStore {
  Future<BackgroundSettings?> readBackground();
  Future<void> writeBackground(BackgroundSettings s);
}

/// SharedPreferences 实现。JSON 编解码在此层，模型层只产 Map。
class PrefsSettingsStore implements SettingsStore {
  static const _key = 'background_settings';

  @override
  Future<BackgroundSettings?> readBackground() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    return raw == null ? null : BackgroundSettings.fromJson(jsonDecode(raw));
  }

  @override
  Future<void> writeBackground(BackgroundSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(s.toJson()));
  }
}

/// 测试用内存实现。
class InMemorySettingsStore implements SettingsStore {
  BackgroundSettings? stored;
  @override
  Future<BackgroundSettings?> readBackground() async => stored;
  @override
  Future<void> writeBackground(BackgroundSettings s) async => stored = s;
}

/// 背景图片文件 IO 抽象：测试注入 fake。
abstract class BackgroundImageIO {
  /// 把 [sourcePath]（file_selector 临时文件）拷贝到应用私有目录，
  /// 返回新文件绝对路径。失败抛异常。
  Future<String> saveImage(String sourcePath);
  Future<void> deleteImage(String path);
}

/// path_provider 实现：拷贝到 getApplicationSupportDirectory()/background.jpg。
class AppDirBackgroundImageIO implements BackgroundImageIO {
  static const _fileName = 'background.jpg';

  @override
  Future<String> saveImage(String sourcePath) async {
    final dir = await getApplicationSupportDirectory();
    final dest = File('${dir.path}${Platform.pathSeparator}$_fileName');
    await File(sourcePath).copy(dest.path); // 拷贝失败（磁盘/权限）抛异常
    return dest.path;
  }

  @override
  Future<void> deleteImage(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}

/// 测试用 fake：sourcePath 直接当结果路径，记录删除调用。
class FakeBackgroundImageIO implements BackgroundImageIO {
  final List<String> deleted = [];
  @override
  Future<String> saveImage(String sourcePath) async => sourcePath;
  @override
  Future<void> deleteImage(String path) async => deleted.add(path);
}

/// 系统文件选择器挑图片；取消返回 null。
Future<String?> pickImageFile() async {
  final file = await openFile(acceptedTypeGroups: [
    const XTypeGroup(label: 'image', extensions: ['jpg', 'jpeg', 'png', 'webp']),
  ]);
  return file?.path;
}
