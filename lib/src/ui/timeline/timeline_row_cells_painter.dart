import 'dart:math' as math;

import 'package:collection/collection.dart' show lowerBound;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'frame_window_semantics.dart';

import '../../models/frame.dart'
    show InbetweenMark, defaultUnnamedDrawingMark, drawingHeadOf;
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/timeline_row_address.dart' show LayerRowAddress;
import '../../models/timeline_repeat.dart';
import '../../models/app_input_settings.dart' show AppInput;
import '../text/word_condensation.dart';
import '../widgets/instant_tap_region.dart';
import '../widgets/named.dart';
import 'axis_turn.dart'
    show
        endAcross,
        endAlong,
        extentAcross,
        extentAlong,
        offsetAlong,
        partAcross,
        partAlong,
        rectAlong,
        sizeAlong,
        startAcross,
        startAlong;
import 'berth_row.dart';
import 'rail_eyes.dart';
import 'layer_label_controls.dart' show layerMarkColor;
import 'timeline_double_tap.dart';
import 'timeline_cel_content_source.dart';
import 'timeline_cell_exposure_state.dart';
import 'timeline_cell_marker.dart';
import 'inbetween_mark_painter.dart';
import 'timeline_instruction_row_visual.dart' show bandExposureState;
import 'timeline_block_look.dart';
import 'timeline_beat_lines.dart'
    show
        TimelineGridLaw,
        timelineBlockFrameLine,
        timelineFrameLineStep,
        timelineRowPaperExtent;
import 'timeline_cell_style.dart';
import 'timeline_exposure_block_visual.dart';
import 'timeline_frame_geometry.dart';
import 'timeline_frame_window.dart';
import '../text/laid_out_glyph.dart';
import 'timeline_glyph_cache.dart';
import 'timeline_grid_metrics.dart' show timelineFirstOnStride;
import 'timeline_grid_tile_store.dart';
import '../effective_device_pixel_ratio.dart';
import '../repaint_props.dart';
import '../text/word_bake.dart' show RepaintOnWordBakes;
import 'memo_token.dart';
import 'timeline_tile_raster_source.dart';

const String _holdGlyph = timelineHoldGlyph;

/// One hold's line over a stretch of a row, row-local: the [box] it fills —
/// as long as the line, as thick as it — and whether each end of it is the
/// hold's OWN end — rounded, and stood in from the cell's edge — or only
/// where the stretch asked for stops, the line running on past it.
typedef TimelineHoldLine = ({
  Rect box,
  bool startsHere,
  bool endsHere,
  Color ink,
});

/// Glyph TextPainters come from the shared timeline cache (UI-R16):
/// frame numbers and markers repeat heavily across rows and repaints.
TextPainter _glyphPainter(
  String text,
  TextStyle style, {
  double tightening = 0,
}) => laidOutGlyph(text, style, tightening: tightening);

/// Where a cell of [layer]'s row can paint differently from the cell before
/// it, ascending — the edges of its STRETCHES: between two edges every cell
/// paints as the one before it, so a row walks a stretch in one step.
/// I-22's ten-minute floor puts ~10,000 frames in a window, and a cut's own
/// frames are a few hundred of them; the rest is one stretch.
///
/// A cell paints its exposure and its two neighbours' (its corners, whether
/// it starts an empty run) and its block's own facts (its cel's name and
/// picture, whether it is a ghost). Those move only where a block starts,
/// where one ends, at a dot, at a span's edges (a band that is spans only
/// paints its spans) and at frame 0, which has no cell before it. Each of
/// those is an edge, and so is the frame on either side of it.
///
/// ⚠️A camera row's keys are not among them: they live on the cut (㉘), and
/// a camera cell PAINTS the same on a key and off one — its keys are the
/// lane key markers (B4). Its exposure state does change inside a stretch,
/// so nothing that reads the state rather than the paint (the semantics)
/// may walk these.
List<int> timelineRowCellEdges(Layer layer) {
  final changes = <int>{0};
  for (final MapEntry(key: start, value: block) in layer.timeline.entries) {
    changes
      ..add(start)
      ..add(start + (block.length ?? 1));
    for (final offset in block.breakdownOffsets) {
      changes.add(start + offset);
    }
  }
  for (final MapEntry(key: from, value: span)
      in layer.instructions.entries) {
    changes
      ..add(from)
      ..add(from + span.length);
  }
  return {
    for (final change in changes) ...[change - 1, change, change + 1],
  }.toList()..sort();
}

