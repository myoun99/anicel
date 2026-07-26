import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/app_language.dart' show AppLanguage;
import '../../models/audio_clip.dart' show AudioFadeCurve, AudioVolumeKey;
import '../text/app_strings.dart';
import '../../models/camera_instruction.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_mark.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../widgets/field_slider.dart';
import 'layer_label_controls.dart';
import 'timeline_cel_content_source.dart';
import 'timeline_cell_exposure_state.dart';
import 'package:flutter/semantics.dart' show SemanticsProperties;

import 'timeline_cell_style.dart';
import 'timeline_frame_ruler_painter.dart' show TimelineRulerHeaderModel;
import 'timeline_cut_end_handle.dart';
import 'timeline_drag_preview.dart';
import 'timeline_exposure_comma_drag_policy.dart';
import '../../models/project_frame_rate.dart';
import 'timeline_edge_auto_pan.dart';
import 'timeline_row_span_resolver.dart' show resolveBlockMoveTargetLayer;
import 'timeline_frame_range_gesture.dart';
import 'timeline_ruler_cursor_overlay.dart';
import 'timeline_run_end_handles.dart';
import 'timeline_frame_cells_row.dart' show TimelineFrameCellsRow;
import 'timeline_frame_geometry.dart'
    show TimelineFrameGeometry, timelineFrameWindowMarginPx;
import 'timeline_frame_coordinate_policy.dart';
import 'timeline_frame_cursor_layer.dart';
import 'timeline_beat_lines.dart';
import 'timeline_frame_range_policy.dart';
import 'timeline_frame_window.dart';
import 'timeline_glyph_cache.dart';
import 'timeline_body_cut_end_boundary.dart';
import 'timeline_cell_editor_policy.dart';
import 'property_lane_model.dart';
import 'timeline_row_filter.dart';
import 'timeline_grid_metrics.dart';
import 'se_audio_lane.dart';
import 'timeline_lane_rows.dart';
import 'timeline_horizontal_offset_policy.dart';
import 'pen_friendly_scroll_controller.dart';
import 'stylus_glide_stop.dart';
import 'timeline_horizontal_scrollbar_rail.dart';
import 'timeline_ruler_cut_end_boundary.dart';
import 'timeline_section_policy.dart';
import 'timeline_section_runs.dart';
import 'timeline_vertical_scrollbar_rail.dart';
import 'timeline_virtualization_plan.dart';
import 'timeline_visible_range.dart';
import 'timeline_zoom_anchor_policy.dart';

/// The vertical X-sheet: the SAME grid logic as the horizontal
/// [LayerTimelineGrid], transposed.
///
/// The transposition is a metrics trick: the frame axis runs vertically, so
/// [_metrics.frameCellWidth] is the frame ROW height and
/// [_metrics.layerRowHeight] is the layer COLUMN width. Every policy the
/// horizontal grid uses — frame range, offset resolution, virtualization
/// plan, coordinate conversion, cell style/block visuals, selected exposure
/// range, playhead visibility, cut-end boundary — is reused unchanged with
/// the axes swapped; only the thin widget composition differs.
class XSheetTimelineGrid extends StatefulWidget {
  const XSheetTimelineGrid({
    super.key,
    required this.layers,
    required this.activeLayerId,
    required this.frameCursor,
    this.frameCachedSignal,
    required this.frameCount,
    required this.exposureStateForLayer,
    this.frameNameForLayer,
    this.celContent,
    required this.onSelectLayer,
    required this.onSelectFrame,
    this.onScrubFrame,
    this.onScrubEnd,
    this.onActivateCell,
    this.instructionDefById,
    this.audioPeaksFor,
    this.projectFrameRate = ProjectFrameRate.fps24,
    this.showSeconds = false,
    this.audioLane,
    this.onSetAudioClipFadeCurve,
    this.onSetAudioClipEnvelope,
    this.resolveStrings,
    this.isLayerSoloed,
    this.onToggleLayerSolo,
    this.onEditLayerAudio,
    required this.onAddLayer,
    required this.onToggleLayerVisibility,
    required this.onLayerOpacityChanged,
    this.onLayerOpacityChangeEnd,
    this.opacityDragPreview,
    required this.onToggleLayerTimesheet,
    required this.onLayerMarkSelected,
    this.layerFxEnabledOf,
    this.onToggleLayerFx,
    this.onToggleLayerFillReference,
    this.onToggleLayerMuted,
    this.commaDrag,
    this.rangeHooks,
    this.laneRange,
    this.runEdit,
    this.isFrameCached,
    this.metrics = defaultMetrics,
    this.expandedLaneLayerIds = const {},
    this.onToggleLayerLanes,
    this.lanesForLayer,
    this.laneEdit,
    this.onToggleLaneGroup,
    this.hiddenSections = const {},
    this.rowFilter = TimelineRowFilter.none,
    this.collapsedAttachBaseIds = const {},
    this.seSpillInLayerIds = const {},
    this.seClipMarkerTooltip,
    this.dragPreview,
    this.cutEndDrag,
  });

  final List<Layer> layers;
  final LayerId? activeLayerId;

  /// Track-SE layers whose sound spills in from the previous cut (UI-R7 #6):
  /// their first block shows the `~` continuation mark instead of a start
  /// grip. Mirrors the horizontal timeline's plumbing.
  final Set<LayerId> seSpillInLayerIds;

  /// The recorded-take clipping warning tooltip (REC1-D): non-null mounts
  /// the red block-corner marker on SE cells, matching the horizontal
  /// timeline. Null hides it (the "clipping notice" setting is off).
  final String? seClipMarkerTooltip;

  /// The session's edit-drag preview channel: a comma-drag step rebuilds
  /// only the dragged layer's column (its gate) and the cursor overlay —
  /// never this grid.
  final ValueListenable<TimelineDragPreview?>? dragPreview;

  /// End-line drag hooks (UI-R18 #14): the red cut-end boundary grows a
  /// grip that end-trims the ACTIVE cut; the line follows the live trim
  /// preview. Null = display-only.
  final TimelineCutEndDragCallbacks? cutEndDrag;

  /// The frame cursor (editing playhead / playback position). Only the
  /// cursor layer, the frame-number rail and the lane headers subscribe —
  /// ticks never rebuild the grid (playback-performance architecture,
  /// mirroring the horizontal timeline).
  final ValueListenable<int> frameCursor;

  /// Repaints the frame rail's cached-range green strip as frames warm.
  final Listenable? frameCachedSignal;

  /// Playback frame count of the active cut (the visible range extends to
  /// the shared minimum, exactly like the horizontal timeline).
  final int frameCount;
  final TimelineCellExposureState Function(Layer layer, int frameIndex)
  exposureStateForLayer;
  final String? Function(Layer layer, int frameIndex)? frameNameForLayer;

  /// R26 #44: the unworked-block tint's fact and its event (null = no tint).
  final TimelineCelContentSource? celContent;
  final ValueChanged<LayerId> onSelectLayer;
  final ValueChanged<int> onSelectFrame;

  /// Frame-rail scrub path: per-move frames go to [onScrubFrame]
  /// (cursor-only, no commit) and the pointer's release fires [onScrubEnd]
  /// to commit once. Null falls back to [onSelectFrame] per move.
  final ValueChanged<int>? onScrubFrame;
  final VoidCallback? onScrubEnd;

  /// Double-tap cell editor hook (SE label dialog; see
  /// [layerKindOpensCellEditorOnDoubleTap]).
  final void Function(LayerId layerId, int frameIndex)? onActivateCell;

  /// Resolves instruction ids to defs for CAM column chips.
  final CameraInstructionDef? Function(String instructionId)?
  instructionDefById;

  /// Waveform peaks for SE columns' audio clips + the removal hook.
  final AudioPeaks? Function(String filePath)? audioPeaksFor;
  final ProjectFrameRate projectFrameRate;

  /// The frame rail's number mode (UI-R10 #27): seconds display repeats
  /// 1..fps per second instead of absolute frame numbers.
  final bool showSeconds;

  /// What the audio lane may ask the session to do; null = display-only.
  final TimelineAudioLaneCallbacks? audioLane;

  /// Commits the audio-lane fade-curve toggle (AUDIO-PRO R1).
  final void Function(LayerId layerId, int clipIndex, AudioFadeCurve curve)?
  onSetAudioClipFadeCurve;

  /// Commits the audio-lane volume-envelope dialog (AUDIO-PRO R1).
  final void Function(
    LayerId layerId,
    int clipIndex,
    List<AudioVolumeKey> keys,
  )?
  onSetAudioClipEnvelope;

  /// The PROGRAM-language table for the audio menus and dialogs; null
  /// keeps English (the incremental-coverage rule).
  final AppStrings Function()? resolveStrings;

  /// The SE mix menu (AUDIO-PRO R1): solo state/toggle + the fader/pan
  /// dialog entrance, on the speaker button's context menu.
  final bool Function(LayerId layerId)? isLayerSoloed;
  final ValueChanged<LayerId>? onToggleLayerSolo;
  final ValueChanged<LayerId>? onEditLayerAudio;

  final VoidCallback onAddLayer;
  final ValueChanged<LayerId> onToggleLayerVisibility;
  final void Function(LayerId layerId, double opacity) onLayerOpacityChanged;

  /// Commit-on-release hook (R4 #4); null keeps per-move writes.
  final void Function(LayerId layerId, double opacity)? onLayerOpacityChangeEnd;

  /// The session's live opacity-drag preview (UI-R6 #2).
  final ValueListenable<({Set<LayerId> layerIds, double opacity})?>?
  opacityDragPreview;

