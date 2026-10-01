import 'package:flutter/foundation.dart';

/// How the frame grid is drawn — a user preference, not project data
/// (Preferences ▸ Display).
class AppFrameGridSettings {
  const AppFrameGridSettings({this.blockFrameLines = false});

  /// Whether the frame lines cross a block's paper.
  ///
  /// 🗣️유저 2026-09-24: 「블록 세로선 역시 있는것도 좋아서 환경설정에 옵션으로
  /// 두고싶어. 기본값은 있음으로」. I-44 had taken them off every block on the
  /// user's own answer the day before (「세로선 지움(가로선 남김)」); both
  /// looks are the user's, so it is a switch.
  /// ↩️ON was the default until 2026-10-01 (유저: 「환경설정-화면-블록안 프레임
  /// 선을 기본값 off로」) — the switch stays, OFF is the default.
  final bool blockFrameLines;

  AppFrameGridSettings copyWith({bool? blockFrameLines}) =>
      AppFrameGridSettings(
        blockFrameLines: blockFrameLines ?? this.blockFrameLines,
      );

  Map<String, dynamic> toJson() => {'blockFrameLines': blockFrameLines};

  factory AppFrameGridSettings.fromJson(Map<String, dynamic> json) =>
      json['blockFrameLines'] is bool
      ? AppFrameGridSettings(blockFrameLines: json['blockFrameLines'] as bool)
      // Nothing saved reads as the default — the constructor's, the one
      // place it is written.
      : const AppFrameGridSettings();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppFrameGridSettings && other.blockFrameLines == blockFrameLines;

  @override
  int get hashCode => blockFrameLines.hashCode;

  /// The LIVE app-wide value (the workspace colours' idiom): the grids read
  /// it through their host's law, and the session restores and persists it.
  static final ValueNotifier<AppFrameGridSettings> settings =
      ValueNotifier<AppFrameGridSettings>(const AppFrameGridSettings());
}
