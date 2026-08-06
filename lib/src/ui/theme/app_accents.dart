import 'package:flutter/material.dart';

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
  const AppAccentSettings({this.accent = defaultAccent});

  /// The historical program teal.
  static const Color defaultAccent = Color(0xFF4FA8A0);

  final Color accent;

  AppAccentSettings copyWith({Color? accent}) =>
      AppAccentSettings(accent: accent ?? this.accent);

  Map<String, dynamic> toJson() => {'accent': accent.toARGB32()};

  /// A stored `accent2` from an older build is simply not read: the key stays
  /// on disk and is dropped on the next save, and nothing crashes.
  static AppAccentSettings fromJson(Map<String, dynamic> json) =>
      AppAccentSettings(
        accent: Color(json['accent'] as int? ?? defaultAccent.toARGB32()),
      );

  @override
  bool operator ==(Object other) =>
      other is AppAccentSettings && other.accent == accent;

  @override
  int get hashCode => accent.hashCode;
}