  final ValueChanged<LayerId> onToggleLayerTimesheet;
  final void Function(LayerId layerId, LayerMark mark) onLayerMarkSelected;

  /// The AE-style layer fx switch (session view state); null hides it.
  final bool Function(LayerId layerId)? layerFxEnabledOf;
  final ValueChanged<LayerId>? onToggleLayerFx;

  /// Drawing rows' fill-reference toggle (R20-C2); null hides it.
  final ValueChanged<LayerId>? onToggleLayerFillReference;

  /// SE columns' speaker button (mute); null hides it.
  final ValueChanged<LayerId>? onToggleLayerMuted;

  /// Comma-drag hooks for the block edge grips (shared policy with the
  /// horizontal timeline); null hides the grips.
  final TimelineCommaDragCallbacks? commaDrag;

  /// The frame-range select/move hooks (UI-R8, the block-body move's
  /// successor): the grid resolves the pointer's COLUMN onto display
  /// entries and forwards frame delta + target layer to the session.
  final TimelineFrameRangeHooks? rangeHooks;

  /// The LANE selection domain's gesture bundle (UI-R23 #3 part 2); null
  /// keeps the lane bands display-only.
  final TimelineLaneRangeCallbacks? laneRange;

  /// The run-edge [+]/[↻] handle hooks (UI-R8); null hides the handles.
  final TimelineRunEditCallbacks? runEdit;

  /// Cached-range resolver for the frame rail's green strip (the transposed
  /// counterpart of the horizontal ruler's strip).
  final bool Function(int frameIndex)? isFrameCached;

  /// Grid geometry (transposed); frameCellWidth carries the frame-axis zoom
  /// as the frame ROW height here.
  final TimelineGridMetrics metrics;

  /// AE-style property lanes, transposed: an expanded layer's lanes appear
  /// as COLUMNS beside it (the layer axis runs horizontally here). Same
  /// generic provider + edit hooks as the horizontal timeline.
  final Set<LayerId> expandedLaneLayerIds;
  final ValueChanged<LayerId>? onToggleLayerLanes;
  final List<PropertyLaneRow> Function(Layer layer)? lanesForLayer;
  final PropertyLaneEditCallbacks? laneEdit;

  /// Group headers: tapping twirls the group's member lanes (AE collapse).
  final void Function(Layer layer, PropertyLaneRow lane)? onToggleLaneGroup;

  /// Sections hidden from the grid entirely (toolbar visibility toggles;
  /// the section axis runs horizontally here, so hiding drops columns).
  final Set<TimelineSection> hiddenSections;

  /// The rail's row FILTER (R2): drops the columns of layers failing its
  /// predicate; the active layer is exempt. Shared with the horizontal
  /// timeline (Axis rule).
  final TimelineRowFilter rowFilter;

  /// Bases whose attach group is twirled shut (UI-R20 #9): their attach
  /// columns drop — the shared view state; the fold toggle lives on the
  /// horizontal rail.
  final Set<LayerId> collapsedAttachBaseIds;

  /// TRANSPOSED metrics: frameCellWidth = frame row height, layerRowHeight
  /// = layer column width, layerControlsWidth = frame-number rail width.
  /// No section gutter here — the X-sheet's section axis is horizontal and
  /// section controls live on the column headers.
  static const TimelineGridMetrics defaultMetrics = TimelineGridMetrics(
    frameCellWidth: 36,
    layerRowHeight: 164,
    layerControlsWidth: 72,
    sectionLabelGutterWidth: 0,
  );

  static const double _headerHeight = 92;

  /// The section band above the layer headers: the paper sheet's
  /// ACTION/SE/CAM group headings, each wrapping its columns.
  static const double _sectionBandHeight = 20;
  static const double _totalHeaderHeight = _headerHeight + _sectionBandHeight;

  @override
  State<XSheetTimelineGrid> createState() => _XSheetTimelineGridState();
}

class _XSheetTimelineGridState extends State<XSheetTimelineGrid> {
  /// The integer rate the grid COUNTS with — the ruler's second marks
  /// and row labels are frame arithmetic, never real time (see
  /// [ProjectFrameRate.countingBase]).
  int get _countingFps => widget.projectFrameRate.countingBase;

  /// Resolves range-move column deltas against the entries built this pass.
  final TimelineRangeMoveRowResolver _rangeMoveResolver =
      TimelineRangeMoveRowResolver();

  /// The LIVE frame-axis geometry the painted columns follow (R28 #4 — the
  /// timeline's rule, transposed). Its identity outlives zoom steps, so the
  /// row memo hands cached columns back while the geometry underneath moves;
  /// listeners are render objects only (see the timeline body's note).
  final ValueNotifier<TimelineFrameGeometry> _frameGeometry = ValueNotifier(
    const TimelineFrameGeometry(
      frameCellExtent: 1,
      frameStartIndex: 0,
      frameEndIndexExclusive: 0,
    ),
  );

  /// The WINDOWED twin (zoom round, the timeline body's split transposed):
  /// the columns whose every consumer reads geometry live are laid out at a
  /// constant pixel window instead of `frames * cellHeight`, so a zoom step
  /// re-lays-out one box per column rather than everything inside it. The
  /// sparse kinds keep [_frameGeometry] — their span overlays are widgets
  /// positioned from build-time scalars, and a window sliding under them
  /// without a rebuild would strand them.
  final ValueNotifier<TimelineFrameGeometry> _windowedFrameGeometry =
      ValueNotifier(
        const TimelineFrameGeometry(
          frameCellExtent: 1,
          frameStartIndex: 0,
          frameEndIndexExclusive: 0,
        ),
      );

  /// The frame-axis viewport recorded by the last build — the window's
  /// extent, needed again when the bucket moves outside a build.
  double _frameViewportExtent = 0;

  TimelineFrameGeometry _baseFrameGeometry() => TimelineFrameGeometry(
    frameCellExtent: _metrics.frameCellWidth,
    frameStartIndex: 0,
    frameEndIndexExclusive: _renderedFrameCount,
  );

  TimelineFrameGeometry _windowedFrameGeometryValue() {
    final base = _baseFrameGeometry();
    final cellExtent = base.frameCellExtent;
    if (_frameViewportExtent <= 0 || cellExtent <= 0) {
      return base;
    }
    final spanPx = timelineFrameWindowSpanFor(cellExtent) * cellExtent;
    return base.windowed(
      originPx: math.max(
        0.0,
        _frameWindowBucket.value * spanPx - timelineFrameWindowMarginPx,
      ),
      extentPx: _frameViewportExtent + 2 * timelineFrameWindowMarginPx,
    );
  }

  void _handleFrameWindowBucket() {
    _windowedFrameGeometry.value = _windowedFrameGeometryValue();
  }

  /// The handle every column follows (see [_windowedFrameGeometry]).
  ///
  /// EVERY kind takes the windowed one now: the sparse columns' span
  /// overlays are placed by [TimelineFrameSpanLayout] at layout time, so a
  /// window sliding under them carries them along.
  ValueNotifier<TimelineFrameGeometry> _publishFrameGeometry(LayerKind kind) {
    _frameGeometry.value = _baseFrameGeometry();
    _windowedFrameGeometry.value = _windowedFrameGeometryValue();
    return _windowedFrameGeometry;
  }

  /// The per-build gesture bundle (rebuilt in [build], consumed by the
  /// column builder).
  TimelineRangeGestureCallbacks? _rangeGesture;

  late final ScrollController _frameScrollController;
  late final ScrollController _layerScrollController;

  /// Frame-axis offset + window bucket notifiers (UI-R9 #12a, the
  /// horizontal grid's structure transposed): scroll pixels move the rail
  /// translate only; cell crossings re-window the columns; the grid never
  /// rebuilds per pixel.
  final ValueNotifier<double> _frameAxisOffset = ValueNotifier<double>(0);
  final ValueNotifier<int> _frameWindowBucket = ValueNotifier<int>(0);
  ScrollPosition? _watchedFramePosition;

  double _lastEffectiveFrameScrollOffset = 0;
  double? _scheduledFrameOffsetCorrection;
  int _endlessTrailingFrames = 0;
  final GlobalKey _railScrubViewportKey = GlobalKey();
  int? _lastRailScrubbedFrameIndex;

  TimelineGridMetrics get _metrics => widget.metrics;

  @override
  void initState() {
    super.initState();
    // PEN-10: pen-friendly positions — while a stylus is nearby, a
    // coasting fling stops hiding the cells from hit-testing.
    _frameScrollController = PenFriendlyScrollController();
    _layerScrollController = PenFriendlyScrollController();
    _frameScrollController.addListener(_handleFrameScroll);
    _frameWindowBucket.addListener(_handleFrameWindowBucket);
  }

  @override
  void didUpdateWidget(covariant XSheetTimelineGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Zoom-around-playhead (transposed): the playhead ROW stays put on
    // screen through zoom when visible; otherwise the top-edge frame
    // anchors. Same policy as the horizontal timeline (Axis rule).
    final oldCell = oldWidget.metrics.frameCellWidth;
    final newCell = widget.metrics.frameCellWidth;
    if (oldCell != newCell && _frameScrollController.hasClients) {
      _frameScrollController.jumpTo(
        zoomAnchoredScrollOffset(
          oldOffset: _frameScrollController.offset,
          oldPixelsPerFrame: oldCell,
          newPixelsPerFrame: newCell,
          viewportExtent: _frameScrollController.position.viewportDimension,
          anchorFrame: widget.frameCursor.value,
        ),
      );
    }
  }

