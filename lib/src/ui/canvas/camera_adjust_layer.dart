import 'package:flutter/material.dart';

import '../../core/point_bounds.dart';
import '../../models/camera_pose.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/transform_pose.dart';
import '../../services/camera_frame_corners.dart'
    show cameraFrameCornersInCanvas;
import '../session/canvas_adjust.dart';
import '../text/app_strings.dart';
import '../widgets/panel_flyout.dart';
import 'canvas_target_pill.dart';
import 'canvas_viewport_offset.dart';
import 'row_transform_box.dart';

/// The project camera's frame being resized ON the canvas (I-80): the
/// frame where the camera stands at this frame, in the box a layer's
/// transform wears — its two scales about the frame's middle
/// ([RowBoxTwoScales]: a corner keeps the frame's shape, an edge's middle
/// moves its one side, in the camera's own axes when it is turned) — and
/// under it the canvas's pill with the size, the ratio the frame keeps,
/// 확정 and 취소 ([CanvasTargetPill]).
///
/// 🗣️I-80-Q1 (유저 2026-10-08): 「가운데가 그대로 — 크기만 바뀐다」, and
/// 「카메라 사이즈 변경은 변형도구 규칙 그대로 따라간다 생각하면 규칙
/// 새로만드는게 아님」. I-80-Q2: the ratio is a list on the pill.
///
/// Its ✓ lands the size through [onLand] — the one landing Enter and the
/// rail's ↵ reach through 확정 too (`landCanvasAdjust`).
class CameraAdjustLayer extends StatelessWidget {
  const CameraAdjustLayer({
    super.key,
    required this.adjust,
    required this.pose,
    required this.viewport,
    required this.canvasSize,
    required this.onLand,
  });

  final CanvasAdjust adjust;

  /// Where the camera stands at the frame the canvas shows.
  final CameraPose pose;
  final CanvasViewport viewport;

  /// The cut's canvas — the stage the box measures against.
  final CanvasSize canvasSize;

  /// Lands the size: the project camera's frame becomes it.
  final VoidCallback onLand;

  /// The ratio list's word for [lock]: a screen's ratio says itself.
  static String labelOf(CameraRatioLock lock) => switch (lock) {
    CameraRatioLock.free => AppText.strings.cameraRatioFree,
    CameraRatioLock.current => AppText.strings.cameraRatioCurrent,
    CameraRatioLock.wide => '16:9',
    CameraRatioLock.scope => '2.39:1',
    CameraRatioLock.standard => '4:3',
    CameraRatioLock.square => '1:1',
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: adjust,
    builder: (context, _) {
      final shown = adjust.shown;
      final grabbed = adjust.draft;
      if (shown is! CameraSizeDraft || grabbed is! CameraSizeDraft) {
        return const SizedBox.shrink();
      }
      final corners = [
        for (final corner in cameraFrameCornersInCanvas(
          pose: pose,
          cameraFrameSize: shown.size,
        ))
          CanvasPoint(x: corner.dx, y: corner.dy),
      ];
      return Stack(
        children: [
          Positioned.fill(
            child: RowTransformBox(
              corners: corners,
              pose: TransformPose.uniform(
                center: pose.center,
                rotationDegrees: pose.rotationDegrees,
              ),
              canvasSize: canvasSize,
              viewport: viewport,
              // The canvas stays the tools' and the view's: a press is the
              // box's on its handles alone.
              claimsCanvas: false,
              onCancelled: adjust.dropShowing,
              // The box stands at scale 1 over the size the grab began at,
              // so what it lands is that size's two factors.
              scale: RowBoxTwoScales((
                changed: (factors) =>
                    adjust.show(grabbed.scaled(factors.x, factors.y)),
                committed: (factors) =>
                    adjust.move(grabbed.scaled(factors.x, factors.y)),
              )),
            ),
          ),
          Positioned.fill(
            child: CanvasTargetPill(
              keyValue: 'camera-adjust-pill',
              target: pointsBounds([
                for (final corner in corners)
                  viewport.canvasToViewportOffset(corner),
              ]),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '${shown.size.width} × ${shown.size.height}',
                    key: const ValueKey<String>('camera-adjust-size'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                PanelFlyoutButton(
                  key: const ValueKey<String>('camera-adjust-ratio'),
                  label: labelOf(shown.lock),
                  entriesBuilder: () => CameraRatioLock.values
                      .asFlyoutValueChoices(
                        current: shown.lock,
                        choiceOf: (lock) => PanelFlyoutChoice(
                          key: 'camera-adjust-ratio-${lock.name}',
                          label: labelOf(lock),
                        ),
                        onPicked: (lock) => adjust.move(shown.locked(lock)),
                      ),
                ),
                ...targetPillVerbs(
                  'camera-adjust',
                  onConfirm: onLand,
                  onCancel: adjust.end,
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
