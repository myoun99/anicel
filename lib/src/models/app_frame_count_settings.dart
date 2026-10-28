import 'package:flutter/foundation.dart';

import 'frame.dart' show InbetweenMark, defaultInbetweenMark;

/// How a frame count is typed (I-24): as frames, or as seconds+frames.
enum FrameCountEntry { frames, secondsPlusFrames }

/// Which way a frame count was last typed — a user setting, not project
/// data.
///
/// 🗣️I-24-open-entry-Q1 (유저 2026-10-01): 「마지막에 쓴 방식으로 연다」 — the
/// count window opens on the entry last switched to, after a restart too.
class AppFrameCountSettings {
  const AppFrameCountSettings({
    this.lastEntry = FrameCountEntry.frames,
    this.lastEveryMark = defaultInbetweenMark,
  });

  final FrameCountEntry lastEntry;

  /// The mark the mark-every window last picked — it opens on it, as the
  /// count window opens on [lastEntry]: 🗣️I-130-Q2 (유저 2026-10-25 「창에서
  /// 마크를 고른다」 — 지난번 고른 것 기억).
  ///
  /// Until one is picked, [defaultInbetweenMark] — 🗣️F-469 (유저 2026-10-25
  /// 「기본마크, 앞으로 마크1 사용 … 다른곳도 같은곳있으면 확인해서 법 통일」).
  /// ↩️The ●, the one mark the window laid before marks were two.
  final InbetweenMark lastEveryMark;

  AppFrameCountSettings copyWith({
    FrameCountEntry? lastEntry,
    InbetweenMark? lastEveryMark,
  }) => AppFrameCountSettings(
    lastEntry: lastEntry ?? this.lastEntry,
    lastEveryMark: lastEveryMark ?? this.lastEveryMark,
  );

  Map<String, dynamic> toJson() => {
    'lastEntry': lastEntry.name,
    'lastEveryMark': lastEveryMark.name,
  };

  factory AppFrameCountSettings.fromJson(Map<String, dynamic> json) =>
      AppFrameCountSettings(
        lastEntry:
            FrameCountEntry.values.asNameMap()[json['lastEntry']] ??
            FrameCountEntry.frames,
        lastEveryMark:
            InbetweenMark.values.asNameMap()[json['lastEveryMark']] ??
            defaultInbetweenMark,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppFrameCountSettings &&
          other.lastEntry == lastEntry &&
          other.lastEveryMark == lastEveryMark;

  @override
  int get hashCode => Object.hash(lastEntry, lastEveryMark);

  /// The LIVE app-wide value (the workspace colours' idiom): the count
  /// window opens on it, and the session restores and persists it.
  static final ValueNotifier<AppFrameCountSettings> settings =
      ValueNotifier<AppFrameCountSettings>(const AppFrameCountSettings());
}
