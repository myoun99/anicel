/// A conte body page as MARKS — the one walk the panel, the PNG and the PDF
/// all print from ([SheetMark]).
library;

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import '../../core/contain_rect.dart';
import '../camera_work_marks.dart';
import '../project_frame_rate.dart'
    show runningTimeLabel, secondsPlusFramesLabel;
import '../sheet_marks.dart';
import '../sheet_paint_layer.dart';
import 'conte_ink_windows.dart';
import 'conte_sheet_layout.dart';
import 'conte_sheet_source.dart';
import 'conte_words.dart';

/// The conte's ink — what its words print in, and what the ACTION field
/// types in on the page.
const int conteInkArgb = 0xFF101010;
const int _ink = conteInkArgb;

/// A cell's ACTION and DIALOGUE size — the printed words and the field that
/// edits them in place.
const double conteCellTextSize = 8.5;

/// The conte's line, as many times its words' size: the panel's text style
/// (`conteTextStyle`), the PDF and the cover set every line so.
const double conteLineHeight = 1.25;

/// One line of a cell's words — a cell's fixed lines stand one apart.
const double _cellLine = conteCellTextSize * conteLineHeight;

const int _rule = 0xFF404040;

/// The paper — inside a picture window too: an empty window, the canvas
/// past a picture's edge and the slot of a cut not made yet are all paper
/// (유저 2026-09-30, H52: 「빈곳? 밖공간이나 존재안하는컷의 코마가
/// 회색표시인데, 그냥 그런거 규칙두지말고 흰색인채로」). ↩️A window had a
/// grey well of its own (0xFFEDEDED), and each of those showed it.
const int _paper = 0xFFFFFFFF;

/// A block's own length: small and light, so the cut's total is the number
/// that reads (유저 2026-09-25: 「컷 전체 길이를 눈에띄게 하고싶으니까
/// 텍스트를 연하게, 작게」).
const int _blockLength = 0xFF8C8C8C;

/// How large the conte writes a camera's work, in points on its paper —
/// its colours are every surface's ([cameraWorkMarks]).
const CameraMarkSizes _cameraSizes = CameraMarkSizes(
  frameWidth: 1.2,
  trailWidth: 0.8,
  // Smaller, nearer the canvas's against its frame (유저 2026-10-12: 「IN
  // OUT 이런 글자 크니까 카메라 출력궤도랑 비슷하게 좀 더 작게」) — ↩️8.
  labelSize: 6,
  // A key's cross: small — it has one point to show (H55 「좀 작아도
  // 알기쉬우니 작고」).
  crossArm: 2.5,
  crossWidth: 0.8,
  labelInset: 2,
);

/// The length a cut is being dragged to, or null to print what the layout
/// built (F-88: the conte's numbers follow a cut-length drag).
typedef ConteLiveLength = int? Function(String cutId);

/// Every mark [page] prints, each in its stratum: the paper, the form, the
/// typed values, the film's pictures (with the camera work written on
/// them), the handwriting — a cover, a blank page or a body page. A
/// picture and a value never overlap, so the strata stack to this page in
/// any order a layered export or a bake picks.
List<SheetMark> contePageMarks(
  ContePageLayout page,
  ConteSheetSource source, {
  ConteLiveLength? liveFramesOf,
  required ConteWords words,
}) {
  final metrics = page.metrics;
  return [
    SheetFill(
      SheetPaintLayer.paper,
      rect: Rect.fromLTWH(0, 0, metrics.pageWidth, metrics.pageHeight),
      argb: _paper,
    ),
    ...switch (page.kind) {
      ContePageKind.cover => _cover(metrics, source, words),
      ContePageKind.blank => const <SheetMark>[],
      ContePageKind.body => [
        ..._form(metrics, words),
        ..._content(page, source, liveFramesOf),
      ],
    },
    ...conteInkMarks(page, metrics),
  ];
}