class TimelineRowCellsPainter extends CustomPainter
    with RepaintOnProps, RepaintOnWordBakes
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
    this.nextPage,
    this.stepsUntilShown,
    this.tileStore,
    this.substrateGeneration = '',
    this.followsTheLiveCut = true,
    this.devicePixelRatio = 1.0,
    this.celContent,
    this.coverageIdentity,
    this.paperGround,
    this.blockFrameLines = false,
    this.unnamedMark = defaultUnnamedDrawingMark,
    this.framesPerSecond = 0,
    this.shown = true,
  }) : super(
         repaint: Listenable.merge([
           geometry,
           ?windowBucket,
           // Its OWN row's landings — never every row's (I-22 ③).
           ?tileStore?.noticesFor(
             substrateGeneration: substrateGeneration,
             layerId: layer.id,
             axis: axis,
           ),
           // And its OWN row's answers — never every row's when one block
           // turns white (one-cel-turning-white-repaints-every-row).
           ?celContent?.revision.forRow(layer.id),
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

  @override
  final bool followsTheLiveCut;

  /// R26 #44: the unworked-block tint's fact AND its event. Null = no tint.
  final TimelineCelContentSource? celContent;

  @override
  bool Function(Layer layer, int frameIndex)? get celHasContentForLayer =>
      celContent?.hasContent;

  /// Whether a block's cel could not be read — the block goes red.
  ///
  /// ⚠️Not in a baked tile's identity of its own: it comes from the source
  /// [celHasContentForLayer] comes from, which is, and
  /// [celContentRevision] moves whenever it can have changed.
  bool Function(Layer layer, int frameIndex)? get celCannotBeReadForLayer =>
      celContent?.cannotRead;

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

  /// What a cell exposes — and with the cel names and pictures below, it may
  /// change only where [layer]'s blocks, dots and spans do
  /// ([timelineRowCellEdges]): the row walks its cells by stretch (I-22) and
  /// asks a stretch's first cell for all of it. Every host's answers are
  /// read off the layer (a camera row's keys live on the cut, and a camera
  /// cell paints the same on a key and off one).
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

  /// The scroll viewport's main-axis extent for the self-windowing path —
  /// read off the live geometry, so a widened view repaints a kept row
  /// rather than building it again ([TimelineFrameGeometry.viewExtentPx]).
  double get viewportMainExtent => geometry.value.viewExtentPx;

  /// ⛔Not a paint input: it never repaints the row.
  @override
  final TimelineNextPage? Function()? nextPage;

  /// ⛔Not a paint input either: it orders what the store lets go of.
  @override
  final int? Function(int frame)? stepsUntilShown;

  /// The substrate TILE store (UI-R18 O7 T2): with it set, span-sized
  /// pre-rastered images replace the substrate's canvas work —
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

  /// Whether the frame lines cross this row's block paper — the host law's
  /// answer ([TimelineGridLaw], Preferences ▸ Display, 유저 2026-09-24).
  /// Off without a host: the lines are the host grid's, and a row with no
  /// host has no grid to continue.
  @override
  final bool blockFrameLines;

  /// The mark a drawing with no name wears where its block starts — the
  /// host law's answer ([TimelineGridLaw], Preferences ▸ Display, F-489).
  @override
  final InbetweenMark unnamedMark;

  /// The counting fps — which of those lines are SECOND lines.
  @override
  final int framesPerSecond;

  /// Whether the row is shown — its own eye on, and no folder above hiding
  /// it ([RailEye.shown]): a hidden row's blocks wear the switched-off look
  /// its label plate and name wear (I-129). True where nothing says.
  @override
  final bool shown;

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
  /// `timeline_frame_cursor_layer`, whose outline showed the block you stood
  /// in — so a row could DRAW a block it would not outline the day the two
  /// drifted ([[no-copy-to-share]]). The outline went with F-212.
  ///
  /// Read once a pass ([readInOnePass]): a cell's model asks its own state
  /// and both its neighbours', the models beside it ask them again, and a
  /// word's room walks them once more.
  TimelineCellExposureState _stateAt(int frameIndex) {
    final pass = _passStates;
    final read = pass?[frameIndex];
    if (read != null) {
      return read;
    }
    final state = bandExposureState(
      layer,
      frameIndex,
      ownCels: exposureStateForLayer,
    );
    pass?[frameIndex] = state;
    return state;
  }

  /// The cell's rect in the ROW's local coordinates — the probe geometry
  /// tests and the row's hit-testing share (single source of truth).
  @override
  Rect cellRectFor(int frameIndex) {
    final frames = geometry.value;
    final main = frames.edgeAt(frameIndex);
    final extent = frames.edgeAt(frameIndex + 1) - main;
    return rectAlong(
      axis,
      along: (from: main, to: main + extent),
      across: (from: 0, to: crossAxisExtent),
    );
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

  /// The exposure states of the CURRENT pass's cells ([_stateAt]) — the same
  /// lifetime as [_passModels], for the same reason.
  Map<int, TimelineCellExposureState>? _passStates;

  /// Runs [reads] as ONE pass: however often they ask for a cell, it is
  /// resolved once. A paint is one; so is what a tile bakes of a span.
  ///
  /// ⛔Never across an `await`: the resolvers answer from the live session,
  /// which may move between two turns of the event loop.
  @override
  T readInOnePass<T>(T Function() reads) {
    if (_passModels != null) {
      return reads();
    }
    _passModels = {};
    _passStates = {};
    try {
      return reads();
    } finally {
      _passModels = null;
      _passStates = null;
    }
  }

  /// [timelineRowCellEdges] of this painter's layer — found once: a layer
  /// is immutable, and an edited one is a new painter.
  late final List<int> _cellEdges = timelineRowCellEdges(layer);

  /// [from, to) as its stretches, in order, each from [from] or an edge to
  /// the next edge — every cell of one paints as its first.
  Iterable<({int start, int end})> _stretchesIn(int from, int to) sync* {
    var start = from;
    for (
      var edge = lowerBound(_cellEdges, from + 1);
      start < to;
      edge += 1
    ) {
      final end = edge < _cellEdges.length
          ? math.min(_cellEdges[edge], to)
          : to;
      yield (start: start, end: end);
      start = end;
    }
  }

  /// The first cell of the stretch that holds [frameIndex].
  int _stretchStartOf(int frameIndex) =>
      _cellEdges[lowerBound(_cellEdges, frameIndex + 1) - 1];

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
    // A hold ghost writes in no cell: its line is the whole ghost's
    // ([holdLinesIn]). The glyph is what says «a hold» to whoever reads the
    // model ([_isHold]).
    final holdGhost =
        runEdgeGhostAt(layer, frameIndex)?.mode == TimelineRunEdgeMode.hold;
    final TimelineCellWriting writing;
    if (holdGhost) {
      writing = (word: _holdGlyph, mark: null);
    } else if (ghost) {
      // Ghosts are TEXT-ONLY (UI-R10 #11): a repeat ghost prints just the
      // cel names, exactly like before — the SHEET alone carries the
      // repeat-word convention (UI-R14 #3 rolled the timeline back).
      writing = switch (exposureState) {
        TimelineCellExposureState.drawingStart => drawingHeadOf(
          frameName,
          kind: layer.kind,
          unnamedMark: unnamedMark,
        ),
        _ when exposureState.isMark => timelineDotWriting(exposureState),
        _ => timelineCellWritesNothing,
      };
    } else {
      writing = timelineCellMarker(
        layer: layer,
        exposureState: exposureState,
        emptyRunStart: emptyRunStart,
        unnamedMark: unnamedMark,
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
      glyph: writing.word,
      mark: writing.mark,
      semanticsLabel: timelineCellSemanticsLabel(
        layerKind: layer.kind,
        exposureState: exposureState,
        frameName: frameName,
      ),
    );
  }

  /// The cell's RESOLVED paint style (dim blends, band tint, block
  /// radius) — what [substrateIn] lays down and what tests assert against
  /// (the successor of reading the widget cell's BoxDecoration).
  ({Color background, Color border, BorderRadius? radius}) resolvedCellStyleFor(
    int frameIndex,
  ) {
    final model = cellModelAt(frameIndex);
    // Ghosts carry NO block chrome (UI-R10 #11): the cell paints as plain
    // empty paper and only the dimmed glyph marks the derived exposure.
    // A camera summary cell is empty-styled for the same reason — its
    // coverage is a key marker, not paper.
    final paper = layerMarkColor(layer.mark);
    final cellPaper = timelineCellPaper(
      model.ghost || _cameraSummaryRow
          ? TimelineCellExposureState.uncovered
          : model.exposureState,
      // ⑲: the row's blocks are its layer's colour label.
      paper: paper,
    );
    // I-129: a block wears what its row and its cel show — the switched-off
    // look on a hidden row, the empty look where its cel holds no picture
    // (ACTION-section rows only: the resolver stands down elsewhere), red
    // where its picture could not be read ([blockLookAt]). Ghosts stay plain
    // (they carry no block chrome at all). I-44: onto [paperGround], so the
    // grid sheet under the row cannot show through it.
    final look =
        !model.ghost && !_cameraSummaryRow && model.exposureState.isCovered
        ? blockLookAt(frameIndex, paper: cellPaper)
        : null;
    final baseBackground = look == null
        ? cellPaper
        : look.paper ?? Colors.transparent;
    // ↩️The border is an EMPTY block's outline now (I-129) — the whole
    // block's, laid once per run ([substrateIn]), never a cell's.
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
    // one rect in its own overlay ([TimelineOutsideCutWash]), which
    // is what lets it follow a live drag while these tiles stay baked.
    return (
      background: baseBackground,
      border: look?.line ?? Colors.transparent,
      radius: timelineCellBorderRadius(
        model.segment,
        axis,
        cellExtent: frameCellExtent,
        crossExtent: timelineRowPaperExtent(crossAxisExtent),
      ),
    );
  }

  /// The look of the block over [frameIndex], made of [paper] with words in
  /// [ink] — as its row ([shown]) and its cel ([celContent]) show it, onto
  /// [paperGround] ([timelineFrameBlockLook]).
  TimelineBlockLook blockLookAt(
    int frameIndex, {
    required Color paper,
    Color? ink,
  }) => timelineFrameBlockLook(
    (layer: layer, shown: shown, content: celContent, ground: paperGround),
    frameIndex,
    paper: paper,
    ink: ink ?? timelineInBlockInk(),
  );

  /// The cell's PAPER — its rect short of the row seam at the trailing
  /// cross edge ([timelineRowPaperExtent]), which the grid sheet draws under
  /// the row and the paper must leave showing.
  Rect paperRectFor(int frameIndex) {
    final cell = cellRectFor(frameIndex);
    final paper = timelineRowPaperExtent(crossAxisExtent);
    final alongStart = startAlong(axis, cell);
    final acrossStart = startAcross(axis, cell);
    return rectAlong(
      axis,
      along: (from: alongStart, to: alongStart + extentAlong(axis, cell.size)),
      across: (from: acrossStart, to: acrossStart + paper),
    );
  }

  /// What frames [from, to) lay down under their ink — THE contract the
  /// classic pass paints and the tile emitter bakes (the probe-the-painter
  /// rule): the paper, one piece per run, and the frame lines across it.
  @override
  TimelineRowSubstrate substrateIn(int from, int to) =>
      // One resolution per cell for the whole answer — every cell is asked
      // for its style, its segment and its line.
      readInOnePass(() => _substrateIn(from, to));

  TimelineRowSubstrate _substrateIn(int from, int to) {
    final paper = <({Rect rect, Color color, BorderRadius? radius})>[];
    final rings = <TimelineRowRing>[];
    var runStart = from;
    // What the run lays: its paper and its outline (transparent for none).
    ({Color paper, Color line})? run;
    ({Color paper, Color line}) lookAt(int frame) {
      final style = resolvedCellStyleFor(frame);
      return (paper: style.background, line: style.border);
    }

    void close(int runEnd) {
      final laid = run;
      if (laid == null) {
        return;
      }
      final first = cellModelAt(runStart).segment;
      final last = cellModelAt(runEnd - 1).segment;
      final rect = paperRectFor(
        runStart,
      ).expandToInclude(paperRectFor(runEnd - 1));
      // The run's corners are its end cells' — the one corner law, asked
      // about the run as the block it is.
      final radius = timelineCellBorderRadius(
        TimelineExposureBlockVisualSegment(
          kind: first.kind,
          continuesFromPrevious: first.continuesFromPrevious,
          continuesToNext: last.continuesToNext,
        ),
        axis,
        cellExtent: frameCellExtent,
        crossExtent: timelineRowPaperExtent(crossAxisExtent),
      );
      if (laid.paper.a > 0) {
        paper.add((rect: rect, color: laid.paper, radius: radius));
      }
      if (laid.line.a > 0) {
        final along = axis == Axis.horizontal;
        rings.add((
          rect: rect,
          color: laid.line,
          radius: radius,
          width: timelineBlockLineWidth,
          // Open where the block runs on past the run.
          open: (
            left: along && first.continuesFromPrevious,
            top: !along && first.continuesFromPrevious,
            right: along && last.continuesToNext,
            bottom: !along && last.continuesToNext,
          ),
        ));
      }
      run = null;
    }

    // A cell joins the run before it when no corner stands between them and
    // it lays the same.
    bool joins(int frame, ({Color paper, Color line}) look) =>
        look == run && cellModelAt(frame).segment.continuesFromPrevious;

    // By stretch (I-22): the rest of a stretch is its first cell again, so
    // it joins the run that cell joined or started, or lays nothing.
    for (final (start: frame, :end) in _stretchesIn(from, to)) {
      final look = lookAt(frame);
      final lays = look.paper.a > 0 || look.line.a > 0;
      assert(
        end - frame == 1 ||
            cellModelAt(frame).segment.continuesFromPrevious ||
            !lays,
        'a stretch that starts a block is that one cell',
      );
      if (joins(frame, look)) {
        continue;
      }
      close(frame);
      // UI-R21 #2: an empty cell paints NOTHING — its ground, and every
      // line on it, is the grid sheet's under the row (I-44).
      if (lays) {
        runStart = frame;
        run = look;
      }
    }
    // 🗣️F-208 (유저 2026-09-29, Android): 「6콤마에 한번 세로선 존재. 줌 할때마다
    // 위치바뀜」. Through [to] itself when the paper runs on into it: a tile
    // ending here is as many pixels as its length rounds UP to, so at a
    // fractional device pixel ratio its last pixel holds a sliver of the
    // cell at [to]. Paper that stopped at [to] left that pixel part-covered —
    // a line of ground wherever two tiles of one block met. The lines below
    // reach through [to] for the same sliver.
    close(to < frameEndIndexExclusive && joins(to, lookAt(to)) ? to + 1 : to);

    final lines = <({Rect rect, Color color})>[];
    if (blockFrameLines) {
      // Through [to] itself: a second line is 1.5 wide about a centre half
      // a pixel past its boundary, so the line starting frame [to] leans a
      // quarter pixel back into this stretch, and a tile ending here owns
      // that sliver. Only the boundaries a line can stand on are asked
      // ([timelineFrameLineStep]) — the sheet's and the ruler's walk; I-22's
      // floor puts ~19,000 frames in a window.
      final step = timelineFrameLineStep(frameCellExtent, framesPerSecond);
      for (
        var frame = timelineFirstOnStride(from, step);
        frame <= to;
        frame += step
      ) {
        final line = _blockFrameLineAt(frame);
        if (line != null) {
          lines.add(line);
        }
      }
    }
    return (paper: paper, lines: lines, rings: rings);
  }

  /// The frame line at [frameIndex]'s leading boundary, where it crosses
  /// the block's paper — an interior boundary only: a block's first
  /// boundary is its edge, and the run starts there.
  ///
  /// Asked of its STRETCH's first cell, which the cell paints as (I-22): a
  /// line inside a block asks no cell of its own.
  ({Rect rect, Color color})? _blockFrameLineAt(int frameIndex) {
    final stretch = _stretchStartOf(frameIndex);
    final segment = cellModelAt(stretch).segment;
    if (!segment.isBlock || !segment.continuesFromPrevious) {
      return null;
    }
    final paper = paperRectFor(frameIndex);
    return timelineBlockFrameLine(
      axis: axis,
      frameIndex: frameIndex,
      boundary: startAlong(axis, paper),
      across: (from: startAcross(axis, paper), to: endAcross(axis, paper)),
      frameCellExtent: frameCellExtent,
      framesPerSecond: framesPerSecond,
      colorScheme: colorScheme,
      paper: resolvedCellStyleFor(stretch).background,
    );
  }

  @override
  void paintWords(Canvas canvas, Size size) =>
      readInOnePass(() => _paint(canvas, size));

  void _paint(Canvas canvas, Size size) {
    // Self-windowing (UI-R15): only the cells under the live viewport
    // record — a scroll is a repaint of this thin pass, never a rebuild.
    final window = visibleFrameWindow();
    final store = tileStore;
    // Spans whose FRESH tile already carries the foreground ink (T3):
    // the Dart glyph/dash pass skips them.
    final tiledSpans = <(int, int)>[];
    if (store == null || frameCellExtent <= 0) {
      _paintSubstrate(canvas, window.startIndex, window.endIndexExclusive);
    } else {
      tiledSpans.addAll(_paintTiledSubstrate(canvas, window, store));
    }
    _paintForegrounds(canvas, window, tiledSpans);
    _paintGhostInk(canvas, window);

    // No line is drawn here: the 6f/24f beats went to ONE grid-wide
    // overlay (UI-R13 #7) so they span every row, and with I-44 every
    // other line and the row's ground followed them into that one grid
    // sheet ([TimelineGridSheetPainter]). The one exception rides in the
    // substrate: that sheet's own lines on the block paper, where the
    // user's switch shows them ([substrateIn]).
  }

  /// The substrate through the tile store: a tile is one drawImageRect —
  /// baked in this paint where an edit moved the span
  /// ([TimelineGridTileStore.tileFor]) — a cold span keeps the classic
  /// paint underneath while its raster lands off-frame, and the two spans
  /// past the window are asked for so a scroll finds them warm. Answers the
  /// spans whose tile already carries the foreground ink.
  List<(int, int)> _paintTiledSubstrate(
    Canvas canvas,
    ({int startIndex, int endIndexExclusive}) window,
    TimelineGridTileStore store,
  ) {
    final tiledSpans = <(int, int)>[];
    final grid = _tileGridIn(window, frameEndIndexExclusive);
    final tilePaint = Paint()..filterQuality = FilterQuality.low;
    for (final (spanStart, spanEnd) in grid.shown) {
      final image = store.tileFor(
        painter: this,
        spanStartIndex: spanStart,
        spanEndIndexExclusive: spanEnd,
        devicePixelRatio: devicePixelRatio,
      );
      if (image != null) {
        final origin = startAlong(axis, cellRectFor(spanStart));
        final mainExtent = endAlong(axis, cellRectFor(spanEnd - 1)) - origin;
        final dst = rectAlong(
          axis,
          along: (from: origin, to: origin + mainExtent),
          across: (from: 0, to: crossAxisExtent),
        );
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          dst,
          tilePaint,
        );
        tiledSpans.add((spanStart, spanEnd));
        continue;
      }
      // ⛔This call was lost once, silently: `a055c51a`(2026-09-04) — a
      // commit about the accessibility sentence and the corner radius —
      // swapped it for an empty `/*P4*/` marker, the shape of a mutant
      // from that day's mutation campaign committed by accident. Every
      // zoom step that crossed a span boundary then drew no block paper
      // for a frame (F-94). `a_row_paints_its_substrate_and_its_glyphs_
      // test` pins it now, with the engine on and the store cold.
      _paintSubstrate(
        canvas,
        math.max(spanStart, window.startIndex),
        math.min(spanEnd, window.endIndexExclusive),
      );
    }
    // PREFETCH one span beyond both window edges (scroll warm-up):
    // warming is enough — the raster lands before the crossing reveals
    // it, so steady scrolling never hits the fallback, and its landing
    // repaints nothing this row shows.
    for (final (spanStart, spanEnd) in grid.ahead) {
      store.warmAhead(
        painter: this,
        spanStartIndex: spanStart,
        spanEndIndexExclusive: spanEnd,
        devicePixelRatio: devicePixelRatio,
      );
    }
    return tiledSpans;
  }

  /// The tile grid's spans under [window], in order (`shown`), and the one
  /// past each edge a paint keeps warm (`ahead`), the last cut at the
  /// [builtFrames] the axis ends at — the grid rides the SHARED window
  /// policy ([timelineFrameWindowSpanFor], UI-R18 O7 T2).
  ({List<(int, int)> shown, List<(int, int)> ahead}) _tileGridIn(
    ({int startIndex, int endIndexExclusive}) window,
    int builtFrames,
  ) {
    final span = timelineFrameWindowSpanFor(frameCellExtent);
    (int, int)? spanAt(int tile) {
      final start = tile * span;
      final end = math.min(start + span, builtFrames);
      return start < 0 || end <= start ? null : (start, end);
    }

    final first = window.startIndex < 0 ? 0 : window.startIndex ~/ span;
    var past = first;
    while (past * span < window.endIndexExclusive) {
      past += 1;
    }
    return (
      shown: [for (var tile = first; tile < past; tile += 1) ?spanAt(tile)],
      ahead: [?spanAt((window.startIndex ~/ span) - 1), ?spanAt(past)],
    );
  }

  @override
  ({List<(int, int)> shown, List<(int, int)> ahead}) get tileSpans =>
      _tileGridIn(visibleFrameWindow(), frameEndIndexExclusive);

  /// A row that windows itself off no bucket paints every span already,
  /// and has no page to turn to.
  ///
  /// ↩️It was a viewport's frames from where the window ends: a window
  /// reaches past the viewport by its bucket and its overscan, so the
  /// turn's window ended a span later than what was warmed, and the span
  /// past that edge was never warmed at all — 🔬two spans a row landed cold
  /// after every turn and repainted their rows (10-12, cut 302 at 144Hz).
  /// ↩️Then each row guessed the turn from its own bucket, and took a window
  /// that reached the built end for a run about to wrap
  /// ([TimelineFrameAxisFollower.nextPage] has what that cost).
  @override
  List<(int, int)> tileSpansOfThePage(TimelineNextPage page) {
    if (windowBucket == null ||
        frameCellExtent <= 0 ||
        viewportMainExtent <= 0) {
      return const [];
    }
    final grid = _tileGridIn(
      frameWindowAtBucket(
        page.bucket,
        viewportMainExtent: viewportMainExtent,
        cellExtent: frameCellExtent,
        frames: (
          startIndex: frameStartIndex,
          endIndexExclusive: page.builtFrames,
        ),
      ),
      page.builtFrames,
    );
    return [...grid.shown, ...grid.ahead];
  }

  /// The Dart glyph pass over every cell in [window] whose span no fresh
  /// tile covers (T3: a tiled span already carries its ink) — what a tile
  /// would bake there; a ghost's ink is [_paintGhostInk]'s.
  ///
  /// F-96: a word grows on past its cell, so each untiled stretch also lays
  /// the word that grows into it from before ([bakedWordGrowingInto]), and
  /// paints under a clip of its own extent — a word that also lives in a
  /// tile is never inked twice: the tile holds its part, this pass the rest.
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
    canvas.save();
    canvas.clipRect(
      rectAlong(
        axis,
        along: (
          from: startAlong(axis, cellRectFor(from)),
          to: startAlong(axis, cellRectFor(to)),
        ),
        across: (from: 0, to: crossAxisExtent),
      ),
    );
    final lead = bakedWordGrowingInto(from);
    if (lead != null) {
      _paintCellForeground(canvas, lead);
    }
    for (final frameIndex in bakedWritingCellsIn(from, to)) {
      _paintCellForeground(canvas, frameIndex);
    }
    canvas.restore();
  }

  /// A ghost's ink over [window], laid over the tiles at every paint and
  /// never baked into one: the words and marks of its cells, the X that
  /// closes it ([_writesGhostInk]) and a hold's line. A tile bakes the rest
  /// ([bakedWritingCellsIn]), so each cell inks once, by one of the two.
  ///
  /// 🗣️F-446: a ghost is what the cut's length draws (the last run's fills
  /// to the drawn end), so an end-line step moved it in every row, and the
  /// tile it ended in baked again at every step. Over the whole window it
  /// is one stroke a hold and one word a cell, with no tile edge to cut.
  void _paintGhostInk(
    Canvas canvas,
    ({int startIndex, int endIndexExclusive}) window,
  ) {
    final (startIndex: from, endIndexExclusive: to) = window;
    if (to <= from) {
      return;
    }
    final lead = _wordGrowingInto(from);
    if (lead != null && _writesGhostInk(lead)) {
      _paintCellForeground(canvas, lead);
    }
    for (final frameIndex in ghostInkCellsIn(from, to)) {
      _paintCellForeground(canvas, frameIndex);
    }
    for (final line in holdLinesIn(from, to)) {
      _paintHoldLine(canvas, line);
    }
  }

  /// Whether [model] is a hold ghost's cell — one that writes nothing of
  /// its own ([holdLinesIn]).
  bool _isHold(TimelineRowCellModel model) =>
      model.ghost && model.glyph == _holdGlyph;

  /// The cells of [from, to) that WRITE — a word or a mark — in order; every
  /// other cell inks nothing. A tile bakes them and the classic pass inks
  /// them ([bakedWritingCellsIn]) but for a ghost's, which the row lays over
  /// both ([ghostInkCellsIn]).
  ///
  /// By stretch (I-22): a stretch whose first cell writes nothing is passed
  /// in one step — a hold's among them, whose line is [holdLinesIn]'s.
  Iterable<int> writingCellsIn(int from, int to) sync* {
    for (final (:start, :end) in _stretchesIn(from, to)) {
      final model = cellModelAt(start);
      if (model.mark == null && (model.glyph.isEmpty || _isHold(model))) {
        continue;
      }
      for (var frameIndex = start; frameIndex < end; frameIndex += 1) {
        yield frameIndex;
      }
    }
  }

  @override
  Iterable<int> bakedWritingCellsIn(int from, int to) =>
      writingCellsIn(from, to).where((cell) => !_writesGhostInk(cell));

  /// The cells of [from, to) that write a ghost's ink ([_writesGhostInk]),
  /// in order — what the row lays over its tiles ([_paintGhostInk]).
  Iterable<int> ghostInkCellsIn(int from, int to) =>
      writingCellsIn(from, to).where(_writesGhostInk);

  /// Whether the cell at [frameIndex] writes a GHOST's ink: a word or a mark
  /// of a ghost's own cells, or the X of the empty cell that closes one —
  /// which stands where the ghost ends, so it follows the cut's length too.
  bool _writesGhostInk(int frameIndex) =>
      cellModelAt(frameIndex).ghost ||
      _stateAt(frameIndex) == TimelineCellExposureState.uncovered &&
          timelineIndexIsGhost(layer, frameIndex - 1);

  /// The holds' lines over [from, to) — one a hold ghost that reaches it.
  ///
  /// ↩️UI-R12 #18 drew A DASH A CELL: a line nearly as wide as its cell with
  /// 「a deliberate 3px break per boundary so it never fuses into a solid
  /// rule」 (유저: 「이어진 느낌, 완벽하게는 안 이어지게」). 유저 2026-10-08
  /// (I-73) turned that round: 「점선말고 이어진선으로하자. 쓸데없이
  /// 보기힘들어. 잘 이어지도록」 · 「실선으로 바꿈. 뒤집는거임」. A hold is ONE
  /// line now, from the first of its cells to the last.
  ///
  /// ⛔Where it is drawn did not move: in the FREE cells beside a run whose
  /// edge property is hold — the ghost — and never in a block's own cells
  /// (유저, the same day: 「블록에 그리는게아니라 성질이 홀드일때 빈공간에
  /// 그리는것임」).
  ///
  /// A hold ghost is one entry of the timeline, so the walk is the
  /// timeline's — an entry at a time, never a cell at a time (I-22).
  Iterable<TimelineHoldLine> holdLinesIn(int from, int to) sync* {
    final timeline = layer.timeline;
    for (
      var start =
          timeline.lastKeyBefore(from + 1) ?? timeline.firstKeyAfter(from);
      start != null && start < to;
      start = timeline.firstKeyAfter(start)
    ) {
      final entry = timeline[start]!;
      final end = start + (entry.length ?? 1);
      if (end <= from || entry.ghostOf?.mode != TimelineRunEdgeMode.hold) {
        continue;
      }
      final line = _holdLineOver(start: start, end: end, from: from, to: to);
      if (line != null) {
        yield line;
      }
    }
  }

  /// The line of the hold ghost [start, end) as it shows over [from, to):
  /// its own ends stand [timelineHoldLineInset] in from the cells' edges,
  /// and where the stretch stops short of one the line runs to the edge.
  ///
  /// ↩️It reached through the cell at [to] for F-208's sliver, as the paper
  /// does ([substrateIn]) — the last pixel of the tile it was baked in. A
  /// hold is laid over the row's window now (F-446), whose edges stand in
  /// the overscan, where no pixel shows.
  ///
  /// Null while there is no room for it between its ends — the cell a hold
  /// of one frame gets at a far zoom.
  TimelineHoldLine? _holdLineOver({
    required int start,
    required int end,
    required int from,
    required int to,
  }) {
    final first = math.max(start, from);
    final past = math.min(end, to);
    final head = cellRectFor(first);
    final tail = cellRectFor(past - 1);
    final startsHere = first == start;
    final endsHere = past == end;
    final lo =
        startAlong(axis, head) + (startsHere ? timelineHoldLineInset : 0);
    final hi = endAlong(axis, tail) - (endsHere ? timelineHoldLineInset : 0);
    if (hi - lo <= 1) {
      return null;
    }
    const half = timelineJoiningLineWidth / 2;
    final across = partAcross(axis, head.center);
    return (
      box: rectAlong(
        axis,
        along: (from: lo, to: hi),
        across: (from: across - half, to: across + half),
      ),
      startsHere: startsHere,
      endsHere: endsHere,
      ink: foregroundInkFor(cellModelAt(first)),
    );
  }

  /// The row's dense, mostly-static part over frames [from, to) — exactly
  /// what the substrate TILES bake ([substrateIn]), so the two paths
  /// cannot drift.
  void _paintSubstrate(Canvas canvas, int from, int to) {
    final substrate = substrateIn(from, to);
    for (final piece in substrate.paper) {
      final paint = Paint()..color = piece.color;
      final radius = piece.radius;
      if (radius == null) {
        canvas.drawRect(piece.rect, paint);
      } else {
        canvas.drawRRect(radius.toRRect(piece.rect), paint);
      }
    }
    for (final line in substrate.lines) {
      canvas.drawRect(line.rect, Paint()..color = line.color);
    }
    for (final ring in substrate.rings) {
      _paintRing(canvas, ring);
    }
  }

  /// [ring] as a tile lays it (the `rrectRing` op): the band
  /// its width wide inside its rect, open on the sides it leaves open.
  static void _paintRing(Canvas canvas, TimelineRowRing ring) {
    final past = ring.width + 2;
    final rect = ring.rect;
    final open = ring.open;
    final outer = (ring.radius ?? BorderRadius.zero).toRRect(
      Rect.fromLTRB(
        rect.left - (open.left ? past : 0),
        rect.top - (open.top ? past : 0),
        rect.right + (open.right ? past : 0),
        rect.bottom + (open.bottom ? past : 0),
      ),
    );
    canvas
      ..save()
      ..clipRect(rect)
      ..drawDRRect(
        outer,
        outer.deflate(ring.width),
        Paint()..color = ring.color,
      )
      ..restore();
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
        // F-24: the same ink the block's 코마 number takes — as the block
        // shows it (I-129).
        ? blockLookAt(
            model.frameIndex,
            paper: layerMarkColor(layer.mark),
            ink: timelineInBlockInk(dimmed: model.dimmed),
          ).ink
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
      // 🚨ONE SIZE AT EVERY ZOOM (유저 2026-09-24, B): the word narrows into
      // its block instead ([cellWordSetFor]). ↩️R26 #38/#4 shrank names
      // and marks with the cell rather than blanking them below ~14px, and
      // #15 shrank them with a squeezed row — both are the narrowing now, on
      // the axis that ran short.
      fontSize: timelineBlockNameFontSize(baseTextStyle),
      bold:
          !model.ghost &&
          !isEmptyX &&
          model.exposureState != TimelineCellExposureState.held,
    );
  }

  /// The word [text] of the cell at [frameIndex], set in [style] where it is
  /// laid, row-local — the block-word law ([timelineBlockWordLayout]):
  /// centred on its cell while it fits, growing on into its block past that
  /// (F-96). Where the block runs short its letter gaps give way first
  /// ([timelineWordSetOnto], F-234-Q1), and only past that is it narrowed,
  /// where it would leave the block or its paper (B, 유저 2026-09-24:
  /// 「이름은 블록안에서만」). The room is the one its NATURAL length asks
  /// for — the block's rest, where tightening happens at all. PUBLIC: the
  /// tile emitter bakes its word exactly here, this tight.
  @override
  ({double tightening, Offset origin, WordFit fit}) cellWordSetFor(
    int frameIndex,
    String text,
    TextStyle style,
  ) {
    final slot = _wordSlotFor(
      frameIndex,
      _glyphPainter(text, style).size,
    );
    final set = timelineWordSetOnto(text, style, slot.room.width);
    final layout = timelineBlockWordLayout(set.glyph.size, slot);
    return (
      tightening: set.tightening,
      origin: layout.origin,
      fit: layout.fit,
    );
  }

  TimelineBlockWordSlot _wordSlotFor(int frameIndex, Size word) {
    final cell = cellRectFor(frameIndex);
    final cellStart = startAlong(axis, cell);
    final roomEnd = _wordRoomEnd(frameIndex, extentAlong(axis, word));
    final paper = timelineRowPaperExtent(crossAxisExtent);
    return (
      axis: axis,
      room: rectAlong(
        axis,
        along: (from: cellStart, to: roomEnd),
        across: (from: 0, to: paper),
      ),
      cellStart: cellStart,
      // The cell the law laid (F-220), not the zoom's nominal width.
      cellExtent: extentAlong(axis, cell.size),
      growth: TimelineBlockWordGrowth.towardBlockEnd,
      acrossAlignment: 0,
    );
  }

  /// Where the in-between mark of the cell at [frameIndex] stands, row-local,
  /// and the box it fills: centred on the cell's paper, at the size of the
  /// cell's word ([timelineInbetweenMarkSize]). PUBLIC: the tile emitter
  /// bakes the mark exactly here.
  ///
  /// It keeps to its cell, so the tile that holds the cell is the only one
  /// that draws it — a word growing past its cell needed
  /// [bakedWordGrowingInto].
  @override
  InbetweenMarkPlace inbetweenMarkLayoutFor(int frameIndex) {
    final paper = paperRectFor(frameIndex);
    // The cell the law laid (F-220): a 1.3px zoom lays cells of 1 and 2,
    // and a mark sized from 1.3 left the 1px ones.
    final cell = cellRectFor(frameIndex).size;
    return (
      center: paper.center,
      size: timelineInbetweenMarkSize(
        timelineBlockNameFontSize(baseTextStyle),
        cell: sizeAlong(
          axis,
          along: extentAlong(axis, cell),
          across: extentAcross(axis, paper.size),
        ),
      ),
    );
  }

  /// Where the room the word at [frameIndex] may grow into ENDS along the
  /// frame axis: the end of its block or the cell before the block's next
  /// in-between mark, looked up only as far as a word of [extent] could
  /// reach. A word on no block — an empty stretch's `x` — has its own cell.
  ///
  /// 🚨A MARK IS A LETTER OF ITS BLOCK (F-297, 유저 2026-10-05): 「중간나누기
  /// 점도 하나의 글자로 인식해서 헤드의 프레임이름 작아진다거나 할것」. ↩️A
  /// name's room ran to the end of its block whatever stood in it, so a
  /// name wider than its cell was written over the dot beside it; it narrows
  /// before the dot now, as it would before a letter.
  ///
  /// The block is the EXPOSURE's ([_stateAt]), not the chrome's: a repeat
  /// ghost wears no paper (UI-R10 #11) but it is still a run of one drawing,
  /// and its name stays inside that run as a drawn block's does.
  double _wordRoomEnd(int frameIndex, double extent) {
    double endOf(int index) => endAlong(axis, cellRectFor(index));

    final start = startAlong(axis, cellRectFor(frameIndex));
    var index = frameIndex;
    var end = endOf(index);
    while (end - start < extent &&
        timelineExposureBlockSegmentAt(
          frameIndex: index,
          stateAt: _stateAt,
        ).continuesToNext &&
        cellModelAt(index + 1).mark == null) {
      index += 1;
      end = endOf(index);
    }
    return end;
  }

  /// The nearest cell before [frameIndex] that writes a WORD, or null when
  /// a hold stands nearer or there is none — the word that may grow into
  /// [frameIndex]'s cell from before it (F-96); [_wordGrowingInto] asks
  /// whether it does.
  ///
  /// A mark is no word: it keeps to its own cell and grows into no other.
  /// The word before it stops at it ([_wordRoomEnd]), so a word found past
  /// a mark reaches [frameIndex] no more than its own room lets it.
  ///
  /// Walked back by stretch (I-22): a stretch whose first cell writes no
  /// word is passed in one step.
  int? wordCellBefore(int frameIndex) {
    var index = frameIndex - 1;
    while (index >= frameStartIndex) {
      final start = _stretchStartOf(index);
      final model = cellModelAt(start);
      if (model.glyph.isNotEmpty) {
        return _isHold(model) ? null : index;
      }
      index = start - 1;
    }
    return null;
  }

  /// [wordCellBefore], where its word is laid on into [frameIndex]'s cell:
  /// a word keeps to its room ([_wordRoomEnd]) — its own cell while it fits
  /// there, its block's rest past that. A room ending right at the cell
  /// counts: a glyph's last soft pixel may lie on the edge.
  int? _wordGrowingInto(int frameIndex) {
    final cell = wordCellBefore(frameIndex);
    if (cell == null) {
      return null;
    }
    final model = cellModelAt(cell);
    final word = _glyphPainter(model.glyph, glyphStyleFor(model)).size;
    final roomEnd = _wordRoomEnd(cell, extentAlong(axis, word));
    return roomEnd >= startAlong(axis, cellRectFor(frameIndex)) ? cell : null;
  }

  /// [_wordGrowingInto] but a ghost's, which the row lays whole over its
  /// tiles ([_paintGhostInk]).
  @override
  int? bakedWordGrowingInto(int frameIndex) {
    final cell = _wordGrowingInto(frameIndex);
    return cell == null || _writesGhostInk(cell) ? null : cell;
  }

  /// The cell's sparse foreground ink (in-between marks, glyph text) — the
  /// classic pass; tile mode bakes the same content into the tiles (T3) and
  /// skips this for covered spans. Only a cell that writes is handed here
  /// ([writingCellsIn], [_wordGrowingInto]) — never a hold's.
  void _paintCellForeground(Canvas canvas, int frameIndex) {
    final model = cellModelAt(frameIndex);
    final mark = model.mark;
    if (mark != null) {
      paintInbetweenMark(
        canvas,
        mark,
        inbetweenMarkLayoutFor(frameIndex),
        foregroundInkFor(model),
      );
      return;
    }
    if (model.glyph.isEmpty) {
      return;
    }
    // Snap the draw to the PHYSICAL pixel grid (UI-R20 #6): the tile
    // path blits glyphs at integer physical positions, so the classic
    // pass must land on the same grid — otherwise the classic↔tile
    // swap on row activation reads as the text thinning/thickening.
    // F-96: centred while the word fits its cell, growing on into the
    // block when it does not, its letter gaps giving way and only then
    // narrowed past the block ([cellWordSetFor]).
    final style = glyphStyleFor(model);
    final layout = cellWordSetFor(frameIndex, model.glyph, style);
    final raw = layout.origin;
    final dpr = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
    paintFittedText(
      canvas,
      _glyphPainter(model.glyph, style, tightening: layout.tightening),
      Offset(
        (raw.dx * dpr).roundToDouble() / dpr,
        (raw.dy * dpr).roundToDouble() / dpr,
      ),
      layout.fit,
    );
  }

  /// One hold's [line], as the classic pass draws it: a PAINTED stroke along
  /// the frame axis (UI-R12 #18 — the text glyph was too short to chain),
  /// round at the hold's own ends and filling [TimelineHoldLine.box] exactly
  /// — what the tile bakes there. An end that is only the stretch's runs to
  /// the box's edge, where the stretch's clip takes the round end off.
  void _paintHoldLine(Canvas canvas, TimelineHoldLine line) {
    const half = timelineJoiningLineWidth / 2;
    final box = line.box;
    canvas.drawLine(
      offsetAlong(
        axis,
        along: startAlong(axis, box) + (line.startsHere ? half : 0),
        across: partAcross(axis, box.center),
      ),
      offsetAlong(
        axis,
        along: endAlong(axis, box) - (line.endsHere ? half : 0),
        across: partAcross(axis, box.center),
      ),
      Paint()
        ..color = line.ink
        ..strokeWidth = timelineJoiningLineWidth
        ..strokeCap = StrokeCap.round,
    );
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
    colorScheme,
    exposureStateForLayer,
    frameNameForLayer,
    celHasContentForLayer,
    celCannotBeReadForLayer,
    celContentRevision,
    substrateGeneration,
    followsTheLiveCut,
    ByIdentity(tileStore),
    // I-44: what the unworked paper is pre-blended onto is a painted fact
    // like any other (a theme change moves it).
    paperGround,
    blockFrameLines,
    unnamedMark,
    framesPerSecond,
    shown,
    devicePixelRatio,
  );

  // The row's window said in ONE node — what each non-empty cell says, in
  // frame order ([frameWindowSentence], I-57-Q3 c), windowed with the paint
  // pass.
  //
  // 🚨ONLY WHAT THE SENTENCE READS (I-57, 10-14). It asked each cell for
  // its whole model outside any pass — the block off both neighbours, the
  // writing — five exposure searches a cell for a sentence that reads
  // one: 🔬on the AMMI OP, half the SEMANTICS of a cut crossing's frame,
  // and SEMANTICS was half the frame (CPU samples). Read so, a cell is
  // asked once and no pass has anything to keep.
  @override
  SemanticsBuilderCallback get semanticsBuilder =>
      (size) => frameWindowSentence(
        window: visibleFrameWindow(),
        rectFor: cellRectFor,
        cellAt: _semanticsCellAt,
      );

  /// What the cell at [frameIndex] says to a screen reader — its model's
  /// [TimelineRowCellModel.semanticsLabel], read off the two things the
  /// sentence is made of — and whether it carries on the run before it: a
  /// cell inside a block does, the block's first cell begins its own.
  ({String label, bool runsOn})? _semanticsCellAt(int frameIndex) {
    final state = _stateAt(frameIndex);
    final label = timelineCellSemanticsLabel(
      layerKind: layer.kind,
      exposureState: state,
      frameName: frameNameForLayer?.call(layer, frameIndex),
    );
    return label == null
        ? null
        : (
            label: label,
            runsOn: state != TimelineCellExposureState.drawingStart,
          );
  }
}

