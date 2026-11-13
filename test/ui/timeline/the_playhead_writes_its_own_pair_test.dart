import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/ruler_marker.dart';
import 'package:anicel/src/ui/text/word_condensation.dart';
import 'package:anicel/src/ui/theme/ruler_marker_palette.dart';
import 'package:anicel/src/ui/timeline/ruler_marker_layer.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timeline/frame_ruler_view.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_header_row.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_ruler_painter.dart';
import 'package:anicel/src/ui/text/laid_out_glyph.dart';
import 'package:anicel/src/ui/timeline/timeline_glyph_cache.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_ruler_playhead_writing.dart';
import 'package:anicel/src/ui/widgets/tick_layer.dart';
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
    FrameRulerView rulerView = FrameRulerView.frames,
    int? pageFrames,
    int frames = 120,
  }) => TimelineRulerScale(
    axis: axis,
    frameStartIndex: 0,
    frameEndIndexExclusive: frames,
    playbackFrameCount: frames,
    leadingFrameSpacer: 0,
    crossExtent: 28,
    metrics: TimelineGridMetrics.defaults.copyWith(frameCellWidth: cell),
    colorScheme: scheme,
    face: const TextStyle(),
    numberType: axis == Axis.horizontal
        ? TimelineFrameRulerPainter.numberType
        : XSheetFrameRailPainter.numberType,
    secondsFontSize: axis == Axis.horizontal ? 9 : 8,
    rulerView: rulerView,
    pages: pageFrames == null ? null : TimelineRulerPages.every(pageFrames),
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
    test('is the number and the second at the playhead, bold, in the '
        'accent (F-239)', () {
      expect(
        scheme.primary,
        isNot(scheme.onSurfaceVariant),
        reason: 'fixture: the two inks differ',
      );
      final writing = rulerWriting(scaleOf(), 30);
      expect(writing.pair.map(textOf), ['31', '1']);
      for (final glyph in writing.pair) {
        expect(styleOf(glyph).fontWeight, FontWeight.w700);
        expect(styleOf(glyph).color, scheme.primary);
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
        rulerWriting(
          scaleOf(rulerView: FrameRulerView.secondsPlusFrames),
          30,
        ).pair.map(textOf),
        ['7', '1'],
      );
    });

    // F-539 「초 숫자도 같이 초기화」. ↩️It wrote the page it stood in, then
    // the second as the frames view does (I-81-Q4).
    test('I-81: under the page view it writes its number and its second in '
        'its page', () {
      final pages = scaleOf(rulerView: FrameRulerView.pages, pageFrames: 48);
      expect(rulerWriting(pages, 47).pair.map(textOf), ['48', '1']);
      expect(rulerWriting(pages, 50).pair.map(textOf), ['3', '0']);
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
        expect(styleOf(glyph).color, scheme.primary);
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
        reason: 'a mark keeps the marks\' ink; only the pair wears the accent',
      );
    });
  });

  group('the painter', () {
    TimelineGlyphPlacement at(String text, Offset offset) => (
      painter: laidOutGlyph(text, const TextStyle(fontSize: 10)),
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

    // 🚨I-22 ③ (09-27): the strip lays its paper a stretch at a time
    // ([TimelineRulerScale.paintPaperIn]); the uncovering laid it a CELL at a
    // time — at 0.16px hundreds of rects under one glyph on every playback
    // tick, each a sixth of a pixel wide.
    test('at the ten-minute floor the paper comes back the way the strip '
        'lays it — a stretch at a time', () {
      final scale = scaleOf(cell: 0.16, frames: 3000);
      // Halfway along the strip, on a frame it writes at — the strip's own
      // writing there is what the pair covers.
      final frame = 1500 ~/ scale.writingStep * scale.writingStep;
      final x = scale.cellRectFor(frame).left;
      final pair = at('P', Offset(x, 0));
      final covered = at('AAAAAA', Offset(x - 20, 5));
      List<TimelineGlyphPlacement> layout(
        TimelineRulerScale scale,
        int frameIndex, {
        required bool current,
      }) => [
        if (frameIndex == frame && current) pair,
        if (frameIndex == frame && !current) covered,
      ];

      expect(covered.rect.overlaps(pair.rect), isTrue, reason: 'fixture');
      expect(
        covered.rect.width / 0.16,
        greaterThan(100),
        reason: 'fixture: the glyph lies over a hundred cells and more',
      );

      final playhead = ValueNotifier<int?>(frame);
      addTearDown(playhead.dispose);
      final spy = _Spy();
      TimelineRulerPlayheadWritingPainter(
        scale: scale,
        playhead: playhead,
        layout: layout,
      ).paint(spy, const Size(480, 28));

      final clip = spy.log.indexWhere((entry) => entry.$1 == 'clip');
      final restore = spy.log.indexWhere((entry) => entry.$1 == 'restore');
      expect(clip, isNonNegative, reason: 'premise: a glyph stood down');
      expect(
        spy.log.sublist(clip + 1, restore).where((e) => e.$1 == 'paper'),
        hasLength(lessThan(5)),
        reason: 'one ground is one rect, as on the strip',
      );
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

  // 🗣️I-169-Q1 (유저 2026-11-13 took 「A · 룰러 안의 깃발」, whose own words
  // were 「초가 서는 칸에서는 초 글자가 깃발 위에 그대로 보인다」) and Q4:
  // 「마커랑 재생헤드쪽의 초/프레임 숫자 겹칠텐데 겹치는거 전혀문제없음.
  // 재생헤드 숫자 텍스트가 마커보다 위 층이면 됨」.
  group('over a marker\'s ribbon', () {
    List<TimelineGlyphPlacement> over(
      TimelineRulerScale scale,
      List<RulerMarker> markers, {
      List<Rect> pair = const [],
    }) => timelineRulerWritingOverMarkers(
      scale: scale,
      layout: scale.axis == Axis.horizontal
          ? TimelineFrameRulerPainter.glyphsAt
          : XSheetFrameRailPainter.glyphsAt,
      markers: markers,
      pair: pair,
    );

    RulerMarkerHooks hooksOf(
      RulerMarkers markers,
      ValueNotifier<TimelineDragPreview?> preview,
    ) => RulerMarkerHooks(
      holder: const RulerMarkerHolder.timeline(),
      markers: markers,
      dragPreview: preview,
      onBeginDrag: (_) => false,
      onUpdateDrag: (_) {},
      onEndDrag: () {},
      onCancelDrag: () {},
      onOpen: (_) {},
    );

    test('🚨the second a ribbon stands on is written again ON it — the '
        'strip\'s own glyph where the strip set it, in the markers\' ink', () {
      final scale = scaleOf();
      final strip = TimelineFrameRulerPainter.glyphsAt(
        scale,
        24,
        current: false,
      ).singleWhere((glyph) => textOf(glyph) == '1');
      final written = over(scale, const [RulerMarker(start: 24)]);

      expect(written.map(textOf), ['1']);
      expect(written.single.offset, strip.offset);
      expect(written.single.rect, strip.rect);
      expect(styleOf(written.single).color, rulerMarkerInk);
      expect(styleOf(strip).color, isNot(rulerMarkerInk), reason: 'premise');
      expect(
        styleOf(written.single).copyWith(color: styleOf(strip).color),
        styleOf(strip),
        reason: 'the ink alone is another',
      );
    });

    test('a ribbon that stands on none of the strip\'s writing has none '
        'written on it — the numbers\' line is not the ribbons\'', () {
      final scale = scaleOf();
      expect(
        TimelineFrameRulerPainter.glyphsAt(scale, 12, current: false),
        isNotEmpty,
        reason: 'premise: a number is written under it',
      );
      expect(over(scale, const [RulerMarker(start: 12, length: 2)]), isEmpty);
      expect(over(scale, const []), isEmpty);
    });

    test('a second that reaches out of its cell into a ribbon is written '
        'on that ribbon too, and no further', () {
      final scale = scaleOf(cell: 8);
      final second = rulerGlyph(scale, 24, '1');
      expect(
        second.right,
        greaterThan(scale.cellRectFor(25).left),
        reason: 'premise: it reaches into the next cell',
      );
      expect(
        second.right,
        lessThanOrEqualTo(scale.cellRectFor(26).left),
        reason: 'premise: and not into the one after',
      );
      expect(over(scale, const [RulerMarker(start: 25)]).map(textOf), ['1']);
      expect(over(scale, const [RulerMarker(start: 26)]), isEmpty);
    });

    test('what the playhead\'s pair covers stays down under it', () {
      final scale = scaleOf();
      final pair = [for (final mine in rulerWriting(scale, 24).pair) mine.rect];
      expect(over(scale, const [RulerMarker(start: 24)], pair: pair), isEmpty);
    });

    test('a ribbon off the painted window is not walked', () {
      final bucket = ValueNotifier<int>(0);
      addTearDown(bucket.dispose);
      final windowed = TimelineRulerScale(
        axis: Axis.horizontal,
        frameStartIndex: 0,
        frameEndIndexExclusive: 6000,
        playbackFrameCount: 6000,
        leadingFrameSpacer: 0,
        crossExtent: 28,
        metrics: TimelineGridMetrics.defaults.copyWith(frameCellWidth: 24),
        colorScheme: scheme,
        face: const TextStyle(),
        numberType: TimelineFrameRulerPainter.numberType,
        secondsFontSize: 9,
        windowBucket: bucket,
        viewportMainExtent: 480,
      );
      final window = windowed.visibleWindow();
      expect(window.endIndexExclusive, lessThan(4800), reason: 'premise');
      expect(
        over(windowed, const [RulerMarker(start: 4800)]),
        isEmpty,
        reason: 'frame 4800 is a second\'s, off the window',
      );
      expect(over(windowed, const [RulerMarker(start: 24)]).map(textOf), [
        '1',
      ]);

      // …and the painter shows none of a marker off its window: a tick
      // neither clips by that ribbon nor walks its neighbourhood.
      final preview = ValueNotifier<TimelineDragPreview?>(null);
      addTearDown(preview.dispose);
      final playhead = ValueNotifier<int?>(null);
      addTearDown(playhead.dispose);
      expect(
        TimelineRulerPlayheadWritingPainter(
          scale: windowed,
          playhead: playhead,
          layout: TimelineFrameRulerPainter.glyphsAt,
          markers: hooksOf(
            RulerMarkers.settled(const [
              RulerMarker(start: 24),
              RulerMarker(start: 4800),
            ]),
            preview,
          ),
        ).markersShown(),
        const [RulerMarker(start: 24)],
      );
    });

    test('🚨on the rail the frame\'s number stands across the whole '
        'breadth: it is written on the ribbon with the second', () {
      final scale = scaleOf(axis: Axis.vertical);
      final written = over(scale, const [RulerMarker(start: 24)]);
      expect(written.map(textOf).toSet(), {'1', '25'});
      for (final glyph in written) {
        expect(styleOf(glyph).color, rulerMarkerInk);
      }
    });

    test('the painter writes them inside the ribbons\' outline, and the '
        'pair after them — over everything', () {
      final scale = scaleOf();
      final playhead = ValueNotifier<int?>(3);
      addTearDown(playhead.dispose);
      final preview = ValueNotifier<TimelineDragPreview?>(null);
      addTearDown(preview.dispose);
      final spy = _Spy();
      TimelineRulerPlayheadWritingPainter(
        scale: scale,
        playhead: playhead,
        layout: TimelineFrameRulerPainter.glyphsAt,
        markers: hooksOf(
          RulerMarkers.settled(const [RulerMarker(start: 24)]),
          preview,
        ),
      ).paint(spy, const Size(2880, 28));

      final clip = spy.log.indexWhere((entry) => entry.$1 == 'clipPath');
      expect(
        spy.log[clip].$2,
        rulerMarkerOutline(
          Axis.horizontal,
          rulerMarkerRect(scale, const RulerMarker(start: 24)),
        ).getBounds(),
      );
      expect(spy.log.sublist(clip + 1, clip + 3), [
        ('text', rulerGlyph(scale, 24, '1').topLeft),
        ('restore', null),
      ]);
      expect(spy.log.sublist(clip + 3), [
        for (final mine in rulerWriting(scale, 3).pair) ('text', mine.offset),
      ]);
    });

    test('🚨no paper is laid back on a ribbon: the pair\'s uncovering is '
        'cut clear of it', () {
      final scale = scaleOf();
      final second = rulerGlyph(scale, 24, '1');
      final playhead = ValueNotifier<int?>(24);
      addTearDown(playhead.dispose);
      final preview = ValueNotifier<TimelineDragPreview?>(null);
      addTearDown(preview.dispose);
      expect(
        rulerWriting(scale, 24).covered,
        contains(second),
        reason: 'premise: the pair covers the strip\'s second',
      );

      List<(String, Object?)> painted(RulerMarkers markers) {
        final spy = _Spy();
        TimelineRulerPlayheadWritingPainter(
          scale: scale,
          playhead: playhead,
          layout: TimelineFrameRulerPainter.glyphsAt,
          markers: hooksOf(markers, preview),
        ).paint(spy, const Size(2880, 28));
        return spy.log;
      }

      Iterable<Object?> clips(List<(String, Object?)> log) =>
          log.where((entry) => entry.$1 == 'clip').map((entry) => entry.$2);

      expect(
        clips(painted(const RulerMarkers.none())),
        contains(second),
        reason: 'with no ribbon there, the paper comes back under the glyph',
      );
      final marked = painted(
        RulerMarkers.settled(const [RulerMarker(start: 24)]),
      );
      expect(clips(marked), isNot(contains(second)));
      Iterable<Object?> texts(List<(String, Object?)> log) =>
          log.where((entry) => entry.$1 == 'text').map((entry) => entry.$2);
      expect(
        texts(marked),
        texts(painted(const RulerMarkers.none())),
        reason: 'nothing more is written: what the pair covers stays down',
      );
    });

    test('the painter shows the markers a drag in flight shows, and is '
        'painted again for each of its steps', () {
      final markers = RulerMarkers.settled(const [RulerMarker(start: 24)]);
      final playhead = ValueNotifier<int?>(3);
      addTearDown(playhead.dispose);
      final preview = ValueNotifier<TimelineDragPreview?>(null);
      addTearDown(preview.dispose);
      final painter = TimelineRulerPlayheadWritingPainter(
        scale: scaleOf(),
        playhead: playhead,
        layout: TimelineFrameRulerPainter.glyphsAt,
        markers: hooksOf(markers, preview),
      );
      var repaints = 0;
      void heard() => repaints += 1;
      painter.addListener(heard);
      addTearDown(() => painter.removeListener(heard));

      expect(painter.markersShown(), markers.inOrder);
      expect(painter.writtenOverMarkers().map(textOf), ['1']);
      preview.value = RulerMarkerDragPreview(
        holder: const RulerMarkerHolder.timeline(),
        markers: markers.moved(0, 5),
      );
      expect(repaints, 1);
      expect(painter.markersShown(), markers.moved(0, 5).inOrder);
      expect(painter.writtenOverMarkers(), isEmpty);

      // Another ruler's drag is not this ruler's.
      preview.value = RulerMarkerDragPreview(
        holder: const RulerMarkerHolder.cut(CutId('other')),
        markers: markers.moved(0, 9),
      );
      expect(painter.markersShown(), markers.inOrder);
    });
  });

  testWidgets('a ruler with markers and no playhead still mounts the '
      'writing: it is where the strip\'s own shows over a ribbon', (
    tester,
  ) async {
    final preview = ValueNotifier<TimelineDragPreview?>(null);
    addTearDown(preview.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelineFrameHeaderRow(
            frameStartIndex: 0,
            frameEndIndexExclusive: 30,
            playbackFrameCount: 30,
            leadingFrameSpacerWidth: 0,
            trailingFrameSpacerWidth: 0,
            metrics: TimelineGridMetrics.defaults,
            onSelectFrame: (_) {},
            markers: RulerMarkerHooks(
              holder: const RulerMarkerHolder.timeline(),
              markers: RulerMarkers.settled(const [RulerMarker(start: 24)]),
              dragPreview: preview,
              onBeginDrag: (_) => false,
              onUpdateDrag: (_) {},
              onEndDrag: () {},
              onCancelDrag: () {},
              onOpen: (_) {},
            ),
          ),
        ),
      ),
    );
    final painter =
        tester
                .widget<CustomPaint>(
                  find.byKey(
                    const ValueKey<String>('timeline-ruler-playhead-writing'),
                  ),
                )
                .painter!
            as TimelineRulerPlayheadWritingPainter;
    expect(painter.writtenFrame(), isNull);
    expect(
      [for (final glyph in painter.writtenOverMarkers()) textOf(glyph)],
      ['1'],
    );
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
    // Its own layer: the first boundary above the writing is its tick
    // layer's — the first one down from the tick layer, whichever render
    // object it is — under the strip's.
    var boundary = tester.renderObject(writing).parent;
    while (boundary != null && !boundary.isRepaintBoundary) {
      boundary = boundary.parent;
    }
    RenderObject? tickBoundary = tester.renderObject(
      find.ancestor(of: writing, matching: find.byType(TickLayer)),
    );
    while (tickBoundary != null && !tickBoundary.isRepaintBoundary) {
      RenderObject? first;
      tickBoundary.visitChildren((child) => first ??= child);
      tickBoundary = first;
    }
    expect(boundary, isNotNull, reason: '⛔premise: a boundary above it');
    expect(
      boundary,
      same(tickBoundary),
      reason: 'its repaints never re-record the strip',
    );

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
  void clipPath(Path path, {bool doAntiAlias = true}) =>
      log.add(('clipPath', path.getBounds()));

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