/// The cover (유저 2026-09-25, with a reference cover: 「타이틀/화수/이미지
/// 그리고 아래에 총컷, 총 길이 이렇게 까지는 넣고싶어. 스태프도
/// 기본값으로서 콘티까진 넣어도 될듯?」): the work large, the episode large,
/// the cover's picture, the book's cut count and running time, and the
/// conte artist. It carries no page number.
///
/// Laid about the PICTURE (유저 2026-09-25, on the first two previews:
/// 「작품제목 더 크게하고, 길어져서 다 안들어가면 크기 작게하는방향 …
/// 화수는 좀 더 타이틀이랑 붙여서」 · 「표지 컷이랑 콘티랑 같은 폰트로.
/// 크기나 이런거 전부」 · 「너무 위쪽정렬이야. 표지에서 컷이랑 콘티는
/// 중앙아래 느낌 원해. 정확히는 로고랑 밑 공간의 중앙쯤? 로고도 좀 더
/// 내리자. 중앙느낌」): the picture holds the page's middle, the title —
/// as large as its line allows — and the episode right under it stand on
/// it, and the two closing lines, set alike, sit in the middle of the room
/// below it. The picture's place is kept whether or not there is one.
Iterable<SheetMark> _cover(
  ConteSheetMetrics m,
  ConteSheetSource source,
  ConteWords words,
) sync* {
  final slots = _CoverSlots(m);
  SheetWords centred(
    String text,
    Rect slot,
    double size, {
    bool bold = false,
    SheetWordsFit fit = SheetWordsFit.oneLine,
  }) => SheetWords(
    SheetPaintLayer.content,
    text: text,
    slot: slot,
    size: size,
    argb: _ink,
    bold: bold,
    h: SheetAlign.center,
    v: SheetAlign.center,
    fit: fit,
  );

  yield centred(
    source.title,
    slots.title,
    _CoverSlots.titleSize,
    bold: true,
    fit: SheetWordsFit.shrink,
  );
  yield centred(
    source.episode,
    slots.episode,
    _CoverSlots.episodeSize,
    fit: SheetWordsFit.shrink,
  );
  final image = source.coverImagePath;
  if (image != null) {
    yield SheetImage(
      SheetPaintLayer.picture,
      assetPath: image,
      slot: slots.picture,
    );
  }
  final frames = source.cuts.fold<int>(
    0,
    (sum, cut) => sum + cut.durationFrames,
  );
  yield centred(
    '${source.cuts.length}${words.cutsSuffix}      '
    '${runningTimeLabel(frames, source.framesPerSecond)}',
    slots.cuts,
    _CoverSlots.closingSize,
  );
  if (source.conteStaffName.isNotEmpty) {
    yield centred(
      '${words.artist}      ${source.conteStaffName}',
      slots.staff,
      _CoverSlots.closingSize,
    );
  }
}

/// Where the cover's things stand — laid about the picture.
class _CoverSlots {
  _CoverSlots(ConteSheetMetrics m)
    : picture = Rect.fromCenter(
        center: Offset(m.pageWidth / 2, m.pageHeight / 2),
        width: m.pageWidth * 0.44,
        height: m.pageHeight * 0.26,
      ),
      _m = m;

  static const titleSize = 60.0;
  static const episodeSize = 40.0;
  static const closingSize = 13.0;
  static const _pictureGap = 28.0;
  static const _closingGap = 4.0;

  final ConteSheetMetrics _m;

  /// The page's middle.
  final Rect picture;

  /// Right under the title, standing on the picture.
  Rect get episode =>
      _across(picture.top - _pictureGap - _line(episodeSize), episodeSize);
  Rect get title => _across(episode.top - _line(titleSize), titleSize);

  /// The two closing lines, in the middle of the room below the picture.
  Rect get cuts {
    final closing = _line(closingSize) * 2 + _closingGap;
    return _across(
      (picture.bottom + _m.pageHeight) / 2 - closing / 2,
      closingSize,
    );
  }

  Rect get staff => _across(cuts.bottom + _closingGap, closingSize);

  // The conte's line: a slot one line tall.
  static double _line(double size) => size * conteLineHeight;

  Rect _across(double top, double size) =>
      Rect.fromLTWH(_m.marginX, top, _m.bodyWidth, _line(size));
}

/// The printed form: the cut box, the table and the silhouette — the
/// page's SHAPE, never the film's.
Iterable<SheetMark> _form(ConteSheetMetrics m, ConteWords words) sync* {
  yield* _rules(m);
  yield* _silhouette(m);
  yield* _head(m, words);
}

