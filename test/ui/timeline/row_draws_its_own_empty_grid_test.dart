import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show buildAppTheme;
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart'
    show timelineDrawingHeldColor;
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart'
    show timelineGridSubstrateOps;
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import 'timeline_frame_geometry_probe.dart';

/// 🚨D43-2 (유저 2026-08-21): 「행이 있는데 **블록이 없는 곳**에 그리드가
/// 없단거야. 근데 **fx행은 존재**한단거고」
///
/// 🎯**원인은 z-order였다.** The line overlay sits UNDER the rows, and a row
/// paints an OPAQUE full-width ground (`ColoredBox(surface)` + the active
/// wash). So the overlay is covered for the whole width of every row that
/// draws one — and shows through a LANE row, which draws none. That is the
/// report, both halves, from one fact.
///
/// ⇒ The empty cells' lines cannot come from the overlay. They are the
/// ROW's, drawn on the row's own ground, through the SAME law function the
/// block interiors already use — so one boundary reads as one line whether
/// it crosses paper or empty space.
///
/// ⛔The rejected fix is pinned in `layer_timeline_grid_test`: stretching
/// the scroll content to the viewport put a grid where no row is, which is
/// 「레이어가 없는곳에 그리드를 만들란게아니야」.
void main() {
  final scheme = buildAppTheme().colorScheme;

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
    timeline: {10: const TimelineExposure.drawing(FrameId('f1'), length: 4)},
  );

  TimelineRowCellsPainter painterFor({Color? rowGround}) =>
      TimelineRowCellsPainter(
        layer: layer,
        geometry: testFrameGeometry(
          frameCellExtent: 24,
          frameEndIndexExclusive: 40,
        ),
        crossAxisExtent: 28,
        exposureStateForLayer: stateFor,
        colorScheme: scheme,
        baseTextStyle: const TextStyle(fontSize: 11),
        framesPerSecond: 24,
        rowGround: rowGround,
      );

  test('an EMPTY cell in a row gets the law\'s line, on the row\'s ground', () {
    final painter = painterFor(rowGround: scheme.surface);

    // Frame 5: empty, a plain base boundary at this zoom.
    final line = painter.heldSeamLineFor(5)!;
    final ink = timelineFrameBoundaryLineInk(
      frameIndex: 5,
      frameCellExtent: 24,
      framesPerSecond: 24,
      colorScheme: scheme,
    )!;
    expect(
      line.color,
      timelineGridLineInkOnGround(ink, scheme.surface),
      reason:
          'the ROW\'s ground, not the panel\'s and not the cell\'s — an '
          'empty cell paints nothing, so its own background is transparent',
    );
    expect(
      line.rect.width,
      ink.strokeWidth,
      reason: 'and the law\'s width, like every other boundary',
    );
  });

  test('the same boundary reads the SAME whether it crosses paper or empty '
      'space — one line, one layer', () {
    final painter = painterFor(rowGround: scheme.surface);
    // 11 is interior to the block, 5 is empty. Both are plain boundaries at
    // this zoom, so the only thing that may differ is the GROUND each is
    // multiplied onto — never the ink, the width or the position.
    final inBlock = painter.heldSeamLineFor(11)!;
    final onEmpty = painter.heldSeamLineFor(5)!;
    expect(inBlock.rect.width, onEmpty.rect.width);
    expect(
      inBlock.rect.left - painter.cellRectFor(11).left,
      onEmpty.rect.left - painter.cellRectFor(5).left,
      reason: 'the same offset inside its own cell — the law\'s snap',
    );
    expect(
      inBlock.color,
      isNot(onEmpty.color),
      reason:
          'fixture premise: two different papers, so two results — what '
          'must match is the RULE, and that is asserted above',
    );
  });

  test(
    'a block\'s LEADING edge is still not a seam — the run starts there',
    () {
      final painter = painterFor(rowGround: scheme.surface);
      expect(painter.heldSeamLineFor(10), isNull);
    },
  );

  test('a chromeless row keeps the raw ink — it lies over the ARTWORK and '
      'has no ground to multiply against', () {
    final painter = painterFor();
    final ink = timelineFrameBoundaryLineInk(
      frameIndex: 5,
      frameCellExtent: 24,
      framesPerSecond: 24,
      colorScheme: scheme,
    )!;
    expect(painter.heldSeamLineFor(5)!.color, ink.color);
  });

  test('the cadence still thins empty-space lines out at small zooms — the '
      'row did not grow a second grid rule', () {
    final painter = TimelineRowCellsPainter(
      layer: layer,
      geometry: testFrameGeometry(
        frameCellExtent: 8,
        frameEndIndexExclusive: 40,
      ),
      crossAxisExtent: 28,
      exposureStateForLayer: stateFor,
      colorScheme: scheme,
      baseTextStyle: const TextStyle(fontSize: 11),
      framesPerSecond: 24,
      rowGround: scheme.surface,
    );
    expect(
      painter.heldSeamLineFor(5),
      isNull,
      reason: 'thinned out, exactly as the empty-space overlay thins it',
    );
    expect(
      painter.heldSeamLineFor(6),
      isNotNull,
      reason: 'and the 6f beat survives, in empty space too',
    );
  });

  /// 🚨D43-2 재개 (유저 2026-08-22, 스크린샷) — 「**아직도 레이어행에만
  /// 그리드 없거든? fx쪽엔 있는데**」.
  ///
  /// ⛔EVERY TEST ABOVE ASKS THE PAINTER, AND THE PAINTER WAS ALWAYS RIGHT.
  /// The tile emitter is a SECOND reader of the same contract, and it
  /// skipped any cell with no background and no border — which is the exact
  /// definition of an empty cell — before it ever reached the line. The
  /// classic pass does draw it, and the classic pass is skipped wherever a
  /// tile covers the span, so on screen nobody drew it at all. fx rows were
  /// never affected: they lay down no opaque ground, so the overlay under
  /// them still shows through, which is precisely the split reported.
  ///
  /// ⇒ these ask the EMITTER. "The law file is green and the panel is
  /// broken" is this round's recurring shape, and the cure is always to pin
  /// the reader the screen actually goes through.
  group('the TILE path carries the empty-cell line too', () {
    int opWordsFor(int start, int endExclusive) => timelineGridSubstrateOps(
      painter: painterFor(rowGround: scheme.surface),
      spanStartIndex: start,
      spanEndIndexExclusive: endExclusive,
      devicePixelRatio: 1,
    ).length;

    test('a span of PURELY EMPTY cells still emits ops', () {
      // 2..8 hold no block at all — the fixture's block is at 10..13.
      expect(
        opWordsFor(2, 9),
        greaterThan(0),
        reason:
            '⛔this was ZERO. An empty cell paints no background and no '
            'border by design (UI-R21 #2), so the emitter\'s "nothing to '
            'draw" test was true for exactly the cells D43-2 serves',
      );
    });

    test('the emitted stream grows with the number of lines the law names', () {
      final painter = painterFor(rowGround: scheme.surface);
      var lines = 0;
      for (var frame = 2; frame < 9; frame += 1) {
        if (painter.heldSeamLineFor(frame) != null) {
          lines += 1;
        }
      }
      expect(lines, greaterThan(1), reason: 'presence first');
      // Two empty spans, one strictly longer: more lines must mean more
      // stream. An emitter that dropped some would flatten this.
      expect(
        opWordsFor(2, 9),
        greaterThan(opWordsFor(2, 4)),
        reason: 'a longer empty span carries more of the law\'s lines',
      );
    });

    test('a span with a BLOCK still emits MORE than an empty one — the fix '
        'did not turn paper into bare lines', () {
      expect(opWordsFor(10, 14), greaterThan(opWordsFor(2, 6)));
    });
  });

  // 🚨D43-2 재개 b (유저 2026-08-22): 「**카메라레이어는 그리드 안보이고**」.
  //
  // The camera row was excluded from `heldSeamLineFor` outright — a guard I
  // wrote in 07334e2b that nobody asked for and that no reason survives.
  // Its cells are key-summary markers, which changes what the row DRAWS,
  // not where the frames are.
  test('the CAMERA row is on the same sheet — its boundaries get the same '
      'line as everybody else\'s', () {
    final camera = Layer(
      id: const LayerId('cam'),
      name: 'Camera',
      kind: LayerKind.camera,
      frames: const [],
      timeline: const {},
    );
    final cameraLine = TimelineRowCellsPainter(
      layer: camera,
      geometry: testFrameGeometry(
        frameCellExtent: 24,
        frameEndIndexExclusive: 40,
      ),
      crossAxisExtent: 28,
      exposureStateForLayer: (_, _) => TimelineCellExposureState.uncovered,
      colorScheme: scheme,
      baseTextStyle: const TextStyle(fontSize: 11),
      framesPerSecond: 24,
      rowGround: scheme.surface,
    ).heldSeamLineFor(5);

    expect(
      cameraLine,
      isNotNull,
      reason:
          '⛔a row does not opt out of the grid — the grid is where the '
          'frames are, and every row stands on the same frames',
    );
    expect(
      cameraLine!.color,
      painterFor(rowGround: scheme.surface).heldSeamLineFor(5)!.color,
      reason: 'and it is the SAME line, not a camera-flavoured one',
    );
  });

  // 🚨D43-2 재개 d (유저 2026-08-23): 「**fx행엔 그리드의 가로선 있는데
  // 레이어쪽 프레임쪽엔 없거든?** 그거 통일로 추가해주고」.
  //
  // ⛔SAME SHAPE AS THE VERTICAL LINES, one axis over: the overlay draws row
  // seams and sits UNDER the rows (D32), so a row with an opaque ground
  // erased its own. The fx band kept one only because it had written a
  // `BorderSide` of its own — in its own words, at half the law's width.
  group('the CROSS-axis row seam is the same law', () {
    test('a frame cells row draws its own seam, on its own ground', () {
      final painter = painterFor(rowGround: scheme.surface);
      final seam = painter.rowSeamLineFor(5)!;
      final ink = timelineGridRowSeamInk(scheme);

      expect(seam.color, timelineGridLineInkOnGround(ink, scheme.surface));
      expect(seam.rect.height, ink.strokeWidth);
      expect(
        seam.rect.width,
        painter.cellRectFor(5).width,
        reason:
            'per CELL, so the baked tiles and the classic pass emit the '
            'same segments and cannot drift',
      );
    });

    test('it sits at the row\'s TRAILING edge — the boundary to the next '
        'row, not inside this one', () {
      final painter = painterFor(rowGround: scheme.surface);
      final cell = painter.cellRectFor(5);
      final seam = painter.rowSeamLineFor(5)!;
      // Its CENTRE sits the law's snap in from the row's trailing edge, so
      // the whole stroke lands inside this row's own extent rather than
      // half of it bleeding into the next row's canvas.
      expect(
        seam.rect.center.dy,
        closeTo(cell.bottom - timelineGridLineSnap, 0.01),
      );
      expect(seam.rect.bottom, lessThanOrEqualTo(cell.bottom));
    });

    test('the seam takes the block\'s paper where it crosses one — the same '
        'ground question the vertical line asks', () {
      final painter = painterFor(rowGround: scheme.surface);
      expect(
        painter.rowSeamLineFor(11)!.color,
        isNot(painter.rowSeamLineFor(5)!.color),
        reason: 'fixture premise: 11 is inside the block, 5 is empty',
      );
      final ink = timelineGridRowSeamInk(scheme);
      final blockGround = painter.resolvedCellStyleFor(11).background;
      expect(
        painter.rowSeamLineFor(11)!.color,
        timelineGridLineInkOnGround(
          ink,
          Color.alphaBlend(blockGround, scheme.surface),
        ),
        reason:
            '⛔the translucent paper is composited FIRST here too — the '
            'seam cannot repeat the white-line bug on the other axis',
      );
    });

    test('a CHROMELESS row draws none — a row lying on the artwork has no '
        'seam, exactly as the folded overlay draws none', () {
      final chromeless = TimelineRowCellsPainter(
        layer: layer,
        geometry: testFrameGeometry(
          frameCellExtent: 24,
          frameEndIndexExclusive: 40,
        ),
        crossAxisExtent: 28,
        exposureStateForLayer: stateFor,
        colorScheme: scheme,
        baseTextStyle: const TextStyle(fontSize: 11),
        framesPerSecond: 24,
        chromeless: true,
      );
      expect(chromeless.rowSeamLineFor(5), isNull);
      expect(
        chromeless.heldSeamLineFor(5),
        isNotNull,
        reason:
            'the FRAME boundaries still run there — it is the row-to-row '
            'seam that has no meaning over artwork, which is the same call '
            '`collapsed_row_overlay` already makes (crossCellExtent 0)',
      );
    });

    test('the TILE path carries it too — the emitter is the reader the '
        'screen actually goes through', () {
      List<int> opsFor(int start, int endExclusive) => timelineGridSubstrateOps(
        painter: painterFor(rowGround: scheme.surface),
        spanStartIndex: start,
        spanEndIndexExclusive: endExclusive,
        devicePixelRatio: 1,
      );

      // Every cell owes a seam, empty ones included — so a span of purely
      // empty cells emits strictly more than it did when only the vertical
      // boundaries were carried. Growing with LENGTH is what proves the
      // per-cell emission actually reaches the writer.
      expect(opsFor(2, 9).length, greaterThan(opsFor(2, 4).length));
    });
  });

  _grid43Round();
}

/// 🚨D43-2 재개 b (유저 2026-08-22) — **ONE GRID LAW, AND IT RESOLVES ITS
/// GROUND FIRST.**
///
/// > 「왜 아직 **블록이 회색일때 그리드선이 흰색**인거지? 안보일까봐 같은
/// > 이유라면 **코마텍스트도 흰색으로 했을 상황**일텐데」 · 「**카메라레이어는
/// > 그리드 안보이고**」
///
/// Two places had not been put through the law. An UNWORKED block is
/// 43%-alpha paper over the row's underlay, and the multiply was handed
/// that translucent colour as if it were opaque — `lerp` climbs the ALPHA
/// too, so the line came out MORE opaque than its surroundings and read
/// white. And the camera row was excluded from the line outright.
void _grid43Round() {
  final scheme = buildAppTheme().colorScheme;
  double lum(Color c) => 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;

  test('a TRANSLUCENT paper is composited before the multiply — the line is '
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
