import 'layer_process.dart';

/// The layer's 색 라벨 — which 공정 this layer is, and whose 수정 it is.
///
/// 🚨★★★THIS IS THE OLD COLOUR TAG, GROWN UP — not a second label beside it.
/// It used to be eight bare colours (red…pink) with the colour's own English
/// name written on the plate; the plate, the rail slot, the flyout and the
/// frame blocks' paper all already ran through here. The colour label needed
/// exactly that slot, so it took it rather than opening a parallel one —
/// 유저 2026-08-27: 「사본 남으면 **진짜 용서안할게**」.
///
/// The swatch widget had even written the plan down: *"the palette is planned
/// to become process names — LO, 作監"*.
///
/// ⛔A mark is not a colour any more. The colour is looked up from the
/// process/revise pair through the chosen palette, so switching palettes
/// repaints every mark in the project without touching a single layer.
class LayerMark {
  const LayerMark({required this.process, this.revise});

  const LayerMark._none() : process = null, revise = null;

  /// No label. ⚠️Kept as a value rather than a null `Layer.mark` because the
  /// plate is painted for it too — it wears the paper colour so the tap
  /// target stays discoverable (⑳, 2026-08-17).
  static const LayerMark none = LayerMark._none();

  /// Which stage this layer is. Null only for [none].
  final LayerProcess? process;

  /// Whose correction it is. Null means 소재 (上がり) — the stage's own
  /// delivered work, which is the FIRST entry in the popover rather than a
  /// 「수정 없음」 (유저 2026-08-27: 「제일 위에 수정없음말고 上がり 라고 하자.
  /// 그 공정의 소재」).
  final LayerRevise? revise;

  bool get isNone => process == null;

  /// What the chip writes: the stage's abbreviation, and the correction's
  /// after it. 유저: 「공정이름+공정수정이름인데 축약어로」.
  ///
  /// ⚠️The chip stacks these vertically with the STAGE on the right, because
  /// Japanese vertical writing reads right to left (유저 2026-08-27). The
  /// widget does that with two columns; this getter only says what text.
  String get processText => process?.abbreviation ?? '';
  String get reviseText => revise?.abbreviation ?? '';

  /// The unabbreviated reading, for tooltips and the flyout.
  String get displayName {
    final stage = process;
    if (stage == null) {
      return '';
    }
    final correction = revise;
    return correction == null
        ? stage.displayName
        : '${stage.displayName} ${correction.displayName}';
  }

  /// The stable slug this mark is addressed by — flyout item keys, filter
  /// keys, test finders. ⛔ONE builder rather than a format string at each
  /// call site: three surfaces spell the same key and a fourth is coming.
  String get keySlug => isNone
      ? 'none'
      : revise == null
      ? process!.jsonValue
      : '${process!.jsonValue}-${revise!.jsonValue}';

  /// A stable order for lists of marks — 공정 순서, 그 안에서 수정 순서.
  /// 소재(수정 없음)가 자기 공정의 맨 앞에 온다.
  int get sortKey =>
      isNone ? -1 : process!.index * 100 + (revise == null ? 0 : revise!.index + 1);

  Object toJson() => isNone
      ? 'none'
      : <String, Object?>{
          'process': process!.jsonValue,
          if (revise != null) 'revise': revise!.jsonValue,
        };

  /// ⚠️Reads the OLD eight-colour spelling as [none] rather than throwing.
  /// The colours carried no meaning a process could be recovered from — a
  /// layer marked "red" could have been any stage — so guessing one would
  /// invent data. A project opened from before this lands simply has no
  /// labels, which is honest and is what the user's own project has anyway
  /// (there is no production data to protect).
  static LayerMark fromJson(Object? json) {
    if (json is Map) {
      final process = LayerProcess.fromJson(json['process']);
      if (process == null) {
        return none;
      }
      return LayerMark(
        process: process,
        revise: LayerRevise.fromJson(json['revise']),
      );
    }
    return none;
  }

  @override
  bool operator ==(Object other) =>
      other is LayerMark && other.process == process && other.revise == revise;

  @override
  int get hashCode => Object.hash(process, revise);

  @override
  String toString() => isNone ? 'LayerMark.none' : 'LayerMark($displayName)';
}
