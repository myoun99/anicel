import 'layer_kind.dart';
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
  /// A drawing stage's label, its correction (null for 소재) after it.
  ///
  /// ⛔Not a 用紙 label — that one is [LayerMark.paper], which cannot be
  /// written without saying what it is the paper of.
  const LayerMark({
    required this.process,
    LayerRevise? revise,
    this.take = firstTake,
  }) : step = revise,
       assert(process != LayerProcess.paper, 'a 用紙 label is LayerMark.paper');

  /// A 用紙 label: the paper of [of], a stage or a correction — 🗣️F-578
  /// (유저 2026-11-10): 「용지-레이아웃, 용지-러프원, 용지-작감 이런식으로 …
  /// 용지는 용지-소재가 아니라 용지-LO 이런식으로」. There is no 用紙 소재.
  /// ↩️用紙 was a label of its own, with no second axis (유저 2026-08-27:
  /// 「용지는 수정공정 존재 안하도록」).
  const LayerMark.paper(LabelStep of, {this.take = firstTake})
    : process = LayerProcess.paper,
      step = of,
      assert(of != LayerProcess.paper, 'a paper is the paper of a stage');

  const LayerMark._of(this.process, this.step, this.take);

  /// The same label with a different take — the take chip's one writer.
  LayerMark withTake(int next) => LayerMark._of(process, step, next);

  const LayerMark._none() : process = null, step = null, take = firstTake;

  /// 리테이크를 안 한 상태 = 1판. 유저 2026-08-27: 「테이크는 **기본값 T1**」.
  ///
  /// ⛔There is no 「없음」 for a take, and that is deliberate: a drawing is
  /// always SOME pass, so the first one is 1 rather than an absence. The
  /// colour label keeps its 「라벨 없음」 — 유저: 「색라벨은 라벨없음 그대로
  /// 두자」 — because a row genuinely can have no stage.
  static const int firstTake = 1;

  /// No label. ⚠️Kept as a value rather than a null `Layer.mark` because the
  /// plate is painted for it too — it wears the paper colour so the tap
  /// target stays discoverable (⑳, 2026-08-17).
  static const LayerMark none = LayerMark._none();

  /// This label as the first value of a row made FROM this row (F-133, 유저
  /// 2026-09-14): 「+ 종류버튼 통해 어태치 레이어 생성시, 색라벨의 초기값은
  /// 대상 레이어의 색라벨을 이어받음 … 하드코딩하지말것 … 이어받는건 초기
  /// 값을 그렇게 세팅한단거지 이후 변경가능」. The door names the row it makes
  /// from and reads this off it.
  ///
  /// ⚠️The TAKE is not carried: the user named the colour label, and the take
  /// is a chip of its own — the new row starts at its own first pass.
  LayerMark get inherited => colorLabel;

  /// The COLOUR LABEL alone, the take left out — what the legend's colour
  /// solo lists and passes a row by (F-553, 유저 2026-11-04: 「색 라벨로만
  /// 보고 인식하도록. 테이크 다른거는 신경쓰지않음. 그거는 테이크 레전드버튼
  /// 만들어서 별도구현」).
  LayerMark get colorLabel => isNone ? none : LayerMark._of(process, step, firstTake);

  /// The label a row of [kind] made from nothing is born with (F-76, 유저
  /// 2026-09-12): 「콘티레이어 생성하면 색라벨 콘티 소재가 되도록. 이미지
  /// 레이어는 미술 소재, 애니메이션 레이어는 LO 소재」 — the kind's stage, as its
  /// 소재. The kinds the user did not name are born unlabelled.
  ///
  /// 🗣️F-578 (유저 2026-11-10): an image row is born LO 소재 like an
  /// animation row — 美術 is gone, its pictures being the layout artist's
  /// ([LayerProcess]). ↩️It was born 美術 소재 (F-76).
  static LayerMark bornOfKind(LayerKind kind) => switch (kind) {
    LayerKind.storyboard => const LayerMark(process: LayerProcess.conte),
    LayerKind.image ||
    LayerKind.animation => const LayerMark(process: LayerProcess.layout),
    LayerKind.folder ||
    LayerKind.se ||
    LayerKind.instruction ||
    LayerKind.transition ||
    LayerKind.camera ||
    LayerKind.adjustment => none,
  };

  /// Which stage this layer is. Null only for [none].
  final LayerProcess? process;

  /// The label's second axis ([LabelStep]): whose correction it is, or for
  /// a 用紙 label what it is the paper of. Null means 소재 (上がり) — the
  /// stage's own delivered work, which is the FIRST entry in the popover
  /// rather than a 「수정 없음」 (유저 2026-08-27: 「제일 위에 수정없음말고
  /// 上がり 라고 하자. 그 공정의 소재」).
  final LabelStep? step;

  /// Whose correction it is — null for 소재, and for a 用紙 label that is
  /// the paper of a stage.
  LayerRevise? get revise => switch (step) {
    final LayerRevise correction => correction,
    _ => null,
  };

  /// 리테이크 번호 1–9. ⚠️언제나 값이 있다 — 기본은 [firstTake].
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
  final int take;

  /// Whether there is no COLOUR label. ⚠️Asks about the stage alone: the
  /// take is always shown, so a row with no stage still reads 「T1」.
  bool get isNone => process == null;

  /// 테이크 칩이 쓰는 글자 — 「T2」.
  String get takeText => 'T$take';

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
  String get stepText => step?.abbreviation ?? '';

  /// The unabbreviated reading, for tooltips and the flyout.
  String get displayName {
    final stage = process;
    if (stage == null) {
      return '';
    }
    final second = step;
    return second == null
        ? stage.displayName
        : '${stage.displayName} ${second.displayName}';
  }

  /// The stable slug this mark is addressed by — flyout item keys, filter
  /// keys, test finders. ⛔ONE builder rather than a format string at each
  /// call site: three surfaces spell the same key and a fourth is coming.
  String get keySlug => isNone
      ? 'none'
      : step == null
      ? process!.jsonValue
      : '${process!.jsonValue}-${step!.jsonValue}';

  /// A stable order for lists of marks — 공정 순서, 그 안에서 그 공정의
  /// 하위 메뉴 순서([labelsOf]). 소재(수정 없음)가 자기 공정의 맨 앞에 온다.
  int get sortKey {
    if (isNone) {
      return -1;
    }
    final place = labelsOf(process!).indexOf(colorLabel);
    return process!.index * 100 + (place < 0 ? 99 : place);
  }

  /// ⚠️「라벨 없음」 은 공정이 없고 테이크도 1판일 때다 — 테이크만 올린 행은
  /// 저장돼야 한다.
  Object toJson() => isNone && take == firstTake
      ? 'none'
      : <String, Object?>{
          if (process != null) 'process': process!.jsonValue,
          ...switch (step) {
            null => const {},
            final LayerRevise correction => {'revise': correction.jsonValue},
            final LayerProcess stage => {'paperOf': stage.jsonValue},
          },
          if (take != firstTake) 'take': take,
        };

  /// ⚠️Reads the OLD eight-colour spelling as [none] rather than throwing.
  /// The colours carried no meaning a process could be recovered from — a
  /// layer marked "red" could have been any stage — so guessing one would
  /// invent data. A project opened from before this lands simply has no
  /// labels, which is honest and is what the user's own project has anyway
  /// (there is no production data to protect).
  ///
  /// A 用紙 label that names nothing it is the paper of is no label: this
  /// build writes none such (v35 — `anicelFormatVersion`).
  static LayerMark fromJson(Object? json) {
    if (json is Map) {
      final rawTake = json['take'];
      // ⚠️Clamped by the choices rather than trusted: a number outside
      // 1–9 would draw a chip the popover can never unset.
      final take = rawTake is int && takeChoices.contains(rawTake)
          ? rawTake
          : firstTake;
      final process = LayerProcess.fromJson(json['process']);
      final revise = LayerRevise.fromJson(json['revise']);
      if (process == LayerProcess.paper) {
        return switch (revise ?? LayerProcess.fromJson(json['paperOf'])) {
          final LabelStep of when of != LayerProcess.paper =>
            LayerMark.paper(of, take: take),
          _ => none,
        };
      }
      if (process == null && rawTake is! int) {
        return none;
      }
      return LayerMark(process: process, revise: revise, take: take);
    }
    return none;
  }

  @override
  bool operator ==(Object other) =>
      other is LayerMark &&
      other.process == process &&
      other.step == step &&
      other.take == take;

  @override
  int get hashCode => Object.hash(process, step, take);

  @override
  String toString() => isNone ? 'LayerMark.none' : 'LayerMark($displayName)';
}

