import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/background_provider.dart';
import '../../application/providers.dart';
import '../../core/background_settings.dart';
import '../widgets/app_scaffold.dart';

/// 内置底色色板（name, ARGB）。'默认' 的特殊值 0 表示恢复跟随主题。
const backgroundColors = <(String, int)>[
  ('默认', 0x00000000),
  ('浅灰蓝', 0xFFF4F6FA),
  ('米白', 0xFFFAF7F0),
  ('薄荷', 0xFFEAF4EE),
  ('淡紫', 0xFFF0EDF8),
  ('淡橙', 0xFFFBF1E7),
  ('浅粉', 0xFFF9EDEF),
  ('浅绿', 0xFFEEF4E4),
  ('浅黄', 0xFFFBF6E3),
];

/// 背景设置：实时预览 + 底色色板 + 相册选图 + 不透明度调节。
class BackgroundScreen extends ConsumerWidget {
  const BackgroundScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(backgroundProvider);
    final notifier = ref.read(backgroundProvider.notifier);
    final pick = ref.read(imagePickerProvider);

    Future<void> pickImage() async {
      final path = await pick();
      if (path == null) return; // 取消
      try {
        await notifier.setImage(path);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('图片设置失败')));
        }
      }
    }

    return AppScaffold(
      appBar: AppBar(title: const Text('自定义背景')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 预览卡片：直接复用 AppScaffold 的背景逻辑，包成固定高度圆角容器
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 180,
              child: Stack(fit: StackFit.expand, children: [
                _previewLayer(context, settings),
                const Center(
                  child: Text('背景预览',
                      style: TextStyle(color: Colors.black54)),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 24),
          const Text('底色', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final (name, argb) in backgroundColors)
                _Swatch(
                  name: name,
                  argb: argb,
                  selected: settings.type == BackgroundType.color
                      ? settings.colorValue == argb
                      : name == '默认',
                  onTap: () => argb == 0x00000000
                      ? notifier.clearBackground()
                      : notifier.setColor(argb),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Row(children: [
            const Text('图片', style: TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton.icon(
                onPressed: pickImage,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('从相册选择')),
            if (settings.type == BackgroundType.image &&
                settings.imagePath != null)
              TextButton.icon(
                  onPressed: notifier.clearBackground,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('移除图片')),
          ]),
          if (settings.type == BackgroundType.image &&
              settings.imagePath != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 120,
                child: Image.file(
                  File(settings.imagePath!),
                  key: const Key('background-thumb'),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Center(child: Text('图片无法加载')),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Row(children: [
            const Text('不透明度'),
            const Spacer(),
            Text('${(settings.clampedOpacity * 100).round()}%'),
          ]),
          Slider(
            value: settings.clampedOpacity,
            onChanged: settings.type == BackgroundType.image
                ? (v) => notifier.setImageOpacity(v)
                : null, // 非图片模式禁用
          ),
          const SizedBox(height: 8),
          const Text('仅图片背景可调节不透明度',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  /// 预览层与 AppScaffold 的 _BackgroundLayer 同构（底层色 + 图片 + scrim）。
  Widget _previewLayer(BuildContext context, BackgroundSettings s) {
    final theme = Theme.of(context);
    final baseColor = switch (s.type) {
      BackgroundType.none => theme.scaffoldBackgroundColor,
      BackgroundType.color => Color(s.colorValue),
      BackgroundType.image => theme.scaffoldBackgroundColor,
    };
    return ColoredBox(
      color: baseColor,
      child: s.type == BackgroundType.image && s.imagePath != null
          ? Stack(fit: StackFit.expand, children: [
              Image.file(
                File(s.imagePath!),
                fit: BoxFit.cover,
                opacity: AlwaysStoppedAnimation(s.clampedOpacity),
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
              ColoredBox(color: Colors.black.withValues(alpha: 0.15)),
            ])
          : const SizedBox.shrink(),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(
      {required this.name, required this.argb, required this.selected, required this.onTap});

  final String name;
  final int argb;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: argb == 0x00000000 ? c.surfaceContainerHighest : Color(argb),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? c.primary : c.outlineVariant,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: argb == 0x00000000
              ? Icon(Icons.auto_awesome, size: 18, color: c.onSurfaceVariant)
              : null,
        ),
        const SizedBox(height: 4),
        Text(name, style: const TextStyle(fontSize: 11)),
      ]),
    );
  }
}