  @override
  void dispose() {
    _watchedFramePosition?.isScrollingNotifier.removeListener(
      _handleFrameScrollActivity,
    );
    _frameScrollController
      ..removeListener(_handleFrameScroll)
      ..dispose();
    _layerScrollController.dispose();
    _frameWindowBucket.removeListener(_handleFrameWindowBucket);
    _frameGeometry.dispose();
    _windowedFrameGeometry.dispose();
    _frameAxisOffset.dispose();
    _frameWindowBucket.dispose();
    super.dispose();
  }

  /// Frame-axis scroll (UI-R9 #12a): NO setState per pixel — only an
  /// endless-extent growth (a real relayout, rare) rebuilds the grid.
  void _handleFrameScroll() {
    if (!_frameScrollController.hasClients) {
      return;
    }
    _watchFrameScrollActivity();
    final offset = _frameScrollController.offset;
    if (offset == _frameAxisOffset.value) {
      return;
    }
    _frameAxisOffset.value = offset;
    // Quantized span buckets (UI-R16): repaint once per span crossing.
    final bucket = timelineFrameWindowBucketOf(
      offset: offset,
      cellExtent: _metrics.frameCellWidth,
    );
    if (bucket != _frameWindowBucket.value) {
      _frameWindowBucket.value = bucket;
    }
    final position = _frameScrollController.position;
    final nextTrailingFrames = endlessTrailingFrames(
      baseFrameCount: _visibleFrameCount,
      currentTrailingFrames: _endlessTrailingFrames,
      scrollOffset: offset,
      viewportExtent: position.viewportDimension,
      frameCellExtent: _metrics.frameCellWidth,
      // Discrete moves (wheel ticks, programmatic jumps) may shrink right
      // away; gesture pixels never rescale mid-drag (the settle listener
      // applies the release).
      allowShrink: !position.isScrollingNotifier.value,
    );
    if (nextTrailingFrames != _endlessTrailingFrames) {
      setState(() => _endlessTrailingFrames = nextTrailingFrames);
    }
  }

  void _watchFrameScrollActivity() {
    final position = _frameScrollController.position;
    if (identical(position, _watchedFramePosition)) {
      return;
    }
    _watchedFramePosition?.isScrollingNotifier.removeListener(
      _handleFrameScrollActivity,
    );
    _watchedFramePosition = position;
    position.isScrollingNotifier.addListener(_handleFrameScrollActivity);
  }

  /// Scroll settled: the lazy endless SHRINK (UI-R9 #11).
  void _handleFrameScrollActivity() {
    final position = _watchedFramePosition;
    if (position == null || position.isScrollingNotifier.value) {
      return;
    }
    final nextTrailingFrames = endlessTrailingFrames(
      baseFrameCount: _visibleFrameCount,
      currentTrailingFrames: _endlessTrailingFrames,
      scrollOffset: position.pixels,
      viewportExtent: position.viewportDimension,
      frameCellExtent: _metrics.frameCellWidth,
      allowShrink: true,
    );
    if (nextTrailingFrames != _endlessTrailingFrames && mounted) {
      setState(() => _endlessTrailingFrames = nextTrailingFrames);
    }
  }

  TimelineFrameRange get _frameRangePolicy =>
      TimelineFrameRange.fromPlaybackDuration(
        playbackFrameCount: widget.frameCount,
        minimumVisibleFrameCells: _metrics.minimumVisibleFrameCells,
      );

  int get _visibleFrameCount => _frameRangePolicy.visibleFrameCount;

  /// Frame cells the current viewport needs to be fully papered (UI-R12
  /// #16) — recorded by build's outer LayoutBuilder. Zero until layout.
  int _viewportFillFrameCells = 0;

  /// Render extent (UI-R12 #16 contract): the cells scrolled into
  /// existence PLUS the viewport fill — no runway beyond. Scroll physics
  /// and the rail clamp here; the frame-rail edge-drag overshoots and the
  /// growth listener materializes what the overshot view needs.
  int get _renderedFrameCount => math.max(
    _visibleFrameCount + _endlessTrailingFrames,
    _viewportFillFrameCells,
  );

  double get _totalFrameContentHeight =>
      _renderedFrameCount * _metrics.frameCellWidth;

  double _effectiveFrameScrollOffset({
    required double requestedOffset,
    required double viewportExtent,
  }) {
    // Same offset policy as the horizontal grid, transposed to y.
    return resolveTimelineHorizontalOffset(
      requestedOffset: requestedOffset,
      totalContentWidth: _totalFrameContentHeight,
      viewportWidth: viewportExtent,
    ).effectiveOffset;
  }

  void _synchronizeFrameScrollController(double effectiveOffset) {
    if (!_frameScrollController.hasClients ||
        _frameScrollController.offset == effectiveOffset ||
        _scheduledFrameOffsetCorrection == effectiveOffset) {
      return;
    }

    _scheduledFrameOffsetCorrection = effectiveOffset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_frameScrollController.hasClients) {
        _scheduledFrameOffsetCorrection = null;
        return;
      }

      final maxScrollExtent = _frameScrollController.position.maxScrollExtent;
      final targetOffset = effectiveOffset
          .clamp(0.0, maxScrollExtent)
          .toDouble();

