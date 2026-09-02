import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/attached_layer_resolve.dart';
import '../../models/camera_instruction.dart';
import '../../models/layer.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
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
    required this.active,
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
    this.seClipMarkerTooltip,
    this.showSeconds = false,
    this.audioLane,
    this.commaDrag,
    this.rangeGesture,
    this.runEdit,
    this.baseLayer,
    this.seSpillsIn = false,
    this.windowBucket,
    this.viewportMainExtent = 0,
    this.substrateGeneration = '',
    this.chromeless = false,
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

  /// GROUND OFF — see [TimelineRowCellsPainter.chromeless] for the confirmed
  /// look and for why the flag lives on the row instead of in its caller.
  ///
  /// The twin is [TimelineLayerControlsRow.chromeless]: the collapsed row
  /// mounts BOTH halves of the real thing, and each half takes its ground off
  /// the same way. That is the whole of ⑩'s root C — an overlay that owns no
  /// drawing code cannot drift from what the panel shows.
  final bool chromeless;

  final Layer layer;
  final bool active;
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

  /// Track-SE rows whose display clone starts with a block spilling in
  /// from an earlier cut (UI-R7 #6): the cut start draws the `~`
  /// continuation and the block's start grip stands down (its real start
  /// lives in that earlier cut).
  final bool seSpillsIn;

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
      layerKindHoldsDrawings(layer.kind) &&
      !layerKindHoldsSingleCel(layer.kind) &&
      !isSyncedAttachedLayer(layer);

  /// The run clusters carry the N/H/R property tag, so the rows that refuse
  /// repeat regions (the storyboard's, design E) show no cluster rather than
  /// one whose menu is dead.
  bool get _wantsRunEdges =>
      runEdit != null &&
      layerKindAcceptsRepeatRegions(layer.kind) &&
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
      crossAxisExtent: crossAxisExtent,
      axis: axis,
      includeRunEdges: wantsRunEdges,
    );
  }

  List<TimelineChromeGripBlock> _gripBlocks() => timelineLayerGripBlocks(
    layer,
    // The spill-in block's `~` replaces its start grip (UI-R7 #6).
    suppressStartGripAtZero:
        seSpillsIn && layerKindUsesSeSheetCells(layer.kind),
    // A storyboard row has NO start grips at all (edge unification;
    // feedback #10 removed the one at zero): every boundary is the trailing
    // edge on its left, and the row's true front edge is the cut's start,
    // which lives on the storyboard strip.
    suppressAllStartGrips: layerKindCoversWithoutGaps(layer.kind),
  );

  /// A positioned overlay layer placed by [TimelineFrameSpanLayout] at
  /// LAYOUT time, which is what lets these rows keep their memo through a
  /// zoom step — position used to be a build-time scalar, so a zoom
  /// reconstructed every one of them.
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
        spillsInAtStart: seSpillsIn,
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
    if (!layerKindCarriesInstructions(layer.kind) || defById == null) {
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
  /// get: its local placement is a projection ([layerKindIsReadOnlyInCut]),
  /// so dragging an edge here would be editing a lie. Authoring lives on the
  /// global axis, in the storyboard.
  List<Widget> _spanGrips(TimelineFrameGeometry frames) {
    final drag = commaDrag;
    if (drag == null ||
        !layerKindCarriesInstructions(layer.kind) ||
        layerKindIsReadOnlyInCut(layer.kind)) {
      return const [];
    }
    return timelineRowInstructionEdgeGrips(
      layer: layer,
      frameStartIndex: frames.frameStartIndex,
      frameEndIndexExclusive: frames.frameEndIndexExclusive,
      resolveFrameCellExtent: () => geometry.value.frameCellExtent,
      commaDrag: drag,
      axis: axis,
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
    active: active,
    geometry: geometry,
    crossAxisExtent: crossAxisExtent,
    axis: axis,
    windowBucket: windowBucket,
    viewportMainExtent: viewportMainExtent,
    substrateGeneration: substrateGeneration,
    chromeless: chromeless,
    // D32/D38: the interior seam law's beat strengths.
    framesPerSecond: projectFrameRate.countingBase,
    foregroundPainter: _runLabelsPainter(),
    // Instruction-carrying rows have no timeline entries — their events
    // adapt onto the shared exposure states so the cells paint the same
    // paper blocks. A TOP-LEVEL tear-off, not a closure: the painter
    // value-compares this field, and a fresh closure per build would
    // re-record the row on every pass.
    exposureStateForLayer: layerKindBandIsInstructionsOnly(layer.kind)
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
  /// `layerKindHoldsDrawings` 이고 se 는 거기서 true 다.
  CustomPainter? _runLabelsPainter() {
    if (!layerKindHoldsDrawings(layer.kind)) return null;
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
    if (onDrop == null ||
        layerKindUsesSeSheetCells(layer.kind) ||
        !layerKindHoldsDrawings(layer.kind)) {
      return null;
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
  });

  final Key dropKey;
  final LayerId layerId;
  final TimelineFrameGeometryHandle geometry;
  final Axis axis;
  final void Function(LayerId layerId, int frameIndex, String path) onDrop;

  /// This widget's box IS the span that starts at the row's first frame, so
  /// a local offset plus that frame's edge is a ROW-local one — which is the
  /// coordinate space the geometry answers in, window and all.
  int _frameIndexAt(BuildContext context, Offset globalPosition) {
    final frames = geometry.value;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return frames.frameStartIndex;
    }
    final local = box.globalToLocal(globalPosition);
    return frames.frameIndexAt(
      frames.edgeAt(frames.frameStartIndex) +
          (axis == Axis.horizontal ? local.dx : local.dy),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MediaAssetDropTarget(
      key: dropKey,
      onDrop: (path, globalPosition) =>
          onDrop(layerId, _frameIndexAt(context, globalPosition), path),
    );
  }
}
