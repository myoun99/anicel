import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/canvas_viewport.dart';
import '../../models/cut.dart';
import '../../models/playback_quality.dart';
import '../../models/project_background.dart';
import '../../services/se_name_tag_plan.dart';
import 'cut_frame_composite_cache.dart';
import 'playback_frame_painter.dart';

/// The canvas content while a ruler scrub is in flight: the frame under the
/// cursor straight from the composite cache, drawn IN CANVAS SPACE — the
/// scrub shows the editing view's picture moving through time, not the
/// playback presentation (no camera projection, no cut fade; the camera
/// FRAME overlay stays visible on top exactly like normal editing). The
/// CUT pose follows the editing canvas (R9-B): with the V-row fx on, the
/// content rides the pose per cursor frame — paper static.
///
/// Cache misses keep the last displayed frame on screen (the playback
/// view's stale-frame policy); the release commit swaps back to the editing
/// canvas at the final frame.
class CanvasScrubPreview extends StatefulWidget {
  const CanvasScrubPreview({
    super.key = const ValueKey<String>('canvas-scrub-preview'),
    required this.frameCursor,
    required this.compositeCache,
    required this.cut,
    required this.qualityOf,
    this.cutFadeOpacityAt,
    this.seNameTagsAt,
    this.viewport,
    this.paperBackground = ProjectBackground.defaultBackground,
    this.gapParking,
    this.gapContentBuilder,
  });

  final ValueListenable<int> frameCursor;
  final CutFrameCompositeCache compositeCache;
  /// Null = no active cut (gap state, UI-R9 #3): the preview is the void
  /// regardless of the parking value.
  final Cut? cut;
  final PlaybackQuality Function() qualityOf;

  /// The session's gap parking (UI-R7 #9): non-null while the scrub sits
  /// in a gap — no cut there, so the preview shows the paperless void
  /// instead of clamping to the owner cut's last frame. Subscribed like
  /// the cursor: the leading gap pins the cut-local cursor at 0, so the
  /// parking is the only move signal there. Null = never parked.
  final ValueListenable<int?>? gapParking;

  /// What a gap parking shows INSTEAD of the void (the multitrack display
  /// path): the scrubbed track gaps here, but another track may cover the
  /// frame — the builder mounts the parked track stack, which follows the
  /// parking per move on its own. Null = the void.
  final WidgetBuilder? gapContentBuilder;

  // `cutPoseSampleAt` went with the V row's transform: there is no cut-level
  // pose for a scrub to sample.

  /// The cut fade per cursor frame (fx-gated by the caller, R9-C → R3b:
  /// transparency — the painter thins the cut's unit, revealing the
  /// panel's stage behind it). Null = no fade.
  final double Function(int frameIndex)? cutFadeOpacityAt;

  /// The SE rows' on-canvas name tags per cursor frame (R5b) — the scrub
  /// shows the editing view moving through time, tags included.
  final List<ResolvedSeNameTag> Function(int frameIndex)? seNameTagsAt;

  /// The panel's live pan/zoom; identity when null.
  final CanvasViewport? viewport;

  /// The project paper (R10-⑥) — mirrors the editing canvas.
  final ProjectBackground paperBackground;

  @override
  State<CanvasScrubPreview> createState() => _CanvasScrubPreviewState();
}

class _CanvasScrubPreviewState extends State<CanvasScrubPreview> {
  /// Our own clone of the last displayed composite: the cache may evict and
  /// dispose its image at any time, a clone shares the pixels but has an
  /// independent lifetime.
  ui.Image? _heldFrame;

  /// The cache image the clone came from (identity only, may be disposed);
  /// cloning happens only when this changes, not on every cursor move.
  ui.Image? _heldSource;

  @override
  void initState() {
    super.initState();
    widget.frameCursor.addListener(_onCursorMoved);
    widget.gapParking?.addListener(_onCursorMoved);
  }

  @override
  void didUpdateWidget(covariant CanvasScrubPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.frameCursor, widget.frameCursor)) {
      oldWidget.frameCursor.removeListener(_onCursorMoved);
      widget.frameCursor.addListener(_onCursorMoved);
    }
    if (!identical(oldWidget.gapParking, widget.gapParking)) {
      oldWidget.gapParking?.removeListener(_onCursorMoved);
      widget.gapParking?.addListener(_onCursorMoved);
    }
    if (oldWidget.cut?.id != widget.cut?.id) {
      // A held frame belongs to ITS cut: a cut swap under a live preview
      // (a second pointer activating another cut mid-scrub) must not draw
      // the old cut's pixels stretched onto the new cut's canvas size.
      _heldFrame?.dispose();
      _heldFrame = null;
      _heldSource = null;
    }
  }

  @override
  void dispose() {
    widget.frameCursor.removeListener(_onCursorMoved);
    widget.gapParking?.removeListener(_onCursorMoved);
    _heldFrame?.dispose();
    super.dispose();
  }

  void _onCursorMoved() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final cut = widget.cut;
    // A gap parking (or the no-cut state itself): the track stack when a
    // builder is wired (the multitrack display path), else the VOID
    // (R16-⑥ semantics, live during the drag — UI-R7 #9): no paper, no
    // frame.
    if (cut == null || widget.gapParking?.value != null) {
      final gapContent = widget.gapContentBuilder;
      if (gapContent != null) {
        return gapContent(context);
      }
      return const SizedBox.expand(
        key: ValueKey<String>('canvas-scrub-preview-gap-void'),
      );
    }
    // Over-end cursors (the endless runway) display the cut's last frame.
    final maxFrame = cut.duration > 0 ? cut.duration - 1 : 0;
    final frameIndex = widget.frameCursor.value.clamp(0, maxFrame);
    final composite = widget.compositeCache.validCompositeOrNull(
      cut: cut,
      frameIndex: frameIndex,
      quality: widget.qualityOf(),
    );
    if (composite != null && !identical(composite, _heldSource)) {
      _heldFrame?.dispose();
      _heldSource = composite;
      _heldFrame = composite.clone();
    }

    return SizedBox.expand(
      child: CustomPaint(
        painter: PlaybackFramePainter(
          image: _heldFrame,
          canvasSize: cut.canvasSize,
          viewport: widget.viewport,
          paperBackground: widget.paperBackground,
          fadeOpacity: widget.cutFadeOpacityAt?.call(frameIndex) ?? 1,
          seNameTags: widget.seNameTagsAt?.call(frameIndex) ?? const [],
        ),
      ),
    );
  }
}
