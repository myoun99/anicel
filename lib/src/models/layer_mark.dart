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
  const LayerMark({required this.process, this.revise, this.take});

  /// The same label with a different take — the take chip's one writer.
  LayerMark withTake(int? next) =>
      LayerMark(process: process, revise: revise, take: next);

  const LayerMark._none() : process = null, revise = null, take = null;

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

  /// 리테이크 번호 1–9, null 이면 없음 (I-5).
  ///
  /// 🚨★★★IT RIDES HERE RATHER THAN IN A FIELD OF ITS OWN. 유저 2026-08-27:
  /// 「작업하다보면 **리테이크**가 존재한단말이지? 그때 원화작업자가 레이아웃
  /// 그리고 리테이크 발생하면 똑같은 색 라벨만으로는 **테이크1인지 2인지 구분
  /// 안되잖아**」 — it answers「which version of this stage」, which is the
  /// same identity the process and revise answer.
  ///
  /// ⛔A `Layer.take` beside `Layer.mark` would have meant a second command,
  /// a second link-group mirror, a second JSON site and a second place to
  /// forget — for a value that travels with the label everywhere it goes.
  /// The two CHIPS stay separate; only the storage is one.
  ///
  /// ⚠️Null is the default and it stays null: 리테이크가 없는 컷에 T1 이
  /// 줄줄이 붙으면 정보가 아니라 노이즈다.
  final int? take;

  /// Whether there is no LABEL. ⚠️Asks about the stage alone — a take with
  /// no stage is representable (you can number a version of a row you have
  /// not staged yet) and the take chip shows it either way.
  bool get isNone => process == null;

  /// 테이크 칩이 쓰는 글자 — 「T2」. 없으면 빈 문자열이고, 자리는 그대로
  /// 예약된다(⛔없다가 생기는 UI 금지).
  String get takeText => take == null ? '' : 'T$take';

  /// The numbers the popover offers. ⛔One list rather than a `1..9` spelled
  /// at the widget and again at the test.
  static const List<int> takeChoices = [1, 2, 3, 4, 5, 6, 7, 8, 9];

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

  /// ⚠️A take with no stage still has to survive, so «no label at all» is
  /// stage AND take being absent — not [isNone], which asks about the stage.
  Object toJson() => isNone && take == null
      ? 'none'
      : <String, Object?>{
          if (process != null) 'process': process!.jsonValue,
          if (revise != null) 'revise': revise!.jsonValue,
          if (take != null) 'take': take,
        };

  /// ⚠️Reads the OLD eight-colour spelling as [none] rather than throwing.
  /// The colours carried no meaning a process could be recovered from — a
  /// layer marked "red" could have been any stage — so guessing one would
  /// invent data. A project opened from before this lands simply has no
  /// labels, which is honest and is what the user's own project has anyway
  /// (there is no production data to protect).
  static LayerMark fromJson(Object? json) {
    if (json is Map) {
      final take = json['take'];
      final process = LayerProcess.fromJson(json['process']);
      if (process == null && take is! int) {
        return none;
      }
      return LayerMark(
        process: process,
        revise: LayerRevise.fromJson(json['revise']),
        // ⚠️Clamped by the choices rather than trusted: a number outside
        // 1–9 would draw a chip the popover can never unset.
        take: take is int && takeChoices.contains(take) ? take : null,
      );
    }
    return none;
  }

  @override
  bool operator ==(Object other) =>
      other is LayerMark &&
      other.process == process &&
      other.revise == revise &&
      other.take == take;

  @override
  int get hashCode => Object.hash(process, revise, take);

  @override
  String toString() => isNone ? 'LayerMark.none' : 'LayerMark($displayName)';
}