/// The rules of the cut box and the table.
///
/// 🚨EVERY COLUMN BOUNDARY IS ONE MARK, from the header's top to the body's
/// foot (유저 2026-09-25: 「헤더의 사각형 실루엣 선이랑 아래쪽 본문이랑
/// 라인이 미묘하게 어긋나있거나 하는데 절대 어긋나지않도록」). A header
/// divider and a body line at one x worked out apart are two numbers, and
/// two numbers drift. Where the silhouette IS the boundary — the picture
/// column's two sides, the head's underside, the foot — the rule's outer
/// edge is the silhouette's own number and it lies INSIDE that edge, holding
/// it when the screen widens it to a pixel ([SheetRuleHold]).
Iterable<SheetMark> _rules(ConteSheetMetrics m) sync* {
  final w = m.ruleWidth;
  SheetRule rule(
    double left,
    double top,
    double right,
    double bottom, [
    SheetRuleHold hold = SheetRuleHold.middle,
  ]) => SheetRule(
    SheetPaintLayer.form,
    rect: Rect.fromLTRB(left, top, right, bottom),
    argb: _rule,
    hold: hold,
  );
  const near = SheetRuleHold.near;
  const far = SheetRuleHold.far;

  final (cl, cr) = (m.cutColumnLeft, m.cutColumnRight);
  final (left, right) = (m.pictureLeft, m.bodyRight);
  final tableLeft = switch (m.form) {
    // The cut box, apart from the table: four sides inside its outline,
    // and the head's underside on the body's top.
    ConteSheetForm.analog => left,
    // One table from the cut column on (유저 2026-10-21, I-118: 「컷번호
    // 항목도 본문인 화면쪽이랑 붙어있고」): the cut column's right side is
    // the picture column's left.
    ConteSheetForm.digital => cl,
  };
  if (m.form == ConteSheetForm.analog) {
    yield rule(cl, m.tableTop, cr, m.tableTop + w, near);
    yield rule(cl, m.bodyTop - w, cr, m.bodyTop, far);
    yield rule(cr - w, m.tableTop, cr, m.bodyBottom, far);
  }
  yield rule(cl, m.bodyBottom - w, cr, m.bodyBottom, far);
  yield rule(cl, m.tableTop, cl + w, m.bodyBottom, near);

  // The table: its top and the head's underside, over every column.
  yield rule(tableLeft, m.tableTop, right, m.tableTop + w, near);
  yield rule(tableLeft, m.bodyTop - w, right, m.bodyTop, far);
  // The picture column's sides are ruled over the head only — below it the
  // silhouette's black is the edge, and these end on the black's own x.
  // With no black they run head to foot, as every other boundary does.
  final sidesEnd = m.outlined ? m.bodyTop : m.bodyBottom;
  yield rule(left, m.tableTop, left + w, sidesEnd, near);
  yield rule(m.actionLeft - w, m.tableTop, m.actionLeft, sidesEnd, far);
  // Every other boundary runs head to foot as one mark.
  for (final x in [m.dialogueLeft, m.timeLeft]) {
    yield rule(x - w / 2, m.tableTop, x + w / 2, m.bodyBottom);
  }
  yield rule(right - w, m.tableTop, right, m.bodyBottom, far);
  // The foot, under the text columns; the silhouette closes the rest — or,
  // with none, the foot runs under the picture too.
  yield rule(
    m.outlined ? m.actionLeft : left,
    m.bodyBottom - w,
    right,
    m.bodyBottom,
    far,
  );
}

/// The silhouette: ONE black shape down the picture column with a window of
/// the camera's own shape cut per row (유저 2026-09-25: 「검정색 사각형
/// 실루엣은 남기되 그거랑 겹친 이상한 반투명한 라인같은거 없앤단거야」) —
/// square, as every window of the sheet is ([ConteSheetMetrics.windowRect]
/// keeps the rounded corners it wore before).
///
/// Taken off (유저 2026-10-21, I-118: 「화면에 검은 외곽선 적용/미적용」),
/// nothing stands round a window, and its picture takes the cell
/// ([ConteSheetMetrics.windowInset]). ↩️Each window was ruled round in the
/// black's place, the picture where it stood in the black, until the
/// user's 「그만큼 그림이 작아지는것임 … 괘선은 삭제」 the same day.
Iterable<SheetMark> _silhouette(ConteSheetMetrics m) sync* {
  if (!m.outlined) return;
  yield SheetFill(
    SheetPaintLayer.form,
    rect: Rect.fromLTRB(m.pictureLeft, m.bodyTop, m.actionLeft, m.bodyBottom),
    argb: _ink,
  );
  for (var row = 0; row < m.rowsPerPage; row += 1) {
    yield SheetFill(
      SheetPaintLayer.form,
      rect: m.windowRect(row),
      argb: _paper,
    );
  }
}

