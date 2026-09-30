import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/layer.dart';
import '../../models/layer_id.dart';
import 'property_lane_model.dart';
import 'se_audio_lane.dart';
import 'timeline_frame_range_gesture.dart';
import 'timeline_cells_row_facts.dart';
import 'timeline_grid_hooks.dart';
import 'timeline_frame_geometry.dart';
import 'timeline_frame_window.dart' show timelineFrameWindowSpanFor;
import 'timeline_grid_metrics.dart';
import 'timeline_lane_rows.dart';
import 'timeline_section_runs.dart' show timelineDisplayRowExtent;

import '../listenable_rebind.dart';

class TimelineFrameRowsScrollBody extends StatefulWidget {
  const TimelineFrameRowsScrollBody({
    super.key,
    required this.rows,
    required this.hooks,
    required this.frameStartIndex,
    required this.frameEndIndexExclusive,
    required this.leadingFrameSpacerWidth,
    required this.trailingFrameSpacerWidth,
    required this.totalFrameContentWidth,
    this.leadingLayerSpacerHeight = 0,
    this.trailingLayerSpacerHeight = 0,
    this.pinnedLeadingRow,
    this.pinnedLeadingOffset = 0,
    this.pinnedTrailingRow,
    this.pinnedTrailingOffset = 0,
    required this.metrics,
    this.rangeGesture,
    this.laneRange,
    this.windowBucket,
    this.viewportMainExtent = 0,
  });

  /// What the session answers to the rows — the grid's ONE bundle, which
  /// the x-sheet's columns read too ([timelineCellsRowFacts]). The body
  /// used to take some thirty of its fields one by one, a third list of
  /// the answers both grids must agree on.
  final TimelineGridHooks hooks;

  /// PRO-TIMELINE scrolling (UI-R15→R16): with these set the drawing rows
  /// build once for the full bounds (their painters window themselves off
  /// the quantized bucket — repaint per span crossing, pure translation
  /// between) and the sparse rows re-window under the same bucket — a
  /// scroll rebuilds nothing here.
  final ValueListenable<int>? windowBucket;
  final double viewportMainExtent;

  /// Display rows: layer rows interleaved with expanded property lanes.
  /// May be a layer-axis WINDOW of the full row list — the spacer heights
  /// preserve the scroll geometry of the rows sliced away.
  final List<TimelineDisplayRow> rows;
  final int frameStartIndex;
  final int frameEndIndexExclusive;
  final double leadingFrameSpacerWidth;
  final double trailingFrameSpacerWidth;
  final double totalFrameContentWidth;

  /// Layer-axis spacers standing in for the rows above/below the built
  /// window (the vertical counterpart of the frame-axis spacers).
  final double leadingLayerSpacerHeight;
  final double trailingLayerSpacerHeight;

  /// A5/D42: a row a drag is HOLDING, carved out of the spacer it falls in
  /// so its State (the range gesture mid-move) survives the window sliding
  /// past it — the rail's pin, applied to the cells. [pinnedLeadingOffset]
  /// is the height above the pinned row inside the leading region; the
  /// spacer totals are unchanged, so scroll geometry never notices.
  final TimelineDisplayRow? pinnedLeadingRow;
  final double pinnedLeadingOffset;
  final TimelineDisplayRow? pinnedTrailingRow;
  final double pinnedTrailingOffset;

  final TimelineGridMetrics metrics;

  /// The range select/move gesture bundle (UI-R8 — the block-body move
  /// handle's successor); null keeps rows display-only.
  final TimelineRangeGestureCallbacks? rangeGesture;

  /// The LANE selection domain's gesture bundle (UI-R23 #3 part 2); null
  /// keeps the lane bands display-only.
  final TimelineLaneRangeCallbacks? laneRange;

  @override
  State<TimelineFrameRowsScrollBody> createState() =>
      _TimelineFrameRowsScrollBodyState();
}

