import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsProperties;

import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/timeline_repeat.dart';
import '../input/app_input_settings.dart' show AppInput;
import '../widgets/instant_tap_region.dart';
import 'layer_label_controls.dart' show layerMarkColor;
import 'timeline_cell_double_tap.dart';
import 'timeline_cel_content_source.dart';
import 'timeline_cell_exposure_state.dart';
import 'timeline_beat_lines.dart'
    show
        timelineFrameBoundaryLineInk,
        timelineGridLineInkOnGround,
        timelineGridLineSnap;
import 'timeline_cell_style.dart';
import 'timeline_exposure_block_visual.dart';
import 'timeline_frame_geometry.dart';
import 'timeline_frame_window.dart';
import 'timeline_glyph_cache.dart';
import 'timeline_grid_tile_store.dart';
import 'timeline_se_row_visual.dart' show layerKindUsesSeSheetCells;

/// One DRAWING row's frame cells as a single painter (UI-R9 #12b, the
/// hybrid painterization): the dense, mostly-static cell strip — paper
/// blocks, borders, glyphs, ghost dim, band tints — is pure canvas work,
/// so the per-cell widget pipeline (Element + RenderObject + InkWell +
/// Material ink + Semantics per cell) disappears for the rows that carry
/// hundreds of cells. Sparse interactive chrome (edge grips, run handles,
/// the range gesture layer, the cursor layer) stays widgets ON TOP.
///
/// The visual contract mirrors [TimelineFrameCell] exactly — that widget
/// remains the renderer for the sparse row kinds (SE / instruction /
/// camera).
class TimelineRowCellModel {
  const TimelineRowCellModel({
    required this.frameIndex,
    required this.exposureState,
    required this.segment,
    required this.ghost,
    required this.dimmed,
    required this.glyph,
    required this.semanticsLabel,
  });

  final int frameIndex;
  final TimelineCellExposureState exposureState;
  final TimelineExposureBlockVisualSegment segment;
  final bool ghost;
  final bool dimmed;

  /// The text drawn in the cell ('' when none / too narrow).
  final String glyph;
  final String? semanticsLabel;
}

/// The hold ghost's dash glyph — the probe VALUE tests read from
/// [TimelineRowCellsPainter.cellModelAt]. paint() renders it as an
/// axis-aligned line (UI-R12 #18), never as text; the tile emitter (T3)
/// keys the same value to bake it as a capsule.
const String timelineHoldDashGlyph = 'ㅡ';
const String _holdDashGlyph = timelineHoldDashGlyph;

/// Glyph TextPainters come from the shared timeline cache (UI-R16):
/// frame numbers and markers repeat heavily across rows and repaints.
TextPainter _glyphPainter(String text, TextStyle style) =>
    timelineGlyphPainter(text, style);

class TimelineRowCellsPainter extends CustomPainter {
  TimelineRowCellsPainter({
    required this.layer,
    required this.geometry,
    required this.crossAxisExtent,
    required this.exposureStateForLayer,
    this.frameNameForLayer,
    required this.colorScheme,
    required this.baseTextStyle,
    this.axis = Axis.horizontal,
    this.windowBucket,
    this.viewportMainExtent = 0,
    this.tileStore,
    this.substrateGeneration = '',
    this.devicePixelRatio = 1.0,
    this.celContent,
    this.coverageIdentity,
    this.chromeless = false,
    this.framesPerSecond = 24,
  }) : super(
         repaint: Listenable.merge([
           geometry,
           ?windowBucket,
           ?tileStore?.revision,
           ?celContent?.revision,
         ]),
       );

  /// The counting fps, for the seam law's beat strengths (D32/D38): a 6f
  /// or second boundary crossing a block keeps its stronger line, so the
  /// grid reads as ONE line running through paper and dark ground alike.
  final int framesPerSecond;

  /// What this row's COVERAGE follows, when that is not the layer itself.
  ///
  /// ㉘ (user, 2026-08-12): 「카메라 행에 프레임을 추가하면 즉시 갱신이 안
  /// 된다 — 다른 레이어로 이동해야 보인다」. The camera row's cells mirror
  /// `cut.camera`, not the camera LAYER, so adding a key left every field
  /// [shouldRepaint] compares untouched: same layer instance, same
  /// `exposureStateForLayer` tear-off, same cel revision. The row rebuilt
  /// and the painter honestly answered "nothing changed" — and the baked
  /// substrate tile said the same, so even a forced repaint would have
  /// served the old picture.
  ///
  /// ★A row that draws coverage it does not OWN has to say what it is
  /// following. The rails already knew this value — it is the row memo's
  /// auxiliary identity ([TimelineRowMemoAux]) — so nothing new is invented
  /// here; it just had to reach the painter as well as the memo.
  final Object? coverageIdentity;

  /// #29: the (project, cut) world this painter's RESOLVERS answer from —
  /// `'<projectId>:<cutId>'`, handed down by the host that knows the
  /// session. The tile store keys and gates on it, because the resolvers
  /// are live tear-offs: a tile request that outlives a cut switch would
  /// otherwise be rastered against another cut's answers (grey where a
  /// drawing exists), and a same-id row in another cut would be served
  /// this cut's pixels.
  ///
  /// ⚠️A plain String compared with `==`, never an object rebuilt per
  /// frame — R9 #16 is what a fresh-identity value here regresses to.
  /// Empty means "no generation": correct-but-uncached hosts (tests, the
  /// chromeless workspace row) simply behave as one world.
  final String substrateGeneration;

  /// R26 #44: the unworked-block tint's fact AND its event. Null = no tint.
  final TimelineCelContentSource? celContent;

