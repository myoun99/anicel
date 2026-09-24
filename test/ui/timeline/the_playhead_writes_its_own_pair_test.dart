import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/text/word_condensation.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_header_row.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_ruler_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_glyph_cache.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_ruler_playhead_writing.dart';
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart'
    show XSheetFrameRailPainter;

/// 🗣️I-16 (유저 2026-09-11): 「타임라인 플레이헤드쪽에 현재 코마랑 초수 텍스트
/// 항상 표시하도록. 현재 인덱스에만. 볼드체로. 초수는 초수 열에서 뜨고 코마는
/// 코마 열에서 뜨도록 … 겹쳐지는부분있으면 안겹쳐지도록 기존에 있던 텍스트
/// 사라지도록. 현재 인덱스 텍스트를 우선으로 표시」.
///
/// The ruler and the X-sheet rail share one scale, and the pair is written
/// by one function over either strip's own layout — so these pins read the
/// pair and what it covers as VALUES, and the painter's order through a
/// canvas spy.
void main() {
  // Seeded, so the marks' ink and the pair's ink are two colours (the
  // bare light scheme answers onSurfaceVariant with onSurface).
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF3F6E8C));

  TimelineRulerScale scaleOf({
    Axis axis = Axis.horizontal,
    double cell = 24,
    bool showSeconds = false,
  }) => TimelineRulerScale(
    axis: axis,
    frameStartIndex: 0,
    frameEndIndexExclusive: 120,
    currentFrameIndex: -1,
    playbackFrameCount: 120,
    leadingFrameSpacer: 0,
    crossExtent: 28,
    metrics: TimelineGridMetrics.defaults.copyWith(frameCellWidth: cell),
    colorScheme: scheme,
    face: const TextStyle(),
    numberType: axis == Axis.horizontal
        ? TimelineFrameRulerPainter.numberType
        : XSheetFrameRailPainter.numberType,
    showSeconds: showSeconds,
  );

  String textOf(TimelineGlyphPlacement glyph) => glyph.painter.plainText;
  TextStyle styleOf(TimelineGlyphPlacement glyph) =>
      glyph.painter.text!.style!;

  ({
    List<TimelineGlyphPlacement> pair,
    List<Rect> covered,
    List<TimelineGlyphPlacement> standing,
  })
  rulerWriting(TimelineRulerScale scale, int frame) =>
      timelineRulerPlayheadWriting(
        scale: scale,
        frame: frame,
        layout: TimelineFrameRulerPainter.glyphsAt,
      );

  /// The rect of the strip's OWN glyph [text] at [frame].
  Rect rulerGlyph(TimelineRulerScale scale, int frame, String text) =>
      TimelineFrameRulerPainter.glyphsAt(
        scale,
        frame,
        current: false,
      ).singleWhere((glyph) => textOf(glyph) == text).rect;


  /// A horizontal scale wide enough to write EVERY frame's number — ASKED
  /// for, never assumed.
  ///
  /// 🚨I-22 (2026-09-16): the cadence used to be a threshold on the cell
  /// alone (every frame from 20px), so a fixture could name a cell and know
  /// the answer. It MEASURES the numbers now, and the test font's digits are
  /// square — '120' comes out 33px where the app's face writes about half
  /// that — so the cell at which every frame still fits is the FACE's
  /// answer, not a constant. A case that needs neighbouring numbers asks for
  /// a cell that has them.
  TimelineRulerScale everyFrameScale() {
    for (final cell in [24.0, 32.0, 48.0, 64.0, 96.0]) {
      final scale = scaleOf(cell: cell);
      if (scale.labelEveryFrames == 1) {
        return scale;
      }
    }
    fail('fixture: no cell in the zoom range writes every frame');
  }
  group('the pair', () {
    test('is the number and the second at the playhead, bold on the full '
        'ink', () {
      expect(
        scheme.onSurface,
        isNot(scheme.onSurfaceVariant),
        reason: 'fixture: the two inks differ',
      );
      final writing = rulerWriting(scaleOf(), 30);
      expect(writing.pair.map(textOf), ['31', '1']);
      for (final glyph in writing.pair) {
        expect(styleOf(glyph).fontWeight, FontWeight.w700);
        expect(styleOf(glyph).color, scheme.onSurface);
      }
    });

    test('is written whatever the cadence and the boundary say', () {
      final scale = scaleOf(cell: 8);
      expect(scale.labelEveryFrames, 6, reason: 'fixture');
      expect(
        TimelineFrameRulerPainter.glyphsAt(scale, 8, current: false),
        isEmpty,
        reason: 'the strip writes nothing at frame 9 of a 6f cadence, off '
            'any second',
      );
      expect(rulerWriting(scale, 8).pair.map(textOf), ['9', '0']);
    });

    test('counts the second from 0 like the marks, and the number the way '
        'the seconds toggle does', () {
      expect(rulerWriting(scaleOf(), 23).pair.map(textOf), ['24', '0']);
      expect(rulerWriting(scaleOf(), 24).pair.map(textOf), ['25', '1']);
      expect(
        rulerWriting(scaleOf(showSeconds: true), 30).pair.map(textOf),
        ['7', '1'],
      );
    });

    test('the rail writes the pair on a frame its cadence skips', () {
      // ↩️cell 8 → 4 (2026-09-16). The rail measures a number's HEIGHT and
      // the type shrinks with the row, so an 8px row holds its own number
      // and writes every one — a paper timesheet numbers every row. The
      // thinning this case is about starts below that.
      final scale = scaleOf(axis: Axis.vertical, cell: 4);
      expect(8 % scale.labelEveryFrames, isNot(0), reason: 'fixture');
      expect(
        XSheetFrameRailPainter.glyphsAt(scale, 8, current: false),
        isEmpty,
        reason: 'fixture: row 9 is off the rail\'s cadence and any second',
      );
      final writing = timelineRulerPlayheadWriting(
        scale: scale,
        frame: 8,
        layout: XSheetFrameRailPainter.glyphsAt,
      );
      expect(writing.pair.map(textOf), ['0', '9']);
    });

    test('the X-sheet rail writes the same pair, in its own places', () {
      final scale = scaleOf(axis: Axis.vertical);
      final writing = timelineRulerPlayheadWriting(
        scale: scale,
        frame: 30,
        layout: XSheetFrameRailPainter.glyphsAt,
      );
      expect(writing.pair.map(textOf), ['1', '31']);
      for (final glyph in writing.pair) {
        expect(styleOf(glyph).fontWeight, FontWeight.w700);
        expect(styleOf(glyph).color, scheme.onSurface);
      }
      final own = XSheetFrameRailPainter.glyphsAt(scale, 30, current: false);
      expect(
        writing.covered,
        contains(own.singleWhere((glyph) => textOf(glyph) == '31').rect),
      );
    });
  });

  group('what the pair stands on stands down, whole', () {
    test("the cell's own number goes; its neighbours stay", () {
      final scale = everyFrameScale();
      final writing = rulerWriting(scale, 30);
      expect(writing.covered, contains(rulerGlyph(scale, 30, '31')));
      expect(writing.covered, isNot(contains(rulerGlyph(scale, 29, '30'))));
      expect(writing.covered, isNot(contains(rulerGlyph(scale, 31, '32'))));
    });

    test('a wide neighbour that runs into the pair goes whole; a far one '
        'stays standing', () {
      final scale = scaleOf(cell: 8);
      final writing = rulerWriting(scale, 7);
      final near = rulerGlyph(scale, 6, '7');
      expect(
        near.overlaps(writing.pair.first.rect),
        isTrue,
        reason: 'fixture: the 6f label runs past its own cell',
      );
      expect(writing.covered, contains(near));
      final far = rulerGlyph(scale, 12, '13');
      expect(writing.covered, isNot(contains(far)));
      expect(writing.standing.map((glyph) => glyph.rect), contains(far));
    });

    test('on the seconds line too: the boundary mark the pair touches '
        'goes', () {
      final scale = scaleOf(cell: 8);
      final writing = rulerWriting(scale, 25);
      final mark = rulerGlyph(scale, 24, '1');
      expect(
        mark.overlaps(writing.pair.last.rect),
        isTrue,
        reason: 'fixture: the mark one frame back reaches the pair',
      );
      expect(writing.covered, contains(mark));
      final own = TimelineFrameRulerPainter.glyphsAt(scale, 24, current: false)
          .singleWhere((glyph) => textOf(glyph) == '1');
      expect(
        styleOf(own).color,
        scheme.onSurfaceVariant,
        reason: 'a mark keeps the marks\' ink; only the pair wears the full',
      );
    });
  });

  group('the painter', () {
    TimelineGlyphPlacement at(String text, Offset offset) => (
      painter: timelineGlyphPainter(text, const TextStyle(fontSize: 10)),
      offset: offset,
      fit: wordFitsAsItIs,
    );

    test('uncovers under a clip — paper first, then the standing writing '
        'that reaches in — and writes the pair last', () {
      final pair = at('P', const Offset(100, 0));
      final covered = at('AAA', const Offset(95, 5));
      final reaching = at('C', const Offset(120, 12));
      final away = at('D', const Offset(400, 12));
      List<TimelineGlyphPlacement> layout(
        TimelineRulerScale scale,
        int frameIndex, {
        required bool current,
      }) {
        if (current) {
          return frameIndex == 10 ? [pair] : const [];
        }
        return switch (frameIndex) {
          9 => [covered],
          11 => [reaching],
          20 => [away],
          _ => const [],
        };
      }

      expect(covered.rect.overlaps(pair.rect), isTrue, reason: 'fixture');
      expect(reaching.rect.overlaps(pair.rect), isFalse, reason: 'fixture');
      expect(reaching.rect.overlaps(covered.rect), isTrue, reason: 'fixture');

      final playhead = ValueNotifier<int?>(10);
      addTearDown(playhead.dispose);
      final spy = _Spy();
      TimelineRulerPlayheadWritingPainter(
        scale: scaleOf(),
        playhead: playhead,
        layout: layout,
      ).paint(spy, const Size(2880, 28));

      final clip = spy.log.indexWhere((entry) => entry.$1 == 'clip');
      final restore = spy.log.indexWhere((entry) => entry.$1 == 'restore');
      expect(spy.log.where((entry) => entry.$1 == 'clip').map((e) => e.$2), [
        covered.rect,
      ]);
      final inside = spy.log.sublist(clip + 1, restore);
      expect(inside.first.$1, 'paper', reason: 'the paper comes back first');
      expect(inside.where((entry) => entry.$1 == 'text').map((e) => e.$2), [
        reaching.offset,
      ], reason: 'the standing glyph that reaches in is rewritten whole');
      expect(spy.log.sublist(restore + 1), [('text', pair.offset)]);
    });

    test('writes nothing without a playhead, or with one off the window', () {
      final playhead = ValueNotifier<int?>(null);
      addTearDown(playhead.dispose);
      final painter = TimelineRulerPlayheadWritingPainter(
        scale: scaleOf(),
        playhead: playhead,
        layout: TimelineFrameRulerPainter.glyphsAt,
      );
      expect(painter.writtenFrame(), isNull);
      playhead.value = 500;
      expect(painter.writtenFrame(), isNull);
      final spy = _Spy();
      painter.paint(spy, const Size(2880, 28));
      expect(spy.log, isEmpty);
      playhead.value = 30;
      expect(painter.writtenFrame(), 30);
      playhead.value = 120;
      expect(painter.writtenFrame(), isNull, reason: 'the window ends at 120');
      playhead.value = 119;
      expect(painter.writtenFrame(), 119);
    });

    test('repaints when the playhead moves', () {
      final playhead = ValueNotifier<int?>(3);
      addTearDown(playhead.dispose);
      final painter = TimelineRulerPlayheadWritingPainter(
        scale: scaleOf(),
        playhead: playhead,
        layout: TimelineFrameRulerPainter.glyphsAt,
      );
      var repaints = 0;
      void count() => repaints += 1;
      painter.addListener(count);
      addTearDown(() => painter.removeListener(count));
      playhead.value = 4;
      expect(repaints, 1);
    });
  });

  group('the strips write their own writing, never the pair', () {
    List<Object?> textsPainted(CustomPainter painter, Size size) {
      final spy = _Spy();
      painter.paint(spy, size);
      return [
        for (final entry in spy.log)
          if (entry.$1 == 'text') entry.$2,
      ];
    }

    test('the ruler', () {
      final scale = scaleOf(cell: 8);
      final own = [
        for (var frame = 0; frame < 120; frame += 1)
          for (final glyph in TimelineFrameRulerPainter.glyphsAt(
            scale,
            frame,
            current: false,
          ))
            glyph.offset,
      ];
      expect(own, isNotEmpty);
      expect(
        textsPainted(
          TimelineFrameRulerPainter(scale: scale),
          const Size(960, 28),
        ),
        own,
      );
    });

    test('the rail', () {
      final scale = scaleOf(axis: Axis.vertical);
      final own = [
        for (var frame = 0; frame < 120; frame += 1)
          for (final glyph in XSheetFrameRailPainter.glyphsAt(
            scale,
            frame,
            current: false,
          ))
            glyph.offset,
      ];
      expect(own, isNotEmpty);
      expect(
        textsPainted(
          XSheetFrameRailPainter(scale: scale),
          const Size(28, 2880),
        ),
        own,
      );
    });

    test('where the ruler writes (UI-R10 #27): the number centred in its '
        'cell while every cell is labelled, left-anchored on a cadence; the '
        'second two in and one down from the corner — and the pair writes '
        'in those same places', () {
      final every = scaleOf();
      final number = rulerGlyph(every, 30, '31');
      expect(number.center.dx, every.cellRectFor(30).center.dx);
      final cadence = scaleOf(cell: 8);
      expect(
        rulerGlyph(cadence, 6, '7').left,
        cadence.cellRectFor(6).left + 2,
      );
      final mark = rulerGlyph(cadence, 24, '1');
      expect(mark.topLeft, cadence.cellRectFor(24).topLeft + const Offset(2, 1));
      final pair = rulerWriting(every, 30).pair;
      expect(pair.first.rect, number);
    });
  });

  testWidgets('the header row writes the pair on a layer of its own that '
      'follows the playhead; the strip under it is handed none', (
    tester,
  ) async {
    final playhead = ValueNotifier<int?>(3);
    addTearDown(playhead.dispose);
    Widget row({ValueNotifier<int?>? playhead}) => MaterialApp(
      home: Scaffold(
        body: TimelineFrameHeaderRow(
          frameStartIndex: 0,
          frameEndIndexExclusive: 30,
          currentFrameIndex: -1,
          playbackFrameCount: 30,
          leadingFrameSpacerWidth: 0,
          trailingFrameSpacerWidth: 0,
          metrics: TimelineGridMetrics.defaults,
          onSelectFrame: (_) {},
          playhead: playhead,
        ),
      ),
    );
    const writingKey = ValueKey<String>('timeline-ruler-playhead-writing');
    final writing = find.byKey(writingKey);

    await tester.pumpWidget(row(playhead: playhead));
    TimelineRulerPlayheadWritingPainter painter() =>
        tester.widget<CustomPaint>(writing).painter!
            as TimelineRulerPlayheadWritingPainter;
    expect(painter().writtenFrame(), 3);
    playhead.value = 7;
    await tester.pump();
    expect(painter().writtenFrame(), 7);
    expect(
      tester.renderObject(writing).parent,
      isA<RenderRepaintBoundary>(),
      reason: 'its repaints never re-record the strip',
    );
    final strip =
        tester
                .widget<CustomPaint>(
                  find.byKey(
                    const ValueKey<String>('timeline-frame-ruler-paint'),
                  ),
                )
                .painter!
            as TimelineFrameRulerPainter;
    expect(strip.scale.currentFrameIndex, -1);

    await tester.pumpWidget(row());
    expect(writing, findsNothing, reason: 'no playhead, no writing');
  });
}

