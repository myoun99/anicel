import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/timeline_empty_gaps.dart' show emptyGapsBetween;
import '../../models/attached_layer_resolve.dart';
import '../../models/camera_instruction.dart';
import '../../models/layer.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../../models/layer_id.dart';
import '../../models/project_frame_rate.dart';
import '../../models/timeline_row_address.dart';
import '../media/media_asset_drop_target.dart';
import 'layer_label_controls.dart' show layerMarkColor;
import 'timeline_cel_content_source.dart';
import 'timeline_cell_editor_policy.dart';
import 'timeline_cell_exposure_state.dart';
import 'timeline_cell_style.dart' show timelineDrawingInkColor;
import 'timeline_exposure_comma_drag_policy.dart';
import 'timeline_frame_geometry.dart';
import 'timeline_frame_range_gesture.dart';
import 'timeline_beat_lines.dart' show timelineRowPaperExtent;
import 'timeline_frame_span_layout.dart';
import 'property_lane_model.dart' show PropertyLaneRow;
import 'timeline_lane_rows.dart' show timelineUnionKeyMarkerSpans;
import 'se_audio_lane.dart' show TimelineAudioLaneCallbacks;
import 'timeline_row_cells_painter.dart';
import 'timeline_row_edit_chrome.dart';
import 'timeline_row_run_labels_painter.dart';
import 'timeline_run_end_handles.dart';
import 'timeline_instruction_row_visual.dart';
import 'timeline_se_row_visual.dart';
import 'timeline_silhouette_painter.dart';

/// One layer's row of frame cells. CURSOR-INDEPENDENT by design: nothing
/// here reads the playhead — the selected-cell ring, the selected-exposure
/// outline and the playhead tint live on the grid's TimelineCursorLayer,
/// so a frame tick never rebuilds this row (playback-performance
/// architecture).
class TimelineFrameCellsRow extends StatelessWidget {
  const TimelineFrameCellsRow({
    super.key,
    this.axis = Axis.horizontal,
    this.keyPrefix = 'timeline',
    required this.layer,
    required this.playbackFrameCount,
    required this.geometry,
    required this.crossAxisExtent,
    required this.exposureStateForLayer,
    this.frameNameForLayer,
    this.celContent,
    this.coverageIdentity,
    required this.onSelectLayer,
    required this.onSelectFrame,
    this.onSettledPress,
    this.onActivateCell,
    this.instructionDefById,
    this.instructionCrossingTooltip,
    this.audioPeaksFor,
    this.projectFrameRate = ProjectFrameRate.fps24,
    this.onDropMediaAssetOnLayer,
    this.acceptsMediaAssetOnLayer,
    this.onHoverMediaAssetOnLayer,
    this.onLeaveMediaAssetOnLayer,
    this.silhouette,
    this.seClipMarkerTooltip,
    this.showSeconds = false,
    this.audioLane,
    this.commaDrag,
    this.rangeGesture,
    this.runEdit,
    this.baseLayer,
    this.seSpillInLeadFrames,
    this.windowBucket,
    this.viewportMainExtent = 0,
    this.substrateGeneration = '',
    this.unionLane,
  });

  /// The row's UNION key summary (the CAMERA row, B4 2026-08-17): a
  /// [transformUnionHeader] lane whose keys this row draws with the SHARED
  /// lane key markers — the same drawing, metric law and union data as the
  /// fx transform header's band. Null on every row whose union lives on a
  /// real lane row (or that has none).
  final PropertyLaneRow? unionLane;

  /// #29: the (project, cut) world this row's resolvers answer from —
  /// see [TimelineRowCellsPainter.substrateGeneration]. Rides the same
  /// rebuild that carries the new cut's rows, so the tile store's live
  /// generation can never skew from the rows on screen.
  final String substrateGeneration;

  final Layer layer;
  final int playbackFrameCount;

  /// The LIVE frame-axis geometry — the part a ZOOM STEP moves (R28 #4).
  ///
  /// It arrives as a listenable, not as scalars, so the row's memo can key
  /// on its IDENTITY and a zoom step reaches the painted rows as a repaint
  /// plus one box relayout instead of rebuilding every visible row's whole
  /// subtree. The SPARSE kinds (SE / instruction / camera, whose cells and
  /// overlays are still a widget apiece) read `geometry.value` at build time
  /// and stay in the memo key by value — they rebuild on zoom exactly as
  /// before.
  final TimelineFrameGeometryHandle geometry;

  /// Row height (horizontal) / column width (X-sheet). NOT a zoom field.
  final double crossAxisExtent;