  bool Function(Layer layer, int frameIndex)? get celHasContentForLayer =>
      celContent?.hasContent;

  /// Read LIVE, never captured: the whole point is that the row does NOT
  /// rebuild when a cel gains pixels — it repaints — so a value frozen at
  /// construction would hand the tile store yesterday's answer forever and
  /// the baked tile would keep serving the old tint.
  int get celContentRevision => celContent?.revision.value ?? 0;

  final Layer layer;

  /// The LIVE frame-axis geometry (R28 #4): read through, never copied, so a
  /// zoom step repaints this painter instead of rebuilding the row that
  /// built it. Every geometry getter below reads `geometry.value`.
  final TimelineFrameGeometryHandle geometry;

  int get frameStartIndex => geometry.value.frameStartIndex;
  int get frameEndIndexExclusive => geometry.value.frameEndIndexExclusive;
  double get leadingFrameSpacerWidth => geometry.value.leadingFrameSpacerWidth;
  double get frameCellExtent => geometry.value.frameCellExtent;

  final double crossAxisExtent;
  final TimelineCellExposureState Function(Layer layer, int frameIndex)
  exposureStateForLayer;
  final String? Function(Layer layer, int frameIndex)? frameNameForLayer;

  final ColorScheme colorScheme;

  /// The ambient text style the widget cells inherited (DefaultTextStyle);
  /// glyphs merge color/weight onto it so painted text matches exactly.
  final TextStyle baseTextStyle;
  final Axis axis;

  /// PRO-TIMELINE scrolling (UI-R15→R16): with these set, the painter
  /// windows ITSELF off the QUANTIZED bucket — the bucket notifier is the
  /// `repaint` listenable, so a repaint happens once per span crossing
  /// (several cells), not per pixel; between crossings scrolling is pure
  /// translation of the already-painted (raster-cacheable) picture. The
  /// row widget builds ONCE for the full frame bounds and never rebuilds
  /// on scroll. Null keeps the classic pre-windowed contract.
  final ValueListenable<int>? windowBucket;

  /// The scroll viewport's main-axis extent for the self-windowing path.
  final double viewportMainExtent;

  /// The substrate TILE store (UI-R18 O7 T2): with it set, span-sized
  /// pre-rastered images replace the per-cell fill/border canvas work —
  /// its revision joins the repaint listenable so landed tiles paint on
  /// the next frame. Null (or no native engine) keeps the classic path.
  final TimelineGridTileStore? tileStore;

  /// GROUND OFF — the row drawn over the artwork instead of over a panel.
  ///
  /// 유저 확정 (2026-08-10), restated 2026-08-13 when it went missing:
  /// 「프레임셀쪽은 **바탕색은 싹 없애고** 그리드선 띄우고 그 부분도 전체적으로
  /// **반투명**하게」. The collapsed row's design is in its negative space —
  /// no panel fill, no rail fill, no active-row wash — and the one fill that
  /// survives is the out-of-cut shading, because that one IS information.
  ///
  /// 🚨T16 — this exists because the collapsed overlay MOUNTS this row now
  /// rather than re-drawing it (⑩'s root C). Mounting was right and it
  /// brought the timeline's ground along with it, since only the RAIL row had
  /// a way to take its ground off. So the flag goes where the twin already
  /// is ([TimelineLayerControlsRow.chromeless]) instead of the overlay
  /// growing a second painter again.
  ///
  /// ★It is a GROUND rule, not a look of its own: empty paper stops being
  /// painted and a block keeps a translucent body, at the exact values the
  /// strip painter used while it owned this drawing — so nothing about the
  /// confirmed appearance is being re-decided here, only re-hosted.
  final bool chromeless;

  // ⛔The two per-cell alphas are GONE (유저 확정 2026-08-14): 「반투명 =
  // 오버레이 루트 하나, 70%」. `0x66` on a block's body and `0x9E` on its
  // edge came over verbatim from the painter this replaced, and two numbers
  // meant the folded row carried an opacity SCHEME of its own — body and
  // border fading by different amounts, so it never read as a dimmer copy of
  // the open row, which is the only thing it is supposed to be. One value on
  // the overlay root reads that way by construction, and it is one number to
  // change.

  /// Physical resolution for the tiles (tiles raster at logical × DPR
  /// and draw 1:1, so hidpi rows stay crisp).
  final double devicePixelRatio;

  /// The frame window paint() actually draws: the full bounds under the
  /// classic contract, the bucket-derived span (shared policy) under the
  /// self-windowing one. THE probe surface for visibility tests.
  ({int startIndex, int endIndexExclusive}) visibleFrameWindow() {
    final bucket = windowBucket;
    if (bucket == null || viewportMainExtent <= 0 || frameCellExtent <= 0) {
      return (
        startIndex: frameStartIndex,
        endIndexExclusive: frameEndIndexExclusive,
      );
    }
    final window = timelineFrameWindowFor(
      bucket: bucket.value,
      cellExtent: frameCellExtent,
      viewportExtent: viewportMainExtent,
    );
    return (
      startIndex: math.max(frameStartIndex, window.startIndex),
      endIndexExclusive: math.min(
        frameEndIndexExclusive,
        window.endIndexExclusive,
      ),
    );
  }

  TimelineCellExposureState _stateAt(int frameIndex) =>
      exposureStateForLayer(layer, frameIndex);

  /// The cell's rect in the ROW's local coordinates — the probe geometry
  /// tests and the row's hit-testing share (single source of truth).
  Rect cellRectFor(int frameIndex) {
    final main =
        leadingFrameSpacerWidth +
        (frameIndex - frameStartIndex) * frameCellExtent;
    return axis == Axis.horizontal
        ? Rect.fromLTWH(main, 0, frameCellExtent, crossAxisExtent)
        : Rect.fromLTWH(0, main, crossAxisExtent, frameCellExtent);
  }