/// The head's words, in the notation language — a word longer than its
/// column (「TIME」 over the slim time column) is set smaller, never broken.
Iterable<SheetMark> _head(ConteSheetMetrics m, ConteWords words) sync* {
  for (final (text, from, to) in [
    (words.cut, m.cutColumnLeft, m.cutColumnRight),
    (words.picture, m.pictureLeft, m.actionLeft),
    (words.action, m.actionLeft, m.dialogueLeft),
    (words.dialogue, m.dialogueLeft, m.timeLeft),
    (words.seconds, m.timeLeft, m.bodyRight),
  ]) {
    yield SheetWords(
      SheetPaintLayer.form,
      text: text,
      slot: Rect.fromLTRB(from + 1, m.tableTop, to - 1, m.bodyTop),
      size: 8,
      argb: _ink,
      h: SheetAlign.center,
      v: SheetAlign.center,
      fit: SheetWordsFit.shrink,
    );
  }
}

/// The values: what the film puts on the form.
Iterable<SheetMark> _content(
  ContePageLayout page,
  ConteSheetSource source,
  ConteLiveLength? liveFramesOf,
) sync* {
  final m = page.metrics;
  // Top-left, this page among the body's pages; top-right, the company logo
  // (유저 답 conte-body-header: 「쪽번호를 왼쪽위로 옮기고(1/51이런식으로
  // 전체 페이지도 표시), 오른쪽위는 회사로고」).
  yield SheetWords(
    SheetPaintLayer.content,
    text: '${page.bodyNumber} / ${page.bodyCount}',
    slot: m.pageNumberSlot,
    size: 9.5,
    argb: _ink,
    v: SheetAlign.center,
  );
  final logo = source.logoAssetPath;
  if (logo != null) {
    yield SheetImage(
      SheetPaintLayer.content,
      assetPath: logo,
      slot: m.logoSlot,
    );
  }

  for (final band in page.cutBands) {
    if (band.showsNumber) {
      yield SheetWords(
        SheetPaintLayer.content,
        text: band.cutName,
        slot: band.cutRect.deflate(3),
        size: 9,
        argb: _ink,
        bold: true,
        h: SheetAlign.center,
        fit: SheetWordsFit.oneLine,
      );
    }
  }
  yield* _rulesAcross(page);
  for (final cell in page.cells) {
    yield* _cell(m, source, cell);
  }
  yield* _times(page, source, liveFramesOf);

  yield SheetWords(
    SheetPaintLayer.content,
    text: conteLiveTotalOf(page, source, liveFramesOf),
    slot: m.pageTotalSlot,
    size: 9,
    argb: _ink,
    bold: true,
    h: SheetAlign.center,
    fit: SheetWordsFit.oneLine,
  );
}

/// In the digital form, a rule across the table under every cut that ends
/// above the page's foot (유저 2026-10-21, I-118: 「컷 마다 가로로 선 그어서
/// 칸 제대로 나누는방식」) — a cut's words stop on it
/// ([ContePlacedCell.actionRect]) — and under every row no cut takes
/// (「컷이 없는 공간도 1칸마다 가로선 긋도록. 지금 컷 없으면 가로선
/// 없으니까」). Content, since where a cut ends is the film's. Not over the
/// silhouette: its black between two windows parts them already.
Iterable<SheetMark> _rulesAcross(ContePageLayout page) sync* {
  final m = page.metrics;
  if (m.form != ConteSheetForm.digital) return;
  final w = m.ruleWidth;
  final spans = m.outlined
      ? [(m.cutColumnLeft, m.pictureLeft), (m.actionLeft, m.bodyRight)]
      : [(m.cutColumnLeft, m.bodyRight)];
  final ends = [
    for (final band in page.cutBands) band.cutRect.bottom,
    if (page.emptyRowsFrom case final empty?)
      for (var row = empty + 1; row < m.rowsPerPage; row += 1) m.rowTop(row),
  ];
  for (final y in ends) {
    if (y >= m.bodyBottom - 1e-9) continue;
    for (final (left, right) in spans) {
      yield SheetRule(
        SheetPaintLayer.content,
        rect: Rect.fromLTRB(left, y - w / 2, right, y + w / 2),
        argb: _rule,
      );
    }
  }
}