  /// The frame axis this row lays its cells along: horizontal in the layer
  /// timeline, vertical in the X-sheet. Every axis-aware child overlay and
  /// the cell strip dispatch on it, so both orientations share this widget.
  final Axis axis;

  /// The semantic-key namespace ('timeline' | 'xsheet'): the widget's keys
  /// read `<keyPrefix>-frame-<row|column>-...` so each surface keeps the
  /// keys its widget tests pin.
  final String keyPrefix;

  /// PRO-TIMELINE scrolling (UI-R15→R16): with these set, the row builds
  /// ONCE for the FULL frame bounds — the painter windows itself off the
  /// quantized [windowBucket] (repaint once per span crossing, pure
  /// translation between), the sparse widget-cell kinds re-window their
  /// cells under the same bucket, and the overlays (grips, handles, SE
  /// writing) position content-absolutely. Null keeps the classic
  /// pre-windowed contract.
  final ValueListenable<int>? windowBucket;
  final double viewportMainExtent;
  final TimelineCellExposureState Function(Layer layer, int frameIndex)
  exposureStateForLayer;
  final String? Function(Layer layer, int frameIndex)? frameNameForLayer;

  /// R26 #44: the unworked-block tint's fact source (see
  /// [TimelineCelContentSource]); null = no tint.
  final TimelineCelContentSource? celContent;

  /// ㉘: what this row's coverage follows when it is not the layer — see
  /// [TimelineRowCellsPainter.coverageIdentity].
  final Object? coverageIdentity;
  final ValueChanged<LayerId> onSelectLayer;
  final ValueChanged<int> onSelectFrame;

  /// 🚨T10's second half: the press turned out to be a TAP, so whatever was
  /// selected goes (유저: 「클릭하고 떼면 뭐든 비우게」). Null on surfaces
  /// that own no selection.
  final VoidCallback? onSettledPress;

  /// Double-tap cell editor hook; only kinds that open an editor get it
  /// (policy: [layerKindOpensCellEditorOnDoubleTap]).
  final void Function(LayerId layerId, int frameIndex)? onActivateCell;

  /// Resolves instruction ids to their vocabulary defs for CAM row chips;
  /// null hides instruction overlays.
  final CameraInstructionDef? Function(String instructionId)?
  instructionDefById;

  /// D26: the crossing-fade warning resolver, by span start key — null (or
  /// a null answer) mounts nothing, a string mounts the shared red corner
  /// marker with that hover text. The seClipMarkerTooltip threading
  /// convention, per span instead of per row.
  final String? Function(int spanStartKey)? instructionCrossingTooltip;

  /// Waveform peaks resolver for SE rows' audio clips; null hides them.
  final AudioPeaks? Function(String filePath)? audioPeaksFor;
  final ProjectFrameRate projectFrameRate;

  /// A media-browser row dropped on THIS drawing layer. Null on the rows
  /// that cannot take one (sound has its own block-level target).
  final void Function(LayerId layerId, int frameIndex, String path)?
  onDropMediaAssetOnLayer;

  /// Whether the file at a frame of THIS row can land there — the
  /// session's answer, which the drag's chip wears (「불가능 = 칩의 금지
  /// 표시」). Null is yes.
  final bool Function(LayerId layerId, int frameIndex, String path)?
  acceptsMediaAssetOnLayer;

  /// Where a file being dragged STANDS on this row, while it hovers — the
  /// same coordinate the drop would get, from the same conversion.
  ///
  /// ⚠️Separate from [acceptsMediaAssetOnLayer] because they answer two
  /// questions: that one says whether a landing is possible (the chip wears
  /// it), this one says where it would be. One callback doing both would be
  /// a flag answering two questions.
  final void Function(LayerId layerId, int frameIndex, String path)?
  onHoverMediaAssetOnLayer;

  /// The file is off this row: it left, or it was let go.
  final VoidCallback? onLeaveMediaAssetOnLayer;

  /// The cells this row would GAIN if the file now being dragged were let
  /// go — 「끄는 동안 보이는 것은 놓았을 때 생길 것이다」 (미디어 배치 라운드
  /// 2d-2). Null when nothing is being dragged over this row.
  ///
  /// ⚠️The cells themselves come from [layer], which is already the drag
  /// preview's row (the gate above substituted it): the blocks in the way
  /// have moved, and these are the ones that are not there yet. This span
  /// only says WHICH — it does not author anything, and nothing here asks
  /// where the drop would go.
  final ({int startIndex, int endIndexExclusive})? silhouette;