  /// The frame index under a row-local position (the row Listener's
  /// pointer-down select); clamped non-negative.
  int frameIndexAt(Offset localPosition) {
    final main = axis == Axis.horizontal ? localPosition.dx : localPosition.dy;
    final cell = ((main - leadingFrameSpacerWidth) / frameCellExtent).floor();
    final frame = frameStartIndex + cell;
    return frame < 0 ? 0 : frame;
  }

  /// Camera rows are a SUMMARY column, not a sheet: their "coverage" is the
  /// lane-key union, drawn as a marker on empty-cell styling rather than as
  /// paper (the widget cells' `cameraSummaryCell` rule, brought over intact).
  bool get _cameraSummaryRow => layer.kind == LayerKind.camera;

  /// The cell state with ghost coverage READ AS EMPTY — ghosts render
  /// text-only (UI-R10 #11), so block-segment math and cell chrome treat
  /// them as uncovered cells. Camera summary cells read empty ALWAYS.
  TimelineCellExposureState _chromeStateAt(int frameIndex) =>
      timelineIndexIsGhost(layer, frameIndex) || _cameraSummaryRow
      ? TimelineCellExposureState.uncovered
      : _stateAt(frameIndex);

  /// Resolved models for the cells of the CURRENT paint pass; null outside
  /// one. Every cell is asked for twice per pass — once by the substrate
  /// (through [resolvedCellStyleFor]) and once by the ink — and each
  /// resolution is five exposure lookups plus a name lookup. The pass is the
  /// exact lifetime this may live for: the layer and the cel revision cannot
  /// move inside one paint, and holding it longer would serve stale cells.
  Map<int, TimelineRowCellModel>? _passModels;

  /// The resolved per-cell model — THE probe surface for tests (glyphs,
  /// dim/ghost flags, exposure states live here, not in widget trees).
  TimelineRowCellModel cellModelAt(int frameIndex) {
    final pass = _passModels;
    if (pass == null) {
      return _resolveCellModelAt(frameIndex);
    }
    return pass[frameIndex] ??= _resolveCellModelAt(frameIndex);
  }

  TimelineRowCellModel _resolveCellModelAt(int frameIndex) {
    final exposureState = _stateAt(frameIndex);
    final ghost = timelineIndexIsGhost(layer, frameIndex);
    final previous = frameIndex == 0 ? null : _stateAt(frameIndex - 1);
    final emptyRunStart = timelineEmptyRunStartsAt(
      current: exposureState,
      previous: previous,
    );
    final frameName = frameNameForLayer?.call(layer, frameIndex);
    // Hold ghosts keep their dash at ANY zoom (it paints as a line, not
    // text — UI-R12 #18): the continuing stroke is structure, so it never
    // joins the narrow-cell text suppression below.
    final holdGhost =
        ghost &&
        runBehaviorOwningGhostAt(layer, frameIndex)?.mode ==
            TimelineRunEdgeMode.hold;
    String glyph;
    if (holdGhost) {
      glyph = _holdDashGlyph;
    } else if (ghost) {
      // Ghosts are TEXT-ONLY (UI-R10 #11): a repeat ghost prints just the
      // cel names, exactly like before — the SHEET alone carries the
      // repeat-word convention (UI-R14 #3 rolled the timeline back).
      glyph = switch (exposureState) {
        TimelineCellExposureState.drawingStart =>
          frameName == null || frameName.isEmpty ? '○' : frameName,
        TimelineCellExposureState.markHeld ||
        TimelineCellExposureState.markUncovered => '●',
        _ => '',
      };
    } else {
      glyph = _marker(
        exposureState: exposureState,
        emptyRunStart: emptyRunStart,
        frameName: frameName,
      );
    }
    return TimelineRowCellModel(
      frameIndex: frameIndex,
      exposureState: exposureState,
      segment: calculateTimelineExposureBlockVisualSegment(
        previous: frameIndex == 0 ? null : _chromeStateAt(frameIndex - 1),
        current: _chromeStateAt(frameIndex),
        next: _chromeStateAt(frameIndex + 1),
      ),
      ghost: ghost,
      // GHOSTS only. "Outside the cut" used to dim here too, and that is
      // what tied this baked layer to the cut's length — the wash is its
      // own overlay now, above the cells, so it can follow a drag without
      // re-baking a single tile.
      dimmed: ghost,
      glyph: glyph,
      semanticsLabel: _semanticsLabel(
        exposureState: exposureState,
        frameName: frameName,
      ),
    );
  }

  String _marker({
    required TimelineCellExposureState exposureState,
    required bool emptyRunStart,
    String? frameName,
  }) {
    // THE marker table, all kinds (it was split across this painter and
    // TimelineFrameCell while the sparse rows were still widgets).
    return switch (exposureState) {
      // The timesheet "X": the FIRST cell of each empty run (paper-sheet
      // style). Camera rows mirror keyframes, instruction rows carry
      // instruction events and SE columns stay blank between entries on
      // paper — no X on any of those.
      //
      // It used to stop at the cut's end, which made the X the one GLYPH
      // that knew the cut's length — so a length that moved could not be
      // drawn without re-baking the glyphs. The rule is the same everywhere
      // now (user's rule 2026-08-02): an empty run starts where it starts.
      TimelineCellExposureState.uncovered =>
        !layerKindHoldsDrawings(layer.kind) ||
                layerKindUsesSeSheetCells(layer.kind) ||
                !emptyRunStart
            ? ''
            : 'X',
      // SE entries and instruction events draw their writing through the
      // row-level span overlays; the cells stay glyph-free paper. Camera
      // key summaries are span overlays too since B4 — the shared lane key
      // markers ([timelineUnionKeyMarkerSpans]) — so the text channel says
      // nothing there, and in particular never the paper-cell ○ that used
      // to surface mid-drag when the preview outran the committed name.
      TimelineCellExposureState.drawingStart =>
        layerKindUsesSeSheetCells(layer.kind) ||
                layerKindCarriesInstructions(layer.kind) ||
                _cameraSummaryRow
            ? ''
            : frameName == null || frameName.isEmpty
            ? '○'
            : frameName,
      TimelineCellExposureState.held => '',
      TimelineCellExposureState.markHeld ||
      TimelineCellExposureState.markUncovered => '●',
    };
  }

