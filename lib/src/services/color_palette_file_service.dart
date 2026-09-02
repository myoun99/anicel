import 'dart:convert';
import 'dart:io';

import 'persistence/app_support_path.dart';

/// The editor's color palette (P4): a user-pinned swatch list plus the
/// recent-colors row. Editor/app state like brush presets — an app-support
/// JSON file, never project data.
class ColorPaletteState {
  const ColorPaletteState({
    this.pinned = defaultPinned,
    this.recent = const [],
  });

  /// A small starter set (the old quick swatches); fully user-editable.
  static const List<int> defaultPinned = [
    0xFF000000,
    0xFFE53935,
    0xFF1E88E5,
    0xFFFFFFFF,
  ];

  static const int maxRecent = 10;

  final List<int> pinned;
  final List<int> recent;

  ColorPaletteState copyWith({List<int>? pinned, List<int>? recent}) {
    return ColorPaletteState(
      pinned: pinned ?? this.pinned,
      recent: recent ?? this.recent,
    );
  }

  /// [color] promoted to the newest recent (deduped, capped).
  ColorPaletteState withRecentColor(int color) {
    if (recent.isNotEmpty && recent.first == color) {
      return this;
    }
    return copyWith(
      recent: [
        color,
        ...recent.where((entry) => entry != color),
      ].take(maxRecent).toList(),
    );
  }

  Map<String, Object?> toJson() => {'pinned': pinned, 'recent': recent};

  factory ColorPaletteState.fromJson(Map<String, dynamic> json) {
    List<int> colors(Object? value) => [
      if (value is List)
        for (final entry in value)
          if (entry is int) entry,
    ];
    return ColorPaletteState(
      pinned: colors(json['pinned']),
      recent: colors(json['recent']).take(ColorPaletteState.maxRecent).toList(),
    );
  }
}

/// Loads and saves [ColorPaletteState] (brush-preset file pattern; a
/// missing or corrupt file yields the defaults).
class ColorPaletteFileService {
  ColorPaletteFileService({String? filePath})
    : filePath = filePath ?? defaultColorPaletteFilePath();

  final String filePath;

  static String defaultColorPaletteFilePath() =>
      appSupportFilePath('color_palette.json');

  static const int version = 1;

  Future<ColorPaletteState> loadOrDefaults() async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return const ColorPaletteState();
      }
      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if ((decoded['version'] as int? ?? 0) > version) {
        return const ColorPaletteState();
      }
      return ColorPaletteState.fromJson(decoded);
    } on Object catch (_) {
      return const ColorPaletteState();
    }
  }

  Future<void> save(ColorPaletteState state) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({'version': version, ...state.toJson()}),
    );
  }
}