  /// Clipped-take marker tooltip (REC1-D); null = markers off (the
  /// clipping-notice toggle, threaded as the string itself).
  final String? seClipMarkerTooltip;

  /// The shared frames/seconds display toggle — the block duration labels
  /// (R26 #7) follow it.
  final bool showSeconds;

  /// What the audio lane may ask the session to do; this row uses the
  /// clip-remove menu and the media drop target. Null = display-only.
  final TimelineAudioLaneCallbacks? audioLane;

  /// Comma-drag hooks; null hides the block edge grips.
  final TimelineCommaDragCallbacks? commaDrag;

  /// The range select/move gesture bundle (UI-R8 — the block-body move
  /// handle's successor); null keeps the row display-only.
  final TimelineRangeGestureCallbacks? rangeGesture;

  /// The run-edge [+]/[↻] handle hooks (UI-R8); null hides the handles.
  final TimelineRunEditCallbacks? runEdit;

  /// The row's COMMITTED repository layer while [layer] carries a drag
  /// preview (kept for callers even though the range gesture layer mounts
  /// row-wide and never unmounts mid-preview); null falls back to [layer].
  final Layer? baseLayer;

  /// How far into its sound the block at frame 0 already is, when this
  /// track-SE row's display clone starts with a block spilling in from an
  /// earlier cut — null when nothing spills in. UI-R7 #6: the cut start
  /// draws the `~` continuation and the block's start grip stands down (its
  /// real start lives in that earlier cut). F-113: the block's waveform is
  /// drawn from this far into the file.
  final int? seSpillInLeadFrames;

  @override
  Widget build(BuildContext context) {
    // The SPARSE kinds' build-time snapshot. The painted paths never read
    // this — they take the listenable and follow it live.
    final frames = geometry.value;
    final overlays = _spanOverlays(context, frames);
    final grips = _spanGrips(frames);
    final chrome = _chromeResolver();
    final stack = Stack(
      key: ValueKey<String>('$keyPrefix-frame-$_axisWord-area-${layer.id}'),
      // The frame-axis box below sizes this row, so the cell strip (the one
      // non-positioned child) takes the box outright instead of sizing it.
      fit: StackFit.expand,
      children: [
        _cellsPaintArea(context),
        ?_silhouetteLayer(),
        // NO extra section-divider overlay (R3 feedback #6): section
        // boundaries share the same single hairline as every row boundary;
        // the rail's gutter bracket carries the section identity.
        // NO empty-stretch furniture here (R5-②): uncovered timeline cells
        // are already dark — the gray wash is print-sheet-only.
        if (overlays.isNotEmpty) _spanLayer(overlays),
        ?_rangeGestureLayer(),
        ?_editChromeLayer(chrome),
        // Grips ride ABOVE the chrome so the edges keep comma-drag priority.
        if (grips.isNotEmpty) _spanLayer(grips),
        ?_assetDropTarget(frames),
      ],
    );
    // THE row's box (zoom round): it reports the row's content extent, as it
    // always did, but lays its child out at the geometry's window — a
    // constant pixel extent when the owner supplies one — and paints and
    // hit-tests that child at the window's origin. A zoom step then moves
    // this one box per row instead of the ~25 render objects inside it.
    // Without a window (X-sheet, tests, short content) it is exactly the box
    // it replaced.
    final body = TimelineFrameAxisBox(
      geometry: geometry,
      crossAxisExtent: crossAxisExtent,
      axis: axis,
      child: stack,
    );
    // The X-sheet column is cross-axis sized to the layer's row height (its
    // width); the horizontal row takes its height from the parent list.
    return axis == Axis.vertical
        ? SizedBox(width: crossAxisExtent, child: body)
        : body;
  }

  String get _axisWord => axis == Axis.vertical ? 'column' : 'row';

  /// Grips ride every drawing-holding kind; the run clusters skip the SE
  /// sheet rows (their spans are sound clips, not glued cel runs). SYNCED
  /// attach rows show NEITHER (the synced-block UI): their blocks are
  /// borrowed exposures — timing belongs to the owner, so the row renders
  /// block-shaped but edge-less. The IMAGE row joins that standdown (D22,
  /// 유저 08-17: 엣지 자체 부재): its one picture exists throughout — 1 cell +
  /// a fixed hold — and the cut's length is authored where it lives, on the
  /// storyboard.
  bool get _wantsGrips =>
      commaDrag != null &&
      layer.kind.holdsDrawings &&
      !layer.kind.holdsSingleCel &&
      !isSyncedAttachedLayer(layer);