  String? _semanticsLabel({
    required TimelineCellExposureState exposureState,
    String? frameName,
  }) {
    // Instruction spans carry their own semantics on the row overlay.
    if (layerKindCarriesInstructions(layer.kind)) {
      return null;
    }
    return switch (exposureState) {
      TimelineCellExposureState.uncovered => null,
      TimelineCellExposureState.drawingStart =>
        layer.kind == LayerKind.camera
            ? 'camera keyframe'
            : frameName == null || frameName.isEmpty
            ? 'drawing start'
            : 'drawing start $frameName',
      TimelineCellExposureState.held => 'held exposure',
      TimelineCellExposureState.markHeld ||
      TimelineCellExposureState.markUncovered => 'inbetween mark',
    };
  }

  /// The cell's RESOLVED paint style (dim blends, band tint, block
  /// radius) — what paint() draws and what tests assert against (the
  /// successor of reading the widget cell's BoxDecoration).
  ({Color background, Color border, BorderRadius? radius}) resolvedCellStyleFor(
    int frameIndex,
  ) {
    final model = cellModelAt(frameIndex);
    // Ghosts carry NO block chrome (UI-R10 #11): the cell paints as plain
    // empty paper and only the dimmed glyph marks the derived exposure.
    // A camera summary cell is empty-styled for the same reason — its
    // coverage is a key marker, not paper.
    final paper = layerMarkColor(layer.mark);
    final styleColors = timelineCellStyleColors(
      colorScheme: colorScheme,
      exposureState: model.ghost || _cameraSummaryRow
          ? TimelineCellExposureState.uncovered
          : model.exposureState,
      selected: false,
      // ⑲: the row's blocks are its layer's colour label.
      paper: paper,
    );
    // R26 #44: a block whose cel has no picture yet grays its paper
    // slightly — the whole covered run, ACTION-section rows only (the
    // resolver stands down elsewhere). Ghosts stay plain (they carry no
    // block chrome at all).
    final baseBackground =
        !model.ghost &&
            !_cameraSummaryRow &&
            model.exposureState.isCovered &&
            !(celHasContentForLayer?.call(layer, frameIndex) ?? true)
        ? timelineEmptyCelPaperColor(paper)
        : styleColors.background;
    // D32/D38 (2026-08-18): the per-cell BORDER is gone. It existed to be
    // the seams ("the paper blocks' seams all sit on the shared faint
    // alpha" — UI-R20 #7 already killed the strong start edge), and as a
    // full rect per covered cell it double-stroked every interior seam,
    // ignored the grid cadence, and wore a different weight than the
    // empty-space line. The seams are [heldSeamLineFor] now — ONE line per
    // interior boundary, the grid-line LAW's cadence/strength, multiplied
    // onto this block's own paper. The rounded caps live in the fill.
    // Nothing here asks where the cut ends any more: the out-of-cut wash is
    // one rect in its own overlay ([TimelineOutsideCutWashPainter]), which
    // is what lets it follow a live drag while these tiles stay baked.
    return (
      background: baseBackground,
      border: Colors.transparent,
      radius: _cellRadius(model.segment),
    );
  }

