/// 색 라벨의 두 축 — 공정(세로)과 공정수정(가로).
///
/// 🚨★★★유저 설계 (I-4, 2026-08-27). 일렬로 두면 「콘티 · 콘티감독수정 ·
/// 콘티총감독수정 · 레이아웃 · 레이아웃연출수정 …」로 끝없이 길어지는데,
/// **수정의 종류는 공정이 달라도 똑같습니다** — 레이아웃의 작화감독수정과
/// 원화의 작화감독수정은 이름도 뜻도 같고 앞에 붙는 공정만 다릅니다.
///
/// 그래서 [LayerRevise] 는 **한 벌만** 있고, 공정이 그중 쓸 것을 [revisesFor]
/// 로 **참조**합니다. 유저: 「수정공정이 공통적으로 데이터 어딘가에 존재하고,
/// 그 수정공정을 **어느 공정에 끼워넣을지**같은걸로 판단하는느낌. 그렇게하면
/// **참조**니까 원래꺼 늘린다거나 안해도되고 **원화 수정공정에서 동화검사수정을
/// 뺄수있고**」.
library;

/// 공정 — 대분류(용지·콘티·미술)와 셀 안의 작업 단계를 한 벌로 둡니다.
///
/// ⚠️미술은 BG와 BOOK을 **나누지 않습니다**(유저: 「BG랑 BOOK이랑 나누지말라고.
/// 美術라는. 미술이라는 항목으로 합치고」).
enum LayerProcess {
  /// 用紙 — 그림이 아니라 종이. ⚠️TVPaint 스샷에는 「TAP」으로 되어 있지만
  /// 유저 정정(2026-08-27): 「그게아니라 **용지**로 하자. 이름. 用紙」.
  paper('paper', 'Paper', 'PAP'),
  conte('conte', 'Storyboard', 'SB'),
  art('art', 'Art', 'ART'),
  layout('layout', 'Layout', 'LO'),
  roughKey('rough-key', 'Rough Key', 'RK'),
  key('key', 'Key', 'KEY'),
  inbetween('inbetween', 'Inbetween', 'IB'),
  finish('finish', 'Finish', 'FIN');

  const LayerProcess(this.jsonValue, this.displayName, this.abbreviation);

  /// The stored key. ⚠️Shared with the cut envelope's `Map<공정키, 담당자>`
  /// so a process means the same thing in both — 「같은 것이 두 군데 살면
  /// 갈라진다」.
  final String jsonValue;

  /// The unabbreviated name, in ENGLISH — the other languages are tabled in
  /// `AppStrings.layerProcessName` under [jsonValue]. ⛔The words cannot live
  /// in `AppStrings` alone: `models` may not import `ui/`, so the enum is
  /// the English row and the table holds the rest (the `menuLabel` contract).
  final String displayName;

  /// What the label chip writes. 유저 설계: 공정 축약 + 수정 축약을 붙여
  /// 「LO작감」.
  final String abbreviation;

  static LayerProcess? fromJson(Object? json) {
    for (final process in LayerProcess.values) {
      if (json == process.jsonValue) {
        return process;
      }
    }
    return null;
  }
}

/// 공정수정 — 한 벌만 존재하고 공정이 참조합니다.
///
/// ⛔이름에 「수정」 접미사를 붙이지 않습니다(유저: 「뒤에 공통적으로 수정
/// 붙는거 다 없애. 그냥 연출 작화감독 이렇게만 존재하게」). 무엇의 수정인지는
/// 라벨이 이미 공정을 앞에 달고 있어서 말해 줍니다.
enum LayerRevise {
  direction('direction', 'Direction', 'DIR'),
  animationDirector('animation-director', 'Animation Director', 'AD'),
  chiefAnimationDirector('chief-animation-director', 'Chief Animation Director', 'CAD'),
  director('director', 'Director', 'DR'),
  chiefDirector('chief-director', 'Chief Director', 'CD'),
  actionAnimationDirector('action-animation-director', 'Action Animation Director', 'AAD'),
  inbetweenCheck('inbetween-check', 'Inbetween Check', 'IBC'),
  cellCheck('cell-check', 'Cell Check', 'CC');

  const LayerRevise(this.jsonValue, this.displayName, this.abbreviation);

  final String jsonValue;
  final String displayName;
  final String abbreviation;

  static LayerRevise? fromJson(Object? json) {
    for (final revise in LayerRevise.values) {
      if (json == revise.jsonValue) {
        return revise;
      }
    }
    return null;
  }
}

/// The six every drawing stage carries — 유저: 「레이아웃,러프원화,원화는
/// 공정이 많음. 연출,작화감독,감독,총감독,총작화감독,액션작화감독」.
const List<LayerRevise> _drawingRevises = [
  LayerRevise.direction,
  LayerRevise.animationDirector,
  LayerRevise.chiefAnimationDirector,
  LayerRevise.director,
  LayerRevise.chiefDirector,
  LayerRevise.actionAnimationDirector,
];

/// Which revises [process] offers — the REFERENCE, not a copy.
///
/// 🚨The list is built from the one [LayerRevise] set every time, so renaming
/// a revise renames it everywhere and nothing has to be kept in step. That is
/// the whole reason the axis is a reference: 「원화 수정공정에서 동화검사수정을
/// 뺄수있고」 without the other seven growing a copy of the list.
List<LayerRevise> revisesFor(LayerProcess process) => switch (process) {
  // 용지는 그림이 아니라 종이라 고칠 것이 없습니다 — 유저 정정(2026-08-27):
  // 「용지는 수정공정 존재 안하도록」.
  LayerProcess.paper => const [],
  // 콘티는 감독이 고칩니다 — 유저: 「콘티는 총 공정은 콘티, 콘티 감독수정,
  // 콘티 총감독 수정 아마 3가지임」.
  LayerProcess.conte => const [LayerRevise.director, LayerRevise.chiefDirector],
  // 동화와 시아게는 여섯에 더해 자기 검사를 하나씩 답니다.
  LayerProcess.inbetween => const [..._drawingRevises, LayerRevise.inbetweenCheck],
  LayerProcess.finish => const [..._drawingRevises, LayerRevise.cellCheck],
  // 나머지는 여섯 전부 — 미술도 포함입니다(유저 2026-08-27).
  _ => _drawingRevises,
};
