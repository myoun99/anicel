import 'package:flutter/material.dart';

import '../../core/point_bounds.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/transform_pose.dart';
import '../session/canvas_adjust.dart';
import '../shortcuts/editor_action_registry.dart' show EditorActionIds;
import '../text/app_strings.dart';
import '../widgets/app_icon_button.dart';
import 'canvas_target_pill.dart';
import 'canvas_viewport_offset.dart';
import 'row_transform_box.dart';

/// A canvas being resized ON the canvas (I-79): its edges in the box every
/// box on the canvas wears ([RowTransformBox], each handle moving its own
/// edges — [RowBoxEdges]), and under it the canvas's pill with the size the
/// edges make, 확정 and 취소 ([CanvasTargetPill]).
///
/// 🗣️I-79-Q1 (유저 2026-10-08): the pill stands at the bottom middle of
/// what it adjusts — the canvas here, as it stands under the transform box.
/// I-79-Q2: no anchor is shown; the edge across from the one dragged stays.
///
/// While it is up it binds [onLand] as the adjust's landing
/// ([CanvasAdjust.land]), which Enter and the rail's ↵ reach through 확정.
class CanvasAdjustLayer extends StatefulWidget {
  const CanvasAdjustLayer({
    super.key,
    required this.adjust,
    required this.viewport,
    required this.canvasSize,
    required this.onLand,
  });

  final CanvasAdjust adjust;
  final CanvasViewport viewport;

  /// The canvas as it stands — what the box measures its stage against.
  final CanvasSize canvasSize;

  /// Lands the edges: the canvas resized behind the app's wait window.
  final VoidCallback onLand;

  @override
  State<CanvasAdjustLayer> createState() => _CanvasAdjustLayerState();
}

class _CanvasAdjustLayerState extends State<CanvasAdjustLayer> {
  @override
  void initState() {
    super.initState();
    widget.adjust.bind(this, widget.onLand);
  }

  @override
  void didUpdateWidget(CanvasAdjustLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.adjust, widget.adjust) ||
        oldWidget.onLand != widget.onLand) {
      oldWidget.adjust.unbind(this);
      widget.adjust.bind(this, widget.onLand);
    }
  }

  @override
  void dispose() {
    widget.adjust.unbind(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.adjust,
    builder: (context, _) {
      final edges = widget.adjust.shown;
      if (edges == null) {
        return const SizedBox.shrink();
      }
      final corners = [
        CanvasPoint(x: edges.left, y: edges.top),
        CanvasPoint(x: edges.right, y: edges.top),
        CanvasPoint(x: edges.right, y: edges.bottom),
        CanvasPoint(x: edges.left, y: edges.bottom),
      ];
      return Stack(
        children: [
          Positioned.fill(
            child: RowTransformBox(
              corners: corners,
              pose: TransformPose(
                center: CanvasPoint(
                  x: edges.center.dx,
                  y: edges.center.dy,
                ),
              ),
              canvasSize: widget.canvasSize,
              viewport: widget.viewport,
              // The canvas stays the tools' and the view's: a press is the
              // box's on its handles alone.
              claimsCanvas: false,
              onCancelled: widget.adjust.dropShowing,
              scale: RowBoxEdges((
                changed: widget.adjust.show,
                committed: widget.adjust.move,
              )),
            ),
          ),
          Positioned.fill(
            child: CanvasTargetPill(
              keyValue: 'canvas-adjust-pill',
              target: pointsBounds([
                for (final corner in corners)
                  widget.viewport.canvasToViewportOffset(corner),
              ]),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '${edges.width.round()} × ${edges.height.round()}',
                    key: const ValueKey<String>('canvas-adjust-size'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                AppIconButton(
                  keyValue: 'canvas-adjust-confirm',
                  shortcuts: const [EditorActionIds.confirm],
                  tooltip: AppText.strings.commonApply,
                  icon: const Icon(Icons.check),
                  onPressed: widget.onLand,
                ),
                AppIconButton(
                  keyValue: 'canvas-adjust-cancel',
                  shortcuts: const [EditorActionIds.selectionTransformCancel],
                  tooltip: AppText.strings.commonCancel,
                  icon: const Icon(Icons.close),
                  onPressed: widget.adjust.end,
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