  /// D32/D38: the block-interior seam line at [frameIndex]'s LEADING
  /// boundary, or null — the grid-line law consulted INSIDE blocks.
  ///
  /// Non-null only when the boundary is interior to a run (the cell
  /// continues from the previous one) and the law's cadence shows a line
  /// there at this zoom. The ink is the law line channel-multiplied onto
  /// this cell's own painted ground ([timelineGridLineInkOnGround]), so a
  /// 6f/second beat keeps its stronger line THROUGH the paper and the
  /// zoom that thins the empty-space 1f lines thins these identically.
  ///
  /// PUBLIC contract shared by paint() and the tile emitter (the
  /// probe-the-painter rule): both draw exactly this rect in this colour,
  /// so the baked and classic passes cannot drift.
  ({Rect rect, Color color})? heldSeamLineFor(int frameIndex) {
    final model = cellModelAt(frameIndex);
    if (model.ghost ||
        _cameraSummaryRow ||
        !model.segment.isBlock ||
        !model.segment.continuesFromPrevious) {
      return null;
    }
    final ink = timelineFrameBoundaryLineInk(
      frameIndex: frameIndex,
      frameCellExtent: frameCellExtent,
      framesPerSecond: framesPerSecond,
      colorScheme: colorScheme,
    );
    if (ink == null) {
      return null;
    }
    final rect = cellRectFor(frameIndex);
    final ground = resolvedCellStyleFor(frameIndex).background;
    final color = timelineGridLineInkOnGround(ink, ground);
    final width = ink.strokeWidth;
    return (
      rect: axis == Axis.horizontal
          ? Rect.fromLTWH(
              rect.left + timelineGridLineSnap - width / 2,
              rect.top,
              width,
              rect.height,
            )
          : Rect.fromLTWH(
              rect.left,
              rect.top + timelineGridLineSnap - width / 2,
              rect.width,
              width,
            ),
      color: color,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    _passModels = {};
    try {
      _paint(canvas, size);
    } finally {
      _passModels = null;
    }
  }

  void _paint(Canvas canvas, Size size) {
    // Self-windowing (UI-R15): only the cells under the live viewport
    // record — a scroll is a repaint of this thin pass, never a rebuild.
    final window = visibleFrameWindow();
    final store = tileStore;
    // Spans whose FRESH tile already carries the foreground ink (T3):
    // the Dart glyph/dash pass skips them.
    final tiledSpans = <(int, int)>[];
    if (store == null || frameCellExtent <= 0) {
      for (
        var frameIndex = window.startIndex;
        frameIndex < window.endIndexExclusive;
        frameIndex += 1
      ) {
        _paintCellSubstrate(canvas, frameIndex);
      }
    } else {
      // TILE substrate pass (UI-R18 O7 T2): the span grid rides the
      // SHARED window policy — a fresh tile is one drawImageRect; a
      // cold/stale span keeps the classic paint underneath (no flash)
      // while its raster lands off-frame.
      final span = timelineFrameWindowSpanFor(frameCellExtent);
      final tilePaint = Paint()..filterQuality = FilterQuality.low;
      var tile = window.startIndex < 0 ? 0 : window.startIndex ~/ span;
      for (; tile * span < window.endIndexExclusive; tile += 1) {
        final spanStart = tile * span;
        final spanEnd = math.min(spanStart + span, frameEndIndexExclusive);
        if (spanEnd <= spanStart) {
          continue;
        }
        final image = store.tileFor(
          painter: this,
          spanStartIndex: spanStart,
          spanEndIndexExclusive: spanEnd,
          devicePixelRatio: devicePixelRatio,
        );
        if (image != null) {
          final origin = cellRectFor(spanStart);
          final mainExtent = (spanEnd - spanStart) * frameCellExtent;
          final dst = axis == Axis.horizontal
              ? Rect.fromLTWH(origin.left, 0, mainExtent, crossAxisExtent)
              : Rect.fromLTWH(0, origin.top, crossAxisExtent, mainExtent);
          canvas.drawImageRect(
            image,
            Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            ),
            dst,
            tilePaint,
          );
          tiledSpans.add((spanStart, spanEnd));
          continue;
        }
        final fallbackStart = math.max(spanStart, window.startIndex);
        final fallbackEnd = math.min(spanEnd, window.endIndexExclusive);
        for (var frame = fallbackStart; frame < fallbackEnd; frame += 1) {
          _paintCellSubstrate(canvas, frame);
        }
      }
      // PREFETCH one span beyond both window edges (scroll warm-up):
      // requesting is enough — the raster lands before the crossing
      // reveals it, so steady scrolling never hits the fallback.
      for (final neighbor in [
        (window.startIndex ~/ span) - 1,
        tile, // one past the loop's last drawn tile
      ]) {
        final spanStart = neighbor * span;
        final spanEnd = math.min(spanStart + span, frameEndIndexExclusive);
        if (spanStart < 0 || spanEnd <= spanStart) {
          continue;
        }
        store.tileFor(
          painter: this,
          spanStartIndex: spanStart,
          spanEndIndexExclusive: spanEnd,
          devicePixelRatio: devicePixelRatio,
        );
      }
    }
    for (
      var frameIndex = window.startIndex;
      frameIndex < window.endIndexExclusive;
      frameIndex += 1
    ) {
      var tiled = false;
      for (final span in tiledSpans) {
        if (frameIndex >= span.$1 && frameIndex < span.$2) {
          tiled = true;
          break;
        }
      }
      if (tiled) {
        continue;
      }
      _paintCellForeground(canvas, frameIndex);
    }

    // The 6f/24f beat lines moved to ONE grid-wide overlay
    // (TimelineBeatLinesPainter, UI-R13 #7) so they span every row —
    // SE, camera and lane rows included — not just the painterized
    // drawing rows.
  }

