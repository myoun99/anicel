import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'frame_window_semantics.dart';

import '../../models/frame.dart' show celNumberOrMark, inbetweenMark;
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/timeline_repeat.dart';
import '../../models/app_input_settings.dart' show AppInput;
import '../widgets/instant_tap_region.dart';
import 'layer_label_controls.dart' show layerMarkColor;
import 'timeline_cell_double_tap.dart';
import 'timeline_cel_content_source.dart';
import 'timeline_cell_exposure_state.dart';
import 'timeline_cell_marker.dart';
import 'timeline_instruction_row_visual.dart' show bandExposureState;
import 'timeline_beat_lines.dart'
    show TimelineGridLaw, timelineGridGroundOver, timelineRowPaperExtent;
import 'timeline_cell_style.dart';
import 'timeline_exposure_block_visual.dart';
import 'timeline_frame_geometry.dart';
import 'timeline_frame_window.dart';
import 'timeline_glyph_cache.dart';
import 'timeline_grid_tile_store.dart';
import '../effective_device_pixel_ratio.dart';
import '../repaint_props.dart';
import 'memo_token.dart';
import 'timeline_tile_raster_source.dart';

const String _holdDashGlyph = timelineHoldDashGlyph;

/// Glyph TextPainters come from the shared timeline cache (UI-R16):
/// frame numbers and markers repeat heavily across rows and repaints.
TextPainter _glyphPainter(String text, TextStyle style) =>
    timelineGlyphPainter(text, style);

