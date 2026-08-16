import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show BoxHitTestResult, RenderProxyBox;
import 'package:flutter/semantics.dart' show SemanticsProperties;

import '../input/app_input_settings.dart' show AppInput;
import '../input/eager_pan_gesture_recognizer.dart';

import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/timeline_coverage.dart';
import '../../models/timeline_repeat.dart';
import '../widgets/panel_flyout.dart';
import 'timeline_cell_style.dart' show timelineDrawingHeldColor;
import 'timeline_exposure_comma_drag_handle.dart';
import 'timeline_exposure_comma_drag_policy.dart';
import 'timeline_frame_geometry.dart';
import 'timeline_run_end_handles.dart';
import '../text/app_strings.dart';

/// One pointer target in a dense row's edit chrome. Its [rect] is the
/// row-local hit area — the same rect the painter draws inside, so there is
/// exactly one geometry for "where is it" and "where do I click it".
sealed class TimelineRowChromeTarget {
  const TimelineRowChromeTarget({required this.id, required this.rect});

  /// Stable identity string. It is the successor of the widget keys these
  /// targets replaced (`run-add-end-<layerId>-<anchor>`, …) and is what
  /// tests address instead of `find.byKey`.
  final String id;

  /// Row-local pointer rect.
  final Rect rect;
}

/// A block's comma-drag grip.
class TimelineRowGripTarget extends TimelineRowChromeTarget {
  const TimelineRowGripTarget({
    required super.id,
    required super.rect,
    required this.edge,
    required this.blockStartIndex,
    required this.blockOrdinal,
    required this.barRect,
  });

  final TimelineBlockEdge edge;
  final int blockStartIndex;
  final int blockOrdinal;

  /// Row-local rect of the drawn bar (inside [rect]).
  final Rect barRect;

  @override
  bool operator ==(Object other) =>
      other is TimelineRowGripTarget &&
      other.id == id &&
      other.rect == rect &&
      other.edge == edge &&
      other.blockStartIndex == blockStartIndex &&
      other.blockOrdinal == blockOrdinal &&
      other.barRect == barRect;

  @override
  int get hashCode =>
      Object.hash(id, rect, edge, blockStartIndex, blockOrdinal, barRect);
}

/// A run edge's [+] half.
class TimelineRowRunAddTarget extends TimelineRowChromeTarget {
  const TimelineRowRunAddTarget({
    required super.id,
    required super.rect,
    required this.side,
    required this.blockStartIndex,
  });

  final TimelineRunEdgeSide side;
  final int blockStartIndex;

  bool get atEnd => side == TimelineRunEdgeSide.end;

  @override
  bool operator ==(Object other) =>
      other is TimelineRowRunAddTarget &&
      other.id == id &&
      other.rect == rect &&
      other.side == side &&
      other.blockStartIndex == blockStartIndex;

  @override
  int get hashCode => Object.hash(id, rect, side, blockStartIndex);
}

/// A run edge's N/H/R property tag half.
class TimelineRowRunTagTarget extends TimelineRowChromeTarget {
  const TimelineRowRunTagTarget({
    required super.id,
    required super.rect,
    required this.side,
    required this.blockStartIndex,
    required this.mode,
    required this.hasPattern,
    required this.letter,
  });

  final TimelineRunEdgeSide side;
  final int blockStartIndex;
  final TimelineRunEdgeMode? mode;
  final bool hasPattern;
  final String letter;

  @override
  bool operator ==(Object other) =>
      other is TimelineRowRunTagTarget &&
      other.id == id &&
      other.rect == rect &&
      other.side == side &&
      other.blockStartIndex == blockStartIndex &&
      other.mode == mode &&
      other.hasPattern == hasPattern;

  @override
  int get hashCode =>
      Object.hash(id, rect, side, blockStartIndex, mode, hasPattern);
}

/// Everything a dense row draws and hit-tests for edit chrome.
class TimelineRowEditChromeModel {
  const TimelineRowEditChromeModel({
    required this.targets,
    required this.patternSpans,
  });

  /// Hit order: EARLIEST wins. Grips lead so the block edges keep their
  /// comma-drag priority over a neighbouring run cluster, exactly as the
  /// Stack order used to give them (grips were mounted last, on top).
  final List<TimelineRowChromeTarget> targets;

  /// Row-local rects of the selection-scoped repeat outlines; drawn under
  /// everything and never a pointer target.
  final List<Rect> patternSpans;

  bool get isEmpty => targets.isEmpty && patternSpans.isEmpty;
}

