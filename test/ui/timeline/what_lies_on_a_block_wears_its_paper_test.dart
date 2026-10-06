import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart'
    show timelineBlockCornerRadiusAt;
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_span_layout.dart';
import 'package:anicel/src/ui/timeline/timeline_se_row_visual.dart';

import '../../helpers/raster_parity.dart';

/// 🗣️F-270 (유저 2026-10-03): 「se블록의 이름칸의 강조색으로 되어있는 바탕색,
/// 바탕색 실루엣이 블록이랑 딱 맞춰서 꼭짓점이 동그랗게 되지않아서 바탕색
/// 오버레이만 사각형 실루엣임. 근본/구조적으로 해결」.
///
/// WHAT LIES ON A BLOCK WEARS ITS PAPER. The paper is one shape
/// ([timelineBlockPaperShape]); the SE paper draws it, and the name chip's
/// tint and the warning line are cut by it — so neither has a silhouette of
/// its own to get wrong.
///
/// They are painters, so they are pinned by PIXELS, through the row's own
/// overlay builders. ⚠️At an 8px cell, where the corner law gives 4: at 100%
/// it gives the bare 6, and a pin there cannot tell the paper's shape from a
/// rounded box the chip made for itself.
void main() {
  const cell = 8.0;
  const row = 28.0;
  const frames = 20;
  // Where [pumpSurface] puts the row inside the capture.
  const origin = Offset(20, 20);

  test('the paper is one shape — the row short of its seam, in the block\'s '
      'corner, turned with the axis', () {
    final shape = timelineBlockPaperShape(
      axis: Axis.horizontal,
      along: 3 * cell,
      rowExtent: row,
      frameCellExtent: cell,
    );
    expect(
      shape.outerRect,
      const Rect.fromLTWH(0, 0, 3 * cell, row - timelineGridRowSeamStroke),
    );
    expect(
      shape.tlRadius,
      timelineBlockCornerRadiusAt(
        cellExtent: cell,
        crossExtent: timelineRowPaperExtent(row),
      ),
    );
    expect(shape.tlRadius, const Radius.circular(4), reason: '⛔전제: 법이 문다');
    expect(shape.brRadius, shape.tlRadius, reason: 'every corner');
    // I-44: the corner is measured on the PAPER — a row of 9 lays 8 of
    // paper, and half of that is the corner, not half the row.
    expect(
      timelineBlockPaperShape(
        axis: Axis.horizontal,
        along: 100,
        rowExtent: 9,
        frameCellExtent: 100,
      ).tlRadius,
      const Radius.circular(4),
    );

    expect(
      timelineBlockPaperShape(
        axis: Axis.vertical,
        along: 3 * cell,
        rowExtent: row,
        frameCellExtent: cell,
      ).outerRect,
      const Rect.fromLTWH(0, 0, row - timelineGridRowSeamStroke, 3 * cell),
    );

    // A painter that knows its block in frames reads the cell off its box.
    expect(
      timelineBlockPaperShapeOver(
        axis: Axis.horizontal,
        along: 3 * cell,
        rowExtent: row,
        frames: 3,
      ),
      shape,
    );
    expect(
      timelineBlockPaperShapeOver(
        axis: Axis.horizontal,
        along: 3 * cell,
        rowExtent: row,
        frames: 0,
      ).tlRadius,
      Radius.zero,
      reason: 'no frames, no cell to round by',
    );
  });

  /// An SE row with one named block over `[start, start + length)`.
  Layer named(int start, int length, {bool clipped = false}) => Layer(
    id: const LayerId('se'),
    name: 'S1',
    kind: LayerKind.se,
    frames: [
      Frame(
        id: const FrameId('f1'),
        duration: 1,
        seName: 'A',
        strokes: const [],
      ),
    ],
    timeline: {
      start: TimelineExposure.drawing(const FrameId('f1'), length: length),
    },
    audioClips: [
      if (clipped)
        AudioClip(
          filePath: 'a.wav',
          frameId: const FrameId('f1'),
          clipped: true,
        ),
    ],
  );

  /// The row's overlays for [layer], alone on a transparent ground, as the
  /// capture's pixels.
  Future<_Shot> shoot(
    WidgetTester tester,
    Axis axis,
    List<Widget> overlays,
  ) async {
    await pumpSurface(
      tester,
      TimelineFixedFrameSpanLayer(
        geometry: const TimelineFrameGeometry(
          frameCellExtent: cell,
          frameStartIndex: 0,
          frameEndIndexExclusive: frames,
        ),
        crossAxisExtent: row,
        axis: axis,
        children: overlays,
      ),
      left: origin.dx,
      width: axis == Axis.horizontal ? frames * cell : row,
      height: axis == Axis.horizontal ? row : frames * cell,
    );
    await tester.pump();
    return _Shot(await captureBytes(tester), tester.view.devicePixelRatio);
  }

  /// The paper of the block over `[start, start + length)`, in the capture.
  Rect paperOf(Axis axis, int start, int length) {
    const paper = row - timelineGridRowSeamStroke;
    return axis == Axis.horizontal
        ? Rect.fromLTWH(start * cell, 0, length * cell, paper).shift(origin)
        : Rect.fromLTWH(0, start * cell, paper, length * cell).shift(origin);
  }

  for (final axis in Axis.values) {
    testWidgets('the SE name\'s tint ends where the paper ends — round at '
        'the block\'s corners, short of the row seam ($axis)', (tester) async {
      final layer = named(2, 4);
      final shot = await shoot(
        tester,
        axis,
        timelineRowSeLabelOverlays(
          layer: layer,
          frameStartIndex: 0,
          frameEndIndexExclusive: frames,
          axis: axis,
        ),
      );
      final paper = paperOf(axis, 2, 4);
      // The chip's stretch of the paper: its 16 from the block's start.
      final chip = axis == Axis.horizontal
          ? Rect.fromLTWH(paper.left, paper.top, seNameBoxExtent, paper.height)
          : Rect.fromLTWH(paper.left, paper.top, paper.width, seNameBoxExtent);
      expect(
        shot.alphaAt(chip.center),
        greaterThan(0),
        reason: '⛔전제: the chip is painted',
      );
      expect(shot.painted, chip, reason: 'nothing past the paper — the seam');
      expect(
        shot.cornersOf(paper),
        (0, 0, 0, 0),
        reason: 'the paper is round there, so nothing is laid there',
      );
    });

    testWidgets('a block the chip takes whole is round at both ends ($axis)', (
      tester,
    ) async {
      final shot = await shoot(
        tester,
        axis,
        timelineRowSeLabelOverlays(
          layer: named(10, 2),
          frameStartIndex: 0,
          frameEndIndexExclusive: frames,
          axis: axis,
        ),
      );
      final paper = paperOf(axis, 10, 2);
      expect(shot.alphaAt(paper.center), greaterThan(0), reason: '⛔전제');
      expect(shot.painted, paper, reason: 'the chip is the whole block');
      expect(shot.cornersOf(paper), (0, 0, 0, 0));
    });

    testWidgets('what cuts them IS the paper — the shape the SE paper draws '
        'for the same block ($axis)', (tester) async {
      final layer = named(2, 4, clipped: true);
      await shoot(tester, axis, [
        TimelineFrameSpan(
          placement: const TimelineFrameSpanPlacement(
            startIndex: 2,
            endIndexExclusive: 6,
          ),
          child: SePaperSpan(axis: axis, frameCellExtent: cell, startFrame: 2),
        ),
        ...timelineRowSeLabelOverlays(
          layer: layer,
          frameStartIndex: 0,
          frameEndIndexExclusive: frames,
          axis: axis,
        ),
        ...timelineRowClipMarkerOverlays(
          layer: layer,
          frameStartIndex: 0,
          frameEndIndexExclusive: frames,
          crossAxisExtent: row,
          axis: axis,
          tooltip: 'clipped take',
          color: AppColors.danger,
        ),
      ]);
      final marker = find.byKey(
        const ValueKey<String>('timeline-clip-marker-se-b2'),
      );
      final shape = _laidUnder(tester, find.byType(SePaperSpan)).rrects.first;
      final name = _laidUnder(tester, find.byType(SeSpanVisual));
      final line = _laidUnder(tester, marker);
      expect(shape.tlRadius, const Radius.circular(4), reason: '⛔전제: 법이 문다');

      expect(name.clips, [shape], reason: 'the name\'s tint');
      expect(line.clips, [shape], reason: 'the warning line');
      // What each lays under the cut: the chip's stretch of the block, and
      // the line's own strip.
      final chip = axis == Axis.horizontal
          ? const Rect.fromLTWH(0, 0, seNameBoxExtent, row)
          : const Rect.fromLTWH(0, 0, row, seNameBoxExtent);
      final strip = axis == Axis.horizontal
          ? const Rect.fromLTWH(0, 0, 4 * cell, 2)
          : const Rect.fromLTWH(0, 0, 2, 4 * cell);
      expect(name.rects, [chip]);
      expect(line.rects, [strip]);
      expect(timelineBlockWarningBarThickness, 2, reason: '⛔전제');
    });
  }
}

