import 'package:flutter/foundation.dart';

/// What the colour edit list's pixel verbs run with besides the colour —
/// 2치화's cut and the colour verbs' reach. A user preference, not project
/// data: one for every open project, as the onion skin's pegs are.
///
/// 🗣️I-13 (유저 2026-10-16): the cut is set in the list, in the row it is
/// for (「버튼 안에 공간을 두개로 나눠서」, 09-11), and kept across a
/// restart (Q2 = a, 「기억한다(앱 설정에 저장)」); 색 삭제 · 색 유지 get the
/// same knob for their reach (Q4 = a).
///
/// 🗣️ALL THREE ARE BYTES (I-13-Q5, 유저 2026-10-17): 「손잡이도 0~255 로」 —
/// 「더 정확하게 할수있는건 0~255인거니까 정확하게만 하면됨. 그쪽으로
/// 통일」. A knob holds the byte its pass compares with, on the scale fx
/// 「색 제거」's Tolerance already has. ↩️They were whole per cent, rounded
/// to a byte on the way in (50 % was 128, 1 % was 2) — a hundred steps over
/// 255 bytes, so most bytes had no step that reached them.
///
/// ⚠️ONE VALUE PER ROW. 색 삭제 and 색 유지 each keep their own reach, as two
/// colour-key effects each keep their own Tolerance: a knob shared by two
/// rows would be a rule nobody asked for, moving one row when the other is
/// turned.
class PixelVerbSettings {
  const PixelVerbSettings({
    this.binarizeThreshold = 128,
    this.deleteColourTolerance = 0,
    this.keepColourTolerance = 0,
  }) : assert(
         binarizeThreshold >= lowestBinarizeThreshold &&
             binarizeThreshold <= 255,
       ),
       assert(deleteColourTolerance >= 0 && deleteColourTolerance <= 255),
       assert(keepColourTolerance >= 0 && keepColourTolerance <= 255);

  /// 2치화's cut: a pixel whose alpha is at least this byte goes opaque,
  /// the rest empty. 128 is half, as the row was before it had a knob.
  final int binarizeThreshold;

  /// The least cut there is — the file's, the knob's and this class's.
  /// ⛔Not 0: at 0 an empty pixel would be at least it, and the paper
  /// would turn into drawing.
  static const int lowestBinarizeThreshold = 1;

  /// How far a colour may sit from the current one and still BE it, for
  /// 색 삭제 — the largest single-channel difference, as
  /// `CelColorKey.tolerance`. 0 is the colour itself and nothing else, as
  /// the row was before it had a knob.
  final int deleteColourTolerance;

  /// The same reach, for 색 유지.
  final int keepColourTolerance;

  PixelVerbSettings copyWith({
    int? binarizeThreshold,
    int? deleteColourTolerance,
    int? keepColourTolerance,
  }) => PixelVerbSettings(
    binarizeThreshold: binarizeThreshold ?? this.binarizeThreshold,
    deleteColourTolerance: deleteColourTolerance ?? this.deleteColourTolerance,
    keepColourTolerance: keepColourTolerance ?? this.keepColourTolerance,
  );

  Map<String, dynamic> toJson() => {
    'binarizeThreshold': binarizeThreshold,
    'deleteColourTolerance': deleteColourTolerance,
    'keepColourTolerance': keepColourTolerance,
  };

  /// What was saved, field by field — a field missing or out of reach
  /// reads as the constructor's default, the one place it is written.
  factory PixelVerbSettings.fromJson(Map<String, dynamic> json) {
    const fallback = PixelVerbSettings();
    int? within(Object? value, int lowest) =>
        value is int && value >= lowest && value <= 255 ? value : null;
    return PixelVerbSettings(
      binarizeThreshold:
          within(json['binarizeThreshold'], lowestBinarizeThreshold) ??
          fallback.binarizeThreshold,
      deleteColourTolerance:
          within(json['deleteColourTolerance'], 0) ??
          fallback.deleteColourTolerance,
      keepColourTolerance:
          within(json['keepColourTolerance'], 0) ??
          fallback.keepColourTolerance,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PixelVerbSettings &&
          other.binarizeThreshold == binarizeThreshold &&
          other.deleteColourTolerance == deleteColourTolerance &&
          other.keepColourTolerance == keepColourTolerance;

  @override
  int get hashCode => Object.hash(
    binarizeThreshold,
    deleteColourTolerance,
    keepColourTolerance,
  );

  /// The LIVE app-wide value (the workspace colours' idiom): a pixel verb
  /// reads it at its press, the list's knobs turn it, and the session
  /// restores and persists it.
  static final ValueNotifier<PixelVerbSettings> settings =
      ValueNotifier<PixelVerbSettings>(const PixelVerbSettings());
}
