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
import 'timeline_cell_double_tap.dart';
import 'timeline_cel_content_source.dart';
import 'timeline_cell_exposure_state.dart';
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
    this.devicePixelRatio = 1.0,
    this.celContent,
  }) : super(
         repaint: Listenable.merge([
           geometry,
           ?windowBucket,
           ?tileStore?.revision,
           ?celContent?.revision,
         ]),
       );

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
      // row-level span overlays; the cells stay glyph-free paper.
      TimelineCellExposureState.drawingStart =>
        layerKindUsesSeSheetCells(layer.kind) ||
                layer.kind == LayerKind.instruction
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
    if (layer.kind == LayerKind.instruction) {
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
    final styleColors = timelineCellStyleColors(
      colorScheme: colorScheme,
      exposureState: model.ghost || _cameraSummaryRow
          ? TimelineCellExposureState.uncovered
          : model.exposureState,
      selected: false,
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
        ? timelineEmptyCelBlockColor
        : styleColors.background;
    // Blocks keep their chrome (start edge strong, held seams faint per
    // UI-R18 #8); the PLAIN grid draws NOTHING here — the grid-wide
    // overlay owns every per-cell line now (UI-R18 #2: the grid is
    // always there, lanes and all).
    // Nothing here asks where the cut ends any more: the out-of-cut wash is
    // one rect in its own overlay ([TimelineOutsideCutWashPainter]), which
    // is what lets it follow a live drag while these tiles stay baked.
    return (
      background: baseBackground,
      border: model.segment.isBlock ? styleColors.border : Colors.transparent,
      radius: _cellRadius(model.segment),
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
    final background = style.background;
    final borderColor = style.border;

    final rect = cellRectFor(frameIndex);
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
  /// Deliberately NOT outlined (#15's one deviation): the tile emitter
  /// bakes cell glyphs as single-tint A8 coverage, which cannot carry a
  /// two-color outline+fill, and outlining only the classic pass would
  /// break the classic↔tile swap parity. These glyphs sit on the
  /// near-white paper blocks, where the bright outline is invisible
  /// anyway — the rule's own rationale for being one rule.
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
    const blockRadius = Radius.circular(6);
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
      oldDelegate.crossAxisExtent != crossAxisExtent ||
      oldDelegate.axis != axis ||
      !identical(oldDelegate.windowBucket, windowBucket) ||
      oldDelegate.viewportMainExtent != viewportMainExtent ||
      oldDelegate.colorScheme != colorScheme ||
      oldDelegate.exposureStateForLayer != exposureStateForLayer ||
      oldDelegate.frameNameForLayer != frameNameForLayer ||
      oldDelegate.celHasContentForLayer != celHasContentForLayer ||
      oldDelegate.celContentRevision != celContentRevision ||
      !identical(oldDelegate.tileStore, tileStore) ||
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
  void Function(LayerId layerId, int frameIndex)? onActivateCell,
  bool Function(int frameIndex)? suppressPointerDownSelect,
  ValueListenable<int>? windowBucket,
  double viewportMainExtent = 0,
}) {
  final painter = TimelineRowCellsPainter(
    layer: layer,
    geometry: geometry,
    crossAxisExtent: crossAxisExtent,
    exposureStateForLayer: exposureStateForLayer,
    frameNameForLayer: frameNameForLayer,
    celContent: celContent,
    colorScheme: Theme.of(context).colorScheme,
    baseTextStyle: DefaultTextStyle.of(context).style,
    axis: axis,
    windowBucket: windowBucket,
    viewportMainExtent: viewportMainExtent,
    // Substrate tiles (UI-R18 O7 T2): the app-wide store; it stands down
    // by itself when the native engine is unavailable (tests, web).
    tileStore: TimelineGridTileStore.instance,
    devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0,
  );
  // Read LIVE: the row that built this closure survives zoom steps now.
  bool inWindow(int frameIndex) => geometry.value.contains(frameIndex);
  void select(int frameIndex) {
    onSelectLayer(layer.id);
    onSelectFrame(frameIndex);
  }

  // Selection rides the raw pointer, never the arena — see the shared
  // [InstantTapRegion], which R10 lifted out of the two copies the
  // timeline had written of it (this one and TimelineFrameCell's). It
  // carries the whole policy: pen/mouse act on the DOWN, a finger acts on
  // the release if it did not travel (PEN-12 #6), and the timeline's own
  // device gate decides which is which (UI-R23 feedback #2).
  return InstantTapRegion(
    pressSeeksFor: AppInput.timelineCellPressSeeks,
    // R26 #37: remember WHICH cell this press hit, whatever the device —
    // the double-tap recognizer only reports the second tap's position.
    onPressDown: (localPosition) {
      final frameIndex = painter.frameIndexAt(localPosition);
      if (inWindow(frameIndex)) {
        TimelineCellDoubleTapGate.recordTapDown(layer.id, frameIndex);
      }
    },
    onTap: (localPosition) {
      final frameIndex = painter.frameIndexAt(localPosition);
      if (!inWindow(frameIndex)) {
        return;
      }
      // A press INSIDE the frame-range selection initiates a MOVE — it
      // must not re-seek the playhead first (UI-R10 #12).
      if (!(suppressPointerDownSelect?.call(frameIndex) ?? false)) {
        select(frameIndex);
      }
    },
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      onDoubleTapDown: onActivateCell == null
          ? null
          : (details) {
              final frameIndex = painter.frameIndexAt(details.localPosition);
              // R26 #37: two taps on DIFFERENT cells of the same block are
              // two seeks, not a rename — the recognizer's 100px slop made
              // them one double tap.
              if (inWindow(frameIndex) &&
                  TimelineCellDoubleTapGate.acceptsActivation(
                    layer.id,
                    frameIndex,
                  )) {
                select(frameIndex);
                onActivateCell(layer.id, frameIndex);
              }
            },
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
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Theme.of(context).colorScheme.surface),
            if (active)
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