  /// The cell's dense, mostly-static part: the paper-block fill and its
  /// border — what the substrate TILES rasterize (the emitter probes the
  /// same style/geometry, so the two paths cannot drift).
  void _paintCellSubstrate(Canvas canvas, int frameIndex) {
    final style = resolvedCellStyleFor(frameIndex);
    var background = style.background;
    var borderColor = style.border;

    if (chromeless) {
      // Empty paper simply is not there — that is what 「바탕색은 싹 없애고」
      // means, and it is the difference between a row laid ON the artwork and
      // a row with a panel behind it. A covered cell keeps a body, thinned,
      // so a block still reads as paper.
      final covered = cellModelAt(frameIndex).exposureState.isCovered;
      if (!covered) {
        return;
      }
      // The block keeps its OWN colours here. The row's translucency is one
      // value on the overlay root now, so thinning a second time inside the
      // cell would compound with it — and it was that second thinning, at two
      // different strengths, that made the folded row a look of its own
      // rather than the open row seen through glass.
    }

    final rect = cellRectFor(frameIndex);
    // D32/D38: the interior seam — ONE law line at the leading boundary,
    // multiplied onto this block's paper. Drawn after the fill below.
    final seam = heldSeamLineFor(frameIndex);
    // Border.all paints INSIDE the box: stroke centered half a pixel in.
    final borderRect = rect.deflate(0.5);
    final radius = style.radius;
    final fillPaint = Paint();
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    if (radius == null) {
      canvas.drawRect(rect, fillPaint..color = background);
      if (borderColor.a > 0) {
        canvas.drawRect(borderRect, borderPaint..color = borderColor);
      }
    } else {
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: radius.topLeft,
          topRight: radius.topRight,
          bottomLeft: radius.bottomLeft,
          bottomRight: radius.bottomRight,
        ),
        fillPaint..color = background,
      );
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          borderRect,
          topLeft: radius.topLeft,
          topRight: radius.topRight,
          bottomLeft: radius.bottomLeft,
          bottomRight: radius.bottomRight,
        ),
        borderPaint..color = borderColor,
      );
    }
    if (seam != null) {
      canvas.drawRect(seam.rect, fillPaint..color = seam.color);
    }
  }

  /// The cell's foreground INK — ghost glyphs read quiet near-white,
  /// drawing cels use the paper ink, X marks and dim variants mute
  /// (UI-R11 #5). PUBLIC: the tile emitter (T3) tints glyph blits with
  /// exactly this, so tiles cannot drift from the classic pass.
  Color foregroundInkFor(TimelineRowCellModel model) {
    final isEmptyX = model.exposureState == TimelineCellExposureState.uncovered;
    // Camera key-summary markers read like the lane key diamonds (UI-R24
    // #9): the frame-block WHITE body — selection speaks through the accent
    // outline layers, not the glyph. Dimmed outside the playback range.
    if (_cameraSummaryRow && model.exposureState.isCovered) {
      return timelineDrawingStartColor.withValues(
        alpha: model.dimmed ? 0.55 : 1,
      );
    }
    return model.ghost
        ? colorScheme.onSurface.withValues(alpha: 0.85)
        : timelineCellUsesDrawingInk(model.exposureState)
        ? (model.dimmed
              ? timelineDrawingInkColor.withValues(alpha: 0.55)
              : timelineDrawingInkColor)
        : isEmptyX
        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.55)
        : model.dimmed
        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.45)
        : colorScheme.onSurface;
  }

  /// The glyph's resolved text style (ink + the bold rule) — the shared
  /// glyph cache and the tile emitter's bake key both read this.
  ///
  /// Deliberately a PLAIN fill (#15's one deviation, unchanged through the
  /// difference-blend round and its ground-law successor, 2026-08-17): the
  /// tile emitter bakes cell glyphs as single-tint A8 coverage, which
  /// carries one flat color and no blend, and special-casing only the
  /// classic pass would break the classic↔tile swap parity. These glyphs
  /// sit INSIDE the paper blocks, where this ink already reads.
  TextStyle glyphStyleFor(TimelineRowCellModel model) {
    final isEmptyX = model.exposureState == TimelineCellExposureState.uncovered;
    return baseTextStyle.copyWith(
      color: foregroundInkFor(model),
      // R26 #38/#4: names and marks SHRINK with the cell instead of
      // blanking out below ~14px — "절대 안 사라지도록". #15 adds the
      // vertical half: a squeezed row shrinks them the same way.
      fontSize: timelineFittedGlyphFontSize(
        baseTextStyle.fontSize ?? 12,
        frameCellExtent,
        crossExtent: crossAxisExtent,
      ),
      fontWeight:
          !model.ghost &&
              !isEmptyX &&
              model.exposureState != TimelineCellExposureState.held
          ? FontWeight.bold
          : baseTextStyle.fontWeight,
    );
  }

  /// The cell's sparse foreground ink (hold dashes, glyph text) — the
  /// classic pass; tile mode bakes the same content into the tiles (T3)
  /// and skips this for covered spans.
  void _paintCellForeground(Canvas canvas, int frameIndex) {
    final model = cellModelAt(frameIndex);
    if (model.glyph.isEmpty) {
      return;
    }
    final rect = cellRectFor(frameIndex);
    {
      final ink = foregroundInkFor(model);
      if (model.ghost && model.glyph == _holdDashGlyph) {
        // UI-R12 #18: the hold dash is a PAINTED line along the frame
        // axis, spanning nearly the whole cell — neighbors read as one
        // continuing stroke, with a deliberate 3px break per boundary so
        // it never fuses into a solid rule (user: 이어진 느낌, 완벽하게는
        // 안 이어지게). The text glyph was too short to chain.
        final dashPaint = Paint()
          ..color = ink
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round;
        if (axis == Axis.horizontal) {
          if (rect.width > 4) {
            canvas.drawLine(
              Offset(rect.left + 1.5, rect.center.dy),
              Offset(rect.right - 1.5, rect.center.dy),
              dashPaint,
            );
          }
        } else if (rect.height > 4) {
          canvas.drawLine(
            Offset(rect.center.dx, rect.top + 1.5),
            Offset(rect.center.dx, rect.bottom - 1.5),
            dashPaint,
          );
        }
        return;
      }
      final glyph = _glyphPainter(model.glyph, glyphStyleFor(model));
      // Snap the draw to the PHYSICAL pixel grid (UI-R20 #6): the tile
      // path blits glyphs at integer physical positions, so the classic
      // pass must land on the same grid — otherwise the classic↔tile
      // swap on row activation reads as the text thinning/thickening.
      final raw = rect.center - Offset(glyph.width / 2, glyph.height / 2);
      final dpr = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
      glyph.paint(
        canvas,
        Offset(
          (raw.dx * dpr).roundToDouble() / dpr,
          (raw.dy * dpr).roundToDouble() / dpr,
        ),
      );
    }
  }

  BorderRadius? _cellRadius(TimelineExposureBlockVisualSegment segment) {
    if (!segment.isBlock) {
      return null;
    }
    const blockRadius = timelineBlockCornerRadius;
    final startRadius = segment.continuesFromPrevious
        ? Radius.zero
        : blockRadius;
    final endRadius = segment.continuesToNext ? Radius.zero : blockRadius;
    return switch (axis) {
      Axis.horizontal => BorderRadius.horizontal(
        left: startRadius,
        right: endRadius,
      ),
      Axis.vertical => BorderRadius.vertical(
        top: startRadius,
        bottom: endRadius,
      ),
    };
  }

  @override
  bool shouldRepaint(covariant TimelineRowCellsPainter oldDelegate) =>
      // Geometry is absent on purpose: it arrives through `repaint`, and a
      // rebuilt-but-identical painter must not re-record on its account.
      //
      // Value-compared, never `identical`: a same-receiver tear-off is a
      // FRESH object every build but compares equal, and `AnimatedTheme`
      // hands out a new ColorScheme instance per build — under `!identical`
      // both read as "changed" and this painter re-recorded on every
      // rebuild it saw (the churn that hid in the rulers, F2).
      !identical(oldDelegate.layer, layer) ||
      // ㉘: and what the row's coverage follows, for the rows whose
      // coverage is not on their layer. Value-compared like the rest —
      // a TransformTrack with one more key is a different value.
      oldDelegate.coverageIdentity != coverageIdentity ||
      oldDelegate.crossAxisExtent != crossAxisExtent ||
      oldDelegate.axis != axis ||
      !identical(oldDelegate.windowBucket, windowBucket) ||
      oldDelegate.viewportMainExtent != viewportMainExtent ||
      oldDelegate.colorScheme != colorScheme ||
      oldDelegate.exposureStateForLayer != exposureStateForLayer ||
      oldDelegate.frameNameForLayer != frameNameForLayer ||
      oldDelegate.celHasContentForLayer != celHasContentForLayer ||
      oldDelegate.celContentRevision != celContentRevision ||
      oldDelegate.substrateGeneration != substrateGeneration ||
      !identical(oldDelegate.tileStore, tileStore) ||
      // T16: the ground rule is a painted fact like any other. One row can
      // switch (the collapsed overlay folds and unfolds under a live panel).
      oldDelegate.chromeless != chromeless ||
      oldDelegate.devicePixelRatio != devicePixelRatio;

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
    // One semantics node per NON-EMPTY cell (labels only where content
    // exists), windowed with the paint pass — the per-cell widget tree
    // used to emit these; the painted rows keep the a11y surface without
    // the widget cost.
    final nodes = <CustomPainterSemantics>[];
    final window = visibleFrameWindow();
    for (
      var frameIndex = window.startIndex;
      frameIndex < window.endIndexExclusive;
      frameIndex += 1
    ) {
      final label = cellModelAt(frameIndex).semanticsLabel;
      if (label == null) {
        continue;
      }
      nodes.add(
        CustomPainterSemantics(
          rect: cellRectFor(frameIndex),
          properties: SemanticsProperties(
            label: label,
            textDirection: TextDirection.ltr,
          ),
        ),
      );
    }
    return nodes;
  };
}

