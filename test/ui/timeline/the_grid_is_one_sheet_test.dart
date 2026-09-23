import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show buildAppTheme;
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerMarkColor;
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart'
    show timelineDrawingHeldColor, timelineEmptyCelPaperColor;
import 'package:anicel/src/ui/timeline/timeline_cel_content_source.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import '../../helpers/run_edge_fixtures.dart';
import 'timeline_frame_geometry_probe.dart';

/// 🚨I-44 (유저 2026-09-23 → 09-24): 「가로선이랑 세로선이 2개 중복해서있고 …
/// 블록에도 세로선 3번째중복인데 이거 하나로 못합치나? 그리드오버레이위에
/// 행바닥 뭐지?」 → 「합친다 — 그리드 한 장」.
///
/// The lines came from four places: the overlay under the rows (drawn on
/// every paint, seen nowhere — each row's opaque ground covered it), each row
/// redrawing its empty cells' lines and seams on that ground (D43-2), each
/// block drawing seams on its paper, and each fx band's own grid (F-7).
/// ⇒ ONE SHEET under the rows paints their grounds, every frame line and
/// every row seam; a row paints its paper and nothing else.
///
/// ⛔The fix D43-2 rejected stays rejected (`layer_timeline_grid_test`):
/// stretching the content to the viewport put a grid where no row is —
/// 「레이어가 없는곳에 그리드를 만들란게아니야」.
void main() {
  final scheme = buildAppTheme().colorScheme;
  final host = scheme.surfaceContainerHighest;

  TimelineGridSheetPainter sheet({
    List<TimelineGridRow> rows = const [],
    double cell = 24,
    Color? ground,
    bool noGround = false,
  }) => TimelineGridSheetPainter(
    frameCellExtent: cell,
    framesPerSecond: 24,
    colorScheme: scheme,
    ground: noGround ? null : (ground ?? host),
    rows: TimelineGridRows(rows),
  );

  // Colours are compared as the 32-bit pixels they land as: a `Paint`
  // round-trips its colour through float32, so a recomputed float64
  // expectation is never `==` even when the two print identically.
  bool same(Color a, Color b) => a.toARGB32() == b.toARGB32();

  ({Color color, double strokeWidth}) inkAt(int frame, {double cell = 24}) =>
      timelineFrameBoundaryLineInk(
        frameIndex: frame,
        frameCellExtent: cell,
        framesPerSecond: 24,
        colorScheme: scheme,
      )!;

  group('the sheet', () {
    test('a row on the host ground takes the law\'s line in the host\'s ink; '
        'a row on its own ground is painted and lined in THAT ground\'s', () {
      final lane = timelineLaneGround(host);
      final spy = _PaintSpy();
      sheet(
        rows: [(extent: 28, ground: host), (extent: 28, ground: lane)],
      ).paint(spy, const Size(120, 56));

      // Frame 1's boundary: once the whole height on the host, then again
      // across the lane row, each in the ink its ground asks for.
      final atOne = spy.lines.where((l) => l.from.dx == 24.5).toList();
      expect(atOne.map((l) => (l.from.dy, l.to.dy)), [(0, 56), (28, 56)]);
      expect(
        same(atOne[0].color, timelineGridLineInkOnGround(inkAt(1), host)),
        isTrue,
      );
      expect(
        same(atOne[1].color, timelineGridLineInkOnGround(inkAt(1), lane)),
        isTrue,
      );
      expect(
        atOne[1].color.toARGB32(),
        isNot(atOne[0].color.toARGB32()),
        reason: 'fixture premise: two grounds, two results — the RULE is '
            'what must match, and it is the one law function',
      );
      // The lane's ground is the sheet's to paint (it was the band's own
      // wash, F-7) — and the host rows get none: the panel paints that.
      expect(
        spy.fills.where((f) => same(f.color, lane)).map((f) => f.rect),
        [const Rect.fromLTRB(0, 28, 120, 56)],
      );
      expect(spy.fills.where((f) => same(f.color, host)), isEmpty);
    });

    test('every row is ruled at its LAST pixel, flat, over the lines', () {
      final spy = _PaintSpy();
      sheet(
        rows: [
          (extent: 28, ground: host),
          (extent: 28, ground: host),
        ],
      ).paint(spy, const Size(120, 56));
      final seam = timelineGridRowSeamInk(scheme);
      final seams = spy.fills.where((f) => same(f.color, seam.color)).toList();
      // F-3: the rail's divider continued into the cells — never multiplied
      // onto a ground. At each row's last pixel, so the next row's first is
      // untouched — the pixel a row's paper stops short of.
      expect(seams.map((f) => f.rect), [
        const Rect.fromLTRB(0, 27, 120, 28),
        const Rect.fromLTRB(0, 55, 120, 56),
      ]);
      expect(
        spy.order.lastIndexWhere((op) => op == 'line'),
        lessThan(spy.order.indexWhere((op) => op == 'fill')),
        reason: 'the seam crosses the frame lines, as it did on the rows',
      );
    });

    test('no ground = the ARTWORK: raw ink, no row painted, no seam ruled', () {
      final spy = _PaintSpy();
      sheet(noGround: true).paint(spy, const Size(120, 28));
      expect(spy.fills, isEmpty);
      expect(
        spy.lines.firstWhere((l) => l.from.dx == 24.5).color.toARGB32(),
        inkAt(1).color.toARGB32(),
        reason: 'nothing to multiply against — the folded row\'s lines stay '
            'the law\'s own ink, source-over',
      );
    });

    test('the cadence thins lines at small zooms, and the beats stay', () {
      // 10% (2.4px): a base line and its ground need three frames there
      // (I-22), so frame 5 thins out while frame 6's beat stays.
      final spy = _PaintSpy();
      sheet(
        cell: 2.4,
        rows: [(extent: 28, ground: host)],
      ).paint(spy, const Size(40, 28));
      bool lined(int frame) => spy.lines.any(
        (l) => (l.from.dx - (frame * 2.4 + timelineGridLineSnap)).abs() < 1e-6,
      );
      expect(lined(5), isFalse);
      expect(lined(6), isTrue);
    });
  });

  group('the rows', () {
    TimelineCellExposureState stateFor(Layer layer, int frameIndex) {
      if (layer.timeline[frameIndex]?.isDrawing ?? false) {
        return TimelineCellExposureState.drawingStart;
      }
      if (coveringDrawingBlockAt(layer.timeline, frameIndex) != null) {
        return TimelineCellExposureState.held;
      }
      return TimelineCellExposureState.uncovered;
    }

    /// A block over 10..13 and empty everywhere else.
    final layer = Layer(
      id: const LayerId('draw'),
      name: 'A',
      frames: [Frame(id: const FrameId('f1'), duration: 1, strokes: const [])],
      timeline: {
        10: const TimelineExposure.drawing(FrameId('f1'), length: 4),
      },
    );

    TimelineRowCellsPainter painterFor({
      Color? paperGround,
      bool celHasContent = true,
    }) => TimelineRowCellsPainter(
      layer: layer,
      geometry: testFrameGeometry(
        frameCellExtent: 24,
        frameEndIndexExclusive: 40,
      ),
      crossAxisExtent: 28,
      exposureStateForLayer: stateFor,
      colorScheme: scheme,
      baseTextStyle: const TextStyle(fontSize: 11),
      celContent: TimelineCelContentSource(
        hasContent: (_, _) => celHasContent,
        revision: ValueNotifier<int>(0),
      ),
      paperGround: paperGround,
    );

    test('a row fills its PAPER and nothing else — no line, no ground', () {
      final painter = painterFor(paperGround: host);
      final spy = _PaintSpy();
      painter.paint(spy, const Size(960, 28));
      expect(spy.lines, isEmpty, reason: 'the hold dash aside, no line');
      expect(
        spy.fills.map((f) => f.rect).toSet(),
        {
          for (var frame = 10; frame < 14; frame += 1)
            painter.paperRectFor(frame),
        },
        reason: 'an empty cell paints nothing (UI-R21 #2) — its ground is '
            'the sheet\'s — and a block cell paints its paper box',
      );
    });

    test('the paper stops a seam short of the row\'s trailing edge', () {
      final painter = painterFor(paperGround: host);
      final cell = painter.cellRectFor(11);
      final paper = painter.paperRectFor(11);
      expect(paper.top, cell.top);
      expect(paper.left, cell.left);
      expect(paper.width, cell.width);
      expect(
        paper.bottom,
        cell.bottom - timelineGridRowSeamStroke,
        reason: '「세로선 지움(가로선 남김)」 — the seam is under the row now, '
            'so paper over the last pixel would hide the one line kept',
      );
    });

    /// 🚨F-3 (유저 2026-08-24): 「프레임 그리드가 아예 안 그려지는 레이어가
    /// 있다(확인된 것 = 이미지 레이어)」 — the row's own line skipped ghost
    /// cells, and an IMAGE row is one real cell plus hold ghosts to the cut
    /// end (D22). A ghost carries no block CHROME; it does not stand on
    /// different frames. ⇒ It paints no paper, so the sheet's lines run
    /// through it like through any empty cell.
    test('a hold GHOST paints no paper — the sheet rules it like empty '
        'space', () {
      final ghosted = TimelineRowCellsPainter(
        layer: Layer(
          id: const LayerId('image'),
          name: 'I',
          frames: [
            Frame(id: const FrameId('f1'), duration: 1, strokes: const []),
          ],
          timeline: {
            0: const TimelineExposure.drawing(FrameId('f1'), length: 4),
            6: const TimelineExposure.drawing(
              FrameId('f1'),
              length: 4,
              ghostOf: endHoldGhost,
            ),
          },
        ),
        geometry: testFrameGeometry(
          frameCellExtent: 24,
          frameEndIndexExclusive: 40,
        ),
        crossAxisExtent: 28,
        exposureStateForLayer: stateFor,
        colorScheme: scheme,
        baseTextStyle: const TextStyle(fontSize: 11),
        paperGround: host,
      );
      final spy = _PaintSpy();
      ghosted.paint(spy, const Size(960, 28));
      expect(
        spy.fills.map((f) => f.rect).toSet(),
        {
          for (var frame = 0; frame < 4; frame += 1)
            ghosted.paperRectFor(frame),
        },
        reason: 'the real block\'s paper, and nothing under the ghosts',
      );
    });

    test('an UNWORKED block is pre-blended onto the host, so the sheet '
        'cannot show through it', () {
      final paper = layerMarkColor(layer.mark);
      final onHost = painterFor(paperGround: host, celHasContent: false);
      expect(
        onHost.resolvedCellStyleFor(11).background,
        Color.alphaBlend(timelineEmptyCelPaperColor(paper), host),
      );
      expect(onHost.resolvedCellStyleFor(11).background.a, 1.0);

      // Over the ARTWORK there is nothing to blend onto: it stays
      // translucent — the one place the lines show faintly through (the
      // cost the user took with I-44).
      final overArt = painterFor(celHasContent: false);
      expect(
        overArt.resolvedCellStyleFor(11).background,
        timelineEmptyCelPaperColor(paper),
      );
      expect(overArt.resolvedCellStyleFor(11).background.a, lessThan(1));
    });
  });

  _grid43Round();
}