class TimelineRowCellsPainter extends CustomPainter
    with RepaintOnProps
    implements TimelineTileRasterSource {
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
    this.paperGround,
  }) : super(
         repaint: Listenable.merge([
           geometry,
           ?windowBucket,
           ?tileStore?.revision,
           ?celContent?.revision,
         ]),
       );

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
  @override
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
  @override
  final String substrateGeneration;

  /// R26 #44: the unworked-block tint's fact AND its event. Null = no tint.
  final TimelineCelContentSource? celContent;

  @override
  bool Function(Layer layer, int frameIndex)? get celHasContentForLayer =>
      celContent?.hasContent;

  /// Read LIVE, never captured: the whole point is that the row does NOT
  /// rebuild when a cel gains pixels — it repaints — so a value frozen at
  /// construction would hand the tile store yesterday's answer forever and
  /// the baked tile would keep serving the old tint.
  @override
  int get celContentRevision => celContent?.revision.value ?? 0;

  @override
  final Layer layer;

  /// The LIVE frame-axis geometry (R28 #4): read through, never copied, so a
  /// zoom step repaints this painter instead of rebuilding the row that
  /// built it. Every geometry getter below reads `geometry.value`.
  final TimelineFrameGeometryHandle geometry;

  int get frameStartIndex => geometry.value.frameStartIndex;
  int get frameEndIndexExclusive => geometry.value.frameEndIndexExclusive;
  double get leadingFrameSpacerWidth => geometry.value.leadingFrameSpacerWidth;
  @override
  double get frameCellExtent => geometry.value.frameCellExtent;

  @override
  final double crossAxisExtent;
  @override
  final TimelineCellExposureState Function(Layer layer, int frameIndex)
  exposureStateForLayer;
  @override
  final String? Function(Layer layer, int frameIndex)? frameNameForLayer;

  @override
  final ColorScheme colorScheme;

  /// The ambient text style the widget cells inherited (DefaultTextStyle);
  /// glyphs merge color/weight onto it so painted text matches exactly.
  @override
  final TextStyle baseTextStyle;
  @override
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

  /// What this row's paper stands on when nothing stands on the row — the
  /// host's ground ([TimelineGridLaw.ground]); null over the artwork.
  ///
  /// 🚨I-44: the grid sheet UNDER the rows paints their grounds and every
  /// line now, and the rows paint paper alone. An UNWORKED block's paper is
  /// translucent (R26 #44's grey), so it would let the sheet's lines through
  /// — exactly the lines 「블록에 존재하는 그리드선만 싹 삭제」 took off blocks.
  /// So it is pre-blended onto this ground and painted opaque (the cost the
  /// user took with 「합친다 — 그리드 한 장」: on the ACTIVE row the standing
  /// wash no longer shows through an unworked block).
  ///
  /// ⛔Not the row's STANDING ground: that would put the active layer into
  /// the baked tiles, and switching layers would re-bake them — the thing
  /// UI-R21 #2 took the wash out of the cells to stop.
  @override
  final Color? paperGround;

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
  ({int startIndex, int endIndexExclusive}) visibleFrameWindow() =>
      visibleFrameWindowFor(
        bucket: windowBucket,
        viewportMainExtent: viewportMainExtent,
        cellExtent: frameCellExtent,
        frameStartIndex: frameStartIndex,
        frameEndIndexExclusive: frameEndIndexExclusive,
      );

  /// What this row's BAND shows at [frameIndex] — the union for a row that
  /// has both spans and cels, the layer's own cels for everything else.
  ///
  /// ⛔THE ONE READ SITE, and that is the point. The choice used to be made
  /// by an identical ternary in `timeline_frame_cells_row` AND in
  /// `timeline_frame_cursor_layer`, which is what a range selection
  /// measures — so a row could DRAW a block it would not SELECT the day the
  /// two drifted ([[no-copy-to-share]]).
  TimelineCellExposureState _stateAt(int frameIndex) =>
      bandExposureState(layer, frameIndex, ownCels: exposureStateForLayer);

  /// The cell's rect in the ROW's local coordinates — the probe geometry
  /// tests and the row's hit-testing share (single source of truth).
  @override
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
  @override
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
    final emptyRunStart = timelineEmptyRunStartsAt(
      current: exposureState,
      previous: timelineCellStateBefore(
        frameIndex: frameIndex,
        stateAt: _stateAt,
      ),
    );
    final frameName = frameNameForLayer?.call(layer, frameIndex);
    // Hold ghosts keep their dash at ANY zoom (it paints as a line, not
    // text — UI-R12 #18): the continuing stroke is structure, so it never
    // joins the narrow-cell text suppression below.
    final holdGhost =
        runEdgeGhostAt(layer, frameIndex)?.mode == TimelineRunEdgeMode.hold;
    String glyph;
    if (holdGhost) {
      glyph = _holdDashGlyph;
    } else if (ghost) {
      // Ghosts are TEXT-ONLY (UI-R10 #11): a repeat ghost prints just the
      // cel names, exactly like before — the SHEET alone carries the
      // repeat-word convention (UI-R14 #3 rolled the timeline back).
      glyph = switch (exposureState) {
        TimelineCellExposureState.drawingStart =>
          celNumberOrMark(frameName),
        TimelineCellExposureState.markHeld ||
        TimelineCellExposureState.markUncovered => inbetweenMark,
        _ => '',
      };
    } else {
      glyph = timelineCellMarker(
        layer: layer,
        exposureState: exposureState,
        emptyRunStart: emptyRunStart,
        frameName: frameName,
      );
    }
    return TimelineRowCellModel(
      frameIndex: frameIndex,
      exposureState: exposureState,
      segment: timelineExposureBlockSegmentAt(
        frameIndex: frameIndex,
        stateAt: _chromeStateAt,
      ),
      ghost: ghost,
      // GHOSTS only. "Outside the cut" used to dim here too, and that is
      // what tied this baked layer to the cut's length — the wash is its
      // own overlay now, above the cells, so it can follow a drag without
      // re-baking a single tile.
      dimmed: ghost,
      glyph: glyph,
      semanticsLabel: timelineCellSemanticsLabel(
        layerKind: layer.kind,
        exposureState: exposureState,
        frameName: frameName,
      ),
    );
  }

  /// The cell's RESOLVED paint style (dim blends, band tint, block
  /// radius) — what paint() draws and what tests assert against (the
  /// successor of reading the widget cell's BoxDecoration).
  @override
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
    // block chrome at all). I-44: onto [paperGround], so the grid sheet
    // under the row cannot show through it.
    final baseBackground =
        !model.ghost &&
            !_cameraSummaryRow &&
            model.exposureState.isCovered &&
            !(celHasContentForLayer?.call(layer, frameIndex) ?? true)
        ? timelineGridGroundOver(
            under: paperGround,
            painted: timelineEmptyCelPaperColor(paper),
          )!
        : styleColors.background;
    // D32/D38 (2026-08-18): the per-cell BORDER is gone. It existed to be
    // the seams ("the paper blocks' seams all sit on the shared faint
    // alpha" — UI-R20 #7 already killed the strong start edge), and as a
    // full rect per covered cell it double-stroked every interior seam,
    // ignored the grid cadence, and wore a different weight than the
    // empty-space line. The rounded caps live in the fill.
    // 🚨I-44: and the seams went after it — a block carries no line at all
    // now (「블록에 존재하는 그리드선만 싹 삭제」); the grid sheet under the
    // row is the only thing that draws one.
    // Nothing here asks where the cut ends any more: the out-of-cut wash is
    // one rect in its own overlay ([TimelineOutsideCutWashPainter]), which
    // is what lets it follow a live drag while these tiles stay baked.
    return (
      background: baseBackground,
      border: Colors.transparent,
      radius: timelineCellBorderRadius(
        model.segment,
        axis,
        cellExtent: frameCellExtent,
        crossExtent: timelineRowPaperExtent(crossAxisExtent),
      ),
    );
  }

  /// The cell's PAPER — its rect short of the row seam at the trailing
  /// cross edge ([timelineRowPaperExtent]), which the grid sheet draws under
  /// the row and the paper must leave showing.
  ///
  /// PUBLIC contract shared by paint() and the tile emitter (the
  /// probe-the-painter rule): both fill exactly this box.
  @override
  Rect paperRectFor(int frameIndex) {
    final cell = cellRectFor(frameIndex);
    final paper = timelineRowPaperExtent(crossAxisExtent);
    return axis == Axis.horizontal
        ? Rect.fromLTWH(cell.left, cell.top, cell.width, paper)
        : Rect.fromLTWH(cell.left, cell.top, paper, cell.height);
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
      tiledSpans.addAll(_paintTiledSubstrate(canvas, window, store));
    }
    _paintForegrounds(canvas, window, tiledSpans);

    // No line is drawn here: the 6f/24f beats went to ONE grid-wide
    // overlay (UI-R13 #7) so they span every row, and with I-44 every
    // other line and the row's ground followed them into that one grid
    // sheet ([TimelineGridSheetPainter]).
  }

  /// The substrate through the tile store: a fresh tile is one
  /// drawImageRect, a cold or stale span keeps the classic paint
  /// underneath while its raster lands off-frame, and the two spans past
  /// the window are asked for so a scroll finds them warm. Answers the
  /// spans whose fresh tile already carries the foreground ink.
  List<(int, int)> _paintTiledSubstrate(
    Canvas canvas,
    ({int startIndex, int endIndexExclusive}) window,
    TimelineGridTileStore store,
  ) {
    final tiledSpans = <(int, int)>[];
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
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          dst,
          tilePaint,
        );
        tiledSpans.add((spanStart, spanEnd));
        continue;
      }
      final fallbackStart = math.max(spanStart, window.startIndex);
      final fallbackEnd = math.min(spanEnd, window.endIndexExclusive);
      for (var frame = fallbackStart; frame < fallbackEnd; frame += 1) {
        // ⛔This call was lost once, silently: `a055c51a`(2026-09-04) — a
        // commit about the accessibility sentence and the corner radius —
        // swapped it for an empty `/*P4*/` marker, the shape of a mutant
        // from that day's mutation campaign committed by accident. Every
        // zoom step that crossed a span boundary then drew no block paper
        // for a frame (F-94). `a_row_paints_its_substrate_and_its_glyphs_
        // test` pins it now, with the engine on and the store cold.
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
    return tiledSpans;
  }

  /// The Dart glyph/dash pass over every cell in [window] whose span no
  /// fresh tile covers (T3: a tiled span already carries its ink).
  ///
  /// F-96: a word grows on past its cell, so each untiled stretch also lays
  /// the word that grows into it from before ([wordCellBefore]), and paints
  /// under a clip of its own extent — a word that also lives in a tile is
  /// never inked twice: the tile holds its part, this pass the rest.
  void _paintForegrounds(
    Canvas canvas,
    ({int startIndex, int endIndexExclusive}) window,
    List<(int, int)> tiledSpans,
  ) {
    var from = window.startIndex;
    for (final span in [
      ...tiledSpans,
      (window.endIndexExclusive, window.endIndexExclusive),
    ]) {
      final to = math.min(span.$1, window.endIndexExclusive);
      if (to > from) {
        _paintUntiledForegrounds(canvas, from, to);
      }
      from = math.max(from, span.$2);
    }
  }

  /// One untiled stretch [from, to) of [_paintForegrounds].
  void _paintUntiledForegrounds(Canvas canvas, int from, int to) {
    final first = cellRectFor(from);
    final past = cellRectFor(to);
    canvas.save();
    canvas.clipRect(
      axis == Axis.horizontal
          ? Rect.fromLTRB(first.left, 0, past.left, crossAxisExtent)
          : Rect.fromLTRB(0, first.top, crossAxisExtent, past.top),
    );
    final lead = wordCellBefore(from);
    if (lead != null) {
      _paintCellForeground(canvas, lead);
    }
    for (var frameIndex = from; frameIndex < to; frameIndex += 1) {
      _paintCellForeground(canvas, frameIndex);
    }
    canvas.restore();
  }

  /// The cell's dense, mostly-static part: the paper-block fill and its
  /// border — what the substrate TILES rasterize (the emitter probes the
  /// same style and paper box, so the two paths cannot drift).
  void _paintCellSubstrate(Canvas canvas, int frameIndex) {
    final style = resolvedCellStyleFor(frameIndex);
    final background = style.background;
    final borderColor = style.border;
    // UI-R21 #2: an empty cell paints NOTHING — its ground, and every line
    // on it, is the grid sheet's under the row (I-44).
    if (background.a <= 0 && borderColor.a <= 0) {
      return;
    }
    final rect = paperRectFor(frameIndex);
    // Border.all paints INSIDE the box: stroke centered half a pixel in.
    final borderRect = rect.deflate(0.5);
    final radius = style.radius;
    final fillPaint = Paint()..color = background;
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = borderColor;
    if (radius == null) {
      canvas.drawRect(rect, fillPaint);
      if (borderColor.a > 0) {
        canvas.drawRect(borderRect, borderPaint);
      }
      return;
    }
    RRect rounded(Rect box) => RRect.fromRectAndCorners(
      box,
      topLeft: radius.topLeft,
      topRight: radius.topRight,
      bottomLeft: radius.bottomLeft,
      bottomRight: radius.bottomRight,
    );
    canvas.drawRRect(rounded(rect), fillPaint);
    if (borderColor.a > 0) {
      canvas.drawRRect(rounded(borderRect), borderPaint);
    }
  }

  /// The cell's foreground INK — ghost glyphs read quiet near-white,
  /// drawing cels use the paper ink, X marks and dim variants mute
  /// (UI-R11 #5). PUBLIC: the tile emitter (T3) tints glyph blits with
  /// exactly this, so tiles cannot drift from the classic pass.
  @override
  Color foregroundInkFor(TimelineRowCellModel model) {
    final isEmptyX = model.exposureState == TimelineCellExposureState.uncovered;
    // 🪦The camera summary's own ink went with the glyph it tinted: since
    // B4 that row prints no text at all — its keys are the shared lane key
    // markers, drawn as span overlays — so nothing asked this any more.
    return model.ghost
        ? colorScheme.onSurface.withValues(alpha: 0.85)
        : timelineCellUsesDrawingInk(model.exposureState)
        // F-24: the same ink the block's 코마 number takes.
        ? timelineInBlockInk(dimmed: model.dimmed)
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
  @override
  TextStyle glyphStyleFor(TimelineRowCellModel model) {
    final isEmptyX = model.exposureState == TimelineCellExposureState.uncovered;
    // The block's word, printed the one way ([timelineBlockWordStyle] —
    // the lane key's name goes through the same function).
    return timelineBlockWordStyle(
      baseTextStyle,
      ink: foregroundInkFor(model),
      // R26 #38/#4: names and marks SHRINK with the cell instead of
      // blanking out below ~14px — "절대 안 사라지도록". #15 adds the
      // vertical half: a squeezed row shrinks them the same way.
      fontSize: timelineFittedGlyphFontSize(
        baseTextStyle.fontSize ?? 12,
        frameCellExtent,
        crossExtent: crossAxisExtent,
      ),
      bold:
          !model.ghost &&
          !isEmptyX &&
          model.exposureState != TimelineCellExposureState.held,
    );
  }

  /// Where the word of the cell at [frameIndex] is laid, row-local: along
  /// the frame axis by the block-word law — a name that outgrows its cell
  /// starts at the cell and grows on into its block (F-96,
  /// [timelineBlockWordStart]) — and centred across it. PUBLIC: the tile
  /// emitter bakes its word exactly here.
  @override
  Offset cellWordOriginFor(int frameIndex, Size word) {
    final cell = cellRectFor(frameIndex);
    return axis == Axis.horizontal
        ? Offset(
            timelineBlockWordStart(
              cellStart: cell.left,
              cellExtent: cell.width,
              wordExtent: word.width,
              growth: TimelineBlockWordGrowth.towardBlockEnd,
            ),
            cell.center.dy - word.height / 2,
          )
        : Offset(
            cell.center.dx - word.width / 2,
            timelineBlockWordStart(
              cellStart: cell.top,
              cellExtent: cell.height,
              wordExtent: word.height,
              growth: TimelineBlockWordGrowth.towardBlockEnd,
            ),
          );
  }

  /// The nearest cell before [frameIndex] that writes a WORD, or null when
  /// the nearest writing is a hold dash or there is none — the word that may
  /// grow into [frameIndex]'s cell from before it (F-96). PUBLIC: the
  /// classic pass lays it at the start of what it paints, the tile emitter
  /// at the start of a tile.
  @override
  int? wordCellBefore(int frameIndex) {
    for (var index = frameIndex - 1; index >= frameStartIndex; index -= 1) {
      final model = cellModelAt(index);
      if (model.glyph.isEmpty) {
        continue;
      }
      return model.ghost && model.glyph == _holdDashGlyph ? null : index;
    }
    return null;
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
      // F-96: centred while the word fits its cell, growing on into the
      // block when it does not ([cellWordOriginFor]).
      final raw = cellWordOriginFor(frameIndex, glyph.size);
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

  @override
  // Geometry is absent on purpose: it arrives through `repaint`, and a
  // rebuilt-but-identical painter must not re-record on its account.
  //
  // Value-compared, never `identical`: a same-receiver tear-off is a
  // FRESH object every build but compares equal, and `AnimatedTheme`
  // hands out a new ColorScheme instance per build — under `!identical`
  // both read as "changed" and this painter re-recorded on every
  // rebuild it saw (the churn that hid in the rulers, F2). Every field
  // below that is NOT wrapped in `ByIdentity` is value-compared for that
  // reason.
  Object get props => (
    ByIdentity(layer),
    // ㉘: and what the row's coverage follows, for the rows whose
    // coverage is not on their layer. Value-compared like the rest —
    // a TransformTrack with one more key is a different value.
    coverageIdentity,
    crossAxisExtent,
    axis,
    ByIdentity(windowBucket),
    viewportMainExtent,
    colorScheme,
    exposureStateForLayer,
    frameNameForLayer,
    celHasContentForLayer,
    celContentRevision,
    substrateGeneration,
    ByIdentity(tileStore),
    // I-44: what the unworked paper is pre-blended onto is a painted fact
    // like any other (a theme change moves it).
    paperGround,
    devicePixelRatio,
  );

  // One semantics node per NON-EMPTY cell (labels only where content
  // exists), windowed with the paint pass — the per-cell widget tree
  // used to emit these; the painted rows keep the a11y surface without
  // the widget cost.
  @override
  SemanticsBuilderCallback get semanticsBuilder =>
      (size) => frameWindowSemantics(
        window: visibleFrameWindow(),
        rectFor: cellRectFor,
        labelFor: (frameIndex) => cellModelAt(frameIndex).semanticsLabel,
      );
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
    // Substrate tiles (UI-R18 O7 T2): the app-wide store; it stands down
    // by itself when the native engine is unavailable (tests, web).
    //
    // ↩️T16 kept the folded row off the tiles: its mode dropped the empties,
    // the ground and the seams, and one row over the artwork was not worth
    // teaching the bake key that dimension. I-44 took all three off EVERY
    // row, and what the paper stands on is [paperGround], which the key
    // carries for every row — so the folded row bakes like the rest.
    tileStore: TimelineGridTileStore.instance,
    substrateGeneration: substrateGeneration,
    devicePixelRatio: EffectiveDevicePixelRatio.of(context),
    // I-44: the HOST's ground, stated once by its law — what an unworked
    // block's paper is pre-blended onto (null over the artwork).
    paperGround: TimelineGridLaw.maybeOf(context)?.ground,
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
        // ⛔NO GROUND HERE (I-44). The row's underlay used to live here —
        // the surface base and the active-row wash as two `ColoredBox`es
        // (UI-R21 #2), and a chromeless row had to be taught to drop both
        // (⑨ 「블록 뒤에 전체적으로 해당영역에 깔린 바탕색은 없애라니까?」).
        // They were opaque, so they buried the grid under the row and every
        // row then owed the grid a redraw (D43-2). The grid sheet paints the
        // rows' grounds now, under all of them, and the row is its paper.
        child: SizedBox.expand(
          child: CustomPaint(
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
        ),
      ),
    ),
  );
}