class _TimelineFrameRowsScrollBodyState
    extends State<TimelineFrameRowsScrollBody> {
  /// Identity-gated row memo (the timesheet-document memo, per row): on a
  /// commit-time rebuild the untouched layers come back as the SAME Layer
  /// instances from the repository, so their rows reuse the cached widget
  /// INSTANCE and Flutter skips their whole subtree rebuild. What a row
  /// shows beyond its Layer joins the key ([TimelineCellsRowFacts]) — the
  /// camera track, the SE waveform peaks — and lane rows, which are few,
  /// are not memoized ([keptTimelineCellsRow], the x-sheet's columns' too).
  final Map<LayerId, KeptTimelineCellsRow> _rowMemo = {};

  /// The LIVE frame-axis geometry every painted row follows (R28 #4).
  ///
  /// It lives here, in State, so its IDENTITY survives the rebuilds this
  /// body does on every zoom step — that identity is what lets the memo hand
  /// a painted row's cached widget back while the geometry underneath it has
  /// moved. Republished from `build`, which is safe because every listener is
  /// a render object (the row painters' `repaint`, the axis box's relayout):
  /// both marks are honoured later in the same frame. Never attach a
  /// `ValueListenableBuilder` or a `setState` listener to it.
  late final ValueNotifier<TimelineFrameGeometry> _geometry = ValueNotifier(
    _geometryFromWidget(),
  );

  /// The same geometry seen through the frame-axis WINDOW (zoom round) —
  /// handed to the rows whose every consumer reads it live, so their boxes
  /// stop being `frames * cellWidth` and a zoom step re-lays-out one box per
  /// row instead of everything in it.
  ///
  /// The SPARSE kinds keep [_geometry]: their span overlays are widgets
  /// positioned from build-time scalars, so a window that slides under them
  /// without a rebuild would leave them behind.
  ///
  /// It follows the window bucket DIRECTLY (not through build) because a
  /// scroll must not rebuild this body — the same render-object-only
  /// listener contract as [_geometry].
  late final ValueNotifier<TimelineFrameGeometry> _windowedGeometry =
      ValueNotifier(_windowedGeometryFromWidget());

  TimelineFrameGeometry _geometryFromWidget() => TimelineFrameGeometry(
    frameCellExtent: widget.metrics.frameCellWidth,
    frameStartIndex: widget.frameStartIndex,
    frameEndIndexExclusive: widget.frameEndIndexExclusive,
    leadingFrameSpacerWidth: widget.leadingFrameSpacerWidth,
    trailingFrameSpacerWidth: widget.trailingFrameSpacerWidth,
  );

  /// The window for the CURRENT bucket: origin quantized to the shared
  /// bucket span (so it moves once per crossing, exactly when the painters
  /// re-window), extent a constant pixel span around the viewport.
  ///
  /// Without a bucket or a measured viewport there is no window at all and
  /// every row keeps the content-sized box.
  TimelineFrameGeometry _windowedGeometryFromWidget() {
    final base = _geometryFromWidget();
    final bucket = widget.windowBucket;
    final viewport = widget.viewportMainExtent;
    final cellExtent = base.frameCellExtent;
    if (bucket == null || viewport <= 0 || cellExtent <= 0) {
      return base;
    }
    final spanPx = timelineFrameWindowSpanFor(cellExtent) * cellExtent;
    return base.windowed(
      originPx: math.max(
        0.0,
        bucket.value * spanPx - timelineFrameWindowMarginPx,
      ),
      extentPx: viewport + 2 * timelineFrameWindowMarginPx,
    );
  }

  void _handleWindowBucket() {
    _windowedGeometry.value = _windowedGeometryFromWidget();
  }

  @override
  void initState() {
    super.initState();
    widget.windowBucket?.addListener(_handleWindowBucket);
  }

  @override
  void didUpdateWidget(covariant TimelineFrameRowsScrollBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    rebindListener(oldWidget.windowBucket, widget.windowBucket, _handleWindowBucket);
  }

  @override
  void dispose() {
    widget.windowBucket?.removeListener(_handleWindowBucket);
    _geometry.dispose();
    _windowedGeometry.dispose();
    super.dispose();
  }

  /// Every row keys off its own id; a lane row adds which lane it is.
  /// R10 dropped the folder prefix with the folder's private band — a
  /// folder row is a cells row now, so it keys like one.
  String _rowKeySuffix(TimelineDisplayRow row) => row.lane?.laneId ?? 'cells';

  /// The lane to render: the drag preview's version while one is staged
  /// for this row's layer (R10), the committed one otherwise.
  PropertyLaneRow _laneOf(TimelineDisplayRow row, Layer layer) {
    final lanesForLayer = widget.hooks.lanesForLayer;
    if (lanesForLayer == null) {
      return row.lane!;
    }
    return previewedLaneRow(
      row: row,
      previewLayer: layer,
      lanesForLayer: lanesForLayer,
    );
  }

  Widget _buildLaneRow(TimelineDisplayRow row, Layer layer) {
    return laneIsSeAudio(row.lane!)
        ? SeAudioLaneFrameRow(
            layer: layer,
            frameStartIndex: widget.frameStartIndex,
            frameEndIndexExclusive: widget.frameEndIndexExclusive,
            leadingFrameSpacerWidth: widget.leadingFrameSpacerWidth,
            trailingFrameSpacerWidth: widget.trailingFrameSpacerWidth,
            metrics: widget.metrics,
            frameRate: widget.hooks.projectFrameRate,
            audioPeaksFor: widget.hooks.audioPeaksFor,
            spillInLeadFrames: widget.hooks.spillInLeadFrames[layer.id],
            onSetClipOffset: widget.hooks.audioLane?.onSetClipOffset == null
                ? null
                : (clipIndex, offsetFrames) =>
                      widget.hooks.audioLane!.onSetClipOffset!(
                        layer.id,
                        clipIndex,
                        offsetFrames,
                      ),
            offsetDrag: widget.hooks.audioLane?.offsetDrag,
            onSetClipFades: widget.hooks.audioLane?.onSetClipFades == null
                ? null
                : (clipIndex, fadeIn, fadeOut) =>
                      widget.hooks.audioLane!.onSetClipFades!(
                        layer.id,
                        clipIndex,
                        fadeIn,
                        fadeOut,
                      ),
          )
        : TimelineLaneFrameRow(
            layer: layer,
            lane: _laneOf(row, layer),
            frameStartIndex: widget.frameStartIndex,
            frameEndIndexExclusive: widget.frameEndIndexExclusive,
            leadingFrameSpacerWidth: widget.leadingFrameSpacerWidth,
            trailingFrameSpacerWidth: widget.trailingFrameSpacerWidth,
            metrics: widget.metrics,
            // The LANE selection domain (UI-R23 #3 part 2) — EVERY row's
            // lanes now, camera included. It stood down there until
            // 2026-08-08 on the reading that the camera's keyframes are
            // atomic; they are not (a camera row's lanes edit
            // `cut.camera.track`, a per-property TransformTrack like any
            // other). What was actually missing was the move path's
            // camera arm, which is why wiring this earlier would have
            // written keys into the camera layer's own unused track.
            laneRange: widget.laneRange,
          );
  }

  Widget _buildRow(TimelineDisplayRow row) {
    final rowKey = ValueKey<String>(
      'timeline-row-${row.layer.id}-${_rowKeySuffix(row)}',
    );
    // 🚨F-244: the row's own size, laid FRESH on every build. It is what
    // makes the tick layer's constraints tight — and a zoom step keeps the
    // memo entry below while it moves the content extent, so a box inside
    // the memo would hold the old width: the row cut short of its cells.
    return SizedBox(
      key: rowKey,
      width: widget.totalFrameContentWidth,
      height: timelineDisplayRowExtent(row, widget.metrics),
      child: _layeredRow(row),
    );
  }

  /// The rows as their cells see them — the x-sheet's columns read the same
  /// record turned on its side.
  TimelineCellsRowGrid get _cellsRowGrid => (
    hooks: widget.hooks,
    metrics: widget.metrics,
    geometry: _windowedGeometry,
    windowBucket: widget.windowBucket,
    viewportMainExtent: widget.viewportMainExtent,
    rangeGesture: widget.rangeGesture,
    axis: Axis.horizontal,
    keyPrefix: 'timeline',
  );

  Widget _layeredRow(TimelineDisplayRow row) => row.isLane
      ? timelineGatedRow(
          row,
          widget.hooks.dragPreview,
          (context, layer) => _buildLaneRow(row, layer),
        )
      : keptTimelineCellsRow(_rowMemo, row, _cellsRowGrid);

  @override
  Widget build(BuildContext context) {
    // Republish BEFORE the rows read it: the painted rows' render objects
    // take the mark now and settle it during this frame's layout/paint.
    _geometry.value = _geometryFromWidget();
    _windowedGeometry.value = _windowedGeometryFromWidget();
    final pinnedLeading = widget.pinnedLeadingRow;
    final pinnedTrailing = widget.pinnedTrailingRow;
    final rowHeight = widget.metrics.layerRowHeight;
    final children = <Widget>[
      // A5/D42: a pinned (held) row is carved out of its spacer — the
      // total extent is unchanged, so the scroll geometry never notices.
      if (pinnedLeading != null) ...[
        if (widget.pinnedLeadingOffset > 0)
          SizedBox(height: widget.pinnedLeadingOffset),
        _buildRow(pinnedLeading),
        if (widget.leadingLayerSpacerHeight -
                widget.pinnedLeadingOffset -
                rowHeight >
            0)
          SizedBox(
            height:
                widget.leadingLayerSpacerHeight -
                widget.pinnedLeadingOffset -
                rowHeight,
          ),
      ] else if (widget.leadingLayerSpacerHeight > 0)
        SizedBox(
          key: const ValueKey<String>('timeline-leading-layer-spacer'),
          height: widget.leadingLayerSpacerHeight,
        ),
      for (final row in widget.rows) _buildRow(row),
      if (pinnedTrailing != null) ...[
        if (widget.pinnedTrailingOffset > 0)
          SizedBox(height: widget.pinnedTrailingOffset),
        _buildRow(pinnedTrailing),
        if (widget.trailingLayerSpacerHeight -
                widget.pinnedTrailingOffset -
                rowHeight >
            0)
          SizedBox(
            height:
                widget.trailingLayerSpacerHeight -
                widget.pinnedTrailingOffset -
                rowHeight,
          ),
      ] else if (widget.trailingLayerSpacerHeight > 0)
        SizedBox(
          key: const ValueKey<String>('timeline-trailing-layer-spacer'),
          height: widget.trailingLayerSpacerHeight,
        ),
      if (widget.rows.isEmpty)
        SizedBox(
          width: widget.totalFrameContentWidth,
          height: widget.metrics.layerRowHeight,
        ),
    ];

    // Bound the memo to the rows built this pass (scrolled-out rows just
    // rebuild when they come back).
    final liveLayers = <LayerId>{
      for (final row in widget.rows) row.layer.id,
      if (pinnedLeading != null) pinnedLeading.layer.id,
      if (pinnedTrailing != null) pinnedTrailing.layer.id,
    };
    _rowMemo.removeWhere((layerId, _) => !liveLayers.contains(layerId));

    return KeyedSubtree(
      key: const ValueKey<String>('timeline-frame-rows-scroll-body'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
