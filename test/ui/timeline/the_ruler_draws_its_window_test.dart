import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart';
import 'package:anicel/src/ui/timeline/frame_ruler_view.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_ruler_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_ruler_cursor_overlay.dart';
import 'package:anicel/src/ui/timeline/timeline_ruler_playhead_writing.dart';
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart'
    show XSheetFrameRailPainter;

/// A canvas that keeps where each line and rect handed to it lands — the
/// translations it was handed applied.
class _LandingSpy implements Canvas {
  final List<Offset> _saved = [];
  Offset _at = Offset.zero;
  final List<(Offset, Offset)> lines = [];
  final List<Rect> rects = [];

  @override
  void save() => _saved.add(_at);

  @override
  void saveLayer(Rect? bounds, Paint paint) => _saved.add(_at);

  @override
  void restore() => _at = _saved.removeLast();

  @override
  void translate(double dx, double dy) => _at += Offset(dx, dy);

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) =>
      lines.add((p1 + _at, p2 + _at));

  @override
  void drawRect(Rect rect, Paint paint) => rects.add(rect.shift(_at));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 🔬Card conte-sideways-scroll-build-spikes (11-16): A RULER STANDS IN
/// ITS ROWS' WINDOW BOX (Q8 「타임라인 · X시트 · 콘티 한 법」) — the strip,
/// the X-sheet's rail, the playhead's writing on them and the cursor's
/// strip. Its canvas is the window: it draws its bucket's window whole, not
/// cut where the axis ends, lands every frame where the whole strip has it
/// moved back by the window, and the axis' end a drag past it grows
/// repaints none of it — but for what the strip measures off that end.
/// ↩️As long as the axis, the ruler was laid out and painted again at every
/// screen a drag past the end grew: with the grid sheet, about 70% of such
/// a frame (main PC, profile).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const view = 600.0;
  const across = 28.0;
  const frames = 1000;
  final cell = TimelineGridMetrics.defaults.frameCellWidth;

  TimelineFrameGeometryHandle boxOf(
    int frames,
    int bucket, {
    double? cellExtent,
  }) {
    final handle = TimelineFrameGeometryHandle(
      TimelineFrameGeometry(
        frameCellExtent: cellExtent ?? cell,
        frameStartIndex: 0,
        frameEndIndexExclusive: frames,
        viewExtentPx: view,
      ).windowedAt(bucket),
    );
    addTearDown(handle.dispose);
    return handle;
  }

  ValueNotifier<int> bucketAt(int bucket) {
    final notifier = ValueNotifier<int>(bucket);
    addTearDown(notifier.dispose);
    return notifier;
  }

  TimelineRulerScale scaleOf({
    required int frames,
    required ValueNotifier<int> bucket,
    TimelineFrameGeometryHandle? box,
    Axis axis = Axis.horizontal,
    double? cellExtent,
    FrameRulerView rulerView = FrameRulerView.frames,
    TimelineRulerPages? pages,
  }) => TimelineRulerScale(
    axis: axis,
    frameStartIndex: 0,
    frameEndIndexExclusive: frames,
    playbackFrameCount: 120,
    leadingFrameSpacer: 0,
    crossExtent: across,
    metrics: TimelineGridMetrics.defaults.copyWith(
      frameCellWidth: cellExtent ?? cell,
    ),
    colorScheme: const ColorScheme.light(),
    face: const TextStyle(),
    numberType: axis == Axis.horizontal
        ? TimelineFrameRulerPainter.numberType
        : XSheetFrameRailPainter.numberType,
    secondsFontSize: axis == Axis.horizontal ? 9 : 8,
    rulerView: rulerView,
    pages: pages,
    windowBucket: bucket,
    viewportMainExtent: view,
    geometry: box,
  );

  CustomPainter stripOf(TimelineRulerScale scale) =>
      scale.axis == Axis.horizontal
      ? TimelineFrameRulerPainter(scale: scale)
      : XSheetFrameRailPainter(scale: scale);

  /// A window down the axis — off its start, short of its end.
  TimelineFrameGeometryHandle midway() {
    final box = boxOf(frames, 7);
    final window = box.value;
    const inside = '⛔premise: a window inside the axis';
    expect(window.windowOriginPx, greaterThan(0), reason: inside);
    expect(
      window.windowOriginPx + window.windowExtentPx,
      lessThan(frames * cell),
      reason: inside,
    );
    return box;
  }

  /// Where [spy]'s lines across the frames stand along them.
  List<double> boundariesOf(_LandingSpy spy, Axis axis) => [
    for (final (from, to) in spy.lines)
      if (partAlong(axis, from) == partAlong(axis, to)) partAlong(axis, from),
  ];

  group('the strip and the rail', () {
    test('a window box is compared by identity — the strip hears that one '
        'handle', () {
      final bucket = bucketAt(7);
      final box = midway();
      final twin = boxOf(frames, 7);
      expect(twin.value, box.value, reason: '⛔premise: alike');
      final laid = scaleOf(frames: frames, bucket: bucket, box: box);
      expect(laid, scaleOf(frames: frames, bucket: bucket, box: box));
      expect(laid, isNot(scaleOf(frames: frames, bucket: bucket, box: twin)));
      expect(laid, isNot(scaleOf(frames: frames, bucket: bucket)));
    });

    test('draw their bucket\'s window whole, not cut where the axis '
        'ends', () {
      final bucket = bucketAt(0);
      final box = boxOf(40, 0);
      expect(
        scaleOf(frames: 40, bucket: bucket).visibleWindow().endIndexExclusive,
        40,
        reason: '⛔premise: as long as its axis, a strip is cut at its end',
      );
      final window = scaleOf(
        frames: 40,
        bucket: bucket,
        box: box,
      ).visibleWindow();
      expect(window.endIndexExclusive, greaterThan(40));
      expect(window, box.value.rowDrawnFrames(bucket));
    });

    for (final axis in Axis.values) {
      test('land every frame where the whole strip has it, moved back by '
          'their window — $axis', () {
        final bucket = bucketAt(7);
        final box = midway();
        final origin = box.value.windowOriginPx;
        final windowed = _LandingSpy();
        stripOf(scaleOf(frames: frames, bucket: bucket, box: box, axis: axis))
            .paint(
              windowed,
              sizeAlong(axis, along: box.value.windowExtentPx, across: across),
            );
        final whole = _LandingSpy();
        stripOf(scaleOf(frames: frames, bucket: bucket, axis: axis)).paint(
          whole,
          sizeAlong(axis, along: frames * cell, across: across),
        );
        final back = offsetAlong(axis, along: -origin, across: 0);
        expect(
          boundariesOf(whole, axis),
          isNotEmpty,
          reason: '⛔premise: the strip rules its window',
        );
        expect(boundariesOf(windowed, axis), [
          for (final at in boundariesOf(whole, axis)) at - origin,
        ]);
        expect(whole.rects, isNotEmpty, reason: '⛔premise: paper');
        expect(windowed.rects, [
          for (final rect in whole.rects) rect.shift(back),
        ]);
      });

      test('stand their semantics where they draw — $axis', () {
        final bucket = bucketAt(7);
        final box = midway();
        final back = offsetAlong(
          axis,
          along: -box.value.windowOriginPx,
          across: 0,
        );
        final whole = [
          for (final node in scaleOf(
            frames: frames,
            bucket: bucket,
            axis: axis,
          ).windowSemantics())
            node.rect.shift(back),
        ];
        expect(whole, isNotEmpty, reason: '⛔premise: nodes');
        expect([
          for (final node in scaleOf(
            frames: frames,
            bucket: bucket,
            box: box,
            axis: axis,
          ).windowSemantics())
            node.rect,
        ], whole);
      });
    }

    // The same strip at the axis' end, in its box and as long as its axis:
    // drawn past the end, it names what the long one named and no more.
    test('name no frame past the axis\' end, though they draw on there', () {
      final bucket = bucketAt(0);
      final box = boxOf(40, 0);
      final laid = scaleOf(frames: 40, bucket: bucket, box: box);
      expect(
        laid.visibleWindow().endIndexExclusive,
        greaterThan(40),
        reason: '⛔premise: drawn past the end',
      );
      expect(
        [
          for (var f = 40; f < laid.visibleWindow().endIndexExclusive; f++)
            if (laid.modelAt(f).label.isNotEmpty) f,
        ],
        isNotEmpty,
        reason: '⛔premise: the room past the end is written on',
      );
      List<(String?, Rect)> named(TimelineRulerScale scale) => [
        for (final node in scale.windowSemantics())
          (node.properties.label, node.rect),
      ];
      final long = named(scaleOf(frames: 40, bucket: bucket));
      expect(long, isNotEmpty, reason: '⛔premise: nodes');
      expect(named(laid), long);
    });

    test('the playhead\'s writing lays its paper back where the whole strip '
        'has it, moved back by the window', () {
      final bucket = bucketAt(7);
      final box = midway();
      final origin = box.value.windowOriginPx;
      final playhead = ValueNotifier<int?>(
        box.value.rowDrawnFrames(bucket).startIndex + 24,
      );
      addTearDown(playhead.dispose);
      _LandingSpy written(TimelineFrameGeometryHandle? box, double along) {
        final spy = _LandingSpy();
        TimelineRulerPlayheadWritingPainter(
          scale: scaleOf(frames: frames, bucket: bucket, box: box),
          playhead: playhead,
          layout: TimelineFrameRulerPainter.glyphsAt,
        ).paint(spy, Size(along, across));
        return spy;
      }

      final whole = written(null, frames * cell);
      final windowed = written(box, box.value.windowExtentPx);
      expect(
        whole.rects,
        isNotEmpty,
        reason: '⛔premise: the pair covers the strip\'s own writing',
      );
      expect(windowed.rects, [
        for (final rect in whole.rects) rect.shift(Offset(-origin, 0)),
      ]);
    });

    test('the axis growing in their window repaints none of them, nor the '
        'playhead\'s writing on them', () {
      final bucket = bucketAt(7);
      final box = midway();
      final playhead = ValueNotifier<int?>(200);
      addTearDown(playhead.dispose);
      for (final axis in Axis.values) {
        TimelineRulerScale at(int frames, {TimelineFrameGeometryHandle? box}) =>
            scaleOf(frames: frames, bucket: bucket, box: box, axis: axis);
        expect(
          at(1100).labelEveryFrames,
          at(frames).labelEveryFrames,
          reason: '⛔premise: a growth that turns no cadence',
        );
        expect(
          stripOf(at(1100)).shouldRepaint(stripOf(at(frames))),
          isTrue,
          reason: '⛔premise: as long as its axis, a strip repaints',
        );
        expect(
          stripOf(at(1100, box: box)).shouldRepaint(
            stripOf(at(frames, box: box)),
          ),
          isFalse,
          reason: 'the axis growing repainted the strip — $axis',
        );
        TimelineRulerPlayheadWritingPainter writing(TimelineRulerScale on) =>
            TimelineRulerPlayheadWritingPainter(
              scale: on,
              playhead: playhead,
              layout: TimelineFrameRulerPainter.glyphsAt,
            );
        expect(
          writing(at(1100, box: box)).shouldRepaint(
            writing(at(frames, box: box)),
          ),
          isFalse,
          reason: 'the axis growing repainted the writing — $axis',
        );
      }
    });

    test('where the numbers\' cadence turns with the axis\' end, the strip '
        'repaints', () {
      final bucket = bucketAt(0);
      // A zoom at which a fourth digit thins the numbers out.
      double? turning;
      for (var width = 6.0; width <= 40 && turning == null; width += 0.25) {
        if (scaleOf(frames: 999, bucket: bucket, cellExtent: width)
                .labelEveryFrames !=
            scaleOf(frames: 1000, bucket: bucket, cellExtent: width)
                .labelEveryFrames) {
          turning = width;
        }
      }
      expect(turning, isNotNull, reason: '⛔premise: a zoom it turns at');
      final box = boxOf(999, 0, cellExtent: turning);
      TimelineRulerScale at(int frames) => scaleOf(
        frames: frames,
        bucket: bucket,
        box: box,
        cellExtent: turning,
      );
      expect(
        TimelineFrameRulerPainter(
          scale: at(1000),
        ).shouldRepaint(TimelineFrameRulerPainter(scale: at(999))),
        isTrue,
      );
    });

    test('where a page begins in what the axis grew, the page view '
        'repaints', () {
      final bucket = bucketAt(7);
      final box = midway();
      TimelineRulerScale at(int frames) => scaleOf(
        frames: frames,
        bucket: bucket,
        box: box,
        rulerView: FrameRulerView.pages,
        pages: const TimelineRulerPages.every(24),
      );
      expect(
        TimelineFrameRulerPainter(
          scale: at(1100),
        ).shouldRepaint(TimelineFrameRulerPainter(scale: at(frames))),
        isTrue,
      );
    });
  });

  group('the cursor\'s strip', () {
    List<ReadyRun> ready(int start, int end) => [
      (startIndex: start, endIndexExclusive: end, unreadable: false),
    ];

    TimelineRulerCursorOverlayPainter overlayOf({
      required int frames,
      required ValueNotifier<int> bucket,
      TimelineFrameGeometryHandle? box,
      ValueNotifier<int?>? playhead,
    }) => TimelineRulerCursorOverlayPainter(
      playhead: playhead,
      repaintSignal: null,
      windowBucket: bucket,
      viewportMainExtent: view,
      renderedFrames: frames,
      cellWidth: cell,
      readyRunsIn: ready,
      geometry: box,
    );

    test('draws its window whole, not cut where the axis ends', () {
      final bucket = bucketAt(0);
      expect(
        overlayOf(frames: 40, bucket: bucket).readyRuns().last,
        (startIndex: 0, endIndexExclusive: 40, unreadable: false),
        reason: '⛔premise: as long as its axis, the bar is cut at its end',
      );
      final box = boxOf(40, 0);
      expect(
        overlayOf(frames: 40, bucket: bucket, box: box).readyRuns().last,
        (
          startIndex: 0,
          endIndexExclusive: box.value.rowDrawnFrames(bucket).endIndexExclusive,
          unreadable: false,
        ),
      );
    });

    test('lands its tint and its bar where the whole strip has them, moved '
        'back by its window', () {
      final bucket = bucketAt(7);
      final box = midway();
      final origin = box.value.windowOriginPx;
      final playhead = ValueNotifier<int?>(
        box.value.rowDrawnFrames(bucket).startIndex + 5,
      );
      addTearDown(playhead.dispose);
      final windowed = _LandingSpy();
      overlayOf(
        frames: frames,
        bucket: bucket,
        box: box,
        playhead: playhead,
      ).paint(windowed, Size(box.value.windowExtentPx, across));
      final whole = _LandingSpy();
      overlayOf(
        frames: frames,
        bucket: bucket,
        playhead: playhead,
      ).paint(whole, Size(frames * cell, across));
      expect(whole.rects, hasLength(2), reason: '⛔premise: a bar and a tint');
      expect(windowed.rects, [
        for (final rect in whole.rects) rect.shift(Offset(-origin, 0)),
      ]);
    });

    test('the axis growing in its window repaints none of it', () {
      final bucket = bucketAt(7);
      final box = midway();
      expect(
        overlayOf(
          frames: 1100,
          bucket: bucket,
        ).shouldRepaint(overlayOf(frames: frames, bucket: bucket)),
        isTrue,
        reason: '⛔premise: as long as its axis, the strip repaints',
      );
      expect(
        overlayOf(
          frames: 1100,
          bucket: bucket,
          box: box,
        ).shouldRepaint(overlayOf(frames: frames, bucket: bucket, box: box)),
        isFalse,
      );
    });
  });
}