/// The painted cell strip + its row-level interaction, shared by the
/// horizontal row and the X-sheet column (Axis policy):
/// - raw pointer-down selects the cell under the pointer (instant, the
///   arena never delays it);
/// - a no-op onTap keeps a tap recognizer in the arena so scroll slop
///   over cells behaves exactly as the widget cells did;
/// - double-tap opens the cell editor.
///
/// 🚨I-57 (10-13): the presses are built from the row's SHAPE and act on
/// the layer the row stands for at the event ([layerIdNow]); the picture
/// draws what the row shows ([_RowCellsPicture]). [layer] is the one the
/// row was built for — what both answer where no berth stands above.
Widget timelineRowCellsPaintArea({
  required BuildContext context,
  required String keyPrefix,
  required Layer layer,
  required TimelineFrameGeometryHandle geometry,
  required double crossAxisExtent,
  required Axis axis,

  /// What the strip draws over its cells, for the layer the row shows.
  CustomPainter? Function(BuildContext context, Layer shown)?
  foregroundPainterFor,
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
  TimelineNextPage? Function()? nextPage,
  int? Function(int frame)? stepsUntilShown,
  Object? coverageIdentity,
  String substrateGeneration = '',
}) {
  // Read LIVE: the row that built this closure survives zoom steps now.
  bool inWindow(int frameIndex) => geometry.value.contains(frameIndex);
  int frameAt(Offset localPosition) => geometry.value.cellAt(
    partAlong(axis, localPosition),
  );
  // The row the press is on — asked at the press, the row being kept
  // through a cut switch.
  LayerId pressedLayer() => layerIdNow(context, layer.id);
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
    onSelectLayer(pressedLayer());
  }

  // The frame-block activation law's cell resolver: a position is a cell
  // only inside the visible window. Both halves of the shared double-tap
  // law read THIS one function (R26 #37).
  int? cellAt(Offset localPosition) {
    final frameIndex = frameAt(localPosition);
    return inWindow(frameIndex) ? frameIndex : null;
  }

  // …and the cells the double tap aims at ([timelineDoubleTapAim]).
  final cells = (
    frameAt: cellAt,
    axis: axis,
    cellExtent: () => geometry.value.frameCellExtent,
  );

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
    onPressDown: (localPosition) => timelineCellDoubleTapRecord(
      row: LayerRowAddress(pressedLayer()),
      cells: cells,
    )(localPosition),
    onTap: (localPosition) {
      final frameIndex = frameAt(localPosition);
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
          : (details) => timelineCellDoubleTapActivation(
              row: LayerRowAddress(pressedLayer()),
              cells: cells,
              onActivate: (frameIndex) {
                select(frameIndex);
                onActivateCell(pressedLayer(), frameIndex);
              },
            )(details),
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
          child: _RowCellsPicture(
            keyPrefix: keyPrefix,
            builtFor: layer,
            geometry: geometry,
            crossAxisExtent: crossAxisExtent,
            axis: axis,
            foregroundPainterFor: foregroundPainterFor,
            exposureStateForLayer: exposureStateForLayer,
            frameNameForLayer: frameNameForLayer,
            celContent: celContent,
            windowBucket: windowBucket,
            nextPage: nextPage,
            stepsUntilShown: stepsUntilShown,
            coverageIdentity: coverageIdentity,
            substrateGeneration: substrateGeneration,
          ),
        ),
      ),
    ),
  );
}