/// One block a row hangs comma grips on, as the chrome model sees it.
///
/// A SPAN plus which of its two edges are editable — not a `Layer`'s
/// exposure, because a dense row is not only a layer's: the storyboard's
/// cut row hangs the same grips on cuts. Whose blocks these are, and which
/// edges a rule suppresses (ghosts, spill-in starts), is the caller's to
/// decide before it gets here.
typedef TimelineChromeGripBlock = ({
  int ordinal,
  int startIndex,
  int endIndexExclusive,
  bool startGrip,
  bool endGrip,
});

/// [layer]'s drawing blocks as grip material. Ghost repeat instances are
/// DERIVED, so they carry no timing grips (UI-R8); a spill-in display
/// block's start lives in an earlier cut, so it carries no start grip
/// (UI-R7 #6, TrackSeWindow). A gapless row (the storyboard's) carries no
/// start grips AT ALL ([suppressAllStartGrips], edge unification): every
/// boundary belongs to the trailing edge on its left, so front edges have
/// nothing of their own to move — the row's true front edge is the cut's
/// start, which lives on the storyboard strip.
List<TimelineChromeGripBlock> timelineLayerGripBlocks(
  Layer layer, {
  bool suppressStartGripAtZero = false,
  bool suppressAllStartGrips = false,
}) {
  final blocks = drawingBlocks(layer.timeline);
  return [
    for (var ordinal = 0; ordinal < blocks.length; ordinal += 1)
      if (!blocks[ordinal].entry.ghost)
        (
          ordinal: ordinal,
          startIndex: blocks[ordinal].startIndex,
          endIndexExclusive: blocks[ordinal].endIndexExclusive,
          startGrip:
              !suppressAllStartGrips &&
              !(suppressStartGripAtZero && blocks[ordinal].startIndex == 0),
          endGrip: true,
        ),
  ];
}

/// Resolves a dense row's edit chrome: the comma grips of every visible
/// block plus (layer rows only) each glued run's [+]/property cluster.
///
/// R28 #4 tier 2: these used to be a `Positioned` + `MouseRegion` +
/// `GestureDetector` + `Align` + `Padding` + `Container` PER GRIP and a
/// two-glyph `Column` of `Text` per run edge. A zoom step changes
/// `frameCellWidth`, which invalidates every visible row's memo, and the
/// rows then re-laid-out rows x (blocks + runs) of those boxes — measured
/// as the dominant half of a 736ms zoom step at 24 layers. One model, one
/// painter and one row-level gesture layer replace them.
TimelineRowEditChromeModel timelineRowEditChromeModel({
  required List<TimelineChromeGripBlock> gripBlocks,
  required String gripIdScope,
  Layer? layer,
  Layer? baseLayer,
  required TimelineFrameGeometry geometry,
  required double crossAxisExtent,
  required Axis axis,
  required bool includeRunEdges,
}) {
  final targets = <TimelineRowChromeTarget>[];
  final patternSpans = <Rect>[];
  final horizontal = axis == Axis.horizontal;
  final frameStartIndex = geometry.frameStartIndex;
  final frameEndIndexExclusive = geometry.frameEndIndexExclusive;
  final frameCellExtent = geometry.frameCellExtent;

  Rect mainRect(double start, double extent) => horizontal
      ? Rect.fromLTWH(start, 0, extent, crossAxisExtent)
      : Rect.fromLTWH(0, start, crossAxisExtent, extent);

  for (final block in gripBlocks) {
    if (block.endIndexExclusive <= frameStartIndex ||
        block.startIndex >= frameEndIndexExclusive) {
      continue;
    }
    final blockStartOffset = geometry.edgeAt(block.startIndex);
    final blockEndOffset = geometry.edgeAt(block.endIndexExclusive);
    // The block's own width joins the measure, so a long one keeps a grip
    // you can aim at however far out the axis is zoomed.
    final hitExtent = blockEdgeGripHitExtent(
      frameCellExtent,
      blockExtent: blockEndOffset - blockStartOffset,
    );
    for (final edge in TimelineBlockEdge.values) {
      if (edge == TimelineBlockEdge.start && !block.startGrip) {
        continue;
      }
      if (edge == TimelineBlockEdge.end && !block.endGrip) {
        continue;
      }
      final hitStart = edge == TimelineBlockEdge.start
          ? blockStartOffset
          : blockEndOffset - hitExtent;
      final rect = mainRect(hitStart, hitExtent);
      final bar = blockEdgeGripBarRect(
        edge: edge,
        hitExtent: hitExtent,
        crossAxisExtent: crossAxisExtent,
        axis: axis,
      );
      targets.add(
        TimelineRowGripTarget(
          id: 'block-edge-grip-${edge.name}-$gripIdScope-${block.ordinal}',
          rect: rect,
          edge: edge,
          blockStartIndex: block.startIndex,
          blockOrdinal: block.ordinal,
          barRect: bar.shift(rect.topLeft),
        ),
      );
    }
  }

  if (includeRunEdges && layer != null) {
    final chrome = timelineRunEdgeChrome(
      layer: layer,
      baseLayer: baseLayer,
      frameStartIndex: frameStartIndex,
      frameEndIndexExclusive: frameEndIndexExclusive,
      leadingFrameSpacerWidth: geometry.leadingFrameSpacerWidth,
      frameCellExtent: frameCellExtent,
    );
    for (final span in chrome.patterns) {
      patternSpans.add(mainRect(span.mainStart, span.mainExtent));
    }
    for (final cluster in chrome.clusters) {
      final rect = timelineRunClusterRect(
        cluster: cluster,
        frameCellExtent: frameCellExtent,
        crossAxisExtent: crossAxisExtent,
        axis: axis,
      );
      final (addRect, tagRect) = timelineRunClusterHalves(rect, axis);
      final sideWord = cluster.side == TimelineRunEdgeSide.end
          ? 'end'
          : 'start';
      targets.add(
        TimelineRowRunAddTarget(
          id: 'run-add-$sideWord-${layer.id}-${cluster.anchorValue}',
          rect: addRect,
          side: cluster.side,
          blockStartIndex: cluster.blockStartIndex,
        ),
      );
      targets.add(
        TimelineRowRunTagTarget(
          id: 'run-edge-tag-${layer.id}-${cluster.anchorValue}-$sideWord',
          rect: tagRect,
          side: cluster.side,
          blockStartIndex: cluster.blockStartIndex,
          mode: cluster.mode,
          hasPattern: cluster.hasPattern,
          letter: cluster.modeLetter,
        ),
      );
    }
  }

  return TimelineRowEditChromeModel(
    targets: targets,
    patternSpans: patternSpans,
  );
}