      _scheduledFrameOffsetCorrection = null;
      if (_frameScrollController.offset != targetOffset) {
        _frameScrollController.jumpTo(targetOffset);
      }
    });
  }

  int? _frameIndexForRailLocalY(double localY) {
    // Shared frame/x conversion policy; the rail's local y is the "x".
    return frameIndexFromLocalX(
      localX: localY,
      horizontalScrollOffset: _lastEffectiveFrameScrollOffset,
      frameCellWidth: _metrics.frameCellWidth,
      visibleFrameCount: _renderedFrameCount,
    );
  }

  void _selectClampedFrameFromRail(int frameIndex) {
    // The endless runway IS the selectable tail now (UI-R10 #23 retired
    // the fixed safety frames): clamp against the BUILT extent.
    final clampedFrameIndex = clampFrameIndex(
      frameIndex: frameIndex,
      visibleFrameCount: _renderedFrameCount,
    );
    if (clampedFrameIndex == null ||
        clampedFrameIndex == _lastRailScrubbedFrameIndex) {
      return;
    }

    _lastRailScrubbedFrameIndex = clampedFrameIndex;
    (widget.onScrubFrame ?? widget.onSelectFrame)(clampedFrameIndex);
  }

  /// The scrub gesture's release (raw pointer up/cancel — fires for taps
  /// AND drags). Tracking is NOT reset here so trailing tap handlers stay
  /// deduplicated.
  void _endRailScrub() {
    widget.onScrubEnd?.call();
  }

  void _selectFrameFromRailGlobalPosition(Offset globalPosition) {
    final renderObject = _railScrubViewportKey.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox) {
      return;
    }

    final localY = renderObject.globalToLocal(globalPosition).dy;
    _autoPanRailEdge(renderObject, localY);
    final frameIndex = _frameIndexForRailLocalY(localY);
    if (frameIndex == null) {
      return;
    }

    _selectClampedFrameFromRail(frameIndex);
  }

  /// Edge auto-pan (UI-R10 #24): a rail scrub past the viewport edge
  /// scrolls the frame axis under it — with the endless growth feeding
  /// rows ahead, the rail drag alone reaches ANY frame (the scrollbar
  /// clamps at the built extent by design).
  void _autoPanRailEdge(RenderBox viewport, double localY) {
    if (!_frameScrollController.hasClients || !viewport.hasSize) {
      return;
    }
    final delta = edgeAutoPanDelta(localY, viewport.size.height);
    if (delta == 0) {
      return;
    }
    final position = _frameScrollController.position;
    // Downward the pan OVERSHOOTS the built extent (UI-R12 #16): the rail
    // drag is THE way past the last built cell — growth materializes the
    // frames the overshot view needs; scroll/scrollbar stay clamped.
    final target = math.max(0.0, position.pixels + delta);
    if (target != position.pixels) {
      _frameScrollController.jumpTo(target);
    }
  }

  void _resetRailScrubTracking() {
    _lastRailScrubbedFrameIndex = null;
  }

  List<PropertyLaneRow> _lanesFor(Layer layer) =>
      widget.lanesForLayer?.call(layer) ?? const [];

  /// One column wrapped in its repaint boundary + drag-preview gate: an
  /// edge-drag step re-runs the builder with the preview layer substituted
  /// for the drag target's column only.
  Widget _gatedColumn(
    TimelineDisplayRow entry,
    TimelineVisibleRange frameRange,
    TimelineVirtualizationPlan plan,
    double viewportExtent,
  ) {
    return RepaintBoundary(
      key: ValueKey<String>(
        'xsheet-column-${entry.layer.id}-${entry.lane?.laneId ?? 'cells'}',
      ),
      child: TimelineDragPreviewRowGate(
        dragPreview: widget.dragPreview,
        layer: entry.layer,
        rowBuilder: (context, layer) =>
            _columnFor(entry, layer, frameRange, plan, viewportExtent),
      ),
    );
  }

  Widget _columnFor(
    TimelineDisplayRow entry,
    Layer layer,
    TimelineVisibleRange frameRange,
    TimelineVirtualizationPlan plan,
    double viewportExtent,
  ) {
    // Recorded for the window, which is recomputed on bucket crossings —
    // outside any build.
    _frameViewportExtent = viewportExtent;
    if (entry.isLane) {
      return laneIsSeAudio(entry.lane!)
          ? SeAudioLaneFrameRow(
              axis: Axis.vertical,
              keyPrefix: 'xsheet',
              layer: layer,
              frameStartIndex: frameRange.startIndex,
              frameEndIndexExclusive: frameRange.endIndexExclusive,
              leadingFrameSpacerWidth: plan.leadingFrameSpacerWidth,
              trailingFrameSpacerWidth: plan.trailingFrameSpacerWidth,
              metrics: _metrics,
              frameRate: widget.projectFrameRate,
              audioPeaksFor: widget.audioPeaksFor,
              onSetClipOffset: widget.audioLane?.onSetClipOffset == null
                  ? null
                  : (clipIndex, offsetFrames) =>
                        widget.audioLane!.onSetClipOffset!(
                          entry.layer.id,
                          clipIndex,
                          offsetFrames,
                        ),
              offsetDrag: widget.audioLane?.offsetDrag,
              onSetClipFades: widget.audioLane?.onSetClipFades == null
                  ? null
                  : (clipIndex, fadeIn, fadeOut) =>
                        widget.audioLane!.onSetClipFades!(
                          entry.layer.id,
                          clipIndex,
                          fadeIn,
                          fadeOut,
                        ),
              onSetClipGain: widget.audioLane?.onSetClipGain == null
                  ? null
                  : (clipIndex, gain) => widget.audioLane!.onSetClipGain!(
                      entry.layer.id,
                      clipIndex,
                      gain,
                    ),
              onSetClipFadeCurve: widget.onSetAudioClipFadeCurve == null
                  ? null
                  : (clipIndex, curve) => widget.onSetAudioClipFadeCurve!(
                      entry.layer.id,
                      clipIndex,
                      curve,
                    ),
              onSetClipEnvelope: widget.onSetAudioClipEnvelope == null
                  ? null
                  : (clipIndex, keys) => widget.onSetAudioClipEnvelope!(
                      entry.layer.id,
                      clipIndex,
                      keys,
                    ),
              resolveStrings: widget.resolveStrings,
            )
          : TimelineLaneFrameRow(
              axis: Axis.vertical,
              keyPrefix: 'xsheet',
              layer: layer,
              lane: entry.lane!,
              frameStartIndex: frameRange.startIndex,
              frameEndIndexExclusive: frameRange.endIndexExclusive,
              leadingFrameSpacerWidth: plan.leadingFrameSpacerWidth,
              trailingFrameSpacerWidth: plan.trailingFrameSpacerWidth,
              metrics: _metrics,
              laneEdit: widget.laneEdit,
              // The LANE selection domain (UI-R23 #3 part 2) — layer
              // transform lanes only in v1.
              laneRange: layer.kind == LayerKind.camera
                  ? null
                  : widget.laneRange,
            );
    }
    // PRO-TIMELINE scrolling (UI-R15→R16, transposed): the cells column
    // gets FULL bounds — its painter windows itself off the quantized
    // bucket (repaint per span crossing), so the bucket pass diffs
    // identical params and records nothing; the sparse widget-cell kinds
    // re-window internally under the same bucket.
    return TimelineFrameCellsRow(
      axis: Axis.vertical,
      keyPrefix: 'xsheet',
      onActivateCell: widget.onActivateCell,
      instructionDefById: widget.instructionDefById,
      audioPeaksFor: widget.audioPeaksFor,
      projectFrameRate: widget.projectFrameRate,
      showSeconds: widget.showSeconds,
      audioLane: widget.audioLane,
      seClipMarkerTooltip: widget.seClipMarkerTooltip,
      seSpillsIn: widget.seSpillInLayerIds.contains(layer.id),
      layer: layer,
      baseLayer: entry.layer,
      active: entry.layer.id == widget.activeLayerId,
      playbackFrameCount: widget.frameCount,
      geometry: _publishFrameGeometry(layer.kind),
      crossAxisExtent: _metrics.layerRowHeight,
      windowBucket: _frameWindowBucket,
      viewportMainExtent: viewportExtent,
      exposureStateForLayer: widget.exposureStateForLayer,
      frameNameForLayer: widget.frameNameForLayer,
      celContent: widget.celContent,
      onSelectLayer: widget.onSelectLayer,
      onSelectFrame: widget.onSelectFrame,
      commaDrag: widget.commaDrag,
      rangeGesture: _rangeGesture,
      runEdit: widget.runEdit,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const bottomScrollbarRailHeight = 16.0;

    // PEN-9: a stylus approach stops a coasting fling — mid-glide the
    // viewports ignore-pointer their children, so without the stop a pen
    // landing right after a touch fling scrolls instead of selecting.
    return StylusGlideStop(
      controllers: [_frameScrollController, _layerScrollController],
      // PEN-12 #7: no overscroll stretch/glow — the painterized rails
      // mirror the offset and cannot stretch with the cells (see the
      // horizontal grid).
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bodyViewportHeight = constraints.hasBoundedHeight
                ? (constraints.maxHeight -
                          XSheetTimelineGrid._totalHeaderHeight -
                          bottomScrollbarRailHeight)
                      .clamp(0.0, double.infinity)
                      .toDouble()
                : 0.0;
            // Viewport paper fill (UI-R12 #16): the frame column runs to the
            // body's bottom edge — recorded before every consumer of
            // [_renderedFrameCount] below.
            _viewportFillFrameCells = endlessViewportFillFrames(
              viewportExtent: bodyViewportHeight,
              frameCellExtent: _metrics.frameCellWidth,
            );
            final effectiveFrameScrollOffset = _effectiveFrameScrollOffset(
              requestedOffset: _frameAxisOffset.value,
              viewportExtent: bodyViewportHeight,
            );
            _lastEffectiveFrameScrollOffset = effectiveFrameScrollOffset;
            _synchronizeFrameScrollController(effectiveFrameScrollOffset);

            // Hidden sections contribute no columns; the section band above
            // the headers carries each section's bracket (shared row/run
            // policy with the horizontal grid).
            final entries = buildTimelineDisplayRows(
              layers: widget.layers,
              expandedLayerIds: widget.expandedLaneLayerIds,
              lanesForLayer: _lanesFor,
              hiddenSections: widget.hiddenSections,
              rowFilter: widget.rowFilter,
              collapsedAttachBaseIds: widget.collapsedAttachBaseIds,
              activeLayerId: widget.activeLayerId,
              fxEnabledOf: widget.layerFxEnabledOf,
            );
            final rangeHooks = widget.rangeHooks;
            _rangeMoveResolver
              ..rows = entries
              ..session = rangeHooks?.move;
            _rangeGesture = rangeHooks == null
                ? null
                : TimelineRangeGestureCallbacks(
                    selection: rangeHooks.selection,
                    // Cross-row select (UI-R17 #8), transposed like the moves.
                    onSelectUpdate:
                        (layerId, anchorIndex, headIndex, headRowDelta) =>
                            rangeHooks.onSelectUpdate(
                              layerId,
                              anchorIndex,
                              headIndex,
                              headLayerId: headRowDelta == 0
                                  ? null
                                  : resolveBlockMoveTargetLayer(
                                      rows: entries,
                                      sourceLayerId: layerId,
                                      rowDelta: headRowDelta,
                                    ),
                            ),
                    onTapClear: (_) => rangeHooks.onClear(),
                    onMoveBegin: _rangeMoveResolver.begin,
                    onMoveUpdate: _rangeMoveResolver.update,
                    onMoveEnd: _rangeMoveResolver.end,
                    onMoveCancel: _rangeMoveResolver.cancel,
                  );
            final sectionRuns = timelineSectionRuns(entries);

            // The shared virtualization plan with the frame axis fed through the
            // "horizontal" inputs (the axes are swapped in this grid). Computed
            // INSIDE the window-bucket subscribers (UI-R9 #12a): scroll pixels
            // re-window nothing.
            TimelineVirtualizationPlan framePlan() =>
                calculateTimelineVirtualizationPlan(
                  horizontalScrollOffset: _effectiveFrameScrollOffset(
                    requestedOffset: _frameAxisOffset.value,
                    viewportExtent: bodyViewportHeight,
                  ),
                  verticalScrollOffset: 0,
                  viewportWidth: bodyViewportHeight,
                  viewportHeight: 0,
                  frameCellWidth: _metrics.frameCellWidth,
                  layerRowHeight: _metrics.layerRowHeight,
                  frameCount: _renderedFrameCount,
                  layerCount: entries.length,
                );
            final totalFrameContentHeight = _totalFrameContentHeight;
            // Columns are no longer uniformly wide: collapsed sections fold to
            // a slim strip.
            final columnsContentWidth = timelineDisplayRowsExtent(
              entries,
              _metrics,
            );
            final cutEndBoundaryOffset = timelineCutEndBoundaryX(
              playbackFrameCount: widget.frameCount,
              metrics: _metrics,
            );

            return Column(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: _metrics.layerControlsWidth,
                        child: Column(
                          children: [
                            _HeaderCell(
                              width: _metrics.layerControlsWidth,
                              height: XSheetTimelineGrid._totalHeaderHeight,
                              child: const Text('Frame'),
                            ),
                            Expanded(
                              child: Listener(
                                key: const ValueKey<String>(
                                  'xsheet-frame-rail-scrub-area',
                                ),
                                behavior: HitTestBehavior.translucent,
                                onPointerDown: (event) {
                                  _resetRailScrubTracking();
                                  _selectFrameFromRailGlobalPosition(
                                    event.position,
                                  );
                                },
                                onPointerUp: (_) => _endRailScrub(),
                                onPointerCancel: (_) => _endRailScrub(),
                                child: GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onVerticalDragStart: (details) {
                                    _selectFrameFromRailGlobalPosition(
                                      details.globalPosition,
                                    );
                                  },
                                  onVerticalDragUpdate: (details) {
                                    _selectFrameFromRailGlobalPosition(
                                      details.globalPosition,
                                    );
                                  },
                                  onVerticalDragEnd: (_) =>
                                      _resetRailScrubTracking(),
                                  onVerticalDragCancel: _resetRailScrubTracking,
                                  child: ClipRect(
                                    key: _railScrubViewportKey,
                                    child: OverflowBox(
                                      alignment: Alignment.topLeft,
                                      minHeight: totalFrameContentHeight,
                                      maxHeight: totalFrameContentHeight,
                                      minWidth: _metrics.layerControlsWidth,
                                      maxWidth: _metrics.layerControlsWidth,
                                      // Pixels move the TRANSLATE only; the
                                      // rail painter windows itself off the
                                      // offset (UI-R15 — no bucket rebuild).
                                      child: ValueListenableBuilder<double>(
                                        valueListenable: _frameAxisOffset,
                                        child: Builder(
                                          builder: (context) {
                                            return SizedBox(
                                              width:
                                                  _metrics.layerControlsWidth,
                                              height: totalFrameContentHeight,
                                              child: Stack(
                                                children: [
                                                  // SPLIT (shared with the
                                                  // horizontal rulers): the
                                                  // numbers are static, so a
                                                  // seek no longer re-records
                                                  // a glyph per frame; the
                                                  // tint and the cached bar
                                                  // ride the overlay below.
                                                  // UI-R15: full bounds — the
                                                  // rail painter windows
                                                  // itself off the offset.
                                                  RepaintBoundary(
                                                    child: _XSheetFrameNumberRail(
                                                      frameStartIndex: 0,
                                                      frameEndIndexExclusive:
                                                          _renderedFrameCount,
                                                      // The tint lives in the
                                                      // overlay now.
                                                      currentFrameIndex: -1,
                                                      playbackFrameCount:
                                                          widget.frameCount,
                                                      leadingFrameSpacerHeight:
                                                          0,
                                                      trailingFrameSpacerHeight:
                                                          0,
                                                      metrics: _metrics,
                                                      onSelectFrame:
                                                          _selectClampedFrameFromRail,
                                                      framesPerSecond:
                                                          _countingFps,
                                                      showSeconds:
                                                          widget.showSeconds,
                                                      windowBucket:
                                                          _frameWindowBucket,
                                                      viewportMainExtent:
                                                          bodyViewportHeight,
                                                    ),
                                                  ),
                                                  Positioned.fill(
                                                    child: TimelineRulerCursorOverlay(
                                                      keyValue:
                                                          'xsheet-rail-cursor-overlay',
                                                      axis: Axis.vertical,
                                                      playhead:
                                                          widget.frameCursor,
                                                      repaintSignal: widget
                                                          .frameCachedSignal,
                                                      windowBucket:
                                                          _frameWindowBucket,
                                                      viewportMainExtent:
                                                          bodyViewportHeight,
                                                      renderedFrames:
                                                          _renderedFrameCount,
                                                      contentFrames:
                                                          widget.frameCount,
                                                      cellWidth: _metrics
                                                          .frameCellWidth,
                                                      isFrameCached:
                                                          widget.isFrameCached,
                                                    ),
                                                  ),
                                                  // UI-R18 #14: the rail's
                                                  // line follows the live
                                                  // trim preview so it never
                                                  // splits from the body's.
                                                  if (widget.cutEndDrag !=
                                                          null &&
                                                      widget.dragPreview !=
                                                          null)
                                                    ValueListenableBuilder<
                                                      TimelineDragPreview?
                                                    >(
                                                      valueListenable:
                                                          widget.dragPreview!,
                                                      builder:
                                                          (
                                                            context,
                                                            preview,
                                                            _,
                                                          ) => TimelineRulerCutEndBoundary(
                                                            axis: Axis.vertical,
                                                            left:
                                                                timelineCutEndPreviewFrameCount(
                                                                  preview:
                                                                      preview,
                                                                  cutId: widget
                                                                      .cutEndDrag!
                                                                      .cutId,
                                                                  playbackFrameCount:
                                                                      widget
                                                                          .frameCount,
                                                                ) *
                                                                _metrics
                                                                    .frameCellWidth,
                                                          ),
                                                    )
                                                  else
                                                    TimelineRulerCutEndBoundary(
                                                      axis: Axis.vertical,
                                                      left:
                                                          cutEndBoundaryOffset,
                                                    ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                        builder: (context, offset, child) {
                                          final effective =
                                              _effectiveFrameScrollOffset(
                                                requestedOffset: offset,
                                                viewportExtent:
                                                    bodyViewportHeight,
                                              );
                                          _lastEffectiveFrameScrollOffset =
                                              effective;
                                          return Transform.translate(
                                            offset: Offset(0, -effective),
                                            child: child,
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: _metrics.verticalScrollbarWidth,
                        child: Column(
                          children: [
                            TimelineVerticalScrollbarSlot(
                              width: _metrics.verticalScrollbarWidth,
                              height: XSheetTimelineGrid._totalHeaderHeight,
                            ),
                            Expanded(
                              child: TimelineVerticalScrollbarRail(
                                controller: _frameScrollController,
                                viewportHeight: bodyViewportHeight,
                                contentHeight: totalFrameContentHeight,
                                width: _metrics.verticalScrollbarWidth,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: widget.layers.isEmpty
                            ? Align(
                                alignment: Alignment.topLeft,
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(
                                    'No layers',
                                    style: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              )
                            : ScrollConfiguration(
                                // The custom rails ARE the scrollbars — the
                                // desktop auto-overlay doubled the vertical one
                                // (UI-R10 #22).
                                behavior: ScrollConfiguration.of(
                                  context,
                                ).copyWith(scrollbars: false),
                                child: SingleChildScrollView(
                                  key: const ValueKey<String>(
                                    'xsheet-layer-horizontal-viewport',
                                  ),
                                  controller: _layerScrollController,
                                  scrollDirection: Axis.horizontal,
                                  child: SizedBox(
                                    width: columnsContentWidth,
                                    child: Column(
                                      children: [
                                        // The paper sheet's group headings: one
                                        // bracket cell per section run, wrapping
                                        // its columns.
                                        Row(
                                          children: [
                                            for (final run in sectionRuns)
                                              _XSheetSectionBandCell(
                                                run: run,
                                                extent:
                                                    timelineSectionRunExtent(
                                                      run,
                                                      entries,
                                                      _metrics,
                                                    ),
                                              ),
                                          ],
                                        ),
                                        Row(
                                          children: [
                                            for (
                                              var index = 0;
                                              index < entries.length;
                                              index += 1
                                            )
                                              entries[index].isLane
                                                  // Lane headers show the value AT
                                                  // the cursor: subscribe here so
                                                  // ticks rebuild only these cells.
                                                  ? ValueListenableBuilder<int>(
                                                      valueListenable:
                                                          widget.frameCursor,
                                                      builder:
                                                          (
                                                            context,
                                                            cursorFrame,
                                                            _,
                                                          ) => TimelineLaneControlsRow(
                                                            axis: Axis.vertical,
                                                            keyPrefix: 'xsheet',
                                                            layer:
                                                                entries[index]
                                                                    .layer,
                                                            lane: entries[index]
                                                                .lane!,
                                                            metrics: _metrics,
                                                            width: _metrics
                                                                .layerRowHeight,
                                                            height:
                                                                XSheetTimelineGrid
                                                                    ._headerHeight,
                                                            currentFrameIndex:
                                                                cursorFrame,
                                                            onSelectFrame: widget
                                                                .onSelectFrame,
                                                            laneEdit:
                                                                widget.laneEdit,
                                                            onToggleLaneGroup:
                                                                widget
                                                                    .onToggleLaneGroup,
                                                          ),
                                                    )
                                                  : _LayerHeader(
                                                      layer:
                                                          entries[index].layer,
                                                      active:
                                                          entries[index]
                                                              .layer
                                                              .id ==
                                                          widget.activeLayerId,
                                                      metrics: _metrics,
                                                      onSelectLayer:
                                                          widget.onSelectLayer,
                                                      onToggleLayerVisibility:
                                                          widget
                                                              .onToggleLayerVisibility,
                                                      onLayerOpacityChanged: widget
                                                          .onLayerOpacityChanged,
                                                      onLayerOpacityChangeEnd:
                                                          widget
                                                              .onLayerOpacityChangeEnd,
                                                      opacityDragPreview: widget
                                                          .opacityDragPreview,
                                                      onToggleLayerTimesheet: widget
                                                          .onToggleLayerTimesheet,
                                                      fxEnabled:
                                                          widget
                                                              .layerFxEnabledOf
                                                              ?.call(
                                                                entries[index]
                                                                    .layer
                                                                    .id,
                                                              ) ??
                                                          true,
                                                      onToggleLayerFx: widget
                                                          .onToggleLayerFx,
                                                      onLayerMarkSelected: widget
                                                          .onLayerMarkSelected,
                                                      onToggleLayerFillReference:
                                                          widget
                                                              .onToggleLayerFillReference,
                                                      onToggleLayerMuted: widget
                                                          .onToggleLayerMuted,
                                                      isLayerSoloed:
                                                          widget.isLayerSoloed
                                                              ?.call(
                                                                entries[index]
                                                                    .layer
                                                                    .id,
                                                              ) ??
                                                          false,
                                                      onToggleLayerSolo: widget
                                                          .onToggleLayerSolo,
                                                      onEditLayerAudio: widget
                                                          .onEditLayerAudio,
                                                      resolveStrings:
                                                          widget.resolveStrings,
                                                      hasLanes: _lanesFor(
                                                        entries[index].layer,
                                                      ).isNotEmpty,
                                                      lanesExpanded: widget
                                                          .expandedLaneLayerIds
                                                          .contains(
                                                            entries[index]
                                                                .layer
                                                                .id,
                                                          ),
                                                      onToggleLanes: widget
                                                          .onToggleLayerLanes,
                                                    ),
                                          ],
                                        ),
                                        Expanded(
                                          child: ScrollConfiguration(
                                            // The rail between the frame numbers
                                            // and the cells is THE scrollbar; the
                                            // desktop auto-overlay was the
                                            // duplicate (UI-R10 #22).
                                            behavior: ScrollConfiguration.of(
                                              context,
                                            ).copyWith(scrollbars: false),
                                            child: SingleChildScrollView(
                                              key: const ValueKey<String>(
                                                'xsheet-frame-vertical-viewport',
                                              ),
                                              controller:
                                                  _frameScrollController,
                                              child: SizedBox(
                                                height: totalFrameContentHeight,
                                                // Pixels scroll the real viewport;
                                                // only cell crossings re-window the
                                                // columns (UI-R9 #12a).
                                                child: ValueListenableBuilder<int>(
                                                  valueListenable:
                                                      _frameWindowBucket,
                                                  builder: (context, _, _) {
                                                    final plan = framePlan();
                                                    final frameRange =
                                                        plan.frameRange;
                                                    return Stack(
                                                      children: [
                                                        Row(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            // RepaintBoundary per
                                                            // column (mirrors the
                                                            // horizontal rows): the
                                                            // cursor layer repaints
                                                            // alone on ticks. The
                                                            // gate inside makes an
                                                            // edge-drag step rebuild
                                                            // exactly the dragged
                                                            // layer's column.
                                                            for (
                                                              var index = 0;
                                                              index <
                                                                  entries
                                                                      .length;
                                                              index += 1
                                                            )
                                                              _gatedColumn(
                                                                entries[index],
                                                                frameRange,
                                                                plan,
                                                                bodyViewportHeight,
                                                              ),
                                                          ],
                                                        ),
                                                        // UI-R13 #7: the 6f/24f
                                                        // beat lines span EVERY
                                                        // column — one grid-wide
                                                        // overlay (transposed).
                                                        Positioned.fill(
                                                          child: IgnorePointer(
                                                            child: RepaintBoundary(
                                                              child: CustomPaint(
                                                                key:
                                                                    const ValueKey<
                                                                      String
                                                                    >(
                                                                      'xsheet-beat-lines',
                                                                    ),
                                                                painter: TimelineBeatLinesPainter(
                                                                  axis: Axis
                                                                      .vertical,
                                                                  frameCellExtent:
                                                                      _metrics
                                                                          .frameCellWidth,
                                                                  crossCellExtent:
                                                                      _metrics
                                                                          .layerRowHeight,
                                                                  framesPerSecond:
                                                                      _countingFps,
                                                                  colorScheme:
                                                                      colorScheme,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        // The cursor layer carries
                                                        // the playhead + selection
                                                        // visuals; ticks repaint it
                                                        // alone.
                                                        Positioned.fill(
                                                          child: TimelineCursorLayer(
                                                            axis: Axis.vertical,
                                                            selectedSemanticsKey:
                                                                const ValueKey<
                                                                  String
                                                                >(
                                                                  'xsheet-selected-cell',
                                                                ),
                                                            frameRangeSelection:
                                                                widget
                                                                    .rangeHooks
                                                                    ?.selection,
                                                            // R27 #14: one band
                                                            // for cells and
                                                            // lanes alike.
                                                            laneRangeSelection:
                                                                widget
                                                                    .laneRange
                                                                    ?.selection,
                                                            frameCursor: widget
                                                                .frameCursor,
                                                            dragPreview: widget
                                                                .dragPreview,
                                                            rows: entries,
                                                            activeLayerId: widget
                                                                .activeLayerId,
                                                            frameStartIndex:
                                                                frameRange
                                                                    .startIndex,
                                                            frameEndIndexExclusive:
                                                                frameRange
                                                                    .endIndexExclusive,
                                                            leadingFrameSpacerWidth:
                                                                plan.leadingFrameSpacerWidth,
                                                            metrics: _metrics,
                                                            exposureStateForLayer:
                                                                widget
                                                                    .exposureStateForLayer,
                                                            crossAxisExtent:
                                                                entries.length *
                                                                _metrics
                                                                    .layerRowHeight,
                                                          ),
                                                        ),
                                                        // UI-R18 #14: live
                                                        // line + trim grip
                                                        // on the frame axis
                                                        // (vertical here).
                                                        if (widget.cutEndDrag !=
                                                                null &&
                                                            widget.dragPreview !=
                                                                null)
                                                          ValueListenableBuilder<
                                                            TimelineDragPreview?
                                                          >(
                                                            valueListenable:
                                                                widget
                                                                    .dragPreview!,
                                                            builder: (context, preview, _) => TimelineBodyCutEndBoundary(
                                                              axis:
                                                                  Axis.vertical,
                                                              left:
                                                                  timelineCutEndPreviewFrameCount(
                                                                    preview:
                                                                        preview,
                                                                    cutId: widget
                                                                        .cutEndDrag!
                                                                        .cutId,
                                                                    playbackFrameCount:
                                                                        widget
                                                                            .frameCount,
                                                                  ) *
                                                                  _metrics
                                                                      .frameCellWidth,
                                                            ),
                                                          )
                                                        else
                                                          TimelineBodyCutEndBoundary(
                                                            axis: Axis.vertical,
                                                            left:
                                                                cutEndBoundaryOffset,
                                                          ),
                                                        if (widget.cutEndDrag !=
                                                            null)
                                                          TimelineCutEndDragHandle(
                                                            axis: Axis.vertical,
                                                            cellExtent: _metrics
                                                                .frameCellWidth,
                                                            playbackFrameCount:
                                                                widget
                                                                    .frameCount,
                                                            callbacks: widget
                                                                .cutEndDrag!,
                                                            dragPreview: widget
                                                                .dragPreview,
                                                          ),
                                                      ],
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    SizedBox(
                      key: const ValueKey<String>(
                        'xsheet-bottom-scrollbar-left-spacer',
                      ),
                      width:
                          _metrics.layerControlsWidth +
                          _metrics.verticalScrollbarWidth,
                      height: bottomScrollbarRailHeight,
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final viewportWidth = constraints.hasBoundedWidth
                              ? constraints.maxWidth
                              : 0.0;

                          return TimelineHorizontalScrollbarRail(
                            key: const ValueKey<String>(
                              'xsheet-horizontal-scrollbar',
                            ),
                            controller: _layerScrollController,
                            viewportWidth: viewportWidth,
                            contentWidth: math.max(
                              columnsContentWidth,
                              _metrics.layerRowHeight,
                            ),
                            height: bottomScrollbarRailHeight,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The vertical frame-number rail: the X-sheet counterpart of the
/// horizontal grid's frame header row, sharing its styling and dim rules.
class _XSheetFrameNumberRail extends StatelessWidget {
  const _XSheetFrameNumberRail({
    required this.frameStartIndex,
    required this.frameEndIndexExclusive,
    required this.currentFrameIndex,
    required this.playbackFrameCount,
    required this.leadingFrameSpacerHeight,
    required this.trailingFrameSpacerHeight,
    required this.metrics,
    required this.onSelectFrame,
    this.framesPerSecond = 24,
    this.showSeconds = false,
    this.windowBucket,
    this.viewportMainExtent = 0,
  });

  final int frameStartIndex;
  final int frameEndIndexExclusive;
  final int currentFrameIndex;
  final int playbackFrameCount;
  final double leadingFrameSpacerHeight;
  final double trailingFrameSpacerHeight;
  final TimelineGridMetrics metrics;
  final ValueChanged<int> onSelectFrame;
  final int framesPerSecond;
  final bool showSeconds;

  /// PRO-TIMELINE scrolling (UI-R15→R16): the painter windows itself off
  /// the quantized bucket — pass full bounds, repaint per span crossing.
  final ValueListenable<int>? windowBucket;
  final double viewportMainExtent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final height =
        leadingFrameSpacerHeight +
        (frameEndIndexExclusive - frameStartIndex) * metrics.frameCellWidth +
        trailingFrameSpacerHeight;
    // PAINTERIZED (UI-R14 #1, the ruler's UI-R13 #1 treatment — 통일화):
    // the whole rail is one CustomPaint; per-frame row widgets are gone.
    // Tests probe [XSheetFrameRailPainter.modelAt]/`rowRectFor` through
    // the 'xsheet-frame-rail-paint' key; selection stays on the rail's
    // viewport-level scrub listener.
    return SizedBox(
      key: const ValueKey<String>('xsheet-frame-number-rail'),
      width: metrics.layerControlsWidth,
      height: height,
      child: CustomPaint(
        key: const ValueKey<String>('xsheet-frame-rail-paint'),
        size: Size(metrics.layerControlsWidth, height),
        painter: XSheetFrameRailPainter(
          frameStartIndex: frameStartIndex,
          frameEndIndexExclusive: frameEndIndexExclusive,
          currentFrameIndex: currentFrameIndex,
          playbackFrameCount: playbackFrameCount,
          leadingFrameSpacerHeight: leadingFrameSpacerHeight,
          metrics: metrics,
          colorScheme: colorScheme,
          framesPerSecond: framesPerSecond,
          showSeconds: showSeconds,
          windowBucket: windowBucket,
          viewportMainExtent: viewportMainExtent,
        ),
      ),
    );
  }
}

/// The X-sheet frame rail as ONE CustomPainter (UI-R14 #1 — the shared
/// ruler's UI-R13 #1 treatment, transposed): number rows, the seconds
/// column, selection tint, playback dimming and the cached strip paint
/// in a single pass. Public for the test probe.
class XSheetFrameRailPainter extends CustomPainter {
  XSheetFrameRailPainter({
    required this.frameStartIndex,
    required this.frameEndIndexExclusive,
    required this.currentFrameIndex,
    required this.playbackFrameCount,
    required this.leadingFrameSpacerHeight,
    required this.metrics,
    required this.colorScheme,
    this.framesPerSecond = 24,
    this.showSeconds = false,
    this.windowBucket,
    this.viewportMainExtent = 0,
  }) : super(repaint: windowBucket);

  final int frameStartIndex;
  final int frameEndIndexExclusive;
  final int currentFrameIndex;
  final int playbackFrameCount;
  final double leadingFrameSpacerHeight;
  final TimelineGridMetrics metrics;
  final ColorScheme colorScheme;
  final int framesPerSecond;
  final bool showSeconds;

  /// PRO-TIMELINE scrolling (UI-R15→R16): with these set the rail
  /// windows ITSELF off the quantized bucket — full bounds in, repaint
  /// once per span crossing.
  final ValueListenable<int>? windowBucket;
  final double viewportMainExtent;

  /// The row window paint() actually draws (probe surface).
  ({int startIndex, int endIndexExclusive}) visibleRowWindow() {
    final bucket = windowBucket;
    if (bucket == null ||
        viewportMainExtent <= 0 ||
        metrics.frameCellWidth <= 0) {
      return (
        startIndex: frameStartIndex,
        endIndexExclusive: frameEndIndexExclusive,
      );
    }
    final window = timelineFrameWindowFor(
      bucket: bucket.value,
      cellExtent: metrics.frameCellWidth,
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

  /// The row's rect in the rail's local coordinates.
  Rect rowRectFor(int frameIndex) => Rect.fromLTWH(
    0,
    leadingFrameSpacerHeight +
        (frameIndex - frameStartIndex) * metrics.frameCellWidth,
    metrics.layerControlsWidth,
    metrics.frameCellWidth,
  );

  /// The resolved per-row model — the probe surface (the shared ruler's
  /// model class; the rail labels EVERY row, no cadence).
  TimelineRulerHeaderModel modelAt(int frameIndex) {
    final selected = frameIndex == currentFrameIndex;
    final outside = frameIndex >= playbackFrameCount;
    final safeFps = framesPerSecond > 0 ? framesPerSecond : 24;
    return TimelineRulerHeaderModel(
      frameIndex: frameIndex,
      label: showSeconds ? '${frameIndex % safeFps + 1}' : '${frameIndex + 1}',
      secondsLabel: frameIndex % safeFps == 0
          ? '${frameIndex ~/ safeFps + 1}'
          : '',
      selected: selected,
      outsidePlaybackRange: outside,
      background: selected
          ? Color.alphaBlend(
              timelineSelectedFrameBorderColor.withValues(alpha: 0.12),
              colorScheme.surface,
            )
          : outside
          ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.72)
          : colorScheme.surface,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint();
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final linePaint = Paint()..strokeWidth = 1;
    // Rows draw the shared FAINT grid ink (UI-R14 #4); the structural
    // right edge (the rail/scrollbar divider) paints once below.
    final borderColor = timelineBaseGridInk(
      colorScheme,
      frameCellExtent: metrics.frameCellWidth,
    );

    // Self-windowing (UI-R15): only the rows under the live viewport
    // record — a scroll is a repaint of this thin pass, never a rebuild.
    final window = visibleRowWindow();
    for (
      var frameIndex = window.startIndex;
      frameIndex < window.endIndexExclusive;
      frameIndex += 1
    ) {
      final model = modelAt(frameIndex);
      final rect = rowRectFor(frameIndex);
      canvas.drawRect(rect, fillPaint..color = model.background);
      if (borderColor.a > 0) {
        canvas.drawRect(rect.deflate(0.5), borderPaint..color = borderColor);
      }

      // Seconds column on the left (UI-R10 #27): the 1-based second
      // prints bold on its boundary row.
      if (model.secondsLabel.isNotEmpty) {
        final seconds = _label(
          model.secondsLabel,
          TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurfaceVariant,
          ),
        );
        seconds.paint(canvas, Offset(3, rect.center.dy - seconds.height / 2));
      }

      final number = _label(
        model.label,
        TextStyle(
          fontSize: 14,
          color: model.outsidePlaybackRange
              ? colorScheme.onSurfaceVariant.withValues(alpha: 0.55)
              : colorScheme.onSurface,
        ),
      );
      number.paint(
        canvas,
        Offset(
          rect.center.dx - number.width / 2,
          rect.center.dy - number.height / 2,
        ),
      );

      // The cached-range strip moved to [TimelineRulerCursorOverlay] (in
      // its vertical form, hugging the right edge): cached-ness is derived
      // state with no invalidation event, so it must repaint freely rather
      // than ride this gated painter.
    }

    // The structural right edge, full strength, whatever the zoom.
    canvas.drawLine(
      Offset(size.width - 0.5, 0),
      Offset(size.width - 0.5, size.height),
      linePaint..color = colorScheme.outlineVariant,
    );
  }

  // Shared laid-out-TextPainter cache (UI-R16): rail numbers repeat
  // across repaints — fresh layout per label was the debug hot spot.
  TextPainter _label(String text, TextStyle style) =>
      timelineGlyphPainter(text, style);

  @override
  bool shouldRepaint(covariant XSheetFrameRailPainter oldDelegate) =>
      oldDelegate.frameStartIndex != frameStartIndex ||
      oldDelegate.frameEndIndexExclusive != frameEndIndexExclusive ||
      oldDelegate.currentFrameIndex != currentFrameIndex ||
      oldDelegate.playbackFrameCount != playbackFrameCount ||
      oldDelegate.leadingFrameSpacerHeight != leadingFrameSpacerHeight ||
      oldDelegate.metrics != metrics ||
      oldDelegate.framesPerSecond != framesPerSecond ||
      oldDelegate.showSeconds != showSeconds ||
      !identical(oldDelegate.windowBucket, windowBucket) ||
      oldDelegate.viewportMainExtent != viewportMainExtent ||
      // Value-compared, never `identical`: Theme.of(context).colorScheme is a
      // fresh instance every build, so an identity check re-recorded the
      // whole rail on every rebuild.
      oldDelegate.colorScheme != colorScheme;

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
    final nodes = <CustomPainterSemantics>[];
    final window = visibleRowWindow();
    for (
      var frameIndex = window.startIndex;
      frameIndex < window.endIndexExclusive;
      frameIndex += 1
    ) {
      nodes.add(
        CustomPainterSemantics(
          rect: rowRectFor(frameIndex),
          properties: SemanticsProperties(
            label: 'frame ${frameIndex + 1}',
            textDirection: TextDirection.ltr,
          ),
        ),
      );
    }
    return nodes;
  };
}

/// One cell of the section band above the layer headers: the paper sheet's
/// group heading wrapping its columns. Display-only — section visibility
/// lives on the toolbar toggles. The band label is horizontal already (the
/// band runs along the layer axis here).
class _XSheetSectionBandCell extends StatelessWidget {
  const _XSheetSectionBandCell({required this.run, required this.extent});

  final TimelineSectionRun run;
  final double extent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        width: extent,
        height: XSheetTimelineGrid._sectionBandHeight,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          border: Border.all(color: colorScheme.outline, width: 1),
        ),
        child: Center(
          child: Text(
            timelineSectionLabel(run.section),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 1.2,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _LayerHeader extends StatelessWidget {
  const _LayerHeader({
    required this.layer,
    required this.active,
    required this.onSelectLayer,
    required this.onToggleLayerVisibility,
    required this.onLayerOpacityChanged,
    this.onLayerOpacityChangeEnd,
    this.opacityDragPreview,
    required this.onToggleLayerTimesheet,
    required this.onLayerMarkSelected,
    required this.metrics,
    this.onToggleLayerFillReference,
    this.onToggleLayerMuted,
    this.hasLanes = false,
    this.lanesExpanded = false,
    this.onToggleLanes,
    this.fxEnabled = true,
    this.onToggleLayerFx,
    this.isLayerSoloed = false,
    this.onToggleLayerSolo,
    this.onEditLayerAudio,
    this.resolveStrings,
  });

  final TimelineGridMetrics metrics;

  final Layer layer;
  final bool active;
  final ValueChanged<LayerId> onSelectLayer;
  final ValueChanged<LayerId> onToggleLayerVisibility;
  final void Function(LayerId layerId, double opacity) onLayerOpacityChanged;

  /// Commit-on-release hook (R4 #4); null keeps per-move writes.
  final void Function(LayerId layerId, double opacity)? onLayerOpacityChangeEnd;

  /// The session's live opacity-drag preview (UI-R6 #2).
  final ValueListenable<({Set<LayerId> layerIds, double opacity})?>?
  opacityDragPreview;

  final ValueChanged<LayerId> onToggleLayerTimesheet;
  final void Function(LayerId layerId, LayerMark mark) onLayerMarkSelected;

  /// Drawing columns' fill-reference toggle (R20-C2); null hides it.
  final ValueChanged<LayerId>? onToggleLayerFillReference;

  /// SE columns' speaker button (mute); null hides it.
  final ValueChanged<LayerId>? onToggleLayerMuted;

  /// The SE mix menu (AUDIO-PRO R1) — same speaker context menu as the
  /// horizontal rail.
  final bool isLayerSoloed;
  final ValueChanged<LayerId>? onToggleLayerSolo;
  final ValueChanged<LayerId>? onEditLayerAudio;

  /// The PROGRAM-language table for the mix menu; null keeps English.
  final AppStrings Function()? resolveStrings;

  /// AE-style property-lane twirl-down: layers with lanes lead their name
  /// row with a chevron (lane COLUMNS open beside the layer's). Headers
  /// without lanes skip the slot — names center per column here, so no
  /// cross-column alignment to preserve.
  final bool hasLanes;
  final bool lanesExpanded;
  final ValueChanged<LayerId>? onToggleLanes;

  /// The AE-style fx switch (session view state). Null hides it.
  final bool fxEnabled;
  final ValueChanged<LayerId>? onToggleLayerFx;

  Future<void> _showMixMenu(BuildContext context, Offset globalPosition) async {
    final overlay = Overlay.of(context).context.findRenderObject();
    final strings = resolveStrings?.call() ?? AppStrings.of(AppLanguage.en);
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & (overlay as RenderBox).size,
      ),
      items: [
        if (onToggleLayerSolo != null)
          PopupMenuItem<String>(
            key: ValueKey<String>('xsheet-layer-solo-${layer.id}'),
            value: 'solo',
            child: Text(
              isLayerSoloed ? strings.audioUnsolo : strings.audioSolo,
            ),
          ),
        if (onEditLayerAudio != null)
          PopupMenuItem<String>(
            key: ValueKey<String>('xsheet-layer-audio-${layer.id}'),
            value: 'audio',
            child: Text(strings.audioLayerAudioMenu),
          ),
      ],
    );
    switch (selected) {
      case 'solo':
        onToggleLayerSolo?.call(layer.id);
      case 'audio':
        onEditLayerAudio?.call(layer.id);
      case _:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final showLaneToggle = hasLanes && onToggleLanes != null;

    final header = InkWell(
      key: ValueKey<String>('xsheet-layer-header-${layer.id}'),
      onTap: () => onSelectLayer(layer.id),
      child: Container(
        width: metrics.layerRowHeight,
        height: XSheetTimelineGrid._headerHeight,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? colorScheme.secondaryContainer
              : colorScheme.surfaceContainerHighest,
          // CONSTANT 1px borders, right/top/bottom only (UI-R10 #20):
          // side-by-side headers kept doubling their shared seam and the
          // active column's 2px accent shifted its content — selection
          // reads by COLOR alone (app-wide selection language). The left
          // line is the neighbor's right (the frame rail closes the
          // first column).
          border: Border(
            right: BorderSide(
              color: active
                  ? colorScheme.secondary
                  : colorScheme.outlineVariant,
            ),
            top: BorderSide(
              color: active
                  ? colorScheme.secondary
                  : colorScheme.outlineVariant,
            ),
            bottom: BorderSide(
              color: active
                  ? colorScheme.secondary
                  : colorScheme.outlineVariant,
            ),
          ),
        ),
        child: Semantics(
          key: active ? const ValueKey<String>('xsheet-selected-layer') : null,
          label: active ? 'selected layer' : 'layer',
          container: true,
          child: Stack(
            children: [
              // Fill-reference toggle (R20-C2): OVERLAID top-right over the
              // name row's balance slot — the fixed-height header column
              // has no layout row to spare (adding it inline overflowed).
              // Drawing columns only; selection reads by COLOR.
              if (onToggleLayerFillReference != null &&
                  layer.kind == LayerKind.animation)
                Positioned(
                  top: 0,
                  right: 0,
                  child: IconButton(
                    key: ValueKey<String>(
                      'xsheet-layer-fill-reference-${layer.id}',
                    ),
                    tooltip: layer.isFillReference
                        ? 'Fill reference layer (on)'
                        : 'Fill reference layer',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 20,
                      height: 20,
                    ),
                    icon: Icon(
                      Icons.format_color_fill,
                      size: 13,
                      color: layer.isFillReference
                          ? colorScheme.primary
                          : colorScheme.outline.withValues(alpha: 0.45),
                    ),
                    onPressed: () => onToggleLayerFillReference!(layer.id),
                  ),
                ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      if (showLaneToggle)
                        InkWell(
                          key: ValueKey<String>(
                            'xsheet-lane-toggle-${layer.id}',
                          ),
                          onTap: () => onToggleLanes!(layer.id),
                          customBorder: const CircleBorder(), // R26 #28
                          child: SizedBox(
                            width: 16,
                            height: 24,
                            child: Icon(
                              lanesExpanded
                                  ? Icons.arrow_drop_down
                                  : Icons.arrow_right,
                              size: 16,
                            ),
                          ),
                        ),
                      // Timesheet + mark chips lead the name; ineligible layers
                      // keep empty slots so names align across columns.
                      if (layerKindEligibleForTimesheetToggle(layer.kind))
                        LayerTimesheetToggleButton(
                          keyPrefix: 'xsheet',
                          layerId: layer.id,
                          onTimesheet: layer.onTimesheet,
                          onToggle: onToggleLayerTimesheet,
                        )
                      else
                        const SizedBox(width: layerTimesheetSlotWidth),
                      const SizedBox(width: 4),
                      LayerMarkChip(
                        keyPrefix: 'xsheet',
                        layerId: layer.id,
                        mark: layer.mark,
                        onMarkSelected: onLayerMarkSelected,
                      ),
                      Expanded(
                        child: InkWell(
                          key: ValueKey<String>(
                            'xsheet-layer-name-${layer.id}',
                          ),
                          onTap: () => onSelectLayer(layer.id),
                          // Selection reads by COLOR only (user rule): no
                          // bold flip on the active column's name.
                          child: Text(
                            layer.name,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      // Balance the leading chips so the name stays centered.
                      SizedBox(
                        width:
                            layerTimesheetSlotWidth +
                            layerMarkSlotWidth +
                            4 +
                            (showLaneToggle ? 16 : 0),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      if (onToggleLayerFx != null &&
                          layerKindShowsFxToggle(layer.kind))
                        FxToggleButton(
                          keyValue: 'xsheet-layer-fx-${layer.id}',
                          fxEnabled: fxEnabled,
                          onToggle: () => onToggleLayerFx!(layer.id),
                        ),
                      LayerVisibilityToggleButton(
                        keyValue: 'xsheet-layer-visibility-${layer.id}',
                        isVisible: layer.isVisible,
                        onToggle: () => onToggleLayerVisibility(layer.id),
                        size: 28,
                        iconSize: 16,
                      ),
                      // SE columns carry the mute speaker beside the eye. Tight
                      // SizedBox: the M3 IconButton otherwise inflates to the
                      // 48px tap target, overflowing the header column.
                      if (layer.kind == LayerKind.se &&
                          onToggleLayerMuted != null)
                        SizedBox(
                          width: 24,
                          height: 28,
                          child: GestureDetector(
                            onSecondaryTapUp:
                                onToggleLayerSolo == null &&
                                    onEditLayerAudio == null
                                ? null
                                : (details) => _showMixMenu(
                                    context,
                                    details.globalPosition,
                                  ),
                            onLongPressStart:
                                onToggleLayerSolo == null &&
                                    onEditLayerAudio == null
                                ? null
                                : (details) => _showMixMenu(
                                    context,
                                    details.globalPosition,
                                  ),
                            child: LayerMuteToggleButton(
                              keyValue: 'xsheet-layer-mute-${layer.id}',
                              muted: layer.muted,
                              soloed: isLayerSoloed,
                              width: 24,
                              height: 28,
                              onToggle: () => onToggleLayerMuted!(layer.id),
                            ),
                          ),
                        ),
                      // The camera column's slider drives the camera-view DIM
                      // opacity (unified layer controls). Wrapped in the
                      // session's opacity-drag preview (UI-R6 #2) so a
                      // master-bar sweep updates it live.
                      if (layerKindShowsOpacityControl(layer.kind))
                        Expanded(child: _opacityField(layer))
                      else
                        const Spacer(),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    // Section boundaries draw ONE shared hairline like every column
    // boundary (R3 feedback #6) — the extra 2px overlay double-lined them;
    // the band above carries the section identity.
    return header;
  }

  /// The header's opacity slider, live-following the session's drag
  /// preview when it targets this layer (UI-R6 #2).
  Widget _opacityField(Layer layer) {
    Widget slider(double value) => FieldSlider(
      key: ValueKey<String>('xsheet-layer-opacity-${layer.id}'),
      min: 0,
      max: 1,
      value: value,
      valueText: '${(value * 100).round()}%',
      valueTextBuilder: (next) => '${(next * 100).round()}%',
      displayFactor: 100,
      height: 18,
      onChanged: (opacity) => onLayerOpacityChanged(layer.id, opacity),
      onChangeEnd: onLayerOpacityChangeEnd == null
          ? null
          : (opacity) => onLayerOpacityChangeEnd!(layer.id, opacity),
    );

    final preview = opacityDragPreview;
    final resting = layer.opacity.clamp(0.0, 1.0).toDouble();
    if (preview == null) {
      return slider(resting);
    }
    return ValueListenableBuilder<({Set<LayerId> layerIds, double opacity})?>(
      valueListenable: preview,
      builder: (context, dragging, _) => slider(
        dragging != null && dragging.layerIds.contains(layer.id)
            ? dragging.opacity
            : resting,
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.width,
    required this.height,
    required this.child,
  });

  final double width;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}
