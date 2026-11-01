import 'package:flutter/foundation.dart';

import 'inbetween_mark.dart';

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
    this.lastEveryMark,
    this.lastEveryCount = defaultEveryCount,
  });

  /// What the mark-every window opens on before any count was applied
  /// there: 🗣️F-518 (유저 2026-10-31 「기본값은 0말고 3으로하자」).
  static const int defaultEveryCount = 3;

  final FrameCountEntry lastEntry;

  /// The mark the mark-every window last picked — it opens on it, as the
  /// count window opens on [lastEntry]: 🗣️I-130-Q2 (유저 2026-10-25 「창에서
  /// 마크를 고른다」 — 지난번 고른 것 기억).
  ///
  /// Null until one is picked: the window then opens on the mark an unnamed
  /// drawing wears (`AppFrameGridSettings.unnamedMark`) — 🗣️F-489-Q1 (유저
  /// 2026-10-27 「둘 다 따라간다」). ↩️Mark 1, the ○ (F-469 「기본마크, 앞으로
  /// 마크1 사용」); the ●, the one mark the window laid before marks were two.
  final InbetweenMark? lastEveryMark;

  /// The count the mark-every window last applied — it opens on it, as it
  /// opens on [lastEveryMark]: 🗣️F-518 (유저 2026-10-31 「이 숫자는 마지막에
  /// 적용한값 기억하도록」). ↩️It opened on none, which reads 「-」.
  final int lastEveryCount;

  AppFrameCountSettings copyWith({
    FrameCountEntry? lastEntry,
    InbetweenMark? lastEveryMark,
    int? lastEveryCount,
  }) => AppFrameCountSettings(
    lastEntry: lastEntry ?? this.lastEntry,
    lastEveryMark: lastEveryMark ?? this.lastEveryMark,
    lastEveryCount: lastEveryCount ?? this.lastEveryCount,
  );

  Map<String, dynamic> toJson() => {
    'lastEntry': lastEntry.name,
    if (lastEveryMark case final mark?) 'lastEveryMark': mark.name,
    'lastEveryCount': lastEveryCount,
  };

  factory AppFrameCountSettings.fromJson(Map<String, dynamic> json) =>
      AppFrameCountSettings(
        lastEntry:
            FrameCountEntry.values.asNameMap()[json['lastEntry']] ??
            FrameCountEntry.frames,
        lastEveryMark: InbetweenMark.values.asNameMap()[json['lastEveryMark']],
        lastEveryCount: json['lastEveryCount'] as int? ?? defaultEveryCount,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppFrameCountSettings &&
          other.lastEntry == lastEntry &&
          other.lastEveryMark == lastEveryMark &&
          other.lastEveryCount == lastEveryCount;

  @override
  int get hashCode => Object.hash(lastEntry, lastEveryMark, lastEveryCount);

  /// The LIVE app-wide value (the workspace colours' idiom): the count
  /// window opens on it, and the session restores and persists it.
  static final ValueNotifier<AppFrameCountSettings> settings =
      ValueNotifier<AppFrameCountSettings>(const AppFrameCountSettings());
}