/// 🚨D43-2 재개 b (유저 2026-08-22) — **ONE GRID LAW, AND IT RESOLVES ITS
/// GROUND FIRST.**
///
/// > 「왜 아직 **블록이 회색일때 그리드선이 흰색**인거지? 안보일까봐 같은
/// > 이유라면 **코마텍스트도 흰색으로 했을 상황**일텐데」
///
/// An UNWORKED block is 43%-alpha paper, and the multiply was handed that
/// translucent colour as if it were opaque — `lerp` climbs the ALPHA too,
/// so the line came out MORE opaque than its surroundings and read white.
/// No line crosses a block now (I-44), but every ground the sheet draws on
/// still goes through [timelineGridGroundOver] first — the lane wash is
/// exactly such a translucent colour.
void _grid43Round() {
  final scheme = buildAppTheme().colorScheme;
  double lum(Color c) => 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;

  test('a TRANSLUCENT ground is composited before the multiply — the line is '
      'darker than what the eye actually sees there', () {
    final row = scheme.surface;
    final unworked = timelineDrawingHeldColor.withValues(alpha: 0.43);
    final seen = Color.alphaBlend(unworked, row);
    final ink = timelineGridBaseLineInk(scheme);

    final resolved = timelineGridLineInkOnGround(ink, seen);
    final onScreen = Color.alphaBlend(resolved, row);
    expect(
      lum(onScreen),
      lessThan(lum(seen)),
      reason:
          '⛔the pre-fix path multiplied against the 43% colour and came '
          'out LIGHTER than its ground (measured: 0.471 vs 0.461) — that is '
          'the white line on the grey block',
    );

    // And the un-composited form is the bug, kept here so the difference is
    // a fact in the file rather than a claim in a commit message.
    final naive = timelineGridLineInkOnGround(ink, unworked);
    expect(
      lum(Color.alphaBlend(naive, row)),
      greaterThan(lum(seen)),
      reason:
          'fixture premise: multiplying the translucent colour really '
          'does produce a lighter line',
    );
  });
}

/// Every line and every filled box a painter asks for, with its colour and
/// in the order asked.
class _PaintSpy implements Canvas {
  final lines = <({Offset from, Offset to, Color color})>[];
  final fills = <({Rect rect, Color color})>[];
  final order = <String>[];

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    lines.add((from: p1, to: p2, color: paint.color));
    order.add('line');
  }

  @override
  void drawRect(Rect rect, Paint paint) {
    fills.add((rect: rect, color: paint.color));
    order.add('fill');
  }

  @override
  void drawRRect(RRect rrect, Paint paint) {
    fills.add((rect: rrect.outerRect, color: paint.color));
    order.add('fill');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