/// Holds a row's chrome inputs and hands out the model for whatever geometry
/// is live, remembering the last one.
///
/// The split matters (R28 #4 tier 3 measurement): resolving the model walks
/// the layer's blocks and glued runs, which is the expensive part and does
/// NOT depend on the zoom; the rects are arithmetic. One instance per row
/// survives zoom steps, so a step re-derives rects and nothing else.
class TimelineRowChromeResolver {
  TimelineRowChromeResolver({
    required this.gripBlocks,
    required this.gripIdScope,
    required this.layer,
    required this.baseLayer,
    required this.crossAxisExtent,
    required this.axis,
    required this.includeRunEdges,
  });

  final List<TimelineChromeGripBlock> gripBlocks;
  final String gripIdScope;

  /// The row's layer — needed only for the run-edge half. Null on rows
  /// that have blocks but no runs (the storyboard's cut row).
  final Layer? layer;
  final Layer? baseLayer;
  final double crossAxisExtent;
  final Axis axis;
  final bool includeRunEdges;

  TimelineFrameGeometry? _lastGeometry;
  TimelineRowEditChromeModel? _lastModel;

  /// Whether [other] would resolve the same models — the widget-level
  /// "do I need a new resolver" test.
  bool matches(TimelineRowChromeResolver other) =>
      identical(other.layer, layer) &&
      identical(other.baseLayer, baseLayer) &&
      listEquals(other.gripBlocks, gripBlocks) &&
      other.gripIdScope == gripIdScope &&
      other.crossAxisExtent == crossAxisExtent &&
      other.axis == axis &&
      other.includeRunEdges == includeRunEdges;

  TimelineRowEditChromeModel resolve(TimelineFrameGeometry geometry) {
    final cached = _lastModel;
    if (cached != null && _lastGeometry == geometry) {
      return cached;
    }
    final model = timelineRowEditChromeModel(
      gripBlocks: gripBlocks,
      gripIdScope: gripIdScope,
      layer: layer,
      baseLayer: baseLayer,
      geometry: geometry,
      crossAxisExtent: crossAxisExtent,
      axis: axis,
      includeRunEdges: includeRunEdges,
    );
    _lastGeometry = geometry;
    _lastModel = model;
    return model;
  }
}

/// Draws a dense row's whole edit chrome in one pass.
class TimelineRowEditChromePainter extends CustomPainter {
  TimelineRowEditChromePainter({
    required this.resolver,
    required this.geometry,
    required this.colorScheme,
    required this.hoveredId,
    required this.operatingId,
    required this.draggingGripId,
    this.gripGround = timelineDrawingHeldColor,
  }) : super(repaint: geometry);

