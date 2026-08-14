import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/background_settings.dart';
import 'background_io.dart';
import 'providers.dart';

/// 全局背景设置。所有读写经 [SettingsStore]/[BackgroundImageIO] 抽象（测试注入）。
final backgroundProvider =
    NotifierProvider<BackgroundNotifier, BackgroundSettings>(BackgroundNotifier.new);

class BackgroundNotifier extends Notifier<BackgroundSettings> {
  /// 单飞加载：build 同步返回默认值，异步读持久化设置后刷新。
  /// 所有公开操作先 await [_ensureLoaded]，避免加载完成把用户操作覆盖。
  Future<void>? _loading;

  @override
  BackgroundSettings build() {
    _loading ??= _load();
    return BackgroundSettings.defaults;
  }

  Future<void> _load() async {
    final s = await ref.read(settingsStoreProvider).readBackground();
    if (s != null) state = s;
  }

  Future<void> _ensureLoaded() async {
    await _loading;
  }

  Future<void> setColor(int argb) async {
    await _ensureLoaded();
    state = state.copyWith(type: BackgroundType.color, colorValue: argb);
    await ref.read(settingsStoreProvider).writeBackground(state);
  }

  /// 选图：先拷贝新图成功，再更新状态；旧图最后删（失败不丢旧图）。
  Future<void> setImage(String sourcePath) async {
    await _ensureLoaded();
    final io = ref.read(backgroundImageIOProvider);
    final newPath = await io.saveImage(sourcePath); // 失败抛异常，state 不变
    final old = state.imagePath;
    state = state.copyWith(type: BackgroundType.image, imagePath: newPath);
    await ref.read(settingsStoreProvider).writeBackground(state);
    if (old != null && old != newPath) await io.deleteImage(old);
  }

  Future<void> setImageOpacity(double opacity) async {
    await _ensureLoaded();
    state = state.copyWith(imageOpacity: opacity.clamp(0.0, 1.0));
    await ref.read(settingsStoreProvider).writeBackground(state);
  }

  Future<void> clearBackground() async {
    await _ensureLoaded();
    final old = state.imagePath;
    state = BackgroundSettings.defaults;
    await ref.read(settingsStoreProvider).writeBackground(state);
    if (old != null) await ref.read(backgroundImageIOProvider).deleteImage(old);
  }
}
