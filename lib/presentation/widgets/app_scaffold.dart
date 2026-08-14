import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/background_provider.dart';
import '../../core/background_settings.dart';

/// 全局背景容器：底色 → 图片(不透明度) → scrim → 透明 Scaffold。
/// 所有页面用它替代 Scaffold。背景设置变化全局即时生效。
class AppScaffold extends ConsumerWidget {
  const AppScaffold({super.key, this.appBar, this.body = const SizedBox.shrink(), this.floatingActionButton});

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(backgroundProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        _BackgroundLayer(settings: s),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: appBar,
          body: body,
          floatingActionButton: floatingActionButton,
        ),
      ],
    );
  }
}

class _BackgroundLayer extends StatelessWidget {
  const _BackgroundLayer({required this.settings});
  final BackgroundSettings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = switch (settings.type) {
      BackgroundType.none => theme.scaffoldBackgroundColor,
      BackgroundType.color => Color(settings.colorValue),
      BackgroundType.image => theme.scaffoldBackgroundColor,
    };
    return ColoredBox(
      key: const Key('background-base'),
      color: baseColor,
      child: settings.type == BackgroundType.image && settings.imagePath != null
          ? Stack(fit: StackFit.expand, children: [
              Image.file(
                File(settings.imagePath!),
                key: const Key('background-image'),
                fit: BoxFit.cover,
                opacity: AlwaysStoppedAnimation(settings.clampedOpacity),
                errorBuilder: (_, _, _) => const SizedBox.shrink(), // 文件被删/损坏时只显示底色
              ),
              ColoredBox(
                  key: const Key('background-scrim'),
                  color: Colors.black.withValues(alpha: 0.15)), // 可读性 scrim
            ])
          : const SizedBox.shrink(),
    );
  }
}