/// Every label a layer can wear, in the order the popover lists them —
/// [LayerMark.none] first, then each stage followed by the corrections it
/// references.
///
/// 🚨★★★ONE ENUMERATION. The flyout draws this list and the ink-contrast
/// contract test walks it; building it twice would let a stage gain a
/// correction that nothing ever checked the readability of. It reads
/// [revisesFor] rather than restating it, so the axis stays a reference —
/// and it lives with [LayerMark], the type it enumerates, so the mark and
/// the process no longer import each other (Round 4 of the audit,
/// 2026-09-03).
List<LayerMark> everyLayerMark() => [
  LayerMark.none,
  for (final process in LayerProcess.values) ...labelsOf(process),
];

/// The labels [process] offers, in the order its second level lists them:
/// its 소재 and then the corrections it references ([revisesFor]) — or, for
/// 用紙, the paper of every other stage and then of every correction.
///
/// 🗣️F-578 (유저 2026-11-10): 「용지라벨은 권한대로. 모든 공정을 넣음. 앞으로
/// 발생하는것도.」 — built from the two lists, so a stage or a correction
/// added later is a paper too. There is no 用紙 소재, and 용지-LO comes first
/// where a 소재 would (「용지는 용지-소재가 아니라 용지-LO 이런식으로」).
List<LayerMark> labelsOf(LayerProcess process) => switch (process) {
  LayerProcess.paper => [
    for (final stage in [
      LayerProcess.layout,
      for (final other in LayerProcess.values)
        if (other != LayerProcess.paper && other != LayerProcess.layout)
          other,
    ])
      LayerMark.paper(stage),
    for (final revise in revisesFor(process)) LayerMark.paper(revise),
  ],
  _ => [
    LayerMark(process: process),
    for (final revise in revisesFor(process))
      LayerMark(process: process, revise: revise),
  ],
};