/// The strip's picture: what the row SHOWS ([BerthRow.shows]) in the world
/// it stands in ([BerthWorld]) — built again, alone, whenever either
/// changes, while the presses around it are kept. Where no berth stands
/// above, the layer and the world the row was built for.
class _RowCellsPicture extends StatelessWidget {
  const _RowCellsPicture({
    required this.keyPrefix,
    required this.builtFor,
    required this.geometry,
    required this.crossAxisExtent,
    required this.axis,
    required this.foregroundPainterFor,
    required this.exposureStateForLayer,
    required this.frameNameForLayer,
    required this.celContent,
    required this.windowBucket,
    required this.nextPage,
    required this.stepsUntilShown,
    required this.coverageIdentity,
    required this.substrateGeneration,
  });

  final String keyPrefix;
  final Layer builtFor;
  final TimelineFrameGeometryHandle geometry;
  final double crossAxisExtent;
  final Axis axis;
  final CustomPainter? Function(BuildContext context, Layer shown)?
  foregroundPainterFor;
  final TimelineCellExposureState Function(Layer layer, int frameIndex)
  exposureStateForLayer;
  final String? Function(Layer layer, int frameIndex)? frameNameForLayer;
  final TimelineCelContentSource? celContent;
  final ValueListenable<int>? windowBucket;
  final TimelineNextPage? Function()? nextPage;
  final int? Function(int frame)? stepsUntilShown;
  final Object? coverageIdentity;
  final String substrateGeneration;

