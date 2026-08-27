import 'package:flutter/material.dart';

import 'layer_mark_palette.dart';

/// The program accent (UI-R22 #5).
///
/// One highlight, used sparingly: selection, playhead, active toggles — the
/// historical teal. It is customizable and persisted.
///
/// There used to be a second accent here, the automatic complement of the
/// first, for "states that must read differently from plain selection". It
/// had exactly one production consumer (the selection-repeat pattern span)
/// and the second purpose its docs promised — the selected key-union
/// diamonds — was never wired, so the app carried a persisted, translated,
/// user-facing setting that told half a truth. The span now says what it is
/// with a dashed edge, which is a better sign than a hue nobody could name.
class AppAccentSettings {
  const AppAccentSettings({
    this.accent = defaultAccent,
    this.layerMarkPalette = LayerMarkPalette.fallback,
  });

  /// The historical program teal.
  static const Color defaultAccent = Color(0xFF4FA8A0);

  final Color accent;

  /// Which tone the 색 라벨 wears (I-4). ⚠️It rides HERE rather than in a
  /// store of its own: it is a colour preference belonging to the editor
  /// rather than to a project, which is exactly what this file already is —
  /// one more app-support JSON would be a second answer to «where do the
  /// program's colour choices live».
  ///
  /// 🔒**크림으로 확정**(유저 2026-08-28, 실기에서 넷을 보고 고름). 08-27 의
  /// 「기본값은 원본그대로로 두고」는 **고르는 동안만**의 임시값이었고, 이것이
  /// 그 자리를 대신한다 — 두 확정이 있으면 나중 것이 이긴다.
  ///
  /// ⚠️저장된 설정이 있으면 그쪽이 이긴다. 이 값은 **처음 켜는 사람이 보는 것**이다.
  final LayerMarkPalette layerMarkPalette;

  AppAccentSettings copyWith({
    Color? accent,
    LayerMarkPalette? layerMarkPalette,
  }) => AppAccentSettings(
    accent: accent ?? this.accent,
    layerMarkPalette: layerMarkPalette ?? this.layerMarkPalette,
  );

  Map<String, dynamic> toJson() => {
    'accent': accent.toARGB32(),
    'layerMarkPalette': layerMarkPalette.jsonValue,
  };

  /// A stored `accent2` from an older build is simply not read: the key stays
  /// on disk and is dropped on the next save, and nothing crashes.
  static AppAccentSettings fromJson(Map<String, dynamic> json) =>
      AppAccentSettings(
        accent: Color(json['accent'] as int? ?? defaultAccent.toARGB32()),
        layerMarkPalette: LayerMarkPalette.fromJson(json['layerMarkPalette']),
      );

  @override
  bool operator ==(Object other) =>
      other is AppAccentSettings &&
      other.accent == accent &&
      other.layerMarkPalette == layerMarkPalette;

  @override
  int get hashCode => Object.hash(accent, layerMarkPalette);
}