/// The calls the playhead's writing makes, in order.
class _Spy implements Canvas {
  final log = <(String, Object?)>[];

  // A narrowed number is drawn at the origin of a moved, scaled canvas, so
  // where a paragraph lands is its offset through the canvas's transform.
  final _saved = <(Offset, double, double)>[];
  var _origin = Offset.zero;
  var _scaleX = 1.0;
  var _scaleY = 1.0;

  @override
  void save() {
    _saved.add((_origin, _scaleX, _scaleY));
    log.add(('save', null));
  }

  @override
  void restore() {
    final (origin, scaleX, scaleY) = _saved.removeLast();
    _origin = origin;
    _scaleX = scaleX;
    _scaleY = scaleY;
    log.add(('restore', null));
  }

  @override
  void translate(double dx, double dy) =>
      _origin += Offset(dx * _scaleX, dy * _scaleY);

  @override
  void scale(double sx, [double? sy]) {
    _scaleX *= sx;
    _scaleY *= sy ?? sx;
  }

  @override
  void clipRect(
    Rect rect, {
    ui.ClipOp clipOp = ui.ClipOp.intersect,
    bool doAntiAlias = true,
  }) => log.add(('clip', rect));

  @override
  void drawRect(Rect rect, Paint paint) => log.add(('paper', rect));

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => log.add(('line', p1));

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) => log.add((
    'text',
    _origin + Offset(offset.dx * _scaleX, offset.dy * _scaleY),
  ));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