/// [staff] — who does each stage's work, by its label's [LayerMark.keySlug]
/// — with [mark]'s name set to [name]; an empty one drops the entry, so the
/// map never holds a blank. ONE rule for the work's staff (작품 설정) and a
/// cut's own (컷 설정).
Map<String, String> staffWithName(
  Map<String, String> staff,
  LayerMark mark,
  String name,
) {
  final next = {...staff};
  if (name.isEmpty) {
    next.remove(mark.keySlug);
  } else {
    next[mark.keySlug] = name;
  }
  return next;
}

/// Who keeps the names of the people doing a stage's work.
enum StaffHolder {
  /// The work (작품 설정): the conte — one book for the whole work.
  work,

  /// Each cut (컷 설정): every other stage with staff, whose people change
  /// from cut to cut.
  cut,
}

/// Who keeps [process]'s staff — null for 用紙, which is nobody's work
/// (유저 2026-10-05, F-291: 「용지라는 스태프는 없음」). The label keeps it.
/// ↩️美術 had none either (유저 2026-10-28, F-291: 「컷 설정의 미술 항목 전부
/// 삭제. 작업자나 연출이나 포함해서 미술이란 항목 통째로. 필요없음」) until
/// F-578 took 美術 out of the labels too.
///
/// 🗣️유저 2026-10-08 (F-291-Q1): 「원화 작업자나 시아게는 컷마다 다름 …
/// 공통적인 부분인 제목/화수/회사로고/표지그림등만 남겨두고, 스태프는 콘티만
/// 남겨둠. 나머진 삭제. 나머진 컷마다 스태프설정」. ↩️The work kept every
/// stage's name and a cut's own name stood over it (09-25: 작품 설정에는
/// 기본값, 컷 설정에는 컷별 이름).
StaffHolder? staffHolderOf(LayerProcess process) => switch (process) {
  LayerProcess.paper => null,
  LayerProcess.conte => StaffHolder.work,
  _ => StaffHolder.cut,
};

/// The stages whose staff fold opens before anyone has opened or shut one
/// — 🗣️유저 2026-10-28 (F-291): 「항목들 기본적으로 접힌상태이도록. 디폴트가.
/// 러프원화만 열린상태로」.
const Set<LayerProcess> staffFoldsOpenAtFirst = {LayerProcess.roughKey};

/// A staff map as a file holds it: each stage's name by its key
/// ([LayerMark.keySlug]).
///
/// ↩️It dropped two older shapes here — a value that was a name-and-stamp
/// object (from before the labels vocabulary), and a stage its holder no
/// longer keeps (from before F-291-Q1 gave every stage but the conte to the
/// cut). Only files of formats refused by their number now hold either (the
/// save law, 유저 2026-10-06).
Map<String, String> staffFromJson(Object? json) => {
  for (final MapEntry(:key, :value)
      in (json as Map<String, dynamic>? ?? const {}).entries)
    key: value as String,
};