  /// The run clusters carry the N/H/R property tag, so the rows that refuse
  /// repeat regions (the storyboard's, design E) show no cluster rather than
  /// one whose menu is dead.
  bool get _wantsRunEdges =>
      runEdit != null &&
      layer.kind.acceptsRepeatRegions &&
      !layerKindUsesSeSheetCells(layer.kind) &&
      !isSyncedAttachedLayer(layer);

  TimelineRowChromeResolver? _chromeResolver() {
    final wantsGrips = _wantsGrips;
    final wantsRunEdges = _wantsRunEdges;
    if (!wantsGrips && !wantsRunEdges) return null;
    return TimelineRowChromeResolver(
      gripBlocks: wantsGrips ? _gripBlocks() : const [],
      gripIdScope: layer.id.value,
      layer: layer,
      baseLayer: baseLayer,
      // I-44: the chrome stands on the block's PAPER — the row short of its
      // seam — so the edge triangles sit in the paper's own corners.
      crossAxisExtent: timelineRowPaperExtent(crossAxisExtent),
      axis: axis,
      includeRunEdges: wantsRunEdges,
    );
  }

  List<TimelineChromeGripBlock> _gripBlocks() => timelineLayerGripBlocks(
    layer,
    // The spill-in block's `~` replaces its start grip (UI-R7 #6) — and
    // the conte row's first block answers the same way, for its own
    // reason (below).
    // ↩️I-21 (유저 2026-09-12) GAVE THE CONTE ROW ITS FRONT EDGES BACK:
    // 「이제 이렇게하면 타임라인 내 콘티블록의 앞엣지를 살려도 된다고
    // 생각하니 살리도록. 왜냐면 앞엣지가 더이상 컷길이를 바꾸지 않으니까」.
    // A lead edge trades frames with the block in front of it now, so a
    // gapless row's front edge re-times two blocks inside the cut and
    // leaves the cut's own length alone.
    //
    // ⛔EXCEPT THE FIRST BLOCK'S, which is the cut's own start: 「다만
    // 그렇다고 해도 타임라인 내 콘티블록의 첫번째 블록의 앞엣지는 진짜
    // 컷길이 바꾸니까 그거만 없도록」 — that edge lives on the storyboard
    // strip, where it re-times the film rather than the row.
    suppressStartGripAtZero:
        (seSpillInLeadFrames != null &&
            layerKindUsesSeSheetCells(layer.kind)) ||
        layer.kind.coversWithoutGaps,
  );

  /// A positioned overlay layer placed by [TimelineFrameSpanLayout] at
  /// LAYOUT time, which is what lets these rows keep their memo through a
  /// zoom step — position used to be a build-time scalar, so a zoom
  /// reconstructed every one of them.
  /// 「아직 없는 것」 drawn over the cells it would fill.
  ///
  /// Through the SAME span layout the drop targets and the SE writing ride,
  /// so the outline lands on the cells' own pixels and no second frame→pixel
  /// arithmetic exists to drift from them. ABOVE the cells and BELOW the
  /// gestures: a silhouette is something to look at, not something to press
  /// (a painter-only `CustomPaint` answers no hit test, so the range pan and
  /// the drop target underneath keep every pointer).
  Widget? _silhouetteLayer() {
    final span = silhouette;
    if (span == null) {
      return null;
    }
    return _spanLayer([
      TimelineFrameSpan(
        placement: TimelineFrameSpanPlacement(
          startIndex: span.startIndex,
          endIndexExclusive: span.endIndexExclusive,
        ),
        child: CustomPaint(
          painter: TimelineSilhouettePainter(
            frames: span.endIndexExclusive - span.startIndex,
            axis: axis,
          ),
        ),
      ),
    ]);
  }

  Widget _spanLayer(List<Widget> children) => Positioned.fill(
    child: TimelineFrameSpanLayout(
      geometry: geometry,
      crossAxisExtent: crossAxisExtent,
      axis: axis,
      children: children,
    ),
  );

  // ── the sparse kinds' span overlays ───────────────────────────────────

  List<Widget> _spanOverlays(
    BuildContext context,
    TimelineFrameGeometry frames,
  ) => [
    ..._seOverlays(context, frames),
    ..._instructionOverlays(context, frames),
    ..._unionMarkers(),
  ];