/// The painted cell strip + its row-level interaction, shared by the
/// horizontal row and the X-sheet column (Axis policy):
/// - raw pointer-down selects the cell under the pointer (instant, the
///   arena never delays it — the TimelineFrameCell contract);
/// - a no-op onTap keeps a tap recognizer in the arena so scroll slop
///   over cells behaves exactly as the widget cells did;
/// - double-tap opens the cell editor.
Widget timelineRowCellsPaintArea({
  required BuildContext context,
  required String keyPrefix,
  required Layer layer,
  required bool active,
  required TimelineFrameGeometryHandle geometry,
  required double crossAxisExtent,
  required Axis axis,
  CustomPainter? foregroundPainter,
  required TimelineCellExposureState Function(Layer layer, int frameIndex)
  exposureStateForLayer,
  String? Function(Layer layer, int frameIndex)? frameNameForLayer,
  TimelineCelContentSource? celContent,
  required ValueChanged<LayerId> onSelectLayer,
  required ValueChanged<int> onSelectFrame,

  /// 🚨T10's second half: the press turned out to be a TAP, so whatever was
  /// selected goes (유저: 「클릭하고 떼면 뭐든 비우게」).
  ///
  /// Separate from the pick because the pick may deliberately NOT clear — a
  /// press landing inside a selection is the start of a MOVE — and
  /// something still has to clear when that press does not become one.
  VoidCallback? onSettledPress,
  void Function(LayerId layerId, int frameIndex)? onActivateCell,
  ValueListenable<int>? windowBucket,
  double viewportMainExtent = 0,
  Object? coverageIdentity,
  String substrateGeneration = '',
  bool chromeless = false,
  int framesPerSecond = 24,
}) {
  final painter = TimelineRowCellsPainter(
    layer: layer,
    geometry: geometry,
    crossAxisExtent: crossAxisExtent,
    exposureStateForLayer: exposureStateForLayer,
    frameNameForLayer: frameNameForLayer,
    celContent: celContent,
    coverageIdentity: coverageIdentity,
    colorScheme: Theme.of(context).colorScheme,
    baseTextStyle: DefaultTextStyle.of(context).style,
    axis: axis,
    windowBucket: windowBucket,
    viewportMainExtent: viewportMainExtent,
    chromeless: chromeless,
    // Substrate tiles (UI-R18 O7 T2): the app-wide store; it stands down
    // by itself when the native engine is unavailable (tests, web).
    //
    // ⛔A CHROMELESS row does not tile. A tile is a baked picture of the
    // substrate, and the whole point of this mode is that the substrate is
    // mostly absent — one row over the artwork is not worth teaching the
    // bake key a new dimension it would then have to be trusted with. This
    // is one row on screen; the classic pass is the cheap answer here.
    tileStore: chromeless ? null : TimelineGridTileStore.instance,
    substrateGeneration: substrateGeneration,
    devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0,
    framesPerSecond: framesPerSecond,
  );
  // Read LIVE: the row that built this closure survives zoom steps now.
  bool inWindow(int frameIndex) => geometry.value.contains(frameIndex);
  // 🚨T10 — THE ORDER IS LOAD-BEARING. The frame moves first.
  //
  // Standing is what decides whether the selection is cleared, and it makes
  // that decision about the cell being stood ON. The layer callback carries
  // no frame (it is a `ValueChanged<LayerId>` shared with the rail row), so
  // the session reads the playhead — which has to already BE this cell by
  // then, or a press inside a cell selection looks like a press outside it
  // and wipes the very range a move was about to carry. Measured: with
  // these two the other way round, an SE row move stopped committing.
  void select(int frameIndex) {
    onSelectFrame(frameIndex);
    onSelectLayer(layer.id);
  }

  // The frame-block activation law's cell resolver: a position is a cell
  // only inside the visible window. Both halves of the shared double-tap
  // law read THIS one function (R26 #37).
  int? cellAt(Offset localPosition) {
    final frameIndex = painter.frameIndexAt(localPosition);
    return inWindow(frameIndex) ? frameIndex : null;
  }

  // The pick rides the raw pointer, never the arena — see the shared
  // [InstantTapRegion], which R10 lifted out of the two copies the
  // timeline had written of it (this one and TimelineFrameCell's). ㉟ made
  // the policy device-independent: EVERY device picks on the release, and a
  // press that travelled is a drag that picks nothing
  // ([AppInput.timelineCellPressSeeks] carries the why).
  return InstantTapRegion(
    pressSeeksFor: AppInput.timelineCellPressSeeks,
    // R26 #37: remember WHICH cell this press hit, whatever the device —
    // the double-tap recognizer only reports the second tap's position.
    onPressDown: timelineCellDoubleTapRecord(
      layerId: layer.id,
      frameAt: cellAt,
    ),
    onTap: (localPosition) {
      final frameIndex = painter.frameIndexAt(localPosition);
      if (!inWindow(frameIndex)) {
        return;
      }
      // T10: the PICK. Whether it also clears is not decided here — the
      // session's `standOnRow` holds the selection when the press landed
      // inside it, because that press is most likely the start of a move.
      // ⛔The old UI-R10 #12 guard that used to stand at this call site is
      // not coming back: the question belongs where the selection lives, or
      // the next surface to grow a press forgets to ask it.
      select(frameIndex);
    },
    // And when the press turned out to be a tap, the selection goes —
    // 유저: 「클릭하고 떼면 뭐든 비우게」.
    onSettledTap: onSettledPress == null ? null : (_) => onSettledPress(),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      // R26 #37: two taps on DIFFERENT cells of the same block are two
      // seeks, not a rename — the recognizer's 100px slop made them one
      // double tap. The gate ride is the SHARED builder now, so the
      // storyboard's strips and this row cannot answer differently again.
      onDoubleTapDown: onActivateCell == null
          ? null
          : timelineCellDoubleTapActivation(
              layerId: layer.id,
              frameAt: cellAt,
              onActivate: (frameIndex) {
                select(frameIndex);
                onActivateCell(layer.id, frameIndex);
              },
            ),
      onDoubleTap: onActivateCell == null ? null : () {},
      child: RepaintBoundary(
        // The main-axis size arrives from the row's frame-axis box, which
        // wraps this WHOLE row now (the zoom round) rather than just the
        // cells — so the grips, the range gesture layer and this strip all
        // sit in the one constant-size window and a zoom step re-lays-out
        // none of them.
        //
        // The row's PAPER underlay (UI-R21 #2): the surface base and the
        // active-row wash live HERE, row-wide — the cell substrate paints
        // transparent empties and carries no active state, so switching the
        // active layer re-rasters NOTHING (the wash is one ColoredBox on a
        // row that was rebuilding anyway).
        //
        // 🚨…and BOTH are ground, so a chromeless row has neither (⑨,
        // 「블록 뒤에 전체적으로 해당영역에 깔린 바탕색은 없애라니까?」 —
        // 「니까」 because it was confirmed on 2026-08-10 as 「no panel fill,
        // no rail fill, no active-row wash」 and only half of it landed).
        //
        // ★The flag reached the PAINTER and stopped there. That is why the
        // fix for the cells did not show: the empties went transparent and
        // this pair went on covering the artwork behind them, row-wide,
        // which is exactly the shape the user described. Chromeless is a
        // property of the ROW, not of its cells — every layer that draws
        // ground has to read it.
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!chromeless)
              ColoredBox(color: Theme.of(context).colorScheme.surface),
            if (!chromeless && active)
              ColoredBox(
                color: timelineActiveRowWashColor(
                  Theme.of(context).colorScheme,
                ),
              ),
            CustomPaint(
              key: ValueKey<String>('$keyPrefix-row-cells-${layer.id}'),
              painter: painter,
              // The block duration labels ride HERE rather than as their
              // own Positioned.fill CustomPaint: same geometry, same
              // repaint trigger, two fewer render objects per row to lay
              // out on a zoom step. A foreground painter that does not
              // implement `hitTest` never absorbs a pointer, which is what
              // the IgnorePointer around it used to guarantee.
              foregroundPainter: foregroundPainter,
            ),
          ],
        ),
      ),
    ),
  );
}