/// What the painter under [host] lays, at the size it is mounted at.
_PaperSpy _laidUnder(WidgetTester tester, Finder host) {
  final paint = find
      .descendant(
        of: host,
        matching: find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.painter != null,
        ),
      )
      .first;
  final spy = _PaperSpy();
  tester.widget<CustomPaint>(paint).painter!.paint(spy, tester.getSize(paint));
  return spy;
}

/// The shapes a painter clips to and lays.
class _PaperSpy implements Canvas {
  final clips = <RRect>[];
  final rects = <Rect>[];
  final rrects = <RRect>[];

  @override
  void clipRRect(RRect rrect, {bool doAntiAlias = true}) => clips.add(rrect);

  @override
  void drawRect(Rect rect, Paint paint) => rects.add(rect);

  @override
  void drawRRect(RRect rrect, Paint paint) => rrects.add(rrect);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
class _Shot {
  _Shot(this._bytes, this._ratio);

  final ByteData _bytes;
  final double _ratio;

  int get _width => (parityCaptureWidth * _ratio).round();
  int get _height => (parityCaptureHeight * _ratio).round();

  int _alpha(int x, int y) => _bytes.getUint8((y * _width + x) * 4 + 3);

  /// The alpha of the device pixel under the logical [point].
  int alphaAt(Offset point) =>
      _alpha((point.dx * _ratio).floor(), (point.dy * _ratio).floor());

  /// The alpha of the device pixel in each corner of [rect], inside it:
  /// start-near, start-far, end-near, end-far as the rect is read.
  (int, int, int, int) cornersOf(Rect rect) {
    final left = (rect.left * _ratio).round();
    final top = (rect.top * _ratio).round();
    final right = (rect.right * _ratio).round() - 1;
    final bottom = (rect.bottom * _ratio).round() - 1;
    return (
      _alpha(left, top),
      _alpha(right, top),
      _alpha(left, bottom),
      _alpha(right, bottom),
    );
  }

  /// The box of everything painted, in logical pixels.
  Rect get painted {
    var left = _width;
    var top = _height;
    var right = -1;
    var bottom = -1;
    for (var y = 0; y < _height; y += 1) {
      for (var x = 0; x < _width; x += 1) {
        if (_alpha(x, y) == 0) continue;
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
    return Rect.fromLTRB(
      left / _ratio,
      top / _ratio,
      (right + 1) / _ratio,
      (bottom + 1) / _ratio,
    );
  }
}