  /// SE rows: audio clips painted over the paper cells (clipped to the
  /// row's drawing blocks — no block, no waveform), the sheet's writing on
  /// the blocks (name box at the block start plus the dialogue fitted across
  /// the span), the clipped-take markers (REC1-D — the tooltip string
  /// doubles as the switch), the cut-boundary `~` marks (UI-R7 #6: a sound
  /// running past the cut end / spilling in from the previous cut announces
  /// its other half), and the media-browser drop targets (sound → block
  /// frame).
  List<Widget> _seOverlays(BuildContext context, TimelineFrameGeometry frames) {
    if (!layerKindUsesSeSheetCells(layer.kind)) return const [];
    final peaksFor = audioPeaksFor;
    final clipTooltip = seClipMarkerTooltip;
    final onDropAsset = audioLane?.onDropMediaAsset;
    return [
      if (peaksFor != null)
        ...timelineRowAudioOverlays(
          layer: layer,
          frameStartIndex: frames.frameStartIndex,
          frameEndIndexExclusive: frames.frameEndIndexExclusive,
          axis: axis,
          frameRate: projectFrameRate,
          audioPeaksFor: peaksFor,
          color: timelineDrawingInkColor.withValues(alpha: 0.22),
          leadInAtStart: seSpillInLeadFrames ?? 0,
          keyPrefix: keyPrefix,
        ),
      ...timelineRowSeLabelOverlays(
        layer: layer,
        frameStartIndex: frames.frameStartIndex,
        frameEndIndexExclusive: frames.frameEndIndexExclusive,
        axis: axis,
        keyPrefix: keyPrefix,
      ),
      if (clipTooltip != null)
        ...timelineRowClipMarkerOverlays(
          layer: layer,
          frameStartIndex: frames.frameStartIndex,
          frameEndIndexExclusive: frames.frameEndIndexExclusive,
          crossAxisExtent: crossAxisExtent,
          axis: axis,
          tooltip: clipTooltip,
          color: Theme.of(context).colorScheme.error,
          keyPrefix: keyPrefix,
        ),
      ...timelineRowSeContinuationMarks(
        layer: layer,
        cutFrameCount: playbackFrameCount,
        spillsInAtStart: seSpillInLeadFrames != null,
        frameStartIndex: frames.frameStartIndex,
        frameEndIndexExclusive: frames.frameEndIndexExclusive,
        keyPrefix: keyPrefix,
      ),
      if (onDropAsset != null)
        ...timelineRowSeAssetDropTargets(
          layer: layer,
          frameStartIndex: frames.frameStartIndex,
          frameEndIndexExclusive: frames.frameEndIndexExclusive,
          onAssetDropped: (blockStartFrame, path) =>
              onDropAsset(layer.id, blockStartFrame, path),
          keyPrefix: keyPrefix,
        ),
    ];
  }

  /// Instruction-carrying rows: the sheet's CAM column — bar arrows or the
  /// O.L bowtie on the paper block, A → B endpoint values and the name
  /// snapped to the anchor cell. The TRANSITION row draws here too — its
  /// marks are a projection of the global row, read-only but visible.
  List<Widget> _instructionOverlays(
    BuildContext context,
    TimelineFrameGeometry frames,
  ) {
    final defById = instructionDefById;
    if (!layer.kind.carriesInstructions || defById == null) {
      return const [];
    }
    return timelineRowInstructionOverlays(
      layer: layer,
      frameStartIndex: frames.frameStartIndex,
      frameEndIndexExclusive: frames.frameEndIndexExclusive,
      axis: axis,
      defById: defById,
      keyPrefix: keyPrefix,
      // D26: the crossing-fade refusal wears the SE clip marker's own red
      // corner + tooltip, always-on (a refusal warning takes no settings
      // gate — style reuse is not switch reuse).
      crossingWarningTooltip: instructionCrossingTooltip,
      crossingWarningColor: Theme.of(context).colorScheme.error,
      crossAxisExtent: crossAxisExtent,
    );
  }

  /// The CAMERA row's union key markers (B4): THE shared lane key marker
  /// drawing at THE union size, placed by the span layout so the row's memo
  /// survives zoom steps. Display-only — the range gesture layer above owns
  /// every pointer, exactly like the lane bands'.
  List<Widget> _unionMarkers() {
    final lane = unionLane;
    if (lane == null) return const [];
    return timelineUnionKeyMarkerSpans(
      keyPrefix: keyPrefix,
      layer: layer,
      lane: lane,
      crossExtent: crossAxisExtent,
    );
  }