/// Where [cell]'s picture is printed — inside the silhouette's border, or
/// with none inside the cell's rules ([ConteSheetMetrics.windowInset]). The
/// brush draws into the picture through this same slot, so the pen lands
/// where the picture shows the stroke.
Rect contePictureSlot(ContePlacedCell cell, ConteSheetMetrics m) =>
    cell.pictureRect.deflate(m.windowInset);

/// [cell]'s picture as the page prints it — and as a live picture shows
/// its corner while the brush draws into it: the camera's shape contained
/// in the slot, the whole slot for a window of that shape.
///
/// A cell whose camera moves shows the canvas that camera sweeps instead
/// ([ConteCameraWork.field] — 유저 2026-09-29: 「일단 카메라 팬대로 해당
/// 코마에서 보여주고」), as large as its slot holds it, from the top of the
/// slot (H48: 「위쪽정렬로 배치」) — the plan's own scale
/// ([ConteCameraPlan.scale]) where the black stands round it, a slot the
/// picture's size; larger where none does.
SheetPicture contePictureOf(ContePlacedCell cell, ConteSheetMetrics m) {
  final slot = contePictureSlot(cell, m);
  final work = cell.source.camera;
  final Rect frame;
  if (work == null) {
    frame = containRect(Size(m.cameraAspect, 1), slot);
  } else {
    final scale = math.min(
      slot.width / work.field.width,
      slot.height / work.field.height,
    );
    frame = Rect.fromLTWH(
      slot.left,
      slot.top,
      work.field.width * scale,
      work.field.height * scale,
    );
  }
  return SheetPicture(
    SheetPaintLayer.picture,
    cutId: cell.cutId,
    pictureFrame: cell.source.pictureFrame,
    slot: slot,
    frame: frame,
    canvasRegion: work?.field,
  );
}

/// How many pixels wide [picture] renders when a window's picture renders
/// [windowWidth] wide: as sharp on the paper as every window's, so the
/// canvas a moving camera sweeps takes more pixels as it takes more paper
/// (유저 2026-09-25 conte-picture-resolution-Q1: 「내보낼땐 용지가
/// 실제크기가 꽤 크니까 그에 맞춰서 해상도 높기만하면됨」).
int contePictureRenderWidth(
  SheetPicture picture,
  ConteSheetMetrics m,
  int windowWidth,
) => math.max(
  1,
  (windowWidth * picture.frame.width / m.windowRect(0).width).round(),
);

/// The camera's work written on [cell]'s picture (유저 2026-09-30) — printed
/// over the picture, and over a live picture again, where it covers it.
///
/// The trail each corner of the frame draws, the canvas's own (「궤도는
/// 중앙이아니라 각 꼭짓점 4개 전부야」); the first key's frame in IN's green
/// and the last's in OUT's red, and no frame for a key between (「첫/끝 키
/// 말고 중간키는 실루엣을 안그려」, kept 2026-10-12 — I-89-Q14 B); every key
/// crossed at its frame's centre and labelled at its top-left corner,
/// turned with the frame (「기운 틀의 모서리. 각도 그대로따라감」), as the
/// canvas and the export write a key (유저 2026-10-12: 「카메라
/// 출력궤도랑 완전통일해서 … 중간키들도 표시하고」 · 「아까처럼 중앙에 두자 …
/// 즉 법 통일」) — a key between where its frame would be (「원래
/// 위치해야할곳에 위치시키고 틀만 안보이게」). Labels may overlap (「글자
/// 겹치는거 어쩔수없는거니까」).
///
/// ↩️Only a named key between was crossed, at its corner (유저 2026-10-01,
/// H55: 「s가 어딨는지 … 알기어렵잖아. 그래서 무언가 s의 꼭짓점에
/// 표시하고싶어서. 해당 위치 꼭짓점에 십자가」) — its label now stands at
/// that corner, by the trail the corner draws.
Iterable<SheetMark> conteCameraMarksOf(
  ContePlacedCell cell,
  ConteSheetMetrics m,
) {
  final work = cell.source.camera;
  if (work == null) return const <SheetMark>[];
  final shown = contePictureOf(cell, m).frame;
  final scale = shown.width / work.field.width;
  List<Offset> onPaper(List<Offset> points) => [
    for (final point in points)
      shown.topLeft + (point - work.field.topLeft) * scale,
  ];
  return cameraWorkMarks(
    trails: [for (final trail in work.trails) onPaper(trail)],
    keys: [
      for (final key in work.keys)
        CameraMarkedKey(
          corners: onPaper(key.corners),
          role: key.role,
          framed: key.role != CameraKeyRole.between,
          label: key.label,
        ),
    ],
    sizes: _cameraSizes,
    layer: SheetPaintLayer.picture,
  );
}

