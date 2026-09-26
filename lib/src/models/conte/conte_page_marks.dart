/// A conte body page as MARKS — the one walk the panel, the PNG and the PDF
/// all print from ([SheetMark]).
library;

import 'dart:ui' show Offset, Rect;

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

const int _rule = 0xFF404040;
const int _paper = 0xFFFFFFFF;

/// The tone inside a picture window — the well a panel is drawn into.
/// Light enough that a drawing over it still reads as the drawing.
const int _well = 0xFFEDEDED;

/// A block's own length: small and light, so the cut's total is the number
/// that reads (유저 2026-09-25: 「컷 전체 길이를 눈에띄게 하고싶으니까
/// 텍스트를 연하게, 작게」).
const int _blockLength = 0xFF8C8C8C;

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

  // The conte's 1.25 line: a slot one line tall.
  static double _line(double size) => size * 1.25;

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

  // The cut box, apart from the table: four sides inside its outline, and
  // the head's underside on the body's top.
  final (cl, cr) = (m.cutColumnLeft, m.cutColumnRight);
  yield rule(cl, m.tableTop, cr, m.tableTop + w, near);
  yield rule(cl, m.bodyTop - w, cr, m.bodyTop, far);
  yield rule(cl, m.bodyBottom - w, cr, m.bodyBottom, far);
  yield rule(cl, m.tableTop, cl + w, m.bodyBottom, near);
  yield rule(cr - w, m.tableTop, cr, m.bodyBottom, far);

  // The table: its top and the head's underside, over every column.
  final (left, right) = (m.pictureLeft, m.bodyRight);
  yield rule(left, m.tableTop, right, m.tableTop + w, near);
  yield rule(left, m.bodyTop - w, right, m.bodyTop, far);
  // The picture column's sides are ruled over the head only — below it the
  // silhouette's black is the edge, and these end on the black's own x.
  yield rule(left, m.tableTop, left + w, m.bodyTop, near);
  yield rule(m.actionLeft - w, m.tableTop, m.actionLeft, m.bodyTop, far);
  // Every other boundary runs head to foot as one mark.
  for (final x in [m.dialogueLeft, m.timeLeft]) {
    yield rule(x - w / 2, m.tableTop, x + w / 2, m.bodyBottom);
  }
  yield rule(right - w, m.tableTop, right, m.bodyBottom, far);
  // The foot, under the text columns; the silhouette closes the rest.
  yield rule(m.actionLeft, m.bodyBottom - w, right, m.bodyBottom, far);
}

/// The silhouette: ONE black shape down the picture column with a window of
/// the camera's own shape cut per row (유저 2026-09-25: 「검정색 사각형
/// 실루엣은 남기되 그거랑 겹친 이상한 반투명한 라인같은거 없앤단거야」),
/// each window's corners rounded the app's way (「지브리콘티처럼 모서리
/// 둥글게하자. 우리 앱 통일 모서리 따라서」 · 「카메라는 사각형이라
/// 둥글게하면 둥근만큼 잘리잖아. 그거는 전혀 문제없고 의도한 대가야. 기존
/// 상태에서 둥글게만」).
Iterable<SheetMark> _silhouette(ConteSheetMetrics m) sync* {
  yield SheetFill(
    SheetPaintLayer.form,
    rect: Rect.fromLTRB(m.pictureLeft, m.bodyTop, m.actionLeft, m.bodyBottom),
    argb: _ink,
  );
  for (var row = 0; row < m.rowsPerPage; row += 1) {
    yield SheetFill(
      SheetPaintLayer.form,
      rect: m.windowRect(row),
      argb: _well,
      cornerRadius: m.windowRadius,
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

/// Where [cell]'s picture is printed — inside the silhouette's border. The
/// brush draws into the picture through this same slot, so the pen lands
/// where the picture shows the stroke.
Rect contePictureSlot(ContePlacedCell cell, ConteSheetMetrics m) =>
    cell.pictureRect.deflate(m.silhouetteBorder);

/// One cell: its window grown with its camera work, its picture, the
/// camera's labels and its two text columns.
Iterable<SheetMark> _cell(
  ConteSheetMetrics m,
  ConteSheetSource source,
  ContePlacedCell cell,
) sync* {
  final window = contePictureSlot(cell, m);
  yield* _cameraWork(m, cell, window);
  yield SheetPicture(
    SheetPaintLayer.picture,
    cutId: cell.cutId,
    pictureFrame: cell.source.pictureFrame,
    slot: window,
    cornerRadius: m.windowRadius,
  );
  yield* _cameraLabels(cell.source.cameraLabels, window.deflate(2));
  yield SheetWords(
    SheetPaintLayer.content,
    text: cell.source.action,
    slot: cell.actionRect.deflate(4),
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

/// Camera work makes the cell ONE window over its rows and into the text it
/// claims: the black it reaches beyond the column is its own, and so is the
/// well that covers the bars between its rows.
Iterable<SheetMark> _cameraWork(
  ConteSheetMetrics m,
  ContePlacedCell cell,
  Rect window,
) sync* {
  final picture = cell.pictureRect;
  final encroaches = picture.right > m.actionLeft;
  if (cell.source.rowSpan == 1 && !encroaches) return;
  if (encroaches) {
    yield SheetFill(
      SheetPaintLayer.picture,
      rect: Rect.fromLTRB(
        m.actionLeft,
        picture.top,
        picture.right,
        picture.bottom,
      ),
      argb: _ink,
    );
  }
  yield SheetFill(
    SheetPaintLayer.picture,
    rect: window,
    argb: _well,
    cornerRadius: m.windowRadius,
  );
}

/// The camera's labels, written on the picture: the first at its start, the
/// last at its end.
Iterable<SheetMark> _cameraLabels(List<String> labels, Rect slot) sync* {
  if (labels.isEmpty) return;
  SheetWords label(String text, SheetAlign at) => SheetWords(
    SheetPaintLayer.picture,
    text: text,
    slot: slot,
    size: 8,
    argb: _ink,
    bold: true,
    h: at,
    v: at,
  );
  yield label(labels.first, SheetAlign.start);
  if (labels.length > 1) yield label(labels.last, SheetAlign.end);
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
    final slot = Rect.fromLTRB(
      m.timeLeft,
      m.rowTop(cell.rowOnPage),
      m.bodyRight,
      m.rowTop(cell.rowOnPage + cell.source.rowSpan),
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
