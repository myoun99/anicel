import 'package:flutter/foundation.dart';

/// What the canvas draws of the camera's path (I-89 ④, 유저 2026-10-10
/// 「표시 끄기 / 공간 / 공간 + 시간」).
enum CameraPathShow {
  off,

  /// The path and every key on it.
  space,

  /// The path, its keys, and a cross at every frame the ticks fall on.
  spaceAndTime,
}

/// How much of the path the canvas draws (I-89 ④, 유저 2026-10-10 「범위
/// 키 전체 / 재생헤드 주변」).
enum CameraPathRange {
  allKeys,

  /// The frames within [CameraPathSettings.around] of the playhead.
  aroundPlayhead,
}

/// How the canvas shows a camera's path — a user preference, not project
/// data, one for every open project as the onion skin's pegs are.
class CameraPathSettings {
  const CameraPathSettings({
    this.show = CameraPathShow.spaceAndTime,
    this.range = CameraPathRange.allKeys,
    this.tickEvery = 1,
    this.around = 12,
  }) : assert(tickEvery >= 1 && around >= 1);

  final CameraPathShow show;
  final CameraPathRange range;

  /// The frames apart the time crosses stand, counted from the cut's first
  /// frame — typed, any number (유저 2026-10-10: 「점은 1f2f3f 정하는게아니라
  /// 커스텀으로 … 6f든 뭐든」).
  final int tickEvery;

  /// How many frames either side of the playhead
  /// [CameraPathRange.aroundPlayhead] draws.
  final int around;

  CameraPathSettings copyWith({
    CameraPathShow? show,
    CameraPathRange? range,
    int? tickEvery,
    int? around,
  }) => CameraPathSettings(
    show: show ?? this.show,
    range: range ?? this.range,
    tickEvery: tickEvery ?? this.tickEvery,
    around: around ?? this.around,
  );

  Map<String, dynamic> toJson() => {
    'show': show.name,
    'range': range.name,
    'tickEvery': tickEvery,
    'around': around,
  };

  /// What was saved, field by field — a field missing or out of reach
  /// reads as the constructor's default, the one place it is written.
  factory CameraPathSettings.fromJson(Map<String, dynamic> json) {
    const fallback = CameraPathSettings();
    T? named<T extends Enum>(List<T> values, Object? name) {
      for (final value in values) {
        if (value.name == name) {
          return value;
        }
      }
      return null;
    }

    int? count(Object? value) => value is int && value >= 1 ? value : null;
    return CameraPathSettings(
      show: named(CameraPathShow.values, json['show']) ?? fallback.show,
      range: named(CameraPathRange.values, json['range']) ?? fallback.range,
      tickEvery: count(json['tickEvery']) ?? fallback.tickEvery,
      around: count(json['around']) ?? fallback.around,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraPathSettings &&
          other.show == show &&
          other.range == range &&
          other.tickEvery == tickEvery &&
          other.around == around;

  @override
  int get hashCode => Object.hash(show, range, tickEvery, around);

  /// The LIVE app-wide value (the workspace colours' idiom): the canvas
  /// reads it, and the session restores and persists it.
  static final ValueNotifier<CameraPathSettings> settings =
      ValueNotifier<CameraPathSettings>(const CameraPathSettings());
}
