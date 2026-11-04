import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';

import '../../helpers/painted_glyph_boxes.dart';

/// The paragraphs a sheet paints, and its paths with their colour.
class _HeaderInk extends PaintedGlyphBoxes {
  final paths = <({Rect bounds, int argb})>[];

  @override
  void drawPath(Path path, Paint paint) => paths.add((
    bounds: MatrixUtils.transformRect(
      Matrix4.fromFloat64List(getTransform()),
      path.getBounds(),
    ),
    argb: paint.color.toARGB32(),
  ));
}

/// 🗣️F-558 (유저 2026-11-04): 「고정텍스트 on이든 off이든 연관없음. 항상
/// 보여줌. 위치는 헤더의 컷 번호 아래에 겸용컷들을 텍스트로 둠. 심플하게
/// 텍스트로만 쭉 나열. 그러고 왼쪽에 ( 이 모양으로 컷들 묶는느낌」 · 「다른
/// 겸용컷 보여주는 텍스트는 텍스트색이랑 ( 아이콘 동일하게 연하게 표시하자.
/// 겸용컷의 컷이름 글자도 헤더 컷이름 텍스트보다 작게」 · 「작게하고
/// (아이콘에 붙여야하니까 왼쪽정렬」 · F-558-Q1 「텍스트 층으로만 되면됨」.
///
/// Measured as what the sheet paints in its cut box.
void main() {
  TimesheetDocument sheet({
    List<String> linkedCuts = const [],
    String name = '312',
  }) => TimesheetDocument.fromCut(
    cut: Cut(
      id: const CutId('cut'),
      name: name,
      duration: 24,
      canvasSize: const CanvasSize(width: 1920, height: 1080),
      layers: const [],
    ),
    projectName: 'P',
    fps: 24,
    linkedCuts: linkedCuts,
  );

  Rect cutBox(TimesheetDocumentLayout layout) => layout
      .headerFieldBoxes(0)
      .firstWhere((box) => box.field == TimesheetHeaderField.cut)
      .rect;

  /// What [document]'s sheet paints in strata [layers]: its paragraphs and
  /// its paths that stand in the first page's cut box, or under it.
  ({List<Rect> words, List<({Rect bounds, int argb})> paths, Rect box}) inkOf(
    TimesheetDocument document, {
    Set<SheetPaintLayer>? layers = const {SheetPaintLayer.content},
  }) {
    final layout = TimesheetDocumentLayout(document: document);
    final ink = _HeaderInk();
    TimesheetDocumentPainter(
      words: timesheetWordsIn(AppLanguage.en),
      face: const TextStyle(),
      document: document,
      layout: layout,
      layers: layers,
    ).paint(ink, Size(layout.paperLeft + layout.paperWidth + 8, 2000));
    final box = cutBox(layout);
    // The box's column, down into the memo band under it.
    final column = Rect.fromLTRB(
      box.left,
      box.top,
      box.right,
      layout.memoBandRect(0).bottom,
    );
    return (
      words: [
        for (final word in ink.boxes)
          if (column.contains(word.center)) word,
      ],
      paths: [
        for (final path in ink.paths)
          if (column.contains(path.bounds.center)) path,
      ],
      box: box,
    );
  }

  test('🎯the cut\'s name stands where it stood; under it each 겸용 cut, a '
      'line each, smaller, from the name\'s left', () {
    final alone = inkOf(sheet());
    final linked = inkOf(sheet(linkedCuts: ['265', '266']));
    expect(alone.words, hasLength(1), reason: '⛔전제: the name alone');
    final name = alone.words.single;

    expect(linked.words, hasLength(3));
    final [stood, first, second] = linked.words;
    expect(stood, name, reason: 'the cut reads first, where it did');
    expect(first.top, greaterThanOrEqualTo(name.bottom - 0.5));
    expect(second.top, greaterThanOrEqualTo(first.bottom - 0.5));
    expect(first.height, lessThan(name.height));
    expect(second.height, first.height);
    expect(first.left, closeTo(name.left, 0.5));
    expect(second.left, closeTo(name.left, 0.5));
  });

  test('🎯a 「(」 binds the name and its 겸용 cuts: from the name\'s top to '
      'the last one\'s foot, just left of them', () {
    final linked = inkOf(sheet(linkedCuts: ['265', '266']));
    final [name, _, last] = linked.words;
    final bind = linked.paths.single.bounds;
    expect(bind.right, lessThanOrEqualTo(name.left));
    expect(bind.right, greaterThan(name.left - 6), reason: 'beside them');
    expect(bind.top, closeTo(name.top, 3));
    expect(bind.bottom, closeTo(last.bottom, 3));
    expect(bind.left, greaterThanOrEqualTo(linked.box.left));
  });

  test('no 겸용, no list and no 「(」', () {
    final alone = inkOf(sheet());
    expect(alone.words, hasLength(1));
    expect(alone.paths, isEmpty);
  });

  test('🎯type on the content stratum: the form prints none of it', () {
    final form = inkOf(
      sheet(linkedCuts: ['265', '266']),
      layers: const {SheetPaintLayer.paper, SheetPaintLayer.form},
    );
    final bare = inkOf(
      sheet(),
      layers: const {SheetPaintLayer.paper, SheetPaintLayer.form},
    );
    expect(form.words, bare.words);
    expect(form.paths, bare.paths);
  });

  test('a name wider than the box is set smaller to stand whole in it, '
      'from the same left', () {
    final linked = inkOf(
      sheet(linkedCuts: ['265-and-a-name-far-wider-than-the-box', '266']),
    );
    final value = TimesheetDocumentPainter.headerValueRect(linked.box);
    final [name, wide, narrow] = linked.words;
    expect(wide.right, lessThanOrEqualTo(value.right + 0.5));
    expect(wide.left, closeTo(name.left, 0.5));
    expect(wide.height, lessThan(narrow.height), reason: 'smaller, not cut');
    expect(narrow.top, greaterThanOrEqualTo(wide.bottom - 0.5));
  });

  testWidgets('🎯the list and its 「(」 wear the box label\'s light grey; '
      'the cut\'s name stays in ink', (tester) async {
    final document = sheet(linkedCuts: ['265', '266']);
    final layout = TimesheetDocumentLayout(document: document);
    final width = (layout.paperLeft + layout.paperWidth + 8).ceil();
    final height = layout.memoBandRect(0).bottom.ceil() + 8;

    /// The darkest any pixel of [rect] is, of what strata [layers] print.
    Future<int Function(Rect rect)> darkestOf(
      Set<SheetPaintLayer> layers,
    ) async {
      final bytes = (await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        TimesheetDocumentPainter(
          words: timesheetWordsIn(AppLanguage.en),
          face: const TextStyle(),
          document: document,
          layout: layout,
          layers: layers,
        ).paint(Canvas(recorder), Size(width.toDouble(), height.toDouble()));
        final image = await recorder.endRecording().toImage(width, height);
        return image.toByteData(format: ui.ImageByteFormat.rawRgba);
      }))!;
      return (Rect rect) {
        var least = 255;
        for (var y = rect.top.floor(); y < rect.bottom.ceil(); y += 1) {
          for (var x = rect.left.floor(); x < rect.right.ceil(); x += 1) {
            final at = (y * width + x) * 4;
            for (final channel in [at, at + 1, at + 2]) {
              least = math.min(least, bytes.getUint8(channel));
            }
          }
        }
        return least;
      };
    }

    // Each over the paper, which the strata lie on.
    final form = await darkestOf(const {
      SheetPaintLayer.paper,
      SheetPaintLayer.form,
    });
    final content = await darkestOf(const {
      SheetPaintLayer.paper,
      SheetPaintLayer.content,
    });
    final ink = inkOf(document);
    final [name, first, last] = ink.words;
    final box = ink.box;
    // The box's label, inside its edges.
    final grey = form(
      Rect.fromLTRB(box.left + 3, box.top + 3, box.right - 3, box.top + 20),
    );
    expect(grey, inInclusiveRange(120, 200), reason: '⛔전제: the label');

    final list = Rect.fromLTRB(first.left, first.top, first.right, last.bottom);
    expect(content(list), closeTo(grey, 24));
    expect(content(ink.paths.single.bounds.inflate(1)), closeTo(grey, 24));
    expect(content(name), lessThan(grey - 60), reason: 'in ink');
  });
}
