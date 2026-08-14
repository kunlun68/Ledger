/// 背景类型：none=跟随主题、color=纯底色、image=图片（可调不透明度）。
enum BackgroundType { none, color, image }

/// 全局背景设置。序列化到 SharedPreferences（key: background_settings）。
class BackgroundSettings {
  const BackgroundSettings({
    required this.type,
    required this.colorValue,
    required this.imageOpacity,
    this.imagePath,
  });

  static const defaults = BackgroundSettings(
      type: BackgroundType.none, colorValue: 0, imageOpacity: 0.6);

  final BackgroundType type;
  /// 纯色背景的 ARGB 值（仅 type==color 生效）。
  final int colorValue;
  /// 图片不透明度 0-1（仅 type==image 生效），默认 0.6。
  final double imageOpacity;
  /// 图片在应用私有目录的绝对路径（仅 type==image 生效）。
  final String? imagePath;

  double get clampedOpacity => imageOpacity.clamp(0.0, 1.0);

  BackgroundSettings copyWith(
          {BackgroundType? type, int? colorValue, double? imageOpacity, String? imagePath}) =>
      BackgroundSettings(
        type: type ?? this.type,
        colorValue: colorValue ?? this.colorValue,
        imageOpacity: imageOpacity ?? this.imageOpacity,
        imagePath: imagePath ?? this.imagePath,
      );

  Map<String, Object?> toJson() => {
        'type': type.name,
        'colorValue': colorValue,
        'imageOpacity': imageOpacity,
        'imagePath': imagePath,
      };

  /// 解析持久化 JSON；任何非法输入回退默认值（不崩溃）。
  static BackgroundSettings fromJson(Object? json) {
    if (json is! Map) return defaults;
    final type = BackgroundType.values
        .where((t) => t.name == json['type'])
        .firstOrNull;
    if (type == null) return defaults;
    if (type == BackgroundType.color && json['colorValue'] is! int) {
      return defaults;
    }
    if (type == BackgroundType.image && json['imagePath'] is! String) {
      return defaults;
    }
    return BackgroundSettings(
      type: type,
      colorValue: (json['colorValue'] is int) ? json['colorValue'] as int : 0,
      imageOpacity: (json['imageOpacity'] is num)
          ? (json['imageOpacity'] as num).toDouble()
          : defaults.imageOpacity,
      // 安全转换：color 模式持久化里 imagePath 可能缺失或类型不对
      imagePath: json['imagePath'] is String ? json['imagePath'] as String : null,
    );
  }
}