  /// 🚨Grips are the one instruction facility the transition row does NOT
  /// get: its local placement is a projection ([LayerKind.isReadOnlyInCut]),
  /// so dragging an edge here would be editing a lie. Authoring lives on the
  /// global axis, in the storyboard.
  List<Widget> _spanGrips(TimelineFrameGeometry frames) {
    final drag = commaDrag;
    if (drag == null ||
        !layer.kind.carriesInstructions ||
        layer.kind.isReadOnlyInCut) {
      return const [];
    }
    return timelineRowInstructionEdgeGrips(
      layer: layer,
      frameStartIndex: frames.frameStartIndex,
      frameEndIndexExclusive: frames.frameEndIndexExclusive,
      resolveFrameCellExtent: () => geometry.value.frameCellExtent,
      commaDrag: drag,
      axis: axis,
      crossAxisExtent: crossAxisExtent,
    );
  }

  // ── the cells, the gestures, the chrome, the drop ─────────────────────

  /// EVERY row paints its cells as ONE CustomPaint (UI-R9 #12b, and R28 #4
  /// for the sparse kinds): the SE / instruction / camera rows used to
  /// render a widget per cell, which is what made a zoom step rebuild
  /// 140-180 widgets on four rows alone. The span overlays still position
  /// themselves as widgets — the cells beneath them are canvas work now.
  Widget _cellsPaintArea(BuildContext context) => timelineRowCellsPaintArea(
    context: context,
    keyPrefix: keyPrefix,
    layer: layer,
    geometry: geometry,
    crossAxisExtent: crossAxisExtent,
    axis: axis,
    windowBucket: windowBucket,
    viewportMainExtent: viewportMainExtent,
    substrateGeneration: substrateGeneration,
    foregroundPainter: _runLabelsPainter(),
    // Instruction-carrying rows have no timeline entries — their events
    // adapt onto the shared exposure states so the cells paint the same
    // paper blocks. A TOP-LEVEL tear-off, not a closure: the painter
    // value-compares this field, and a fresh closure per build would
    // re-record the row on every pass.
    exposureStateForLayer: layer.kind.bandIsInstructionsOnly
        ? instructionCellExposureState
        : exposureStateForLayer,
    frameNameForLayer: frameNameForLayer,
    celContent: celContent,
    // ㉘: what this row's coverage follows when it is not the layer.
    coverageIdentity: coverageIdentity,
    onSelectLayer: onSelectLayer,
    onSelectFrame: onSelectFrame,
    onSettledPress: onSettledPress,
    onActivateCell: layerKindOpensCellEditorOnDoubleTap(layer.kind)
        ? onActivateCell
        : null,
  );

  /// R26 #7 / R27 #3: each block prints ITS OWN length at its end cell. It
  /// rides the cells painter as a FOREGROUND pass — above the tiles, so the
  /// frames/seconds toggle stays a plain repaint and never joins a tile bake
  /// key (the reason it is not inside the cells painter itself).
  ///
  /// 🚨F-40 (유저 2026-08-28): 「se블록에 코마표시가 없음. **블록이면 뭐든
  /// 반드시 코마블록이 있어야함**」. 여기 `&& !layerKindUsesSeSheetCells` 가
  /// 붙어 있었다 — 그 술어는 **셀 글리프와 X 마크**를 억제하는 것이고 (SE 의
  /// 글자는 행 단위 오버레이가 그린다), **블록 길이와는 상관이 없다.** 한 술어가
  /// 두 질문에 답하고 있었다. ⇒ 이제 조건은 「블록을 가졌나」 하나다. 그게
  /// `LayerKind.holdsDrawings` 이고 se 는 거기서 true 다.
  CustomPainter? _runLabelsPainter() {
    if (!layer.kind.holdsDrawings) return null;
    return TimelineRowRunLabelsPainter(
      layer: layer,
      geometry: geometry,
      crossAxisExtent: crossAxisExtent,
      showSeconds: showSeconds,
      countingBase: projectFrameRate.countingBase,
      axis: axis,
    );
  }

  /// The range gesture layer replaces the block-body move handle (UI-R8,
  /// TVP style): a pan on the cells SELECTS a frame range — a pan starting
  /// inside the current selection MOVES it. Mounted UNDER the grips so the
  /// edges keep comma-drag priority. EVERY layer row mounts it (UI-R20 #2:
  /// cells are cells — SE, camera and instruction rows select too; what a
  /// selection can DO stays kind-gated at the session seams).
  Widget? _rangeGestureLayer() {
    final gesture = rangeGesture;
    if (gesture == null) return null;
    return TimelineFrameRangeGestureLayer(
      // The SLOT key (R12-③ rule, UI-R22 #1): mid-drag previews add/remove
      // sibling overlays in this Stack — without a key the positional
      // rematch REMOUNTS this layer and its dispose commits the move under
      // the pointer.
      key: ValueKey<String>('$keyPrefix-range-gesture-slot-${layer.id}'),
      row: LayerRowAddress(layer.id),
      geometry: geometry,
      crossAxisExtent: crossAxisExtent,
      callbacks: gesture,
      axis: axis,
    );
  }

