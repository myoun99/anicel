import 'package:flutter/foundation.dart';

import 'inbetween_mark.dart';

/// How the frame grid is drawn, and the mark an unnamed drawing wears on
/// it — a user preference, not project data (Preferences ▸ Display).
class AppFrameGridSettings {
  const AppFrameGridSettings({
    this.blockFrameLines = false,
    this.unnamedMark = defaultUnnamedDrawingMark,
  });

  /// Whether the frame lines cross a block's paper.
  ///
  /// 🗣️유저 2026-09-24: 「블록 세로선 역시 있는것도 좋아서 환경설정에 옵션으로
  /// 두고싶어. 기본값은 있음으로」. I-44 had taken them off every block on the
  /// user's own answer the day before (「세로선 지움(가로선 남김)」); both
  /// looks are the user's, so it is a switch.
  /// ↩️ON was the default until 2026-10-01 (유저: 「환경설정-화면-블록안 프레임
  /// 선을 기본값 off로」) — the switch stays, OFF is the default.
  final bool blockFrameLines;

  /// Which of the two marks a drawing with no name wears where its block
  /// starts ([defaultUnnamedDrawingMark] until one is picked).
  ///
  /// 🗣️F-489 (유저 2026-10-27): 「이름 없는 블록의 기본 마크1,2인지
  /// 설정할수있게. 파일에 기억되도록? 환경설정에서 바꾸도록. 화면 탭에서?
  /// 그런건 판단 맡기고」 — a preference of the hand that draws, kept with the
  /// app as the frame lines are, so a file says nothing about it.
  final InbetweenMark unnamedMark;

  AppFrameGridSettings copyWith({
    bool? blockFrameLines,
    InbetweenMark? unnamedMark,
  }) => AppFrameGridSettings(
    blockFrameLines: blockFrameLines ?? this.blockFrameLines,
    unnamedMark: unnamedMark ?? this.unnamedMark,
  );

  Map<String, dynamic> toJson() => {
    'blockFrameLines': blockFrameLines,
    'unnamedMark': unnamedMark.name,
  };

  /// Nothing saved — or nothing this app can read — reads as the default,
  /// the constructor's, the one place it is written.
  factory AppFrameGridSettings.fromJson(Map<String, dynamic> json) {
    const unsaid = AppFrameGridSettings();
    return AppFrameGridSettings(
      blockFrameLines: switch (json['blockFrameLines']) {
        final bool shown => shown,
        _ => unsaid.blockFrameLines,
      },
      unnamedMark:
          InbetweenMark.values.asNameMap()[json['unnamedMark']] ??
          unsaid.unnamedMark,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppFrameGridSettings &&
          other.blockFrameLines == blockFrameLines &&
          other.unnamedMark == unnamedMark;

  @override
  int get hashCode => Object.hash(blockFrameLines, unnamedMark);

  /// The LIVE app-wide value (the workspace colours' idiom): the grids read
  /// it through their host's law, and the session restores and persists it.
  static final ValueNotifier<AppFrameGridSettings> settings =
      ValueNotifier<AppFrameGridSettings>(const AppFrameGridSettings());
}