  final TimelineRowChromeResolver resolver;

  /// The LIVE frame-axis geometry (R28 #4): a zoom step repaints, never
  /// rebuilds, the row that built this painter.
  final TimelineFrameGeometryHandle geometry;

  TimelineRowEditChromeModel get model => resolver.resolve(geometry.value);
  double get frameCellExtent => geometry.value.frameCellExtent;

  final ColorScheme colorScheme;

  /// The target the pointer rests on; null = nothing hovered.
  final String? hoveredId;

  /// The run target mid-operation (a live [+] drag or an open tag flyout).
  final String? operatingId;

  /// The grip currently being comma-dragged.
  final String? draggingGripId;

  /// The color of what the grips sit ON (feedback #11, re-picked by the
  /// ground law 2026-08-17) — the row's block paper on a timeline row, or
  /// the cut-block plate under the storyboard strip.
  final Color gripGround;

  /// Every target this row would draw, in hit order — THE probe surface,
  /// the successor of `find.byKey` on the widgets these replaced.
  List<TimelineRowChromeTarget> get targets => model.targets;

  /// The first target whose rect contains [position]; null = the row's
  /// cells own that pixel.
  TimelineRowChromeTarget? targetAt(Offset position) {
    for (final target in model.targets) {
      if (target.rect.contains(position)) {
        return target;
      }
    }
    return null;
  }

  /// A painter that does not answer is treated as OPAQUE by
  /// [RenderCustomPaint.hitTestSelf] (`painter.hitTest(position) ?? true`).
  /// Left at the default, this row-wide CustomPaint swallows every pointer
  /// the row gets — seeks, double-taps, SE drops, range moves — because the
  /// Stack stops descending to the cells below it. It answers for its
  /// targets and only its targets.
  @override
  bool? hitTest(Offset position) => targetAt(position) != null;

  @override
  void paint(Canvas canvas, Size size) {
    final model = this.model;
    for (final span in model.patternSpans) {
      paintTimelineRunPatternSpan(canvas, span, ground: gripGround);
    }
    final glyphSize = timelineRunClusterGlyphSize(frameCellExtent);
    for (final target in model.targets) {
      switch (target) {
        case TimelineRowGripTarget():
          paintBlockEdgeGripBar(
            canvas,
            target.barRect,
            target.id == draggingGripId
                ? BlockEdgeGripInk.dragging
                : target.id == hoveredId
                ? BlockEdgeGripInk.hovered
                : BlockEdgeGripInk.rest,
            ground: gripGround,
          );
        case TimelineRowRunAddTarget():
          paintTimelineRunGlyph(
            canvas,
            text: '+',
            slot: target.rect,
            fontSize: glyphSize + 2,
            color: timelineRunGlyphColor(
              colorScheme,
              hovered: target.id == hoveredId,
              operating: target.id == operatingId,
            ),
          );
        case TimelineRowRunTagTarget():
          paintTimelineRunGlyph(
            canvas,
            text: target.letter,
            slot: target.rect,
            fontSize: glyphSize,
            color: timelineRunGlyphColor(
              colorScheme,
              hovered: target.id == hoveredId,
              operating: target.id == operatingId,
            ),
          );
      }
    }
  }

  @override
  bool shouldRepaint(covariant TimelineRowEditChromePainter oldDelegate) =>
      // Geometry is absent on purpose — it arrives through `repaint`.
      // Value-compared, never `identical`: a fresh-but-equal instance is
      // the common case on a rebuild (the churn that hid in the rulers).
      !listEquals(oldDelegate.model.targets, model.targets) ||
      !listEquals(oldDelegate.model.patternSpans, model.patternSpans) ||
      oldDelegate.colorScheme != colorScheme ||
      oldDelegate.hoveredId != hoveredId ||
      oldDelegate.operatingId != operatingId ||
      oldDelegate.draggingGripId != draggingGripId ||
      oldDelegate.gripGround != gripGround;

  @override
  SemanticsBuilderCallback get semanticsBuilder =>
      (size) => [
        // The glyphs these replaced were `Text` widgets, each carrying its own
        // semantics node; dropping them would take the row away from screen
        // readers (tier 1's lesson, applied before it can bite).
        for (final target in resolver.resolve(geometry.value).targets)
          if (target is TimelineRowRunAddTarget)
            CustomPainterSemantics(
              rect: target.rect,
              properties: const SemanticsProperties(
                label: '+',
                textDirection: TextDirection.ltr,
              ),
            )
          else if (target is TimelineRowRunTagTarget)
            CustomPainterSemantics(
              rect: target.rect,
              properties: SemanticsProperties(
                label: target.letter,
                textDirection: TextDirection.ltr,
              ),
            ),
      ];
}