  /// The block edit chrome — comma grips plus the TVP run-edge clusters
  /// ([+] add-frames over the N/H/R property tag, hugging each glued run's
  /// edges). ONE painter and ONE gesture layer for the whole row (R28 #4
  /// tier 2): these were a Positioned box per grip and a two-Text Column per
  /// run edge, so a zoom step re-laid out rows x (blocks + runs) of them.
  ///
  /// Identity vs display (R12-③, UI-R11 #1/#2): the run clusters position
  /// on the DISPLAY layer (they ride previews) but call back with the
  /// COMMITTED run's identity, and the layer itself no longer remounts
  /// mid-gesture at all — its state lives at row level.
  Widget? _editChromeLayer(TimelineRowChromeResolver? resolver) {
    if (resolver == null) return null;
    final drag = commaDrag;
    return Positioned.fill(
      // The SLOT key (R12-③ rule, UI-R22 #1): mid-drag previews add/remove
      // sibling overlays in this Stack.
      key: ValueKey<String>('$keyPrefix-edit-chrome-slot-${layer.id}'),
      child: TimelineRowEditChromeLayer(
        paintKey: ValueKey<String>('$keyPrefix-edit-chrome-${layer.id}'),
        layerId: layer.id,
        resolver: resolver,
        geometry: geometry,
        axis: axis,
        // The grips sit on THIS row's blocks, and the blocks are the layer's
        // color label (⑲) — so a purple row's bars go black by the same
        // ground law its numbers follow.
        gripGround: layerMarkColor(layer.mark),
        // The row closes its LayerId into the identity-free grip hooks — the
        // chrome layer serves cut rows too now, and a grip drag is the same
        // gesture on both.
        grips: drag == null
            ? null
            : TimelineRowGripCallbacks(
                onBegin: (blockStartIndex, _, edge) =>
                    drag.onBegin(layer.id, blockStartIndex, edge),
                onUpdate: drag.onUpdate,
                onEnd: drag.onEnd,
                onCancel: drag.onCancel,
              ),
        runEdit: runEdit,
      ),
    );
  }

  /// A media-browser row dropped on a DRAWING layer opens the place window
  /// with this cut and this layer already answered — the drop FILLS the
  /// answers, and the window still asks them.
  ///
  /// TOP OF THE STACK, and that is the whole of it: mounted with the span
  /// overlays it sat UNDER the range-gesture layer and the edit chrome, both
  /// of which cover the row, and a drop landed on them instead. A DragTarget
  /// is translucent to hit testing and carries no recognizer of its own, so
  /// being on top costs the layers below nothing — the pan that selects a
  /// range still reaches them.
  ///
  /// Whole-row rather than per-cell: what a drop names here is the LAYER,
  /// and a target that only lit over exposed cels would refuse the empty
  /// stretch of a row nobody has drawn on yet. Through the SPAN layout, not
  /// `Positioned.fill`: this row's box reports the whole content extent
  /// while it lays out and hit-tests only the geometry's WINDOW, so a filled
  /// child is mostly rectangle nobody can touch — its centre lands outside
  /// the window on any row long enough to scroll.
  Widget? _assetDropTarget(TimelineFrameGeometry frames) {
    final onDrop = onDropMediaAssetOnLayer;
    if (onDrop == null || !layer.kind.holdsDrawings) {
      return null;
    }
    if (layerKindUsesSeSheetCells(layer.kind)) {
      return _seCellDropTargets(frames, onDrop);
    }
    return _spanLayer([
      TimelineFrameSpan(
        placement: TimelineFrameSpanPlacement(
          startIndex: frames.frameStartIndex,
          endIndexExclusive: frames.frameEndIndexExclusive,
        ),
        child: _LayerAssetDropTarget(
          dropKey: ValueKey<String>('$keyPrefix-layer-asset-drop-${layer.id}'),
          layerId: layer.id,
          geometry: geometry,
          axis: axis,
          onDrop: onDrop,
          acceptsDrop: acceptsMediaAssetOnLayer,
          onHoverAt: onHoverMediaAssetOnLayer,
          onLeave: onLeaveMediaAssetOnLayer,
        ),
      ),
    ]);
  }