/// One cell: its window grown with its camera work, its picture, the
/// camera's work written on it and its two text columns — the ACTION
/// column its fixed lines first, the words typed there under them.
Iterable<SheetMark> _cell(
  ConteSheetMetrics m,
  ConteSheetSource source,
  ContePlacedCell cell,
) sync* {
  yield* _cameraWork(m, cell);
  yield contePictureOf(cell, m);
  yield* conteCameraMarksOf(cell, m);
  final action = cell.actionRect.deflate(4);
  yield* _fixedLines(source, cell, action);
  yield SheetWords(
    SheetPaintLayer.content,
    text: cell.source.action,
    slot: _below(action, conteActionWordsDrop(source, cell)),
    size: conteCellTextSize,
    argb: _ink,
  );
  yield SheetWords(
    SheetPaintLayer.content,
    text: contePrintedDialogueFor(source, cell),
    slot: cell.dialogueRect.deflate(4),
    size: conteCellTextSize,
    argb: _ink,
  );
}

/// The lines [cell]'s ACTION column writes over the words typed there: what
/// the camera does while the cell is on ([ConteCellSource.cameraLines],
/// I-93) and under them the transitions written there
/// ([ConteCellSource.transitionLines], I-93-Q1) — or none where the work
/// leaves them out ([ConteSheetSource.fixedText]).
List<String> conteFixedLinesOf(
  ConteSheetSource source,
  ContePlacedCell cell,
) => source.fixedText
    ? [...cell.source.cameraLines, ...cell.source.transitionLines]
    : const [];

/// How far below the top of its ACTION words [cell]'s typed words begin:
/// under its fixed lines ([conteFixedLinesOf]), a conte line each. The ONE
/// number the page prints the words by and the field types them at, so
/// the typing stands on the printed words — no one types into the fixed
/// lines (유저 2026-10-12, I-93: 「이 고정텍스트는 지울수없도록?」).
double conteActionWordsDrop(ConteSheetSource source, ContePlacedCell cell) =>
    conteFixedLinesOf(source, cell).length * _cellLine;

/// [cell]'s fixed lines in [slot], its ACTION words' slot: from its top a
/// conte line each, each on one line, never broken, in the words' ink
/// (I-93: 「각 FIX PAN 이런거마다 개행되고」).
Iterable<SheetMark> _fixedLines(
  ConteSheetSource source,
  ContePlacedCell cell,
  Rect slot,
) sync* {
  for (final (index, text) in conteFixedLinesOf(source, cell).indexed) {
    final line = _below(slot, index * _cellLine);
    yield SheetWords(
      SheetPaintLayer.content,
      text: text,
      slot: Rect.fromLTRB(
        line.left,
        line.top,
        line.right,
        math.min(line.top + _cellLine, line.bottom),
      ),
      size: conteCellTextSize,
      argb: _ink,
      fit: SheetWordsFit.oneLine,
    );
  }
}

/// [slot] from [drop] below its top — none of it past its bottom.
Rect _below(Rect slot, double drop) => Rect.fromLTRB(
  slot.left,
  math.min(slot.top + drop, slot.bottom),
  slot.right,
  slot.bottom,
);

/// Camera work makes the cell ONE window over its rows and into the
/// columns it claims ([conteCameraPlan]) — a box no larger than its
/// picture, at the top of those rows (유저 2026-09-30, H48: 「칸은 2칸공간
/// 차지하더라도 검은칸은 필요한 만큼만」). The picture column over the
/// cell's rows turns paper, and the box stands on it: black round a window
/// of paper, the picture's. With no black there is nothing to turn paper —
/// the window alone is paper, over the rules of the columns it grew into.
Iterable<SheetMark> _cameraWork(
  ConteSheetMetrics m,
  ContePlacedCell cell,
) sync* {
  if (cell.source.camera == null) return;
  final box = cell.pictureRect;
  if (m.outlined) {
    yield* _pictureColumnPaper(
      m,
      box.top,
      m.rowTop(cell.rowOnPage + cell.rowSpan),
    );
    yield SheetFill(SheetPaintLayer.picture, rect: box, argb: _ink);
  }
  yield SheetFill(
    SheetPaintLayer.picture,
    rect: contePictureSlot(cell, m),
    argb: _paper,
  );
}

