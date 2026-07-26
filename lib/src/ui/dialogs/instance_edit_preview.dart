import 'package:flutter/material.dart';

import '../../models/camera_instruction.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/timeline_exposure.dart';
import '../timeline/timeline_cell_exposure_state.dart';
import '../timeline/timeline_exposure_block_visual.dart';
import '../timeline/timeline_frame_cell.dart';
import '../timeline/timeline_frame_geometry.dart';
import '../timeline/timeline_frame_span_layout.dart';
import '../timeline/timeline_instruction_row_visual.dart';
import '../timeline/timeline_se_row_visual.dart';

/// Live preview inside the instance-edit dialogs: a synthetic block on up
/// to [maxKoma] frames rendered through the REAL row code (paper cells +
/// the SE/instruction overlays), so the dialog shows exactly what the
/// timeline will. [axis] follows the current timeline orientation —
/// horizontal in the timeline, vertical in the X-sheet — and a wider (or
/// taller) dialog shows more koma via LayoutBuilder.
class InstanceEditPreview extends StatelessWidget {
  const InstanceEditPreview.se({
    super.key,
    required this.axis,
    required String dialogue,
    required String seName,
  }) : _kind = LayerKind.se,
       _dialogue = dialogue,
       _seName = seName,
       _event = null,
       _defById = null;

  const InstanceEditPreview.instruction({
    super.key,
    required this.axis,
    required InstructionEvent event,
    required CameraInstructionDef? Function(String instructionId) defById,
  }) : _kind = LayerKind.instruction,
       _dialogue = '',
       _seName = '',
       _event = event,
       _defById = defById;

  final Axis axis;
  final LayerKind _kind;
  final String _dialogue;
  final String _seName;
  final InstructionEvent? _event;
  final CameraInstructionDef? Function(String instructionId)? _defById;

  static const int maxKoma = 6;
  static const double komaExtent = 44;
  static const double crossExtent = 52;
  static const double _verticalMainBudget = 240;

  Layer _previewLayer(int komaCount) {
    const frameId = FrameId('instance-preview-frame');
    return switch (_kind) {
      LayerKind.se => Layer(
        id: const LayerId('instance-preview'),
        name: 'preview',
        kind: LayerKind.se,
        frames: [
          Frame(
            id: frameId,
            duration: komaCount,
            strokes: const [],
            name: _dialogue,
            seName: _seName.isEmpty ? null : _seName,
          ),
        ],
        timeline: {0: TimelineExposure.drawing(frameId, length: komaCount)},
      ),
      _ => Layer(
        id: const LayerId('instance-preview'),
        name: 'preview',
        kind: LayerKind.instruction,
        frames: const [],
        timeline: const {},
        instructions: {0: _event!.copyWith(length: komaCount)},
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mainBudget = axis == Axis.horizontal
            ? constraints.maxWidth
            : _verticalMainBudget;
        final komaCount = (mainBudget / komaExtent).floor().clamp(2, maxKoma);
        final layer = _previewLayer(komaCount);

        // The synthetic block always covers [0, komaCount).
        TimelineCellExposureState stateAt(int frameIndex) {
          if (frameIndex < 0 || frameIndex >= komaCount) {
            return TimelineCellExposureState.uncovered;
          }
          if (_kind == LayerKind.instruction) {
            return instructionCellExposureState(layer, frameIndex);
          }
          return frameIndex == 0
              ? TimelineCellExposureState.drawingStart
              : TimelineCellExposureState.held;
        }

        final cells = [
          for (var frameIndex = 0; frameIndex < komaCount; frameIndex += 1)
            TimelineFrameCell(
              layer: layer,
              frameIndex: frameIndex,
              active: false,
              outsidePlaybackRange: false,
              exposureState: stateAt(frameIndex),
              exposureBlockSegment: calculateTimelineExposureBlockVisualSegment(
                previous: frameIndex == 0 ? null : stateAt(frameIndex - 1),
                current: stateAt(frameIndex),
                next: stateAt(frameIndex + 1),
              ),
              frameName: null,
              onSelectLayer: (_) {},
              onSelectFrame: (_) {},
              axis: axis,
              width: axis == Axis.horizontal ? komaExtent : crossExtent,
              height: axis == Axis.horizontal ? crossExtent : komaExtent,
              cellKeyPrefix: 'instance-preview-cell',
            ),
        ];

        final overlays = _kind == LayerKind.se
            ? timelineRowSeLabelOverlays(
                layer: layer,
                frameStartIndex: 0,
                frameEndIndexExclusive: komaCount,
                axis: axis,
                keyPrefix: 'instance-preview',
              )
            : timelineRowInstructionOverlays(
                layer: layer,
                frameStartIndex: 0,
                frameEndIndexExclusive: komaCount,
                axis: axis,
                defById: _defById!,
                keyPrefix: 'instance-preview',
              );

        final mainExtent = komaCount * komaExtent;
        return Align(
          alignment: Alignment.centerLeft,
          child: IgnorePointer(
            child: SizedBox(
              key: const ValueKey<String>('instance-edit-preview'),
              width: axis == Axis.horizontal ? mainExtent : crossExtent,
              height: axis == Axis.horizontal ? crossExtent : mainExtent,
              // The real cells are InkWells — give them their Material even
              // when the preview is embedded outside a dialog.
              child: Material(
                type: MaterialType.transparency,
                child: Stack(
                  children: [
                    Flex(
                      direction: axis,
                      mainAxisSize: MainAxisSize.min,
                      children: cells,
                    ),
                    // The span overlays place themselves off the frame
                    // geometry now (the timeline's own mechanism); the
                    // preview hands them a fixed one for its koma strip.
                    Positioned.fill(
                      child: TimelineFixedFrameSpanLayer(
                        geometry: TimelineFrameGeometry(
                          frameCellExtent: komaExtent,
                          frameStartIndex: 0,
                          frameEndIndexExclusive: komaCount,
                        ),
                        crossAxisExtent: crossExtent,
                        axis: axis,
                        children: overlays,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