  /// An SE row's EMPTY stretches, each a place entrance for a new sound
  /// (유저 2026-09-11: 「SE 행의 빈 칸 → 새 블록」). On top, like every drop
  /// target on a row — under the range layer and the chrome, an empty
  /// cell's drop lands on THEM — but only over the gaps: a block keeps its
  /// own target in [_seOverlays], and a sound let go on it joins it, as
  /// before. The gaps are [emptyGapsBetween]'s, the one free-span answer.
  Widget? _seCellDropTargets(
    TimelineFrameGeometry frames,
    void Function(LayerId layerId, int frameIndex, String path) onDrop,
  ) {
    final gaps = emptyGapsBetween(
      layer,
      frames.frameStartIndex,
      frames.frameEndIndexExclusive,
    );
    if (gaps.isEmpty) {
      return null;
    }
    return _spanLayer([
      for (final gap in gaps)
        TimelineFrameSpan(
          placement: TimelineFrameSpanPlacement(
            startIndex: gap.startIndex,
            endIndexExclusive: gap.startIndex + gap.length,
          ),
          child: _LayerAssetDropTarget(
            dropKey: ValueKey<String>(
              '$keyPrefix-se-cell-drop-${layer.id}-${gap.startIndex}',
            ),
            layerId: layer.id,
            geometry: geometry,
            axis: axis,
            spanStartIndex: gap.startIndex,
            onDrop: onDrop,
            acceptsDrop: acceptsMediaAssetOnLayer,
            onHoverAt: onHoverMediaAssetOnLayer,
            onLeave: onLeaveMediaAssetOnLayer,
          ),
        ),
    ]);
  }
}

/// The row's share of a place entrance ([MediaAssetDropTarget] is the
/// entrance itself): the one thing a drop on a LAYER row has to work out is
/// WHICH FRAME it landed on.
///
/// The coordinate it reads comes with the anchor caveat the shared target
/// documents — this is the host that depends on it.
class _LayerAssetDropTarget extends StatelessWidget {
  const _LayerAssetDropTarget({
    required this.dropKey,
    required this.layerId,
    required this.geometry,
    required this.axis,
    required this.onDrop,
    this.spanStartIndex,
    this.acceptsDrop,
    this.onHoverAt,
    this.onLeave,
  });

  final Key dropKey;
  final LayerId layerId;
  final TimelineFrameGeometryHandle geometry;
  final Axis axis;
  final void Function(LayerId layerId, int frameIndex, String path) onDrop;

  /// Whether the file at a frame can land there; null is yes.
  final bool Function(LayerId layerId, int frameIndex, String path)?
  acceptsDrop;

  /// Where the hovering file stands, per pointer step — the coordinate the
  /// drop would land on, so what is drawn while it hovers cannot disagree
  /// with what a release does.
  final void Function(LayerId layerId, int frameIndex, String path)? onHoverAt;

  /// It left, or it was let go.
  final VoidCallback? onLeave;

  /// The frame this target's span starts at — the row's first visible frame
  /// when null (a drawing row's whole-row target), a gap's first frame for an
  /// SE row's empty stretch.
  final int? spanStartIndex;

  /// This widget's box IS the span that starts at [spanStartIndex], so a
  /// local offset plus that frame's edge is a ROW-local one — which is the
  /// coordinate space the geometry answers in, window and all.
  int _frameIndexAt(BuildContext context, Offset globalPosition) {
    final frames = geometry.value;
    final start = spanStartIndex ?? frames.frameStartIndex;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return start;
    }
    final local = box.globalToLocal(globalPosition);
    return frames.frameIndexAt(
      frames.edgeAt(start) + (axis == Axis.horizontal ? local.dx : local.dy),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accepts = acceptsDrop;
    final hover = onHoverAt;
    return MediaAssetDropTarget(
      key: dropKey,
      accepts: accepts == null
          ? null
          : (data, globalPosition) => accepts(
              layerId,
              _frameIndexAt(context, globalPosition),
              data.path,
            ),
      onHover: hover == null
          ? null
          : (data, globalPosition) => hover(
              layerId,
              _frameIndexAt(context, globalPosition),
              data.path,
            ),
      onLeave: onLeave,
      onDrop: (data, globalPosition) =>
          onDrop(layerId, _frameIndexAt(context, globalPosition), data.path),
    );
  }
}