/// The picture column from [top] to [bottom] where no window stands — the
/// rows a camera cell's box leaves, and the row its words moved down to:
/// paper, its sides ruled as the head rules the column, and its foot on
/// the page's last row (유저 2026-09-30, the page drawn and taken:
/// 「내려갈땐 다 같이 내려가도록하자」).
Iterable<SheetMark> _pictureColumnPaper(
  ConteSheetMetrics m,
  double top,
  double bottom,
) sync* {
  final w = m.ruleWidth;
  final (left, right) = (m.pictureLeft, m.actionLeft);
  SheetRule rule(Rect rect, SheetRuleHold hold) => SheetRule(
    SheetPaintLayer.picture,
    rect: rect,
    argb: _rule,
    hold: hold,
  );
  yield SheetFill(
    SheetPaintLayer.picture,
    rect: Rect.fromLTRB(left, top, right, bottom),
    argb: _paper,
  );
  yield rule(Rect.fromLTRB(left, top, left + w, bottom), SheetRuleHold.near);
  yield rule(Rect.fromLTRB(right - w, top, right, bottom), SheetRuleHold.far);
  if (bottom >= m.bodyBottom - 1e-9) {
    yield rule(
      Rect.fromLTRB(left, bottom - w, right, bottom),
      SheetRuleHold.far,
    );
  }
}

/// The time column: each block's own length where a cut has more than one,
/// and the cut's total under its last block (유저 2026-09-25: 「해당
/// 패널(우리로 치면 콘티블록)의 길이도 써져있거든? 그 다음 마지막 블록에
/// 컷 전체 길이 … 블록이 하나면 사실상 컷길이랑 블록길이랑 겹치니까
/// 그럴땐 블록길이 안보이게」).
Iterable<SheetMark> _times(
  ContePageLayout page,
  ConteSheetSource source,
  ConteLiveLength? liveFramesOf,
) sync* {
  final m = page.metrics;
  final fps = source.framesPerSecond;
  for (final cell in page.cells) {
    final cut = source.cutById(cell.cutId);
    // Where the cell's words are: beside its picture, or under it with the
    // rest of them (유저 2026-09-30: 「초수도 다음코마에 넣으면되니까」).
    final slot = Rect.fromLTRB(
      m.timeLeft,
      cell.wordsTop,
      m.bodyRight,
      m.rowTop(cell.rowOnPage + cell.rowSpan),
    ).deflate(m.timeInset);
    final isLast = cell.cellIndex == cut.cells.length - 1;
    final total = liveFramesOf?.call(cell.cutId) ?? cut.durationFrames;
    final totalHere =
        isLast &&
        page.cutBands.any((band) => band.cutId == cell.cutId && band.showsLength);
    if (cut.cells.length > 1) {
      // The last block ends where the cut does, so a length drag moves it.
      final blockFrames = isLast
          ? total - cell.source.startFrame
          : cell.source.lengthFrames;
      yield SheetWords(
        SheetPaintLayer.content,
        text: secondsPlusFramesLabel(blockFrames, fps),
        // Above the total when the total stands under it.
        slot: totalHere
            ? Rect.fromLTRB(slot.left, slot.top, slot.right, slot.bottom - 12)
            : slot,
        size: 7,
        argb: _blockLength,
        h: SheetAlign.center,
        v: SheetAlign.end,
        fit: SheetWordsFit.oneLine,
      );
    }
    if (totalHere) {
      yield SheetWords(
        SheetPaintLayer.content,
        text: secondsPlusFramesLabel(total, fps),
        slot: slot,
        size: 9,
        argb: _ink,
        bold: true,
        h: SheetAlign.center,
        v: SheetAlign.end,
        fit: SheetWordsFit.oneLine,
      );
    }
  }
}

/// The page's running total: the lengths of the cuts that END on it, each
/// read live.
String conteLiveTotalOf(
  ContePageLayout page,
  ConteSheetSource source,
  ConteLiveLength? liveFramesOf,
) {
  var total = 0;
  for (final band in page.cutBands) {
    if (band.showsLength) {
      total +=
          liveFramesOf?.call(band.cutId) ??
          source.cutById(band.cutId).durationFrames;
    }
  }
  return secondsPlusFramesLabel(total, source.framesPerSecond);
}
