import 'package:flutter/foundation.dart';

/// How a frame count is typed (I-24): as frames, or as seconds+frames.
enum FrameCountEntry { frames, secondsPlusFrames }

/// Which way a frame count was last typed — a user setting, not project
/// data.
///
/// 🗣️I-24-open-entry-Q1 (유저 2026-10-01): 「마지막에 쓴 방식으로 연다」 — the
/// count window opens on the entry last switched to, after a restart too.
class AppFrameCountSettings {
  const AppFrameCountSettings({this.lastEntry = FrameCountEntry.frames});

  final FrameCountEntry lastEntry;

  AppFrameCountSettings copyWith({FrameCountEntry? lastEntry}) =>
      AppFrameCountSettings(lastEntry: lastEntry ?? this.lastEntry);

  Map<String, dynamic> toJson() => {'lastEntry': lastEntry.name};

  factory AppFrameCountSettings.fromJson(Map<String, dynamic> json) =>
      AppFrameCountSettings(
        lastEntry:
            FrameCountEntry.values.asNameMap()[json['lastEntry']] ??
            FrameCountEntry.frames,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppFrameCountSettings && other.lastEntry == lastEntry;

  @override
  int get hashCode => lastEntry.hashCode;

  /// The LIVE app-wide value (the workspace colours' idiom): the count
  /// window opens on it, and the session restores and persists it.
  static final ValueNotifier<AppFrameCountSettings> settings =
      ValueNotifier<AppFrameCountSettings>(const AppFrameCountSettings());
}