  @override
  Widget build(BuildContext context) {
    final berth = BerthRow.shows(context);
    final layer = berth?.shown ?? builtFor;
    final world = berth?.world;
    final law = TimelineGridLaw.maybeOf(context);
    final painter = TimelineRowCellsPainter(
      layer: layer,
      geometry: geometry,
      crossAxisExtent: crossAxisExtent,
      exposureStateForLayer: exposureStateForLayer,
      frameNameForLayer: frameNameForLayer,
      celContent: celContent,
      coverageIdentity: world == null
          ? coverageIdentity
          : world.coverageIdentity.value,
      colorScheme: Theme.of(context).colorScheme,
      baseTextStyle: DefaultTextStyle.of(context).style,
      axis: axis,
      windowBucket: windowBucket,
      nextPage: nextPage,
      stepsUntilShown: stepsUntilShown,
      // Substrate tiles (UI-R18 O7 T2): the app-wide store; it stands down
      // by itself when the native engine is unavailable (tests, web).
      //
      // ↩️T16 kept the folded row off the tiles: its mode dropped the
      // empties, the ground and the seams, and one row over the artwork was
      // not worth teaching the bake key that dimension. I-44 took all three
      // off EVERY row, and what the paper stands on is [paperGround], which
      // the key carries for every row — so the folded row bakes like the
      // rest.
      tileStore: TimelineGridTileStore.instance,
      substrateGeneration: world?.substrateGeneration ?? substrateGeneration,
      devicePixelRatio: EffectiveDevicePixelRatio.of(context),
      // I-44: the HOST's ground, stated once by its law — what an unworked
      // block's paper is pre-blended onto (null over the artwork).
      paperGround: law?.ground,
      // And whether its lines cross the paper, in its own cadence.
      blockFrameLines: law?.blockFrameLines ?? false,
      unnamedMark: TimelineGridLaw.unnamedMarkOf(context),
      framesPerSecond: law?.framesPerSecond ?? 0,
      // I-129: the eye its rail shows — heard past the row memo, as the
      // rail's own plate and name hear it.
      shown: RailEyes.of(context, layer).shown,
    );
    // Named, not keyed (I-57, 10-13): the row shows one layer and then
    // another in the same elements.
    return Named(
      '$keyPrefix-row-cells-${layer.id}',
      child: CustomPaint(
        painter: painter,
        // The block duration labels ride HERE rather than as their own
        // Positioned.fill CustomPaint: same geometry, same repaint trigger,
        // two fewer render objects per row to lay out on a zoom step. A
        // foreground painter that does not implement `hitTest` never absorbs
        // a pointer, which is what the IgnorePointer around it used to
        // guarantee.
        foregroundPainter: foregroundPainterFor?.call(context, layer),
      ),
    );
  }
}