/// A dense row's edit chrome: ONE painter for every grip bar and run glyph,
/// and ONE gesture layer that routes by hit target.
///
/// The layer fills the row but only ACCEPTS pointers that land on a target
/// ([_ChromeHitGate]); everything else falls straight through to the range
/// gesture layer and the cells below, which is what the small per-affordance
/// boxes used to do implicitly.
/// The chrome layer's own grip hooks — identity-free on purpose.
///
/// A grip drag is the same gesture whether the block is a layer's exposure
/// or a track's cut; only what it re-times differs. The mount closes over
/// WHOSE row it is (its `LayerId`, its `CutId` by ordinal) and hands the
/// session the right verb, exactly the way the range gesture's row address
/// works.
class TimelineRowGripCallbacks {
  const TimelineRowGripCallbacks({
    required this.onBegin,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  /// Returns whether the drag may start (e.g. the block still exists).
  final bool Function(
    int blockStartIndex,
    int blockOrdinal,
    TimelineBlockEdge edge,
  )
  onBegin;

  /// Reports the cumulative whole-frame delta since drag start.
  final ValueChanged<int> onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;
}

class TimelineRowEditChromeLayer extends StatefulWidget {
  const TimelineRowEditChromeLayer({
    super.key,
    required this.paintKey,
    required this.layerId,
    required this.resolver,
    required this.geometry,
    required this.axis,
    required this.grips,
    required this.runEdit,
    this.gripGround = timelineDrawingHeldColor,
  });

  /// Key placed on the [CustomPaint] itself: tests read the painter (and
  /// its render box, for target geometry) off this.
  final Key paintKey;

  /// The row's layer — the RUN-edge half's identity. Null on rows whose
  /// blocks are not a layer's (the storyboard's cut row), which is also
  /// why the grip hooks below carry none: whoever mounts this layer knows
  /// whose row it is and closes over it.
  final LayerId? layerId;

  /// Resolves the targets for whatever geometry is live; rebuilt by the row
  /// only when the LAYER changes, never for a zoom step.
  final TimelineRowChromeResolver resolver;

  /// The LIVE frame-axis geometry (R28 #4).
  final TimelineFrameGeometryHandle geometry;

  final Axis axis;

  /// Comma-drag hooks; null when the row has no grip targets.
  final TimelineRowGripCallbacks? grips;

  /// Run-edge hooks; null when the row has no run targets.
  final TimelineRunEditCallbacks? runEdit;

  /// The color under the grips (feedback #11, re-picked by the ground law
  /// 2026-08-17). The default is the timeline's plain paper; a row whose
  /// blocks wear a color label passes that paper, and the storyboard strip
  /// passes its cut-block plate.
  final Color gripGround;

  @override
  State<TimelineRowEditChromeLayer> createState() =>
      _TimelineRowEditChromeLayerState();
}

class _TimelineRowEditChromeLayerState
    extends State<TimelineRowEditChromeLayer> {
  String? _hoveredId;
  String? _menuOpenId;

  // The grip comma-drag.
  TimelineRowGripTarget? _gripTarget;
  double _gripAccumulated = 0;
  int _gripLastReported = 0;
  bool _gripDragging = false;

  // The run [+] add drag.
  TimelineRowRunAddTarget? _addTarget;
  double _addAccumulated = 0;
  bool _addDragging = false;

  /// The target the last pointer-down landed on — read by the recognizers
  /// when they win the arena.
  ///
  /// R9 #12: it also drives the PRESSED ink. The accent used to wait for
  /// the drag recognizer to win, which is after the slop — so pressing a
  /// grip and holding still looked like nothing had been grabbed. A press
  /// is an answer the affordance owes immediately, and this Listener is
  /// upstream of the arena, so it can give one.
  TimelineRowChromeTarget? _pressed;

  /// The pressed target's id while the pointer is still down (null once it
  /// lifts) — the release path #12 found missing.
  String? _pressedId;

  late final DragGestureRecognizer _gripDrag = widget.axis == Axis.horizontal
      ? HorizontalDragGestureRecognizer(debugOwner: this)
      : VerticalDragGestureRecognizer(debugOwner: this);
  late final TapGestureRecognizer _addTap = TapGestureRecognizer(
    debugOwner: this,
  );
  late final EagerPanGestureRecognizer _addPan = EagerPanGestureRecognizer(
    debugOwner: this,
  );
  late final EagerPanGestureRecognizer _tagPan = EagerPanGestureRecognizer(
    debugOwner: this,
  );

  bool get _horizontal => widget.axis == Axis.horizontal;

  @override
  void initState() {
    super.initState();
    // Drag from the DOWN position (R10) — the same rule the [+] pan below
    // has always had. The slop a recognizer spends winning the arena is
    // real travel of the hand; discarding it left the edge ~18px behind
    // the pointer for the WHOLE gesture, which is what the user meant by
    // "어긋난 채로 유지". The grip mounts and the lane key marker were the
    // delta-accumulating frame-axis drags still on Flutter's default; the
    // ruler and rail scrubs read the pointer's absolute position and never
    // cared.
    _gripDrag.dragStartBehavior = DragStartBehavior.down;
    _gripDrag.onStart = (_) => _startGripDrag();
    _gripDrag.onUpdate = (details) =>
        _updateGripDrag(_horizontal ? details.delta.dx : details.delta.dy);
    _gripDrag.onEnd = (_) => _endGripDrag();
    _gripDrag.onCancel = _cancelGripDrag;
    _addTap.onTap = _tapAdd;
    // Drag from the DOWN position: the [+] count must not lose the first
    // cell to the slop.
    _addPan.dragStartBehavior = DragStartBehavior.down;
    _addPan.onStart = (_) => _startAdd();
    _addPan.onUpdate = (details) => _updateAdd(details.delta);
    _addPan.onEnd = (_) => _endAdd();
    _addPan.onCancel = _cancelAdd;
    // PEN-12 #3: the press already opened the flyout — any drag continuing
    // from it must die HERE, not scroll the timeline under the open menu
    // (every device: a finger press on the tag is the tag's).
    _tagPan.onStart = (_) {};
    _tagPan.onUpdate = (_) {};
    _tagPan.onEnd = (_) {};
    _tagPan.onCancel = () {};
  }

  @override
  void dispose() {
    // A row can unmount mid-drag (its layer scrolls out of the list); the
    // session keeps the preview and the pointer-up never arrives here, so
    // land the operation rather than leaking an open session.
    if (_gripDragging) {
      widget.grips?.onEnd();
    }
    if (_addDragging) {
      final callbacks = widget.runEdit;
      if (callbacks != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => callbacks.onAddEnd(),
        );
      }
    }
    _gripDrag.dispose();
    _addTap.dispose();
    _addPan.dispose();
    _tagPan.dispose();
    super.dispose();
  }

  // ---- grip comma drag ----------------------------------------------

  void _startGripDrag() {
    final target = _pressed;
    final callbacks = widget.grips;
    if (target is! TimelineRowGripTarget || callbacks == null) {
      return;
    }
    if (!callbacks.onBegin(
      target.blockStartIndex,
      target.blockOrdinal,
      target.edge,
    )) {
      return;
    }
    setState(() {
      _gripTarget = target;
      _gripDragging = true;
      _gripAccumulated = 0;
      _gripLastReported = 0;
    });
  }

  void _updateGripDrag(double delta) {
    if (!_gripDragging) {
      return;
    }
    _gripAccumulated += delta;
    final frames = commaDragFrameDelta(
      accumulatedDelta: _gripAccumulated,
      frameCellExtent: widget.geometry.value.frameCellExtent,
    );
    if (frames == _gripLastReported) {
      return;
    }
    _gripLastReported = frames;
    widget.grips?.onUpdate(frames);
  }

  void _endGripDrag() {
    if (!_gripDragging) {
      return;
    }
    setState(() {
      _gripDragging = false;
      _gripTarget = null;
    });
    widget.grips?.onEnd();
  }

  void _cancelGripDrag() {
    if (!_gripDragging) {
      return;
    }
    setState(() {
      _gripDragging = false;
      _gripTarget = null;
    });
    widget.grips?.onCancel();
  }

  // ---- run [+] add ---------------------------------------------------

  void _startAdd() {
    final target = _pressed;
    final callbacks = widget.runEdit;
    final layerId = widget.layerId;
    if (target is! TimelineRowRunAddTarget ||
        callbacks == null ||
        layerId == null) {
      return;
    }
    if (!callbacks.onAddBegin(
      layerId,
      target.blockStartIndex,
      atEnd: target.atEnd,
    )) {
      return;
    }
    setState(() {
      _addTarget = target;
      _addDragging = true;
      _addAccumulated = 0;
    });
  }

  void _updateAdd(Offset delta) {
    final target = _addTarget;
    if (!_addDragging || target == null) {
      return;
    }
    _addAccumulated += _horizontal ? delta.dx : delta.dy;
    final frames = commaDragFrameDelta(
      accumulatedDelta: _addAccumulated,
      frameCellExtent: widget.geometry.value.frameCellExtent,
    );
    widget.runEdit?.onAddUpdate(
      target.atEnd ? (frames < 0 ? 0 : frames) : (frames > 0 ? 0 : -frames),
    );
  }

  void _endAdd() {
    if (!_addDragging) {
      return;
    }
    setState(() {
      _addDragging = false;
      _addTarget = null;
    });
    widget.runEdit?.onAddEnd();
  }

  void _cancelAdd() {
    if (!_addDragging) {
      return;
    }
    setState(() {
      _addDragging = false;
      _addTarget = null;
    });
    widget.runEdit?.onAddCancel();
  }

  /// A plain tap adds exactly ONE cel beside the run (UI-R17 #4) — the drag
  /// flow with a fixed count of 1, committed immediately.
  void _tapAdd() {
    final target = _pressed;
    final callbacks = widget.runEdit;
    final layerId = widget.layerId;
    if (_addDragging ||
        target is! TimelineRowRunAddTarget ||
        callbacks == null ||
        layerId == null) {
      return;
    }
    if (!callbacks.onAddBegin(
      layerId,
      target.blockStartIndex,
      atEnd: target.atEnd,
    )) {
      return;
    }
    callbacks.onAddUpdate(1);
    callbacks.onAddEnd();
  }

  // ---- run property tag ----------------------------------------------

  Future<void> _openModeFlyout(TimelineRowRunTagTarget target) async {
    final callbacks = widget.runEdit;
    final layerId = widget.layerId;
    if (callbacks == null || layerId == null) {
      return;
    }
    void pick(TimelineRunEdgeMode? mode, {bool scopeToSelection = false}) =>
        callbacks.onEdgeModeSelected(
          layerId,
          target.blockStartIndex,
          target.side,
          mode,
          scopeToSelection: scopeToSelection,
        );
    // Whether the LIVE selection can scope a pattern right now (UI-R19 #2):
    // the explicit entry replaces the old silent capture — "Repeat" now
    // ALWAYS means the whole run.
    final selectionScopes =
        callbacks.canScopeToSelection?.call(
          layerId,
          target.blockStartIndex,
          target.side,
        ) ??
        false;
    setState(() => _menuOpenId = target.id);
    await showPanelFlyout(
      context,
      // The tag has no widget of its own to anchor on any more, so the
      // shared flyout takes the painted rect instead (still ONE popup
      // shell — no surface-local copy).
      anchorRect: target.rect,
      entries: [
        PanelFlyoutItem(
          keyValue: 'run-edge-mode-none',
          label: 'None',
          checked: target.mode == null,
          onSelected: () => pick(null),
        ),
        PanelFlyoutItem(
          keyValue: 'run-edge-mode-hold',
          label: 'Hold',
          checked: target.mode == TimelineRunEdgeMode.hold,
          onSelected: () => pick(TimelineRunEdgeMode.hold),
        ),
        PanelFlyoutItem(
          keyValue: 'run-edge-mode-repeat',
          label: AppText.strings.tlRepeat,
          checked:
              target.mode == TimelineRunEdgeMode.repeat && !target.hasPattern,
          onSelected: () => pick(TimelineRunEdgeMode.repeat),
        ),
        // Listed while a selection can scope it — or one already does (the
        // checked row doubles as the "this edge repeats a SELECTION"
        // status).
        if (selectionScopes || target.hasPattern)
          PanelFlyoutItem(
            keyValue: 'run-edge-mode-repeat-selection',
            label: AppText.strings.tlRepeatSelection,
            checked:
                target.mode == TimelineRunEdgeMode.repeat && target.hasPattern,
            onSelected: () =>
                pick(TimelineRunEdgeMode.repeat, scopeToSelection: true),
          ),
      ],
    );
    if (mounted) {
      setState(() => _menuOpenId = null);
    }
  }

  // ---- routing --------------------------------------------------------

  /// The targets for the LIVE geometry. Read through the resolver, never
  /// captured: this layer does not rebuild on a zoom step, so a snapshot
  /// taken at build time would hit-test yesterday's rects.
  List<TimelineRowChromeTarget> get _targets =>
      widget.resolver.resolve(widget.geometry.value).targets;

  TimelineRowChromeTarget? _targetAt(Offset position) {
    for (final target in _targets) {
      if (target.rect.contains(position)) {
        return target;
      }
    }
    return null;
  }

  void _handlePointerDown(PointerDownEvent event) {
    final target = _targetAt(event.localPosition);
    _pressed = target;
    if (target is TimelineRowGripTarget && _pressedId != target.id) {
      setState(() => _pressedId = target.id);
    }
    switch (target) {
      case null:
        return;
      case TimelineRowGripTarget():
        _gripDrag.addPointer(event);
      case TimelineRowRunAddTarget():
        // Tap = add ONE cel (UI-R17 #4); a drag keeps the count-preview
        // flow. PEN-12 #6: TAPS take every device — a clean finger tap
        // clicks [+] even while touch panning belongs to the scroll.
        _addTap.addPointer(event);
        _addPan.addPointer(event);
      case TimelineRowRunTagTarget():
        // The flyout opens on POINTER DOWN (UI-R10 #2).
        _tagPan.addPointer(event);
        _openModeFlyout(target);
    }
  }

  /// The pointer lifted (or the system took it): the press ink lets go.
  /// A drag that started keeps its own accent through [_gripDragging] until
  /// the drag itself ends.
  void _releasePress() {
    if (_pressedId == null) {
      return;
    }
    setState(() => _pressedId = null);
  }

  void _handleHover(Offset position) {
    final id = _targetAt(position)?.id;
    if (id != _hoveredId) {
      setState(() => _hoveredId = id);
    }
  }

  MouseCursor get _cursor {
    final hovered = _hoveredId;
    if (hovered == null) {
      return MouseCursor.defer;
    }
    for (final target in _targets) {
      if (target.id != hovered) {
        continue;
      }
      return switch (target) {
        TimelineRowRunTagTarget() => SystemMouseCursors.click,
        _ =>
          _horizontal
              ? SystemMouseCursors.resizeColumn
              : SystemMouseCursors.resizeRow,
      };
    }
    return MouseCursor.defer;
  }

  @override
  Widget build(BuildContext context) {
    // PEN-11: device gesture settings — manual recognizers do not inject
    // them (kTouchSlop 18 vs device ~8), and the device policy can change
    // under a live tree, so both are refreshed on every build like
    // GestureDetector does.
    final gestureSettings = MediaQuery.maybeGestureSettingsOf(context);
    final editDevices = AppInput.timelineEditPanDevices;
    _gripDrag
      ..gestureSettings = gestureSettings
      ..supportedDevices = editDevices;
    _addTap.gestureSettings = gestureSettings;
    _addPan
      ..gestureSettings = gestureSettings
      ..supportedDevices = editDevices;
    _tagPan.gestureSettings = gestureSettings;

    return CustomPaint(
      key: widget.paintKey,
      painter: TimelineRowEditChromePainter(
        resolver: widget.resolver,
        geometry: widget.geometry,
        colorScheme: Theme.of(context).colorScheme,
        hoveredId: _hoveredId,
        operatingId: _addDragging ? _addTarget?.id : _menuOpenId,
        // R9 #12: pressed reads as engaged from the pointer DOWN, not from
        // the moment the drag recognizer wins.
        draggingGripId: _gripDragging ? _gripTarget?.id : _pressedId,
        gripGround: widget.gripGround,
      ),
      child: _ChromeHitGate(
        // Off-target pixels belong to the cells: the gate keeps the
        // row-wide layer from swallowing seeks and range drags.
        isTarget: (position) => _targetAt(position) != null,
        child: MouseRegion(
          cursor: _cursor,
          // ENTER as well as hover: a pointer can come to rest on a target
          // through a scroll or a relayout, with no move event to follow —
          // the per-affordance MouseRegions this replaced lit up on enter.
          onEnter: (event) => _handleHover(event.localPosition),
          onHover: (event) => _handleHover(event.localPosition),
          onExit: (_) {
            if (_hoveredId != null) {
              setState(() => _hoveredId = null);
            }
          },
          child: Listener(
            // The whole cluster/grip zone swallows pointer-downs (UI-R10
            // #12 — a near-miss must not seek the playhead below).
            behavior: HitTestBehavior.opaque,
            onPointerDown: _handlePointerDown,
            onPointerUp: (_) => _releasePress(),
            onPointerCancel: (_) => _releasePress(),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

/// Passes a hit through only where the row actually has an affordance.
class _ChromeHitGate extends SingleChildRenderObjectWidget {
  const _ChromeHitGate({required this.isTarget, required super.child});

  final bool Function(Offset position) isTarget;

  @override
  _RenderChromeHitGate createRenderObject(BuildContext context) =>
      _RenderChromeHitGate(isTarget);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderChromeHitGate renderObject,
  ) => renderObject.isTarget = isTarget;
}

class _RenderChromeHitGate extends RenderProxyBox {
  _RenderChromeHitGate(this.isTarget);

  bool Function(Offset position) isTarget;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position) || !isTarget(position)) {
      return false;
    }
    return super.hitTest(result, position: position);
  }
}
